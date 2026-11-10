// UT-03: converting an on-screen pixel distance to real millimeters after
// screen calibration against a known reference object.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/wrist_math.dart';

void main() {
  group('mmPerPixelFromReference (screen calibration)', () {
    test('a card (53.98 mm) matched at 250 px gives 0.21592 mm per pixel', () {
      final ratio =
          mmPerPixelFromReference(referenceMm: cardReferenceMm, offsetPx: 250);
      expect(ratio, closeTo(0.21592, 0.00001));
    });

    test('a PHP 20 coin (30 mm) matched at 140 px gives ~0.2143 mm per pixel',
        () {
      final ratio = mmPerPixelFromReference(
          referenceMm: php20CoinReferenceMm, offsetPx: 140);
      expect(ratio, closeTo(0.21429, 0.00001));
    });

    test('a zero or negative pixel offset is rejected', () {
      expect(
          () => mmPerPixelFromReference(referenceMm: 53.98, offsetPx: 0),
          throwsArgumentError);
      expect(
          () => mmPerPixelFromReference(referenceMm: 53.98, offsetPx: -5),
          throwsArgumentError);
    });

    test('a zero or negative reference size is rejected', () {
      expect(() => mmPerPixelFromReference(referenceMm: 0, offsetPx: 250),
          throwsArgumentError);
    });
  });

  group('pxToMm / mmToPx (wrist measurement)', () {
    test('calibrate on a card, then measure: wristWidthMm matches the '
        'expected value', () {
      // Calibration: card edge lined up at 250 px.
      final mmPerPx =
          mmPerPixelFromReference(referenceMm: cardReferenceMm, offsetPx: 250);
      // The user then lines the second guide up with their wrist at 280 px.
      expect(pxToMm(280, mmPerPx), closeTo(60.45, 0.01));
    });

    test('measuring the reference itself returns the reference size', () {
      final mmPerPx =
          mmPerPixelFromReference(referenceMm: cardReferenceMm, offsetPx: 250);
      expect(pxToMm(250, mmPerPx), closeTo(cardReferenceMm, 0.0001));
    });

    test('mmToPx is the inverse of pxToMm', () {
      const mmPerPx = 0.2;
      expect(pxToMm(mmToPx(65, mmPerPx), mmPerPx), closeTo(65, 0.0001));
      expect(mmToPx(60, 0.2), closeTo(300, 0.0001));
    });

    test('0 px is 0 mm', () {
      expect(pxToMm(0, 0.2), 0);
    });
  });

  group('isPlausibleWristMm', () {
    test('accepts values inside 30-120 mm, including both edges', () {
      expect(isPlausibleWristMm(30), isTrue);
      expect(isPlausibleWristMm(60.5), isTrue);
      expect(isPlausibleWristMm(120), isTrue);
    });

    test('rejects values outside the range', () {
      expect(isPlausibleWristMm(29.9), isFalse);
      expect(isPlausibleWristMm(120.1), isFalse);
      expect(isPlausibleWristMm(0), isFalse);
    });
  });
}
