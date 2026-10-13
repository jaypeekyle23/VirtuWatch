import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/format.dart';

void main() {
  test('formatPeso adds separators and drops decimals', () {
    expect(formatPeso(38998.0), 'PHP 38,998');
    expect(formatPeso(999), 'PHP 999');
    expect(formatPeso(1250000), 'PHP 1,250,000');
  });

  test('formatDate writes the month as a short name', () {
    expect(formatDate(DateTime(2026, 10, 13)), 'Oct 13, 2026');
    expect(formatDate(DateTime(2025, 1, 5)), 'Jan 5, 2025');
  });
}