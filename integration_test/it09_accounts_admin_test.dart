// IT-09: Registration and admin account management -> Firestore -> activity log

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/user_service.dart';

import 'support/emulator.dart';

Future<List<String>> _logTypes() async {
  final snap = await FirebaseFirestore.instance.collection('activityLog').get();
  return snap.docs.map((d) => d.data()['type'] as String).toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-09 Registration and Admin Account Management', () {
    late TestUser admin;

    setUp(() async {
      await TestEnv.reset();
      admin = await TestEnv.createStaff('admin');
    });

    test(
      'registering creates a customer profile and an unverified login',
      () async {
        final c = await TestEnv.registerCustomer(
          username: 'Mira',
          stylePreferences: const ['Minimalist'],
          gender: 'Female',
        );

        final doc = await TestEnv.userDoc(c.uid);
        expect(doc['uid'], c.uid);
        expect(doc['email'], c.email);
        expect(doc['username'], 'Mira');
        expect(doc['role'], 'customer');
        expect(doc['accountStatus'], 'active');
        expect(doc['stylePreferences'], ['Minimalist']);
        expect(doc['gender'], 'Female');
        expect(doc['createdAt'], isA<Timestamp>());

        expect(AuthService().currentUser!.emailVerified, isFalse);
      },
    );

    test('registration is recorded in the admin activity log', () async {
      await TestEnv.registerCustomer();
      await TestEnv.signIn(admin.email);
      expect(await _logTypes(), contains('user_registered'));
    });

    test(
      'an admin can suspend and reactivate an account, and it is logged',
      () async {
        final c = await TestEnv.registerCustomer();
        await TestEnv.signIn(admin.email);

        await UserService().suspendAccount(c.uid, accountLabel: c.email);
        expect((await TestEnv.userDoc(c.uid))['accountStatus'], 'suspended');

        await UserService().reactivateAccount(c.uid, accountLabel: c.email);
        expect((await TestEnv.userDoc(c.uid))['accountStatus'], 'active');

        expect(
          await _logTypes(),
          containsAll(['account_disabled', 'account_enabled']),
        );
      },
    );

    test('an admin can change a role, invalid roles are rejected', () async {
      final c = await TestEnv.registerCustomer();
      await TestEnv.signIn(admin.email);

      await UserService().updateUserRole(
        c.uid,
        'merchant',
        previousRole: 'customer',
      );
      expect((await TestEnv.userDoc(c.uid))['role'], 'merchant');
      expect(await _logTypes(), contains('role_changed'));

      await expectLater(
        UserService().updateUserRole(c.uid, 'superuser'),
        throwsA(isA<String>()),
      );
      expect((await TestEnv.userDoc(c.uid))['role'], 'merchant');
    });

    test('an admin can delete an account profile, and it is logged', () async {
      final c = await TestEnv.registerCustomer();
      await TestEnv.signIn(admin.email);

      await UserService().deleteAccountProfile(c.uid, accountLabel: c.email);

      expect(
        (await FirebaseFirestore.instance.collection('users').doc(c.uid).get())
            .exists,
        isFalse,
      );
      expect(await _logTypes(), contains('account_deleted'));
    });
  });
}
