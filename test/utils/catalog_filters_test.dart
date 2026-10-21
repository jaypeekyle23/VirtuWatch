// Tests for the In Stock filter in lib/widgets/catalog_filter_sheet.dart.
// Plain maps, no Firebase needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/widgets/catalog_filter_sheet.dart';

void main() {
  group('CatalogFilters.inStockOnly', () {
    const filters = CatalogFilters(inStockOnly: true);

    test('is off by default and does not narrow anything', () {
      const none = CatalogFilters();
      expect(none.inStockOnly, isFalse);
      expect(none.isDefault, isTrue);
      expect(none.matches({'stock': 0}), isTrue);
    });

    test('keeps watches with at least one unit', () {
      expect(filters.matches({'stock': 1}), isTrue);
      expect(filters.matches({'stock': 40}), isTrue);
    });

    test('drops out-of-stock watches', () {
      expect(filters.matches({'stock': 0}), isFalse);
    });

    test('drops watches with no stock count, since availability is unknown',
        () {
      expect(filters.matches({}), isFalse);
      expect(filters.matches({'stock': null}), isFalse);
    });

    test('counts as one active filter', () {
      expect(filters.activeCount, 1);
      expect(filters.isDefault, isFalse);
    });

    test('copyWith can turn it on and off', () {
      final on = const CatalogFilters().copyWith(inStockOnly: true);
      expect(on.inStockOnly, isTrue);
      expect(on.copyWith(inStockOnly: false).inStockOnly, isFalse);
    });
  });
}
