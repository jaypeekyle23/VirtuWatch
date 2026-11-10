// UT-02: a customer's budget range is applied only as an affordability label
// on a watch's price. It must never change the weighted match score.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/budget_status.dart';
import 'package:virtuwatch/utils/recommendation_scoring.dart';

void main() {
  group('budgetStatus', () {
    const min = 10000.0;
    const max = 50000.0;

    test('a price inside the range is within budget', () {
      expect(budgetStatus(price: 30000, budgetMin: min, budgetMax: max),
          BudgetStatus.within);
    });

    test('a price above budgetMax is over budget', () {
      expect(budgetStatus(price: 50001, budgetMin: min, budgetMax: max),
          BudgetStatus.over);
    });

    test('a price below budgetMin is under budget', () {
      expect(budgetStatus(price: 9999, budgetMin: min, budgetMax: max),
          BudgetStatus.under);
    });

    test('both range edges are inclusive (within, not over/under)', () {
      expect(budgetStatus(price: 10000, budgetMin: min, budgetMax: max),
          BudgetStatus.within);
      expect(budgetStatus(price: 50000, budgetMin: min, budgetMax: max),
          BudgetStatus.within);
    });

    test('the app defaults (0 to 50000) flag only watches above 50000', () {
      expect(budgetStatus(price: 38998, budgetMin: 0, budgetMax: 50000),
          BudgetStatus.within);
      expect(budgetStatus(price: 62000, budgetMin: 0, budgetMax: 50000),
          BudgetStatus.over);
    });
  });

  group('amountOverBudget', () {
    test('returns how far the price is above budgetMax', () {
      expect(amountOverBudget(price: 62000, budgetMax: 50000), 12000);
    });

    test('is 0 at or under budgetMax, never negative', () {
      expect(amountOverBudget(price: 50000, budgetMax: 50000), 0);
      expect(amountOverBudget(price: 20000, budgetMax: 50000), 0);
    });
  });

  group('budget does not affect the weighted score', () {
    ScoringResult score(num price) => scoreWatchAgainstProfile(
          watchData: {
            'price': price,
            'lugToLugMm': 85,
            'styleCategory': 'Minimalist',
            'colorHexes': const ['#000000'],
          },
          wristWidthMm: 100,
          stylePreferences: const ['Minimalist'],
          outfitColors: const [
            {'hex': '#000000', 'percentage': 100.0},
          ],
        );

    test('an affordable and a far-over-budget watch get identical scores', () {
      final cheap = score(5000);
      final pricey = score(900000);

      expect(pricey.combinedScore, cheap.combinedScore);
      expect(pricey.fitScore, cheap.fitScore);
      expect(pricey.styleScore, cheap.styleScore);
      expect(pricey.colorScore, cheap.colorScore);
    });

    test('the over-budget watch is still labelled over budget', () {
      expect(budgetStatus(price: 900000, budgetMin: 0, budgetMax: 50000),
          BudgetStatus.over);
      expect(score(900000).combinedScore, closeTo(1.0, 0.0001));
    });
  });
}
