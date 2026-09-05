import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Registers a new Customer account (the only self-service role).
  /// Creates both the Firebase Auth user and their Firestore profile.
  Future<User?> registerWithEmail({
    required String email,
    required String password,
    required String username,
    List<String> stylePreferences = const [],
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'username': username,
          'role': 'customer',
          'stylePreferences': stylePreferences,
          'accountStatus': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Logs in an existing user and returns their profile document,
  /// which includes their role for routing purposes.
  Future<Map<String, dynamic>?> loginWithEmail(
    String email,
    String password,
  ) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        throw 'No profile found for this account. Please contact support.';
      }

      final data = doc.data()!;
      if (data['accountStatus'] == 'suspended') {
        await _auth.signOut();
        throw 'This account has been suspended. Please contact support.';
      }

      return data;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Signs in with Google. Creates a Firestore profile automatically
  /// on first sign-in (defaulting to the 'customer' role), or returns
  /// the existing profile for returning users.
  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in flow.
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      final docRef = _firestore.collection('users').doc(user.uid);
      final doc = await docRef.get();

      if (!doc.exists) {
        final newProfile = {
          'uid': user.uid,
          'email': user.email ?? '',
          'username': user.displayName ?? 'User',
          'role': 'customer',
          'stylePreferences': <String>[],
          'accountStatus': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        };
        await docRef.set(newProfile);
        return newProfile;
      }

      final data = doc.data()!;
      if (data['accountStatus'] == 'suspended') {
        await _auth.signOut();
        await googleSignIn.signOut();
        throw 'This account has been suspended. Please contact support.';
      }

      return data;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Whether the currently logged-in user can change a password at all
  /// (i.e. they signed up with email/password, not just Google).
  bool get canChangePassword {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  /// Changes the current user's password. Requires re-authentication with
  /// their current password first, since Firebase blocks sensitive
  /// operations like this after a certain time since last login.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw 'You must be logged in.';
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Used by an Admin to create a Merchant or Admin account without
  /// disrupting their own logged-in session. Uses a secondary Firebase
  /// app instance so the admin stays signed in on the main app.
  Future<void> createAccountForRole({
    required String email,
    required String password,
    required String username,
    required String role, // 'customer', 'merchant', or 'admin'
    List<String> stylePreferences = const [],
  }) async {
      if (role != 'customer' && role != 'merchant' && role != 'admin') {
        throw 'Invalid role specified.';
    }

    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'AdminCreateUser_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final newUser = credential.user;
      if (newUser == null) {
        throw 'Account creation failed.';
      }

      await _firestore.collection('users').doc(newUser.uid).set({
        'uid': newUser.uid,
        'email': email,
        'username': username,
        'role': role,
        'stylePreferences': stylePreferences,
        'accountStatus': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await secondaryAuth.signOut();
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  /// Updates the currently logged-in user's own editable profile fields.
  /// Cannot touch role or accountStatus (blocked by Security Rules anyway).
  Future<void> updateOwnProfile({
    required String username,
    List<String> stylePreferences = const [],
    List<String> preferredBrands = const [],
    double? budgetMin,
    double? budgetMax,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    await _firestore.collection('users').doc(uid).update({
      'username': username,
      'stylePreferences': stylePreferences,
      'preferredBrands': preferredBrands,
      'budgetMin': ?budgetMin,
      'budgetMax': ?budgetMax,
    });
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
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
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }
}