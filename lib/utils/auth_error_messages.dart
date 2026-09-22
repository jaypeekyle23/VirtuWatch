/// Maps a Firebase Auth error [code] (e.g. from
/// `FirebaseAuthException.code`) to the friendly message shown to the
/// user. Pulled out of [AuthService] into its own file so the mapping can
/// be unit tested without constructing a real `FirebaseAuthException`.
///
/// [fallbackCode] is used for any code not explicitly handled — normally
/// `FirebaseAuthException.message`, since that's more useful to the user
/// than a completely generic string when the SDK gives us one.
String authErrorMessage(String code, {String? fallbackMessage}) {
  switch (code) {
    case 'email-already-in-use':
      return 'An account already exists with that email.';
    case 'invalid-email':
      return 'That email address looks invalid.';
    case 'weak-password':
      return 'Password should be at least 6 characters.';
    case 'user-not-found':
      return 'No account found with that email.';
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    default:
      return fallbackMessage ?? 'Something went wrong. Please try again.';
  }
}