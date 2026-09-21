// Tests for the 5-tier match-score system in
// lib/utils/match_score_color.dart. This is the piece that keeps the
// on-screen badge color, the chatbot's plain-language verdict, and how
// honestly the chatbot is instructed to talk about a watch all in sync —
// so the boundary behavior and the low-confidence capping are worth
// pinning down explicitly rather than trusting by eye.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/match_score_color.dart';

void main() {
  group('matchVerdictLabel — tier boundaries (uncapped, signalCount: 3)', () {
    test('80 and above is a Great match', () {
      expect(matchVerdictLabel(80), 'Great match');
      expect(matchVerdictLabel(100), 'Great match');
    });

    test('just under the Great threshold (79) is a Good match', () {
      expect(matchVerdictLabel(79), 'Good match');
    });

    test('60 (Good threshold) is inclusive', () {
      expect(matchVerdictLabel(60), 'Good match');
    });

    test('just under the Good threshold (59) is a Fair match', () {
      expect(matchVerdictLabel(59), 'Fair match');
    });

    test('40 (Fair threshold) is inclusive', () {
      expect(matchVerdictLabel(40), 'Fair match');
    });

    test('just under the Fair threshold (39) is a Weak match', () {
      expect(matchVerdictLabel(39), 'Weak match');
    });

    test('20 (Weak threshold) is inclusive', () {
      expect(matchVerdictLabel(20), 'Weak match');
    });

    test('just under the Weak threshold (19) is a Poor match', () {
      expect(matchVerdictLabel(19), 'Poor match');
    });

    test('0 is a Poor match', () {
      expect(matchVerdictLabel(0), 'Poor match');
    });
  });

  group('matchVerdictLabel — confidence capping', () {
    test('a high raw score built on 2 signals is capped at Good, not Great', () {
      expect(matchVerdictLabel(95, signalCount: 2), 'Good match');
    });

    test('a high raw score built on 1 signal is capped at Fair', () {
      expect(matchVerdictLabel(95, signalCount: 1), 'Fair match');
    });

    test('a high raw score built on 0 signals is still capped at Fair (same as 1)', () {
      expect(matchVerdictLabel(95, signalCount: 0), 'Fair match');
    });

    test('capping never pushes a score UP — an already-low score with few signals stays low', () {
      expect(matchVerdictLabel(10, signalCount: 1), 'Poor match');
    });

    test('full confidence (3 signals) applies no cap at all', () {
      expect(matchVerdictLabel(95, signalCount: 3), 'Great match');
    });
  });

  group('matchScoreColor', () {
    test('tiers map to visually distinct colors, worst to best', () {
      final colors = [
        matchScoreColor(10), // Poor
        matchScoreColor(30), // Weak
        matchScoreColor(50), // Fair
        matchScoreColor(70), // Good
        matchScoreColor(90), // Great
      ];
      // All five should be distinct — this is what keeps the 5-tier
      // scale from visually collapsing into fewer perceived bands.
      expect(colors.toSet().length, 5);
    });

    test('a capped tier uses the SAME color as that tier scored honestly', () {
      // A 95% score with only 1 signal must look identical on screen to
      // an honest 50% (Fair) score — that's the whole point of capping.
      expect(matchScoreColor(95, signalCount: 1), matchScoreColor(50));
    });
  });

  group('matchVerdictGuidance', () {
    test('Great match tier instructs a confident recommendation', () {
      final guidance = matchVerdictGuidance(90);
      expect(guidance, contains('recommend it confidently'));
    });

    test('Poor match tier instructs against recommending it', () {
      final guidance = matchVerdictGuidance(5);
      expect(guidance, contains('do NOT tell the customer'));
    });

    test('a capped score is flagged with an explicit low-confidence note', () {
      final guidance = matchVerdictGuidance(95, signalCount: 1);
      expect(guidance, contains('treat it as this lower tier'));
      expect(guidance, contains('1 signal'));
      // Singular "signal", not "signals" — grammar check for the
      // signalCount == 1 special case.
      expect(guidance, isNot(contains('1 signals')));
    });

    test('an uncapped score carries no low-confidence note', () {
      final guidance = matchVerdictGuidance(90, signalCount: 3);
      expect(guidance, isNot(contains('treat it as this lower tier')));
    });

    test('a capped score with 2 signals uses plural "signals" correctly', () {
      final guidance = matchVerdictGuidance(95, signalCount: 2);
      expect(guidance, contains('2 signals'));
    });
  });
}