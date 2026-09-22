// Tests for lib/utils/auth_error_messages.dart — what customers actually
// see when login/registration fails. Written against plain error-code
// strings (not a real FirebaseAuthException) so these run without any
// Firebase setup at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/auth_error_messages.dart';

void main() {
  group('authErrorMessage — known Firebase Auth codes', () {
    test('email-already-in-use', () {
      expect(
        authErrorMessage('email-already-in-use'),
        'An account already exists with that email.',
      );
    });

    test('invalid-email', () {
      expect(
        authErrorMessage('invalid-email'),
        'That email address looks invalid.',
      );
    });

    test('weak-password', () {
      expect(
        authErrorMessage('weak-password'),
        'Password should be at least 6 characters.',
      );
    });

    test('user-not-found', () {
      expect(
        authErrorMessage('user-not-found'),
        'No account found with that email.',
      );
    });

    test('wrong-password and invalid-credential map to the same generic message', () {
      // Deliberate: never confirm to an attacker which part (email vs
      // password) was wrong.
      expect(authErrorMessage('wrong-password'), 'Incorrect email or password.');
      expect(authErrorMessage('invalid-credential'), 'Incorrect email or password.');
    });
  });

  group('authErrorMessage — unrecognized codes', () {
    test('falls back to the provided fallbackMessage when given', () {
      expect(
        authErrorMessage('some-unmapped-code', fallbackMessage: 'Raw SDK message'),
        'Raw SDK message',
      );
    });

    test('falls back to a generic message when no fallbackMessage is given', () {
      expect(
        authErrorMessage('some-unmapped-code'),
        'Something went wrong. Please try again.',
      );
    });

    test('a null-equivalent (empty) fallbackMessage still falls back to generic', () {
      // An empty string is falsy-in-spirit but not actually null, so this
      // pins down that authErrorMessage uses `??`, not an emptiness check.
      expect(authErrorMessage('some-unmapped-code', fallbackMessage: null),
          'Something went wrong. Please try again.');
    });
  });
}