// Tests for lib/utils/glb_header.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/glb_header.dart';

void main() {
  group('isGlbHeader', () {
    test('accepts the glTF magic', () {
      expect(isGlbHeader([0x67, 0x6C, 0x54, 0x46]), isTrue);
      expect(isGlbHeader([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]), isTrue);
    });

    test('rejects other content', () {
      // "<!DO" - an HTML error page saved with a .glb name.
      expect(isGlbHeader([0x3C, 0x21, 0x44, 0x4F]), isFalse);
      // A JSON .gltf starts with "{".
      expect(isGlbHeader([0x7B, 0x22, 0x61, 0x73]), isFalse);
    });

    test('rejects empty or truncated files', () {
      expect(isGlbHeader([]), isFalse);
      expect(isGlbHeader([0x67, 0x6C, 0x54]), isFalse);
    });
  });
}
