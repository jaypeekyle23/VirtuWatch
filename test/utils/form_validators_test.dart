// Tests for lib/utils/form_validators.dart, used on the merchant
// add/edit watch forms (Price, Lug-to-Lug as required fields; Case
// Diameter, Case Thickness, Band Width as optional ones).

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/form_validators.dart';

void main() {
  group('requiredPositiveNumber', () {
    test('null value is rejected as Required', () {
      expect(requiredPositiveNumber(null), 'Required');
    });

    test('empty string is rejected as Required', () {
      expect(requiredPositiveNumber(''), 'Required');
    });

    test('whitespace-only string is rejected as Required', () {
      expect(requiredPositiveNumber('   '), 'Required');
    });

    test('non-numeric input is rejected', () {
      expect(requiredPositiveNumber('abc'), 'Enter a valid number');
    });

    test('zero is rejected (must be greater than 0)', () {
      expect(requiredPositiveNumber('0'), 'Must be greater than 0');
    });

    test('a negative number is rejected', () {
      expect(requiredPositiveNumber('-5'), 'Must be greater than 0');
    });

    test('a valid positive number passes (returns null)', () {
      expect(requiredPositiveNumber('42.5'), isNull);
    });

    test('surrounding whitespace on an otherwise valid number is trimmed', () {
      expect(requiredPositiveNumber('  42.5  '), isNull);
    });
  });

  group('optionalPositiveNumber', () {
    test('null value passes (field left blank is fine)', () {
      expect(optionalPositiveNumber(null), isNull);
    });

    test('empty string passes (field left blank is fine)', () {
      expect(optionalPositiveNumber(''), isNull);
    });

    test('whitespace-only string passes (treated as blank)', () {
      expect(optionalPositiveNumber('   '), isNull);
    });

    test('non-numeric input IS rejected even though the field is optional', () {
      expect(optionalPositiveNumber('abc'), 'Enter a valid number');
    });

    test('zero is rejected even though the field is optional', () {
      expect(optionalPositiveNumber('0'), 'Must be greater than 0');
    });

    test('a negative number is rejected even though the field is optional', () {
      expect(optionalPositiveNumber('-1.5'), 'Must be greater than 0');
    });

    test('a valid positive number passes (returns null)', () {
      expect(optionalPositiveNumber('12'), isNull);
    });
  });
}