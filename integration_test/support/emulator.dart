// Shared setup for the integration tests.
//
// These tests run the REAL VirtuWatch services (AuthService, UserService,
// WatchService, RecommendationService, ChatHistoryService, ...) against the
// Firebase Emulator Suite (Auth + Firestore). The Firestore emulator loads
// the project's real firestore.rules, so security rules are enforced exactly
// as in production. Nothing here touches the live Firebase project.
//
// The Android emulator reaches the PC through 10.0.2.2. For a physical phone
// pass --dart-define=EMULATOR_HOST=<your PC's LAN IP>.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/firebase_options.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/recommendation_service.dart';
import 'package:virtuwatch/services/watch_service.dart';

const String emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);
const int _firestorePort = 8080;
const int _authPort = 9099;

/// Password used for every test account.
const String testPassword = 'Passw0rd!test';

/// A model URL that passes the app's own "supported model" check.
const String sampleModelUrl =
    'https://res.cloudinary.com/demo/raw/upload/v1/virtuwatch/test_watch.glb';

typedef TestUser = ({String uid, String email});

/// An admin-measured AR fit, using values inside the app's accepted ranges.
Map<String, dynamic> sampleArFit([String modelUrl = sampleModelUrl]) => {
  'modelUrl': modelUrl,
  'holeCx': -0.057,
  'holeHalfX': 0.25,
  'holeHalfY': 0.435,
  'scale': 1.0,
};

/// A minimal listed watch. Override fields through [extra].
Map<String, dynamic> sampleWatch({
  required String name,
  List<String> colorHexes = const ['#000000'],
  double lugToLugMm = 48,
  String styleCategory = 'Minimalist',
  bool listed = true,
  Map<String, dynamic> extra = const {},
}) => {
  'name': name,
  'brand': 'TestBrand',
  'price': 25000,
  'styleCategory': styleCategory,
  'caseDiameterMm': 40,
  'lugToLugMm': lugToLugMm,
  'colorHexes': colorHexes,
  'listedInCatalog': listed,
  'stock': 5,
  ...extra,
};

/// The ranked recommendation for the watch called [name].
WatchRecommendation recFor(RecommendationResult result, String name) =>
    result.recommendations.firstWhere((r) => r.data['name'] == name);

/// Watch names in ranked order.
List<String> rankedNames(RecommendationResult result) =>
    result.recommendations.map((r) => r.data['name'] as String).toList();

/// Passes when [action] is rejected by the Firestore security rules.
Future<void> expectPermissionDenied(Future<dynamic> Function() action) async {
  try {
    await action();
  } on FirebaseException catch (e) {
    expect(e.code, 'permission-denied');
    return;
  }
  fail('Expected Firestore rules to deny this operation, but it succeeded.');
}

class TestEnv {
  static bool _ready = false;
  static int _counter = 0;

  static String get _projectId => Firebase.app().options.projectId;

  /// Connects Firebase to the local emulators. Safe to call many times.
  static Future<void> ensureReady() async {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    if (_ready) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      emulatorHost,
      _firestorePort,
    );
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, _authPort);
    _ready = true;
  }

  /// Signs out and wipes every Auth account and Firestore document in the
  /// emulators, so each test starts from an empty project.
  static Future<void> reset() async {
    await FirebaseAuth.instance.signOut();
    final firestore = await http.delete(
      Uri.parse(
        'http://$emulatorHost:$_firestorePort/emulator/v1/projects/$_projectId/databases/(default)/documents',
      ),
    );
    final auth = await http.delete(
      Uri.parse(
        'http://$emulatorHost:$_authPort/emulator/v1/projects/$_projectId/accounts',
      ),
    );
    if (firestore.statusCode != 200 || auth.statusCode != 200) {
      throw StateError(
        'Could not reset the emulators (Firestore ${firestore.statusCode}, '
        'Auth ${auth.statusCode}). Is "firebase emulators:start" running?',
      );
    }
  }

  static String _nextEmail(String prefix) =>
      '$prefix${++_counter}@virtuwatch.test';

  /// Registers a customer through the app's own sign-up code. The new
  /// customer is left signed in.
  static Future<TestUser> registerCustomer({
    String username = 'Test Customer',
    List<String> stylePreferences = const [],
    String? gender,
  }) async {
    final email = _nextEmail('customer');
    final user = await AuthService().registerWithEmail(
      email: email,
      password: testPassword,
      username: username,
      stylePreferences: stylePreferences,
      gender: gender,
    );
    return (uid: user!.uid, email: email);
  }

  /// Creates a merchant or admin account and leaves it signed in. Customers
  /// can self-register but staff roles cannot be self-assigned (the rules
  /// forbid it), so the profile document is seeded through the emulator's
  /// rules-bypass REST endpoint.
  static Future<TestUser> createStaff(String role) async {
    final email = _nextEmail(role);
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: testPassword,
    );
    final uid = cred.user!.uid;
    final res = await http.patch(
      Uri.parse(
        'http://$emulatorHost:$_firestorePort/v1/projects/$_projectId/databases/(default)/documents/users/$uid',
      ),
      headers: {
        'Authorization': 'Bearer owner',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fields': {
          'uid': {'stringValue': uid},
          'email': {'stringValue': email},
          'username': {'stringValue': 'Test $role'},
          'role': {'stringValue': role},
          'accountStatus': {'stringValue': 'active'},
        },
      }),
    );
    if (res.statusCode != 200) {
      throw StateError('Could not seed the $role profile: ${res.body}');
    }
    return (uid: uid, email: email);
  }

  static Future<void> signIn(String email) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: testPassword,
    );
  }

  static Future<void> signOut() => FirebaseAuth.instance.signOut();

  /// Adds a watch as the currently signed-in merchant/admin through the
  /// app's WatchService, then returns its document ID.
  static Future<String> addWatch(
    Map<String, dynamic> data, {
    String? merchantIdOverride,
  }) async {
    await WatchService().addWatch(data, merchantIdOverride: merchantIdOverride);
    final snap = await FirebaseFirestore.instance
        .collection('watches')
        .where('name', isEqualTo: data['name'])
        .get();
    return snap.docs.single.id;
  }

  /// Creates a merchant, lists [watches] under them, and signs out.
  /// Returns the merchant and a name -> document ID map.
  static Future<({TestUser merchant, Map<String, String> ids})> seedCatalog(
    List<Map<String, dynamic>> watches,
  ) async {
    final merchant = await createStaff('merchant');
    final ids = <String, String>{};
    for (final w in watches) {
      ids[w['name'] as String] = await addWatch(w);
    }
    await signOut();
    return (merchant: merchant, ids: ids);
  }

  static Future<Map<String, dynamic>> userDoc(String uid) async =>
      (await FirebaseFirestore.instance.collection('users').doc(uid).get())
          .data()!;

  static Future<Map<String, dynamic>> watchDoc(String id) async =>
      (await FirebaseFirestore.instance.collection('watches').doc(id).get())
          .data()!;

  /// Polls until [condition] is true, failing the test after [timeout].
  static Future<void> waitUntil(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for condition.');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
