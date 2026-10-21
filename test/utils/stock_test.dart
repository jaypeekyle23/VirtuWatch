// Tests for lib/utils/stock.dart, the single rule for low and out of stock.
// Plain maps, no Firebase needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/stock.dart';

void main() {
  group('stockStatus', () {
    test('a missing stock field is untracked, not out of stock', () {
      expect(stockStatus({}), StockStatus.untracked);
      expect(stockOf({}), isNull);
    });

    test('a null or non-number stock is untracked', () {
      expect(stockStatus({'stock': null}), StockStatus.untracked);
      expect(stockStatus({'stock': 'five'}), StockStatus.untracked);
    });

    test('zero is out of stock', () {
      expect(stockStatus({'stock': 0}), StockStatus.out);
      expect(isOutOfStock({'stock': 0}), isTrue);
    });

    test('a negative number is read as zero', () {
      expect(stockOf({'stock': -2}), 0);
      expect(stockStatus({'stock': -2}), StockStatus.out);
    });

    test('1 up to the threshold is low', () {
      expect(stockStatus({'stock': 1}), StockStatus.low);
      expect(stockStatus({'stock': lowStockThreshold}), StockStatus.low);
      expect(isLowStock({'stock': lowStockThreshold}), isTrue);
    });

    test('one above the threshold is in stock', () {
      expect(stockStatus({'stock': lowStockThreshold + 1}), StockStatus.inStock);
      expect(isLowStock({'stock': lowStockThreshold + 1}), isFalse);
    });

    test('a whole number stored as a double still works', () {
      expect(stockOf({'stock': 5.0}), 5);
    });
  });

  group('isInStock', () {
    test('true for in stock and low, false for out and untracked', () {
      expect(isInStock({'stock': 50}), isTrue);
      expect(isInStock({'stock': 1}), isTrue);
      expect(isInStock({'stock': 0}), isFalse);
      expect(isInStock({}), isFalse);
    });
  });

  group('needsStockAttention', () {
    test('true for low and out, false for in stock and untracked', () {
      expect(needsStockAttention({'stock': 0}), isTrue);
      expect(needsStockAttention({'stock': 2}), isTrue);
      expect(needsStockAttention({'stock': 20}), isFalse);
      expect(needsStockAttention({}), isFalse);
    });
  });

  group('labels', () {
    test('customers see the real count when in stock', () {
      expect(customerStockLabel({'stock': 50}), '50 in stock');
    });

    test('customers see the count when low, with correct grammar', () {
      expect(customerStockLabel({'stock': 1}), 'Only 1 left');
      expect(customerStockLabel({'stock': 3}), 'Only 3 left');
    });

    test('customers see out of stock, and nothing when untracked', () {
      expect(customerStockLabel({'stock': 0}), 'Out of stock');
      expect(customerStockLabel({}), isNull);
    });

    test('merchants see the real number', () {
      expect(merchantStockLabel({'stock': 50}), '50 in stock');
      expect(merchantStockLabel({'stock': 2}), 'Low: 2 left');
      expect(merchantStockLabel({'stock': 0}), 'Out of stock');
      expect(merchantStockLabel({}), isNull);
    });

    test('the chatbot line carries the same count customers see', () {
      expect(stockPromptLine({'stock': 50}),
          'Availability: in stock (50 available)');
      expect(stockPromptLine({'stock': 2}),
          'Availability: LOW STOCK (only 2 left)');
      expect(stockPromptLine({'stock': 0}), 'Availability: OUT OF STOCK');
      expect(stockPromptLine({}), contains('NOT on file'));
    });
  });

  group('stockAlertCounts and ordering', () {
    final watches = <Map<String, dynamic>>[
      {'stock': 0},
      {'stock': 0},
      {'stock': 2},
      {'stock': 10},
      {},
    ];

    test('counts out and low, ignoring in stock and untracked', () {
      final counts = stockAlertCounts(watches);
      expect(counts.out, 2);
      expect(counts.low, 1);
    });

    test('urgency sort puts out of stock first, then the fewest left', () {
      final flagged = <Map<String, dynamic>>[
        {'stock': 3},
        {'stock': 0},
        {'stock': 1},
      ]..sort(compareByStockUrgency);
      expect(flagged.map((w) => w['stock']).toList(), [0, 1, 3]);
    });
  });
}
