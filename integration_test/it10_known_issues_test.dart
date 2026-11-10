// IT-10: Suspected problems in firestore.rules / WatchService.
//
// These tests describe the CORRECT behavior, so they are expected to FAIL
// while the problem exists and pass once it is fixed. They are deliberately
// left out of all_test.dart so the main suite stays green. Run them on
// their own:
//
//   flutter test integration_test/it10_known_issues_test.dart --reporter expanded -d <device>
//
// Each failing test has a matching "control" test that passes today, showing
// the failure is caused by the specific rule and not by the test setup.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/user_service.dart';
import 'package:virtuwatch/services/watch_service.dart';

import 'support/emulator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-10 Known issues', () {
    setUp(TestEnv.reset);

    group('merchant deleting a watch that customers saved', () {
      test('CONTROL: deleting a watch nobody saved works', () async {
        final merchant = await TestEnv.createStaff('merchant');
        final id = await TestEnv.addWatch(sampleWatch(name: 'Unsaved'));

        await WatchService().deleteWatch(id, watchLabel: 'Unsaved');

        expect(
          (await FirebaseFirestore.instance.collection('watches').doc(id).get())
              .exists,
          isFalse,
        );
        expect(merchant.uid, isNotEmpty);
      });

      test(
        'deleting a saved watch succeeds and cleans the customer\'s list',
        () async {
          final merchant = await TestEnv.createStaff('merchant');
          final id = await TestEnv.addWatch(
            sampleWatch(name: 'Saved by a customer'),
          );
          await TestEnv.signOut();
          final customer = await TestEnv.registerCustomer();
          await UserService().toggleSavedWatch(id);
          await UserService().recordRecentlyViewed(id);

          await TestEnv.signIn(merchant.email);
          // Expected to throw permission-denied today: the cleanup step updates
          // the customer's user document, which the rules only allow for the
          // customer themselves or an admin.
          await WatchService().deleteWatch(
            id,
            watchLabel: 'Saved by a customer',
          );

          await TestEnv.signIn(customer.email);
          final userDoc = await TestEnv.userDoc(customer.uid);
          expect(userDoc['savedWatches'], isNot(contains(id)));
          expect(userDoc['recentlyViewedWatches'], isNot(contains(id)));
        },
      );
    });

    group('who may create a watch listing', () {
      test(
        'CONTROL: a customer cannot list a watch under another merchant',
        () async {
          final merchant = await TestEnv.createStaff('merchant');
          await TestEnv.signOut();
          await TestEnv.registerCustomer();

          await expectPermissionDenied(
            () => FirebaseFirestore.instance.collection('watches').add({
              ...sampleWatch(name: 'Impersonation'),
              'merchantId': merchant.uid,
            }),
          );
        },
      );

      test(
        'a customer cannot create a watch listing under their own uid',
        () async {
          final customer = await TestEnv.registerCustomer();

          // Expected to succeed today: the create rule checks that merchantId
          // is the caller's uid, but never that the caller is a merchant.
          await expectPermissionDenied(
            () => FirebaseFirestore.instance.collection('watches').add({
              ...sampleWatch(name: 'Customer listing'),
              'merchantId': customer.uid,
            }),
          );
        },
      );
    });
  });
}
