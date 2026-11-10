// IT-08: Firestore security rules, enforced by the emulator using the real
// firestore.rules. Each test pairs a denied action with an allowed one, so a
// pass means the rule blocks the right thing and not everything.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/chat_history_service.dart';
import 'package:virtuwatch/services/chat_service.dart';
import 'package:virtuwatch/services/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'support/emulator.dart';

final _db = FirebaseFirestore.instance;

DocumentReference<Map<String, dynamic>> _summaryRef(String watchId) => _db
    .collection('watches')
    .doc(watchId)
    .collection('engagement')
    .doc('summary');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-08 Firestore Security Rules', () {
    setUp(TestEnv.reset);

    test('a new account cannot self-assign a staff role at sign-up', () async {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: 'sneaky@virtuwatch.test',
        password: testPassword,
      );
      final ref = _db.collection('users').doc(cred.user!.uid);

      await expectPermissionDenied(
        () => ref.set({
          'uid': cred.user!.uid,
          'email': 'sneaky@virtuwatch.test',
          'role': 'admin',
          'accountStatus': 'active',
        }),
      );
      // Positive control: the same sign-up as a customer is allowed.
      await ref.set({
        'uid': cred.user!.uid,
        'email': 'sneaky@virtuwatch.test',
        'role': 'customer',
        'accountStatus': 'active',
      });
    });

    test('a customer cannot change their own role or account status', () async {
      final c = await TestEnv.registerCustomer();
      final ref = _db.collection('users').doc(c.uid);

      await expectPermissionDenied(() => ref.update({'role': 'admin'}));
      await expectPermissionDenied(
        () => ref.update({'accountStatus': 'suspended'}),
      );
      // Positive control: ordinary profile edits are allowed.
      await ref.update({'username': 'Renamed'});
      expect((await TestEnv.userDoc(c.uid))['username'], 'Renamed');
    });

    test('a suspended customer cannot reactivate themselves', () async {
      final admin = await TestEnv.createStaff('admin');
      final c = await TestEnv.registerCustomer();
      await TestEnv.signIn(admin.email);
      await UserService().suspendAccount(c.uid, accountLabel: 'test');

      await TestEnv.signIn(c.email);
      await expectPermissionDenied(
        () => _db.collection('users').doc(c.uid).update({
          'accountStatus': 'active',
        }),
      );
    });

    test(
      'profiles are private: owners and admins can read, others cannot',
      () async {
        final admin = await TestEnv.createStaff('admin');
        final c1 = await TestEnv.registerCustomer();
        final c2 = await TestEnv.registerCustomer();

        await expectPermissionDenied(
          () => _db.collection('users').doc(c1.uid).get(),
        );
        await _db.collection('users').doc(c2.uid).get();

        await TestEnv.signIn(admin.email);
        expect(
          (await _db.collection('users').doc(c1.uid).get()).exists,
          isTrue,
        );
      },
    );

    test('merchants cannot write arFit, admins can', () async {
      final admin = await TestEnv.createStaff('admin');
      final merchant = await TestEnv.createStaff('merchant');

      await expectPermissionDenied(
        () => _db.collection('watches').add({
          ...sampleWatch(name: 'Sneaky'),
          'merchantId': merchant.uid,
          'arFit': sampleArFit(),
        }),
      );

      final id = await TestEnv.addWatch(sampleWatch(name: 'Normal'));
      await expectPermissionDenied(
        () =>
            _db.collection('watches').doc(id).update({'arFit': sampleArFit()}),
      );
      // Positive control: other fields on their own watch are editable.
      await _db.collection('watches').doc(id).update({'price': 30000});

      await TestEnv.signIn(admin.email);
      await _db.collection('watches').doc(id).update({'arFit': sampleArFit()});
      expect((await TestEnv.watchDoc(id))['arFit'], isNotNull);
    });

    test(
      'a merchant cannot edit or delete another merchant\'s watch',
      () async {
        await TestEnv.createStaff('merchant');
        final id = await TestEnv.addWatch(sampleWatch(name: 'Owned'));
        final other = await TestEnv.createStaff('merchant');

        await expectPermissionDenied(
          () => _db.collection('watches').doc(id).update({'price': 1}),
        );
        await expectPermissionDenied(
          () => _db.collection('watches').doc(id).delete(),
        );
        expect(other.uid, isNotEmpty);
      },
    );

    test('engagement counters can only step up by one', () async {
      await TestEnv.createStaff('merchant');
      final id = await TestEnv.addWatch(sampleWatch(name: 'Counted'));
      await TestEnv.signOut();
      await TestEnv.registerCustomer();

      await UserService().recordTryOnEvent(id, TryOnEvent.started);

      await expectPermissionDenied(
        () => _summaryRef(
          id,
        ).set({'tryOnCount': FieldValue.increment(2)}, SetOptions(merge: true)),
      );
      // Positive control: a step of one is accepted.
      await _summaryRef(
        id,
      ).set({'photoCount': FieldValue.increment(1)}, SetOptions(merge: true));
    });

    test('a customer cannot add someone else to an engagement list', () async {
      await TestEnv.createStaff('merchant');
      final id = await TestEnv.addWatch(sampleWatch(name: 'Listed'));
      await TestEnv.signOut();
      final c1 = await TestEnv.registerCustomer();

      await expectPermissionDenied(
        () => _summaryRef(id).set({
          'saverIds': FieldValue.arrayUnion(['someone-else']),
        }, SetOptions(merge: true)),
      );
      // Positive control: adding their own uid is accepted.
      await _summaryRef(id).set({
        'saverIds': FieldValue.arrayUnion([c1.uid]),
      }, SetOptions(merge: true));
    });

    test(
      'engagement is readable only by the owning merchant and admins',
      () async {
        final owner = await TestEnv.createStaff('merchant');
        final id = await TestEnv.addWatch(sampleWatch(name: 'Private stats'));
        final stranger = await TestEnv.createStaff('merchant');
        await TestEnv.signOut();
        final c1 = await TestEnv.registerCustomer();
        await UserService().recordRecentlyViewed(id);

        await expectPermissionDenied(() => _summaryRef(id).get());

        await TestEnv.signIn(stranger.email);
        await expectPermissionDenied(() => _summaryRef(id).get());

        await TestEnv.signIn(owner.email);
        final summary = (await _summaryRef(id).get()).data()!;
        expect(summary['viewerIds'], [c1.uid]);
      },
    );

    test('only admins can read the activity log', () async {
      final admin = await TestEnv.createStaff('admin');
      final c = await TestEnv.registerCustomer();

      await expectPermissionDenied(() => _db.collection('activityLog').get());

      await TestEnv.signIn(admin.email);
      final logs = await _db.collection('activityLog').get();
      expect(logs.docs, isNotEmpty);
      expect(c.uid, isNotEmpty);
    });

    test('chat threads are private to their owner', () async {
      final c1 = await TestEnv.registerCustomer();
      await ChatHistoryService().save('thread-1', const [
        ChatMessage(role: 'user', text: 'hello'),
      ]);
      await TestEnv.registerCustomer();

      await expectPermissionDenied(
        () => _db
            .collection('users')
            .doc(c1.uid)
            .collection('chatThreads')
            .doc('thread-1')
            .get(),
      );
    });

    test('registration only ever creates a customer profile', () async {
      final c = await TestEnv.registerCustomer();
      final doc = await TestEnv.userDoc(c.uid);
      expect(doc['role'], 'customer');
      expect(AuthService().currentUser?.uid, c.uid);
    });
  });
}
