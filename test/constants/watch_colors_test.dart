// Tests for lib/constants/watch_colors.dart, in particular
// describeHexColor — this is what the chatbot now relies on to describe
// any custom (non-palette) watch color in plain language instead of
// reciting a raw hex code. The burgundy and teal cases below are the
// exact hex values from a real conversation with the app's chatbot,
// pinned here so a future change to the hue math can't silently regress
// the specific case that motivated writing this function in the first
// place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/constants/watch_colors.dart';

void main() {
  group('hexToRgb', () {
    test('parses a standard 6-digit hex string', () {
      expect(hexToRgb('#FFFFFF'), (255, 255, 255));
      expect(hexToRgb('#000000'), (0, 0, 0));
      expect(hexToRgb('#FF0000'), (255, 0, 0));
    });

    test('is case-insensitive', () {
      expect(hexToRgb('#c0c0c0'), hexToRgb('#C0C0C0'));
    });

    test('falls back to mid-gray for a malformed string rather than throwing', () {
      expect(hexToRgb('not-a-color'), (128, 128, 128));
      expect(hexToRgb('#12'), (128, 128, 128));
    });
  });

  group('paletteNameForHex', () {
    test('matches every fixed palette swatch by its exact hex', () {
      for (final option in watchColorPalette) {
        expect(paletteNameForHex(option.hex), option.name);
      }
    });

    test('is case-insensitive', () {
      expect(paletteNameForHex('#c0c0c0'), 'Silver');
    });

    test('returns null for a hex outside the fixed palette', () {
      // A custom color from the wheel picker — this is exactly the case
      // describeHexColor exists to handle instead.
      expect(paletteNameForHex('#6F1011'), isNull);
    });
  });

  group('describeHexColor — neutral colors', () {
    test('pure black', () => expect(describeHexColor('#000000'), 'black'));
    test('pure white', () => expect(describeHexColor('#FFFFFF'), 'white'));
    test('mid gray', () => expect(describeHexColor('#808080'), 'gray'));
  });

  group('describeHexColor — real cases from a live conversation', () {
    // From the Presage Cocktail Time Negroni SRPE41 — the chatbot
    // originally had no way to describe this beyond reciting the raw
    // hex, which is what motivated adding this function.
    test('#6F1011 (dark, muted red) reads as burgundy', () {
      expect(describeHexColor('#6F1011'), 'burgundy');
    });

    // From the Seiko x Poorboy Ref. SRPM17.
    test('#4CC0BB (bright cyan-green) reads as teal', () {
      expect(describeHexColor('#4CC0BB'), 'teal');
    });
  });

  group('describeHexColor — hue bucketing at saturated, mid-lightness values', () {
    test('pure red', () => expect(describeHexColor('#FF0000'), 'red'));
    test('pure green', () => expect(describeHexColor('#00FF00'), 'green'));
    test('pure blue', () => expect(describeHexColor('#0000FF'), 'blue'));
  });

  group('describeHexColor — never returns a raw hex code', () {
    test('every palette color describes as a real word, not a hex string', () {
      for (final option in watchColorPalette) {
        final description = describeHexColor(option.hex);
        expect(description, isNot(contains('#')));
        expect(description, isNotEmpty);
      }
    });
  });

  group('nearestPaletteColor', () {
    test('an exact palette color matches itself', () {
      expect(nearestPaletteColor(const Color(0xFFC0C0C0)).name, 'Silver');
      expect(nearestPaletteColor(const Color(0xFF1A1A1A)).name, 'Black');
      expect(nearestPaletteColor(const Color(0xFFD4AF37)).name, 'Gold');
    });

    test('a near-miss color snaps to the closest palette swatch', () {
      // One shade off pure white — should still snap to White, not Silver.
      expect(nearestPaletteColor(const Color(0xFFF8F8F8)).name, 'White');
    });
  });
}