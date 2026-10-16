import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../utils/glb_header.dart';

/// Thrown when a watch model can't be downloaded or isn't a usable .glb.
/// [message] is safe to show to the user.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);

  @override
  String toString() => message;
}

/// Downloads watch .glb files once and keeps them in the app's cache folder,
/// so the native AR renderer can load them from a local path.
///
/// - The cache key is derived from the URL. Cloudinary URLs contain a version
///   number, so when a merchant re-uploads a model the URL changes and the old
///   copy is simply never used again (and later evicted).
/// - Files are written to a `.part` file and renamed only after the download
///   completes and the `glTF` header checks out, so a half-downloaded or
///   non-model file is never served.
/// - Concurrent requests for the same URL share one download.
/// - Only the most recent [maxFiles] models are kept.
class WatchModelCache {
  WatchModelCache({
    http.Client? client,
    this.maxFiles = 6,
    this.maxBytes = 25 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// How many models to keep on disk (least recently used are deleted).
  final int maxFiles;

  /// Hard cap on a single model. Cloudinary already limits uploads to 10 MB;
  /// this protects against a bad or hostile URL.
  final int maxBytes;

  static const _connectTimeout = Duration(seconds: 20);
  static const _idleTimeout = Duration(seconds: 20);

  final Map<String, Future<File>> _inFlight = {};

  /// Returns the local file for [url], downloading it first if needed.
  Future<File> getModel(String url) {
    return _inFlight.putIfAbsent(
      url,
      () => _fetch(url).whenComplete(() => _inFlight.remove(url)),
    );
  }

  void dispose() => _client.close();

  Future<File> _fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      throw const ModelDownloadException('This watch has an invalid model link.');
    }

    final dir = await _cacheDir();
    final file = File('${dir.path}/${cacheKey(url)}.glb');

    if (await file.exists() && await file.length() > 0) {
      // Mark as recently used so eviction keeps it.
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return file;
    }

    final part = File('${file.path}.part');
    IOSink? sink;
    try {
      final response = await _client
          .send(http.Request('GET', uri))
          .timeout(_connectTimeout);
      if (response.statusCode != 200) {
        throw ModelDownloadException(
            'The model could not be downloaded (error ${response.statusCode}).');
      }
      final declared = response.contentLength;
      if (declared != null && declared > maxBytes) {
        throw const ModelDownloadException('This watch model is too large.');
      }

      sink = part.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const ModelDownloadException('This watch model is too large.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (!await _hasGlbHeader(part)) {
        throw const ModelDownloadException(
            'The downloaded file is not a valid .glb model.');
      }
      await part.rename(file.path);
    } on TimeoutException {
      throw const ModelDownloadException('The download timed out.');
    } on SocketException {
      throw const ModelDownloadException(
          'No connection. Check your internet and try again.');
    } on http.ClientException {
      throw const ModelDownloadException(
          'No connection. Check your internet and try again.');
    } on FileSystemException {
      throw const ModelDownloadException(
          'Could not save the model on this device.');
    } on IOException {
      // e.g. a TLS handshake failure.
      throw const ModelDownloadException(
          'Could not download the model. Please try again.');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }

    await _evict(dir, keep: file);
    return file;
  }

  Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/watch_models');
    return dir.create(recursive: true);
  }

  Future<bool> _hasGlbHeader(File f) async {
    final raf = await f.open();
    try {
      return isGlbHeader(await raf.read(4));
    } finally {
      await raf.close();
    }
  }

  /// Keeps the [maxFiles] most recently used models (always including [keep])
  /// and removes abandoned partial downloads.
  Future<void> _evict(Directory dir, {required File keep}) async {
    try {
      final models = <File>[];
      final now = DateTime.now();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        if (e.path.endsWith('.part')) {
          // Not ours if it's fresh: another download may be writing it.
          if (now.difference(await e.lastModified()) >
              const Duration(minutes: 10)) {
            await e.delete();
          }
        } else if (e.path.endsWith('.glb')) {
          models.add(e);
        }
      }
      if (models.length <= maxFiles) return;

      final stamps = <String, DateTime>{
        for (final m in models) m.path: await m.lastModified(),
      };
      models.sort((a, b) => stamps[b.path]!.compareTo(stamps[a.path]!));
      for (final old in models.skip(maxFiles)) {
        if (old.path != keep.path) await old.delete();
      }
    } catch (_) {
      // Eviction is best-effort; never fail a model load because of it.
    }
  }

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
}
