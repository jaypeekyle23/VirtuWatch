// Tests for lib/utils/version_compare.dart — decides whether
// UpdateCheckerService shows an "update available" notification. A bug
// here means either nagging users who are already up to date, or worse,
// silently never telling them about a real update.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/version_compare.dart';

void main() {
  group('isNewerVersion — dotted numeric comparison', () {
    test('a higher patch version is newer', () {
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
    });

    test('a lower patch version is not newer', () {
      expect(isNewerVersion('1.2.9', '1.2.10'), isFalse);
    });

    test('identical versions are not newer', () {
      expect(isNewerVersion('1.1.0', '1.1.0'), isFalse);
    });

    test('a higher major version wins regardless of minor/patch', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('a higher minor version wins when major is equal', () {
      expect(isNewerVersion('1.3.0', '1.2.9'), isTrue);
    });

    // Critically, this is the exact bug this function fixed vs. a naive
    // string comparison: '1.2.10' < '1.2.9' alphabetically ('1' < '9'),
    // but numerically 10 > 9.
    test('numeric comparison beats a naive string/alphabetic comparison', () {
      expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
      expect('1.2.10'.compareTo('1.2.9') < 0, isTrue); // the trap this avoids
    });
  });

  group('isNewerVersion — different segment counts', () {
    test('a missing trailing segment is treated as 0 (1.3 == 1.3.0)', () {
      expect(isNewerVersion('1.3', '1.3.0'), isFalse);
    });

    test('an extra trailing segment counts if it is nonzero (1.3.1 > 1.3)', () {
      expect(isNewerVersion('1.3.1', '1.3'), isTrue);
    });
  });

  group('isNewerVersion — non-numeric tags fall back to string comparison', () {
    test('a non-dotted-numeric remote tag never crashes', () {
      expect(() => isNewerVersion('beta', '1.0.0'), returnsNormally);
    });

    test('identical non-numeric tags are not newer', () {
      expect(isNewerVersion('beta', 'beta'), isFalse);
    });

    test('a non-numeric tag falls back to plain string comparison', () {
      // 'b' > '1' as characters, so this reads as "newer" under the
      // string-comparison fallback — documented behavior, not a good
      // outcome, but a deliberate one: an unusual tag should never
      // silently crash the update check.
      expect(isNewerVersion('beta', '1.0.0'), isTrue);
    });
  });
}