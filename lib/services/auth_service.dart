import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'activity_log_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _activityLog = ActivityLogService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  /// Whether the currently logged-in user can change a password at all
  /// (i.e. they signed up with email/password, not just Google).
  bool get canChangePassword {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'password');
  }

  /// Registers a new Customer account (the only self-service role).
  /// Creates both the Firebase Auth user and their Firestore profile,
  /// and sends a verification email since this is an email/password account.
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
        await user.sendEmailVerification();
        await _activityLog.log(
          'user_registered',
          'New customer registered: $email',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Logs in an existing user and returns their profile document,
  /// which includes their role for routing purposes. Email/password
  /// accounts must have a verified email; Google accounts are exempt
  /// since Google has already verified their email address.
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

      final isGoogleAccount =
          user.providerData.any((p) => p.providerId == 'google.com');

      if (!isGoogleAccount) {
        await user.reload();
        final refreshedUser = _auth.currentUser;
        if (refreshedUser != null && !refreshedUser.emailVerified) {
          await _auth.signOut();
          throw 'EMAIL_NOT_VERIFIED';
        }
      }

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

  /// Signs in with a raw email/password without the verification check,
  /// solely so the verify-email screen can re-authenticate to send another
  /// verification email or refresh status. Not used for normal login.
  Future<User?> signInWithoutVerificationCheck(
      String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential.user;
    } on FirebaseAuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  /// Resends the verification email to the currently signed-in user.
  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) throw 'You must be logged in to resend a verification email.';
    await user.sendEmailVerification();
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
        await _activityLog.log(
          'user_registered',
          'New customer registered via Google: ${user.email ?? 'unknown'}',
        );
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

  /// Permanently deletes the currently logged-in user's own account: their
  /// Firestore profile document and their Firebase Auth account. Requires
  /// re-authentication first, since Firebase blocks account deletion after
  /// a certain time since last login.
  ///
  /// For email/password accounts, pass [currentPassword]. For Google
  /// accounts, leave [currentPassword] null; Google re-authentication is
  /// triggered automatically via a fresh sign-in prompt.
  Future<void> deleteOwnAccount({String? currentPassword}) async {
    final user = _auth.currentUser;
    if (user == null) throw 'You must be logged in.';

    final isGoogleAccount =
        user.providerData.any((p) => p.providerId == 'google.com');

    try {
      if (isGoogleAccount) {
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          throw 'Re-authentication was cancelled.';
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        if (currentPassword == null || user.email == null) {
          throw 'Please enter your current password.';
        }
        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
      }

      await _activityLog.log(
        'account_self_deleted',
        'Account deleted by user: ${user.email ?? user.uid}',
      );
      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();
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

      // Even admin-created accounts must verify their email before their
      // first login, confirming the address is real and accessible.
      await newUser.sendEmailVerification();
      await _activityLog.log(
        'account_created',
        '${role[0].toUpperCase()}${role.substring(1)} account created: $username ($email)',
      );

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
    String? photoUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    await _firestore.collection('users').doc(uid).update({
      'username': username,
      'stylePreferences': stylePreferences,
      'preferredBrands': preferredBrands,
      'budgetMin': ?budgetMin,
      'budgetMax': ?budgetMax,
      'photoUrl': ?photoUrl,
    });
  }

  /// Updates only the currently logged-in user's profile photo URL. Used
  /// by Merchant and Admin accounts via [EditAccountNameScreen], and can
  /// also be called standalone for Customer accounts outside the full
  /// [updateOwnProfile] flow.
  Future<void> updatePhotoUrl(String photoUrl) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    await _firestore.collection('users').doc(uid).update({
      'photoUrl': photoUrl,
    });
  }

  /// Updates only the currently logged-in user's display name. Used by
  /// Merchant and Admin accounts, which don't have the customer-specific
  /// style/brand/budget fields that [updateOwnProfile] handles.
  Future<void> updateUsername(String newUsername) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';
    if (newUsername.trim().isEmpty) throw 'Name cannot be empty.';

    await _firestore.collection('users').doc(uid).update({
      'username': newUsername.trim(),
    });
  }

  /// Persists the results of an Outfit Color Scan on the user's own
  /// profile, so the future recommendations engine can match watches
  /// against these colors. [colors] is a list of maps shaped like
  /// {'hex': '#RRGGBB', 'percentage': 42.0}.
  Future<void> saveOutfitColors(List<Map<String, dynamic>> colors) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    await _firestore.collection('users').doc(uid).update({
      'outfitColors': colors,
      'lastOutfitScanAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves the user's wrist width on their profile, so the future
  /// recommendation engine can filter/rank watches by fit (comparing
  /// against each watch's lugToLugMm). [method] distinguishes a manual
  /// entry from a future camera-based measurement, in case that
  /// distinction matters later (e.g. showing confidence to the user).
  Future<void> saveWristMeasurement(
    double wristWidthMm, {
    String method = 'manual',
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw 'You must be logged in.';

    await _firestore.collection('users').doc(uid).update({
      'wristWidthMm': wristWidthMm,
      'wristMeasurementMethod': method,
      'lastWristMeasurementAt': FieldValue.serverTimestamp(),
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