// Tests for the pure parts of lib/services/watch_model_cache.dart.
// (Downloading itself needs path_provider and a network, so it isn't unit-tested.)

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/services/watch_model_cache.dart';

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
}
