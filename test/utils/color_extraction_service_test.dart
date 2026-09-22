// Tests for colorToHex in lib/services/color_extraction_service.dart —
// converts an extracted outfit color into the '#RRGGBB' string format
// saved via AuthService.saveOutfitColors and later scored against in
// RecommendationService. Only this pure conversion function is under
// test here; the ML Kit segmentation pipeline itself needs a real device
// and isn't covered.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/services/color_extraction_service.dart';

void main() {
  group('colorToHex', () {
    test('pure black', () {
      expect(colorToHex(const Color(0xFF000000)), '#000000');
    });

    test('pure white', () {
      expect(colorToHex(const Color(0xFFFFFFFF)), '#FFFFFF');
    });

    test('an arbitrary color round-trips through its channel values', () {
      // 0xFF6F1011 -> alpha FF, r 6F, g 10, b 11.
      expect(colorToHex(const Color(0xFF6F1011)), '#6F1011');
    });

    test('low channel values are left-padded with a leading zero', () {
      // Without padding, r=0x05 would render as "5" instead of "05" and
      // break the fixed 6-character '#RRGGBB' format downstream code
      // (e.g. hexToRgb) relies on.
      expect(colorToHex(const Color(0xFF050A0F)), '#050A0F');
    });

    test('output is always uppercase', () {
      final hex = colorToHex(const Color(0xFFab34ef));
      expect(hex, hex.toUpperCase());
    });

    test('output always has exactly 7 characters (# plus 6 hex digits)', () {
      expect(colorToHex(const Color(0xFF123456)).length, 7);
    });
  });
}