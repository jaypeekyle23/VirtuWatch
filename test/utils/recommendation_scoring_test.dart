// Tests for scoreWatchAgainstProfile — the actual match-score algorithm
// behind "For You" recommendations (see recommendation_scoring.dart's doc
// comment). This is the single most important piece of scoring logic in
// the app: it decides both the ranking customers see and the numbers the
// chat assistant is told never to contradict, so the missing-signal
// re-normalization and the color-blending math are worth pinning down
// explicitly rather than trusting by eye.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/recommendation_scoring.dart';

void main() {
  group('scoreWatchAgainstProfile — fit signal', () {
    test('all three signals present, all perfect, combinedScore is 1.0', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {
          'lugToLugMm': 85, // ratio 0.85 vs a 100mm wrist — classic sweet spot
          'styleCategory': 'Minimalist',
          'colorHexes': ['#000000'],
        },
        wristWidthMm: 100,
        stylePreferences: const ['Minimalist'],
        outfitColors: const [
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );

      expect(result.fitScore, 1.0);
      expect(result.styleScore, 1.0);
      expect(result.colorScore, 1.0);
      expect(result.combinedScore, closeTo(1.0, 0.0001));
      expect(result.colorNote, 'Matches your outfit colors');
    });

    test('missing wrist measurement leaves fitScore null with the right note', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'lugToLugMm': 85},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [],
      );

      expect(result.fitScore, isNull);
      expect(result.fitNote, 'Add your wrist measurement for fit-based ranking');
    });

    test('watch with no lugToLugMm on file leaves fitScore null with the right note', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {},
        wristWidthMm: 165,
        stylePreferences: const [],
        outfitColors: const [],
      );

      expect(result.fitScore, isNull);
      expect(result.fitNote, 'Fit info unavailable for this watch');
    });
  });

  group('scoreWatchAgainstProfile — style signal', () {
    test('no style preferences saved leaves styleScore null (not zero)', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'styleCategory': 'Sporty'},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [],
      );
      expect(result.styleScore, isNull);
    });

    test('watch with no styleCategory on file leaves styleScore null even with preferences set', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {},
        wristWidthMm: null,
        stylePreferences: const ['Sporty'],
        outfitColors: const [],
      );
      expect(result.styleScore, isNull);
    });

    test('matching style scores exactly 1.0', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'styleCategory': 'Formal'},
        wristWidthMm: null,
        stylePreferences: const ['Sporty', 'Formal'],
        outfitColors: const [],
      );
      expect(result.styleScore, 1.0);
    });

    test('non-matching style scores exactly 0.0 (not null)', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'styleCategory': 'Formal'},
        wristWidthMm: null,
        stylePreferences: const ['Sporty'],
        outfitColors: const [],
      );
      expect(result.styleScore, 0.0);
    });

    test('style match is case-insensitive', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'styleCategory': 'Minimalist'},
        wristWidthMm: null,
        stylePreferences: const ['minimalist'],
        outfitColors: const [],
      );
      expect(result.styleScore, 1.0);
    });
  });

  group('scoreWatchAgainstProfile — color signal, single color', () {
    test('no outfit scan leaves colorScore null', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [],
      );
      expect(result.colorScore, isNull);
      expect(result.colorNote, isNull);
    });

    test('watch with no color on file leaves colorScore null even with an outfit scan', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );
      expect(result.colorScore, isNull);
    });

    test('identical watch and outfit color scores exactly 1.0 with a positive note', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );
      expect(result.colorScore, 1.0);
      expect(result.colorNote, 'Matches your outfit colors');
    });

    test('opposite colors (black vs white) score exactly 0.0 with a negative note', () {
      // Black vs white is the maximum possible RGB distance, i.e. exactly
      // maxRgbDistance — similarity clamps to 0.0, not a small negative.
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#FFFFFF', 'percentage': 100.0},
        ],
      );
      expect(result.colorScore, closeTo(0.0, 0.0001));
      expect(result.colorNote, "Doesn't match your outfit colors");
    });

    test('a middling color distance lands in the no-note zone (0.3, 0.65)', () {
      // Single-channel distance of 200 vs black — deliberately picked so
      // the RGB distance is exact (just one channel differs) and the
      // resulting similarity (1 - 200/441.67 ≈ 0.547) sits clearly
      // between the "matches" and "doesn't match" thresholds.
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#C80000', 'percentage': 100.0}, // rgb(200, 0, 0)
        ],
      );
      expect(result.colorScore, closeTo(0.5471, 0.001));
      expect(result.colorNote, isNull);
    });

    test('legacy single-colorHex watches (no colorHexes array) still score', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHex': '#FFFFFF'}, // pre-multi-color field
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#FFFFFF', 'percentage': 100.0},
        ],
      );
      expect(result.colorScore, 1.0);
    });

    test('outfit color entries with null/zero percentage are ignored, not crashed on', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#FFFFFF', 'percentage': 0.0}, // ignored: zero weight
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );
      // Only the valid #000000 entry should count, giving a perfect match
      // rather than being dragged down by the zero-weight white entry.
      expect(result.colorScore, 1.0);
    });

    test('outfit color entry missing a hex is skipped without crashing', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'colorHexes': ['#000000']},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'percentage': 100.0}, // malformed: no hex
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );
      expect(result.colorScore, 1.0);
    });
  });

  group('scoreWatchAgainstProfile — color signal, multi-color blending', () {
    test('a secondary color can only nudge the score, never dominate it', () {
      // Primary (#000000, prominence 1.0) matches the outfit perfectly.
      // Secondary (#FF0000, prominence 0.6) is a poor match. A naive
      // unweighted average of 1.0 and ~0.4226 would land at ~0.71; the
      // prominence weighting should pull it higher than that, closer to
      // the primary color's score, since the secondary counts for less.
      final result = scoreWatchAgainstProfile(
        watchData: const {
          'colorHexes': ['#000000', '#FF0000'],
        },
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#000000', 'percentage': 100.0},
        ],
      );

      // (1.0*1.0 + 0.4226*0.6) / (1.0 + 0.6) ≈ 0.7835
      expect(result.colorScore, closeTo(0.7835, 0.001));
      final naiveUnweightedAverage = (1.0 + 0.4226) / 2;
      expect(result.colorScore!, greaterThan(naiveUnweightedAverage));
    });

    test('a single-color watch collapses to exactly the old single-color formula', () {
      // Sanity check that multi-color support didn't change scoring for
      // the common (single-color) case — this should equal the
      // single-color test above exactly.
      final singleColor = scoreWatchAgainstProfile(
        watchData: const {
          'colorHexes': ['#000000'],
        },
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [
          {'hex': '#C80000', 'percentage': 100.0},
        ],
      );
      expect(singleColor.colorScore, closeTo(0.5471, 0.001));
    });
  });

  group('scoreWatchAgainstProfile — missing-signal re-normalization', () {
    test('only fitScore available: combinedScore equals fitScore exactly', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'lugToLugMm': 85}, // perfect fit ratio
        wristWidthMm: 100,
        stylePreferences: const [],
        outfitColors: const [],
      );
      expect(result.styleScore, isNull);
      expect(result.colorScore, isNull);
      expect(result.combinedScore, closeTo(result.fitScore!, 0.0001));
    });

    test('fit + style available (no color): re-weighted to just those two', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {'lugToLugMm': 85, 'styleCategory': 'Sporty'},
        wristWidthMm: 100,
        stylePreferences: const ['Sporty'],
        outfitColors: const [],
      );
      // fit=1.0 (weight .55), style=1.0 (weight .30), color absent.
      // (1.0*.55 + 1.0*.30) / (.55+.30) = 1.0
      expect(result.combinedScore, closeTo(1.0, 0.0001));
    });

    test('a genuinely mixed case re-normalizes correctly (fit + style, differing scores)', () {
      final result = scoreWatchAgainstProfile(
        // ratio 200/100 = 2.0 — way past the overhang cutoff, fitScore 0.0
        watchData: const {'lugToLugMm': 200, 'styleCategory': 'Sporty'},
        wristWidthMm: 100,
        stylePreferences: const ['Sporty'], // matches -> styleScore 1.0
        outfitColors: const [],
      );
      // (0.0*.55 + 1.0*.30) / (.55+.30) = .30/.85 = 0.352941...
      expect(result.combinedScore, closeTo(0.352941, 0.0001));
    });

    test('every signal missing defaults to a neutral 0.5, not 0.0', () {
      final result = scoreWatchAgainstProfile(
        watchData: const {},
        wristWidthMm: null,
        stylePreferences: const [],
        outfitColors: const [],
      );
      expect(result.fitScore, isNull);
      expect(result.styleScore, isNull);
      expect(result.colorScore, isNull);
      expect(result.combinedScore, 0.5);
    });
  });
}