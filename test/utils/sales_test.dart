// Tests for lib/utils/sales.dart, the rules and maths behind the sales
// history. Plain maps, no Firebase needed.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/sales.dart';

Map<String, dynamic> _sale({
  required String id,
  String name = 'Seiko 5',
  String brand = 'Seiko',
  required DateTime soldAt,
  num total = 1000,
  int quantity = 1,
  String method = 'Cash',
  String status = saleCompleted,
  String? buyer,
}) =>
    {
      'id': id,
      'watchName': name,
      'watchBrand': brand,
      'soldAt': Timestamp.fromDate(soldAt),
      'totalAmount': total,
      'quantity': quantity,
      'paymentMethod': method,
      'status': status,
      if (buyer != null) 'buyerName': buyer,
    };

void main() {
  final now = DateTime(2026, 11, 16, 15, 30);

  group('money', () {
    test('saleTotal rounds to centavos', () {
      expect(saleTotal(1999.99, 3), 5999.97);
      expect(saleTotal(5000, 2), 10000);
    });

    test('formatSaleMoney shows centavos only when there are some', () {
      expect(formatSaleMoney(12500), 'PHP 12,500');
      expect(formatSaleMoney(1999.5), 'PHP 1,999.50');
      expect(formatSaleMoney(0), 'PHP 0');
    });
  });

  group('dates', () {
    test('today keeps the current time, other days are noon', () {
      expect(soldAtFromDay(DateTime(2026, 11, 16), now: now), now);
      expect(
        soldAtFromDay(DateTime(2026, 11, 1), now: now),
        DateTime(2026, 11, 1, 12),
      );
    });

    test('quick ranges', () {
      final month = presetRange(SalePreset.month, now);
      expect(month.from, DateTime(2026, 11, 1));
      expect(month.to, DateTime(2026, 11, 16));
      expect(presetRange(SalePreset.last30, now).from, DateTime(2026, 10, 18));
      expect(presetRange(SalePreset.year, now).from, DateTime(2026, 1, 1));
      final all = presetRange(SalePreset.all, now);
      expect(all.from, isNull);
      expect(all.to, isNull);
    });
  });

  group('validateSaleInput', () {
    Map<String, String> check({
      int? quantity = 2,
      double? unitPrice = 5000,
      DateTime? soldAt,
      String method = 'GCash',
      int? stock = 5,
      String notes = '',
    }) =>
        validateSaleInput(
          quantity: quantity,
          unitPrice: unitPrice,
          soldAt: soldAt ?? now,
          paymentMethod: method,
          notes: notes,
          stock: stock,
          now: now,
        );

    test('a good sale has no errors', () {
      expect(check(), isEmpty);
    });

    test('an untracked watch (no stock count) can always be sold', () {
      expect(check(stock: null, quantity: 50), isEmpty);
    });

    test('cannot sell more than is in stock', () {
      expect(check(quantity: 6)['quantity'], 'Only 5 in stock.');
      expect(check(stock: 0)['quantity'], 'This watch is out of stock.');
    });

    test('quantity must be at least one', () {
      expect(check(quantity: 0)['quantity'], isNotNull);
      expect(check(quantity: null)['quantity'], isNotNull);
    });

    test('price must be a positive number', () {
      expect(check(unitPrice: 0)['unitPrice'], isNotNull);
      expect(check(unitPrice: null)['unitPrice'], isNotNull);
      expect(check(unitPrice: double.nan)['unitPrice'], isNotNull);
    });

    test('the date cannot be in the future, but later today is fine', () {
      expect(check(soldAt: DateTime(2026, 11, 17, 9))['soldAt'], isNotNull);
      expect(check(soldAt: DateTime(2026, 11, 16, 23)), isEmpty);
    });

    test('payment method must be one of the list', () {
      expect(check(method: 'Crypto')['paymentMethod'], isNotNull);
    });

    test('notes have a length limit', () {
      expect(check(notes: 'x' * 501)['notes'], isNotNull);
    });
  });

  group('filtering, sorting and totals', () {
    final sales = [
      _sale(
          id: 'a',
          soldAt: DateTime(2026, 11, 10, 12),
          total: 8000,
          quantity: 2,
          buyer: 'Ana'),
      _sale(
          id: 'b',
          name: 'G-Shock',
          brand: 'Casio',
          soldAt: DateTime(2026, 10, 1, 12),
          total: 5000,
          method: 'GCash'),
      _sale(
          id: 'c',
          soldAt: DateTime(2026, 11, 12, 12),
          total: 4000,
          status: saleVoided),
    ];
    List<String> ids(List<Map<String, dynamic>> list) =>
        [for (final s in list) s['id'] as String];

    test('voided sales are hidden unless asked for', () {
      expect(ids(filterSales(sales)), ['a', 'b']);
      expect(ids(filterSales(sales, includeVoided: true)), ['a', 'b', 'c']);
    });

    test('search matches watch, brand, buyer and notes', () {
      expect(ids(filterSales(sales, search: 'ana')), ['a']);
      expect(ids(filterSales(sales, search: 'casio')), ['b']);
    });

    test('the date range includes both end days', () {
      expect(
        ids(filterSales(sales,
            from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 10))),
        ['a'],
      );
    });

    test('payment method filter', () {
      expect(ids(filterSales(sales, paymentMethod: 'GCash')), ['b']);
    });

    test('totals leave voided sales out', () {
      final t = salesTotals(sales);
      expect(t.revenue, 13000);
      expect(t.units, 3);
      expect(t.count, 2);
      expect(t.voided, 1);
    });

    test('newest sale first', () {
      expect(ids(sortSalesNewestFirst(sales)), ['c', 'a', 'b']);
    });
  });
}
