// Tests for lib/services/watch_model_cache.dart.
//
// Downloads are tested against a fake HTTP server (package:http's MockClient)
// and a temporary directory, so no network or path_provider is needed.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:virtuwatch/services/watch_model_cache.dart';

/// A valid-looking .glb of exactly [length] bytes: the "glTF" magic, version 2
/// and the total length in the header, then filler.
Uint8List fakeGlb(int length) {
  final bytes = Uint8List(length);
  bytes.setAll(0, [0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]);
  ByteData.view(bytes.buffer).setUint32(8, length, Endian.little);
  for (var i = 12; i < length; i++) {
    bytes[i] = i % 251;
  }
  return bytes;
}

/// A stand-in for the model host. Serves [body], optionally honours Range
/// requests, and can cut the connection part-way through.
class FakeServer {
  FakeServer(this.body, {this.supportsRange = true, this.chunk = 1000});

  final Uint8List body;
  final bool supportsRange;
  final int chunk;

  /// Every request received, in order.
  final requests = <http.BaseRequest>[];

  /// Cut the connection after this many body bytes of the next response
  /// (every response when [dropEveryTime] is set).
  int? dropAfter;
  bool dropEveryTime = false;

  http.Client client() => MockClient.streaming((request, bodyStream) async {
        requests.add(request);

        var start = 0;
        var status = 200;
        final headers = <String, String>{};
        final range = request.headers['Range'];
        if (range != null && supportsRange) {
          start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          if (start >= body.length) {
            return http.StreamedResponse(
              Stream<List<int>>.empty(),
              416,
              headers: {'content-range': 'bytes */${body.length}'},
            );
          }
          status = 206;
          headers['content-range'] =
              'bytes $start-${body.length - 1}/${body.length}';
        }

        final slice = body.sublist(start);
        final drop = dropAfter;
        if (!dropEveryTime) dropAfter = null;

        Stream<List<int>> stream() async* {
          var sent = 0;
          for (var i = 0; i < slice.length; i += chunk) {
            if (drop != null && sent >= drop) {
              throw const SocketException('connection reset');
            }
            final end = math.min(i + chunk, slice.length);
            yield slice.sublist(i, end);
            sent = end;
          }
        }

        return http.StreamedResponse(
          stream(),
          status,
          contentLength: slice.length,
          headers: headers,
        );
      });
}

void main() {
  group('WatchModelCache.cacheKey', () {
    const url = 'https://res.cloudinary.com/demo/raw/upload/v1700000000/a.glb';

    test('is stable: same URL, same key', () {
      expect(WatchModelCache.cacheKey(url), WatchModelCache.cacheKey(url));
    });

    test('is a 16-char lowercase hex string (safe as a file name)', () {
      expect(WatchModelCache.cacheKey(url), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('a re-upload (new version in the URL) gets a new key', () {
      final reuploaded = url.replaceFirst('v1700000000', 'v1800000000');
      expect(WatchModelCache.cacheKey(reuploaded),
          isNot(WatchModelCache.cacheKey(url)));
    });

    test('different URLs get different keys', () {
      final keys = {
        for (var i = 0; i < 500; i++)
          WatchModelCache.cacheKey('https://example.com/models/$i.glb'),
      };
      expect(keys.length, 500);
    });
  });

  group('WatchModelCache downloads', () {
    const url = 'https://res.cloudinary.com/demo/raw/upload/v1/watch.glb';
    late Directory tmp;

    File partFor(String u) =>
        File('${tmp.path}/${WatchModelCache.cacheKey(u)}.glb.part');
    File fileFor(String u) =>
        File('${tmp.path}/${WatchModelCache.cacheKey(u)}.glb');

    WatchModelCache makeCache(
      http.Client client, {
      int maxAttempts = 4,
      int maxFiles = 12,
    }) =>
        WatchModelCache(
          client: client,
          directoryProvider: () async => tmp,
          retryDelay: Duration.zero,
          maxAttempts: maxAttempts,
          maxFiles: maxFiles,
        );

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('watch_model_cache_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('downloads, reports rising progress, then serves from the cache',
        () async {
      final body = fakeGlb(5000);
      final server = FakeServer(body);
      final cache = makeCache(server.client());

      final download = cache.start(url);
      final seen = <double>[];
      download.progress.addListener(() {
        final f = download.progress.value.fraction;
        if (f != null) seen.add(f);
      });
      final file = await download.file;

      expect(await file.readAsBytes(), body);
      expect(seen, isNotEmpty);
      expect(seen.last, 1.0);
      expect(seen, orderedEquals([...seen]..sort()));

      final again = await cache.getModel(url);
      expect(again.path, file.path);
      expect(server.requests, hasLength(1)); // second call never hit the network
    });

    test('everyone asking for the same URL shares one download', () async {
      final server = FakeServer(fakeGlb(4000));
      final cache = makeCache(server.client());

      final a = cache.start(url);
      final b = cache.start(url);
      expect(identical(a, b), isTrue);
      await a.file;
      expect(server.requests, hasLength(1));
    });

    test('resumes a partial download instead of starting over', () async {
      final body = fakeGlb(6000);
      final server = FakeServer(body);
      final cache = makeCache(server.client());
      await partFor(url).writeAsBytes(body.sublist(0, 2500));

      final file = await cache.getModel(url);

      expect(await file.readAsBytes(), body);
      expect(server.requests.single.headers['Range'], 'bytes=2500-');
    });

    test('starts over cleanly when the server ignores Range requests',
        () async {
      final body = fakeGlb(6000);
      final server = FakeServer(body, supportsRange: false);
      final cache = makeCache(server.client());
      await partFor(url).writeAsBytes(body.sublist(0, 2500));

      final file = await cache.getModel(url);

      // The 2500 bytes already on disk must not be duplicated in the result.
      expect(await file.readAsBytes(), body);
    });

    test('a dropped connection is retried and resumes where it stopped',
        () async {
      final body = fakeGlb(6000);
      final server = FakeServer(body)..dropAfter = 3000;
      final cache = makeCache(server.client());

      final file = await cache.getModel(url);

      expect(await file.readAsBytes(), body);
      expect(server.requests, hasLength(2));
      expect(server.requests[1].headers['Range'], 'bytes=3000-');
    });

    test('after giving up, the partial file is kept and a later call resumes it',
        () async {
      final body = fakeGlb(6000);
      final server = FakeServer(body)
        ..dropAfter = 1000
        ..dropEveryTime = true;
      final cache = makeCache(server.client(), maxAttempts: 4);

      await expectLater(
        cache.getModel(url),
        throwsA(isA<ModelDownloadException>().having(
            (e) => e.message, 'message', contains('No connection'))),
      );
      // 4 attempts x 1000 bytes, each one resuming the last.
      expect(await partFor(url).length(), 4000);
      expect(fileFor(url).existsSync(), isFalse);

      // Connection is back (think: the user reopens the AR screen). Clear
      // dropAfter too, or the next response is still cut off once.
      server
        ..dropEveryTime = false
        ..dropAfter = null;
      final file = await cache.getModel(url);

      expect(await file.readAsBytes(), body);
      expect(server.requests.last.headers['Range'], 'bytes=4000-');
    });

    test('a partial file that is already complete is accepted (HTTP 416)',
        () async {
      final body = fakeGlb(6000);
      final server = FakeServer(body);
      final cache = makeCache(server.client());
      await partFor(url).writeAsBytes(body);

      final file = await cache.getModel(url);

      expect(await file.readAsBytes(), body);
      expect(server.requests.single.headers['Range'], 'bytes=6000-');
    });

    test('rejects a non-glb response (e.g. an HTML error page) and deletes it',
        () async {
      final html = Uint8List.fromList(
          utf8.encode('<!DOCTYPE html><html><body>Not found</body></html>'));
      final cache = makeCache(FakeServer(html).client());

      await expectLater(
        cache.getModel(url),
        throwsA(isA<ModelDownloadException>().having(
            (e) => e.message, 'message', contains('not a valid .glb'))),
      );
      expect(partFor(url).existsSync(), isFalse);
      expect(fileFor(url).existsSync(), isFalse);
    });

    test('rejects a glb that is shorter than its own header says', () async {
      // Header declares 6000 bytes, but the file on the server has only 4000.
      final cut = fakeGlb(6000).sublist(0, 4000);
      final cache = makeCache(FakeServer(cut).client());

      await expectLater(
        cache.getModel(url),
        throwsA(isA<ModelDownloadException>().having(
            (e) => e.message, 'message', contains('incomplete'))),
      );
      expect(fileFor(url).existsSync(), isFalse);
    });

    test('HTTP errors become a readable message', () async {
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 404));
      final cache = makeCache(client);

      await expectLater(
        cache.getModel(url),
        throwsA(isA<ModelDownloadException>()
            .having((e) => e.message, 'message', contains('404'))),
      );
    });

    test('rejects a model link that is not http(s)', () async {
      final cache = makeCache(FakeServer(fakeGlb(2000)).client());
      await expectLater(
        cache.getModel('not a url'),
        throwsA(isA<ModelDownloadException>()),
      );
    });

    test('a damaged cached file is downloaded again', () async {
      final body = fakeGlb(5000);
      final server = FakeServer(body);
      final cache = makeCache(server.client());

      final first = await cache.getModel(url);
      await first.writeAsBytes([1, 2, 3]); // corrupt it on disk
      final second = await cache.getModel(url);

      expect(await second.readAsBytes(), body);
      expect(server.requests, hasLength(2));
    });

    test('prefetch never throws, even when the download fails', () async {
      final client = MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream<List<int>>.empty(), 500));
      final cache = makeCache(client);

      expect(() => cache.prefetch(url), returnsNormally);
      await pumpEventQueue(); // lets the failed download finish unobserved
    });

    test('remove() forgets both the file and any partial download', () async {
      final body = fakeGlb(5000);
      final cache = makeCache(FakeServer(body).client());
      await cache.getModel(url);
      await partFor(url).writeAsBytes([1, 2, 3]);

      await cache.remove(url);

      expect(fileFor(url).existsSync(), isFalse);
      expect(partFor(url).existsSync(), isFalse);
    });

    test('keeps only maxFiles models, dropping the least recently used',
        () async {
      final server = FakeServer(fakeGlb(3000));
      final cache = makeCache(server.client(), maxFiles: 2);
      const a = 'https://example.com/a.glb';
      const b = 'https://example.com/b.glb';
      const c = 'https://example.com/c.glb';

      final fa = await cache.getModel(a);
      await fa.setLastModified(DateTime.now().subtract(const Duration(minutes: 3)));
      final fb = await cache.getModel(b);
      await fb.setLastModified(DateTime.now().subtract(const Duration(minutes: 2)));
      final fc = await cache.getModel(c);

      expect(fa.existsSync(), isFalse); // oldest goes
      expect(fb.existsSync(), isTrue);
      expect(fc.existsSync(), isTrue); // the new one always stays
    });
  });

  group('ModelDownloadProgress', () {
    test('fraction is received / total, clamped to 0..1', () {
      expect(const ModelDownloadProgress(25, 100).fraction, 0.25);
      expect(const ModelDownloadProgress(150, 100).fraction, 1.0);
    });

    test('fraction is null when the total is unknown or zero', () {
      expect(const ModelDownloadProgress(25).fraction, isNull);
      expect(const ModelDownloadProgress(0, 0).fraction, isNull);
    });
  });
}
