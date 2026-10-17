import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/glb_header.dart';

/// A download problem with a message that is safe to show to the user.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);

  @override
  String toString() => message;
}

/// How much of one model has arrived. [total] is null when the server didn't
/// say how big the file is.
@immutable
class ModelDownloadProgress {
  const ModelDownloadProgress(this.received, [this.total]);

  final int received;
  final int? total;

  /// 0..1, or null when the total size isn't known.
  double? get fraction {
    final t = total;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is ModelDownloadProgress &&
      other.received == received &&
      other.total == total;

  @override
  int get hashCode => Object.hash(received, total);
}

/// One model download in flight (or just finished). Everyone who asks for the
/// same URL shares the same [ModelDownload].
class ModelDownload {
  const ModelDownload._(this.file, this.progress);

  /// Completes with the cached file, or fails with a [ModelDownloadException].
  final Future<File> file;

  /// Updated while the file downloads. Already complete for cache hits.
  final ValueListenable<ModelDownloadProgress> progress;
}

/// A failure worth retrying. The partial file is kept so the next attempt
/// resumes where this one stopped.
class _TransientDownloadError implements Exception {
  const _TransientDownloadError(this.message);
  final String message;
}

/// A parsed `Content-Range` header: "bytes 100-199/1000" or "bytes */1000".
class _ContentRange {
  const _ContentRange(this.start, this.total);

  final int? start;
  final int? total;

  static final _satisfied =
      RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$', caseSensitive: false);
  static final _unsatisfied = RegExp(r'^bytes\s+\*/(\d+)$', caseSensitive: false);

  static _ContentRange? parse(String? header) {
    if (header == null) return null;
    final text = header.trim();
    final ok = _satisfied.firstMatch(text);
    if (ok != null) {
      final total = ok.group(3)!;
      return _ContentRange(
        int.parse(ok.group(1)!),
        total == '*' ? null : int.parse(total),
      );
    }
    final bad = _unsatisfied.firstMatch(text);
    if (bad != null) return _ContentRange(null, int.parse(bad.group(1)!));
    return null;
  }
}

/// Downloads watch .glb models once and keeps them on the device, so a
/// try-on after the first one starts instantly and works offline.
///
/// Built for slow, flaky mobile connections:
///  * Downloads **resume**. Bytes already received are kept in a ".part" file
///    and the next request asks only for the rest, so leaving the AR screen
///    (or a dropped connection) never throws the progress away.
///  * Downloads are **not tied to a screen**. Use the app-wide [instance]; a
///    download keeps running after the screen that asked for it is closed.
///  * Short network failures are retried automatically.
///  * A finished file must look like a complete .glb (magic bytes and the
///    length its own header declares) before it is kept.
class WatchModelCache {
  WatchModelCache({
    http.Client? client,
    this.maxFiles = 12,
    this.maxBytes = 25 * 1024 * 1024,
    this.maxAttempts = 4,
    this.retryDelay = const Duration(seconds: 1),
    Future<Directory> Function()? directoryProvider,
  })  : _client = client ?? http.Client(),
        _directoryProvider = directoryProvider ?? _defaultDirectory;

  /// The cache the app uses. Shared so downloads outlive any one screen.
  static final WatchModelCache instance = WatchModelCache();

  /// Most models kept at once; the least recently used are deleted first.
  final int maxFiles;

  /// Largest model accepted. Models are capped at 10 MB when merchants upload
  /// them, so this is only a safety net.
  final int maxBytes;

  /// Tries per download. Each retry resumes the partial file.
  final int maxAttempts;

  /// Wait before a retry (multiplied by the attempt number).
  final Duration retryDelay;

  final http.Client _client;
  final Future<Directory> Function() _directoryProvider;
  final Map<String, ModelDownload> _inFlight = {};

  static const _connectTimeout = Duration(seconds: 30);
  // Max silence between chunks. Counted per chunk, not for the whole file, so
  // a slow but steady download is never cut off.
  static const _idleTimeout = Duration(seconds: 20);
  // Abandoned partial downloads are cleaned up after this long.
  static const _stalePartAge = Duration(days: 7);

  /// Stable file name for a URL: two independent 32-bit FNV-1a hashes
  /// (16 hex chars). `String.hashCode` isn't guaranteed stable across runs,
  /// so it can't be used for an on-disk key.
  @visibleForTesting
  static String cacheKey(String url) {
    final bytes = utf8.encode(url);
    var h1 = 0x811C9DC5;
    var h2 = 0x9E3779B1;
    for (final b in bytes) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 << 5) | (h2 >> 27)) & 0xFFFFFFFF; // decorrelate from h1
    }
    String hex(int v) => v.toRadixString(16).padLeft(8, '0');
    return '${hex(h1)}${hex(h2)}';
  }

  /// Starts downloading [url] (or joins the download already running) and
  /// returns a handle with the result and live progress.
  ModelDownload start(String url) {
    final running = _inFlight[url];
    if (running != null) return running;

    final progress =
        ValueNotifier<ModelDownloadProgress>(const ModelDownloadProgress(0));
    final future =
        _fetch(url, progress).whenComplete(() => _inFlight.remove(url));
    final download = ModelDownload._(future, progress);
    _inFlight[url] = download;
    return download;
  }

  /// The local file for [url], downloading it first if needed.
  Future<File> getModel(String url) => start(url).file;

  /// Warms the cache in the background. Never throws; a failure just means
  /// the model is downloaded when it's actually needed.
  void prefetch(String url) {
    unawaited(start(url).file.then<void>((_) {}, onError: (Object _) {}));
  }

  /// Forgets everything stored for [url] (the finished file and any partial
  /// download). Used when the renderer rejects a cached file, so the next
  /// attempt starts clean.
  Future<void> remove(String url) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/${cacheKey(url)}.glb');
      await _deleteQuietly(file);
      await _deleteQuietly(File('${file.path}.part'));
    } catch (_) {
      // Nothing useful to do; the next download overwrites it anyway.
    }
  }

  void dispose() => _client.close();

  // ---------------------------------------------------------------------------

  static Future<Directory> _defaultDirectory() async {
    // Application *support* (not temp): the OS may empty the temp directory
    // at any time, which would throw away a half-finished download.
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/watch_models');
  }

  Future<Directory> _cacheDir() async {
    final dir = await _directoryProvider();
    return dir.create(recursive: true);
  }

  Future<File> _fetch(
    String url,
    ValueNotifier<ModelDownloadProgress> progress,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      throw const ModelDownloadException(
        'This watch has an invalid model link.',
      );
    }

    final dir = await _cacheDir();
    final file = File('${dir.path}/${cacheKey(url)}.glb');

    if (await file.exists()) {
      if (await _isCompleteGlb(file)) {
        try {
          // Mark as recently used so eviction keeps it.
          await file.setLastModified(DateTime.now());
        } catch (_) {}
        final length = await file.length();
        progress.value = ModelDownloadProgress(length, length);
        return file;
      }
      // A damaged cache entry (empty, or not a whole .glb): download it again.
      await _deleteQuietly(file);
    }

    final part = File('${file.path}.part');
    for (var attempt = 1;; attempt++) {
      try {
        await _downloadOnce(uri, part, progress);
        break;
      } on FileSystemException {
        throw const ModelDownloadException(
          'Could not save the model on this device. Is the storage full?',
        );
      } on _TransientDownloadError catch (e) {
        if (attempt >= maxAttempts) throw ModelDownloadException(e.message);
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          throw const ModelDownloadException(
            'The download stalled. Check your connection and try again.',
          );
        }
      } on SocketException {
        if (attempt >= maxAttempts) {
          throw const ModelDownloadException(
            'No connection. Check your internet and try again.',
          );
        }
      } on http.ClientException {
        if (attempt >= maxAttempts) {
          throw const ModelDownloadException(
            'No connection. Check your internet and try again.',
          );
        }
      } on IOException {
        if (attempt >= maxAttempts) {
          throw const ModelDownloadException(
            'Could not download the model. Please try again.',
          );
        }
      }
      // Wait a little, then go round again. The partial file is kept, so the
      // next attempt picks up where this one stopped.
      await Future<void>.delayed(retryDelay * attempt);
    }

    await part.rename(file.path);
    await _evict(dir, keep: file);
    final length = await file.length();
    progress.value = ModelDownloadProgress(length, length);
    return file;
  }

  /// One request. Appends to [part] when the server honours a Range request,
  /// otherwise starts the file over. Returns normally only when [part] holds
  /// a complete, valid .glb.
  Future<void> _downloadOnce(
    Uri uri,
    File part,
    ValueNotifier<ModelDownloadProgress> progress,
  ) async {
    var offset = 0;
    if (await part.exists()) {
      offset = await part.length();
      if (offset > maxBytes) {
        await _deleteQuietly(part);
        offset = 0;
      }
    }

    final request = http.Request('GET', uri)
      // Ask for the raw bytes: byte offsets (and progress) only line up when
      // the body isn't transparently gzip-decoded.
      ..headers['Accept-Encoding'] = 'identity';
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';

    final response = await _client.send(request).timeout(_connectTimeout);

    int? total;
    var append = false;
    switch (response.statusCode) {
      case 200:
        // A full response: either a fresh download, or the server ignored our
        // Range request. Either way, write the file from the start.
        total = response.contentLength;
        break;
      case 206:
        final range = _ContentRange.parse(response.headers['content-range']);
        if (offset == 0 || range == null || range.start != offset) {
          // Not the bytes we asked for. Drop the partial file and start over.
          await _discard(response);
          await _deleteQuietly(part);
          throw const _TransientDownloadError(
            'The download got out of sync. Please try again.',
          );
        }
        final remaining = response.contentLength;
        total = range.total ?? (remaining == null ? null : offset + remaining);
        append = true;
        break;
      case 416:
        // "Range not satisfiable": we asked for bytes past the end. Either the
        // partial file is already complete (the last run stopped right before
        // renaming it) or it is stale.
        await _discard(response);
        final serverTotal =
            _ContentRange.parse(response.headers['content-range'])?.total;
        if (offset > 0 && serverTotal != null && serverTotal == offset) {
          progress.value = ModelDownloadProgress(offset, offset);
          await _verify(part, sizeFromServer: true);
          return;
        }
        await _deleteQuietly(part);
        throw const _TransientDownloadError(
          'The download got out of sync. Please try again.',
        );
      default:
        await _discard(response);
        throw ModelDownloadException(
          'The model could not be downloaded (error ${response.statusCode}).',
        );
    }

    if (total != null && total > maxBytes) {
      await _discard(response);
      await _deleteQuietly(part);
      throw const ModelDownloadException('This watch model is too large.');
    }

    var received = append ? offset : 0;
    progress.value = ModelDownloadProgress(received, total);
    var reported = received;
    // Report roughly once per percent (or every 128 KB when the size is
    // unknown), not once per network chunk.
    final step = (total != null && total > 100) ? total ~/ 100 : 131072;

    var tooLarge = false;
    final sink =
        part.openWrite(mode: append ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        received += chunk.length;
        if (received > maxBytes) {
          tooLarge = true;
          break;
        }
        sink.add(chunk);
        if (received - reported >= step) {
          reported = received;
          progress.value = ModelDownloadProgress(received, total);
        }
      }
      if (!tooLarge) await sink.flush();
    } finally {
      // Always close: whatever was received stays on disk for the next resume.
      try {
        await sink.close();
      } catch (_) {}
    }

    if (tooLarge) {
      await _deleteQuietly(part);
      throw const ModelDownloadException('This watch model is too large.');
    }
    if (total != null && received < total) {
      throw const _TransientDownloadError(
        'The connection dropped before the model finished.',
      );
    }

    progress.value = ModelDownloadProgress(received, total ?? received);
    await _verify(part, sizeFromServer: total != null);
  }

  /// Checks that [part] is a complete .glb. Deletes it and throws when it is
  /// not, or throws a retryable error when it just looks cut off.
  Future<void> _verify(File part, {required bool sizeFromServer}) async {
    final length = await part.length();
    final raf = await part.open();
    final List<int> head;
    try {
      head = await raf.read(12);
    } finally {
      await raf.close();
    }

    if (!isGlbHeader(head)) {
      await _deleteQuietly(part);
      throw const ModelDownloadException(
        'The downloaded file is not a valid .glb model.',
      );
    }

    final declared = glbDeclaredLength(head);
    if (declared != null && length < declared) {
      if (sizeFromServer) {
        // The server sent everything it has, and it is still shorter than the
        // model says it should be: the file was cut off when it was uploaded.
        await _deleteQuietly(part);
        throw const ModelDownloadException(
          'The model file on the server is incomplete.',
        );
      }
      // Unknown size: most likely the connection dropped. Resume.
      throw const _TransientDownloadError(
        'The connection dropped before the model finished.',
      );
    }
  }

  /// True when [file] is a whole .glb: right magic bytes, and at least as
  /// long as the length its own header declares.
  Future<bool> _isCompleteGlb(File file) async {
    try {
      final length = await file.length();
      final raf = await file.open();
      final List<int> head;
      try {
        head = await raf.read(12);
      } finally {
        await raf.close();
      }
      if (head.length < 12 || !isGlbHeader(head)) return false;
      final declared = glbDeclaredLength(head);
      return declared != null && length >= declared;
    } catch (_) {
      return false;
    }
  }

  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _name(File file) => file.uri.pathSegments.last;

  /// Keeps the cache bounded: removes the least recently used models beyond
  /// [maxFiles], and partial downloads that were abandoned long ago.
  Future<void> _evict(Directory dir, {required File keep}) async {
    try {
      final models = <File>[];
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (entity.path.endsWith('.part')) {
          final age = DateTime.now().difference(await entity.lastModified());
          if (age > _stalePartAge) await _deleteQuietly(entity);
        } else if (entity.path.endsWith('.glb') && _name(entity) != _name(keep)) {
          // Compared by file name, not by path string. dir.list() and the
          // path built in _fetch can use different separators on Windows, so
          // the same file would look different and `keep` could be evicted.
          models.add(entity);
        }
      }
      // `keep` always survives, so it takes one of the slots.
      final room = maxFiles - 1;
      if (models.length <= room) return;

      final stamped = <MapEntry<File, DateTime>>[];
      for (final f in models) {
        stamped.add(MapEntry(f, await f.lastModified()));
      }
      stamped.sort((a, b) => a.value.compareTo(b.value));
      for (final entry in stamped.take(models.length - room)) {
        await _deleteQuietly(entry.key);
      }
    } catch (_) {
      // Housekeeping only; never fail a download because of it.
    }
  }
}
