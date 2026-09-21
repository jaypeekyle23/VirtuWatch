// Tests for scoreFit — the single source of truth for "does this watch
// fit this wrist" (see lib/utils/fit_scoring.dart's doc comment). This is
// the highest-weighted signal in the match score (55%) and the one the
// chatbot explains most often, so getting the ratio bands and boundary
// behavior right here matters more than almost anything else in the app.
//
// All test cases below use wristWidthMm = 100 purely so the lug-to-lug
// value can be read directly as the ratio in mm (e.g. lugToLugMm: 75 ==
// ratio 0.75) — this doesn't test anything specific to a 100mm wrist,
// it's just a convenient scale for hand-checking the math.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/fit_scoring.dart';

void main() {
  group('scoreFit — classic sweet spot (ratio 0.75-0.95)', () {
    test('mid-band ratio scores a perfect 1.0', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 85);
      expect(result.score, 1.0);
      expect(result.note, contains('well-proportioned'));
    });

    test('lower boundary (ratio == 0.75) is inclusive', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 75);
      expect(result.score, 1.0);
      expect(result.note, contains('well-proportioned'));
    });

    test('upper boundary (ratio == 0.95) is inclusive', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 95);
      expect(result.score, 1.0);
      expect(result.note, contains('well-proportioned'));
    });
  });

  group('scoreFit — running small (ratio < 0.75)', () {
    test('snug band (0.60-0.75) scores partial credit, not zero', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 68);
      expect(result.score, greaterThan(0.0));
      expect(result.score, lessThan(1.0));
      expect(result.note, contains('Snug'));
    });

    test('ratio exactly at the small/snug boundary (0.60) reads as snug, not small', () {
      // The small-vs-snug note boundary is a strict "<", so 0.60 itself
      // still falls on the "Snug, clean fit" side, not "Runs small".
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 60);
      expect(result.note, contains('Snug'));
      expect(result.note, isNot(contains('small')));
    });

    test('just below the boundary (ratio 0.59) reads as running small', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 59);
      expect(result.note, contains('small'));
    });

    test('score reaches exactly 0 once the full tolerance is used up', () {
      // classicMin (0.75) - toleranceBelow (0.35) = 0.40 exactly.
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 40);
      expect(result.score, closeTo(0.0, 0.0001));
    });

    test('score clamps at 0 rather than going negative for extreme ratios', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 20);
      expect(result.score, 0.0);
      expect(result.note, contains('small'));
    });
  });

  group('scoreFit — running large (ratio > 0.95)', () {
    test('bold band (0.95-1.05) scores partial credit, not zero', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 100);
      expect(result.score, greaterThan(0.0));
      expect(result.score, lessThan(1.0));
      expect(result.note, contains('Bold'));
    });

    test('upper bold boundary (ratio == 1.05) is inclusive', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 105);
      expect(result.note, contains('Bold'));
    });

    test('slight overhang band (1.05-1.20) notes "a bit large", not "too large"', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 112);
      expect(result.note, contains('a bit large'));
      expect(result.note, isNot(contains('too large')));
    });

    test('score reaches exactly 0 once the full tolerance is used up', () {
      // classicMax (0.95) + toleranceAbove (0.25) = 1.20 exactly.
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 120);
      expect(result.score, closeTo(0.0, 0.0001));
    });

    test('past the overhang cutoff (ratio > 1.20), note escalates to "too large"', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 121);
      expect(result.note, contains('too large'));
    });

    test('score clamps at 0 rather than going negative for extreme ratios', () {
      final result = scoreFit(wristWidthMm: 100, lugToLugMm: 200);
      expect(result.score, 0.0);
      expect(result.note, contains('too large'));
    });
  });

  group('scoreFit — note mentions the actual wrist size', () {
    test('wrist width is rounded to the nearest whole mm in the note', () {
      final result = scoreFit(wristWidthMm: 165.4, lugToLugMm: 140);
      expect(result.note, contains('165mm'));
    });
  });
}