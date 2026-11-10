// IT-07: Save / View / Try-On -> user document + engagement summary ->
// merchant analytics

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/user_service.dart';
import 'package:virtuwatch/services/watch_service.dart';

import 'support/emulator.dart';

Future<Map<String, dynamic>?> _summary(String watchId) async =>
    (await FirebaseFirestore.instance
            .collection('watches')
            .doc(watchId)
            .collection('engagement')
            .doc('summary')
            .get())
        .data();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-07 Save/View -> Engagement Tracking', () {
    late TestUser merchant;
    late Map<String, String> ids;

    setUp(() async {
      await TestEnv.reset();
      final seeded = await TestEnv.seedCatalog([
        sampleWatch(name: 'Watch A'),
        sampleWatch(name: 'Watch B'),
        sampleWatch(name: 'Watch C'),
      ]);
      merchant = seeded.merchant;
      ids = seeded.ids;
    });

    test(
      'saving and viewing update the user document and the watch summary',
      () async {
        final a = ids['Watch A']!;
        final c1 = await TestEnv.registerCustomer();
        final users = UserService();

        await users.toggleSavedWatch(a);
        await users.recordRecentlyViewed(a);

        final userDoc = await TestEnv.userDoc(c1.uid);
        expect(userDoc['savedWatches'], [a]);
        expect(userDoc['recentlyViewedWatches'], [a]);

        await TestEnv.signIn(merchant.email);
        final summary = await _summary(a);
        expect(summary!['saverIds'], [c1.uid]);
        expect(summary['viewerIds'], [c1.uid]);
      },
    );

    test(
      'try-on events increment the counters and the merchant sees them',
      () async {
        final a = ids['Watch A']!;
        final c1 = await TestEnv.registerCustomer();
        final users = UserService();

        await users.toggleSavedWatch(a);
        await users.recordRecentlyViewed(a);
        await users.recordTryOnEvent(a, TryOnEvent.started);
        await users.recordTryOnEvent(a, TryOnEvent.photo);
        await users.recordTryOnEvent(a, TryOnEvent.share);

        final c2 = await TestEnv.registerCustomer();
        await UserService().toggleSavedWatch(a);

        await TestEnv.signIn(merchant.email);
        final stats = await WatchService().fetchEngagementStats([a]);

        expect(stats.savedCounts[a], 2);
        expect(stats.viewedCounts[a], 1);
        expect(stats.tryOnerCounts[a], 1);
        expect(stats.tryOnCounts[a], 1);
        expect(stats.photoCounts[a], 1);
        expect(stats.shareCounts[a], 1);
        expect(stats.uniqueSaverCount, 2);
        expect(stats.uniqueTryOnerCount, 1);

        final summary = await _summary(a);
        expect(summary!['saverIds'], containsAll([c1.uid, c2.uid]));
      },
    );

    test(
      'un-saving removes the watch from the user and the saver list',
      () async {
        final a = ids['Watch A']!;
        final c1 = await TestEnv.registerCustomer();
        final users = UserService();

        await users.toggleSavedWatch(a);
        await users.toggleSavedWatch(a);

        expect((await TestEnv.userDoc(c1.uid))['savedWatches'], isEmpty);
        await TestEnv.signIn(merchant.email);
        expect((await _summary(a))!['saverIds'], isEmpty);
      },
    );

    test(
      'recently viewed keeps the newest first and respects the cap',
      () async {
        final c1 = await TestEnv.registerCustomer();
        final users = UserService();
        final a = ids['Watch A']!, b = ids['Watch B']!, c = ids['Watch C']!;

        await users.recordRecentlyViewed(a, maxEntries: 2);
        await users.recordRecentlyViewed(b, maxEntries: 2);
        await users.recordRecentlyViewed(c, maxEntries: 2);
        expect((await TestEnv.userDoc(c1.uid))['recentlyViewedWatches'], [
          c,
          b,
        ]);

        await users.recordRecentlyViewed(b, maxEntries: 2);
        expect((await TestEnv.userDoc(c1.uid))['recentlyViewedWatches'], [
          b,
          c,
        ]);
      },
    );

    test(
      'an admin deleting a watch cleans up customers and its summary',
      () async {
        final a = ids['Watch A']!;
        final admin = await TestEnv.createStaff('admin');
        final c1 = await TestEnv.registerCustomer();
        await UserService().toggleSavedWatch(a);
        await UserService().recordRecentlyViewed(a);

        await TestEnv.signIn(admin.email);
        await WatchService().deleteWatch(a, watchLabel: 'Watch A');

        expect(
          (await FirebaseFirestore.instance.collection('watches').doc(a).get())
              .exists,
          isFalse,
        );
        expect(await _summary(a), isNull);

        await TestEnv.signIn(c1.email);
        final userDoc = await TestEnv.userDoc(c1.uid);
        expect(userDoc['savedWatches'], isEmpty);
        expect(userDoc['recentlyViewedWatches'], isEmpty);
      },
    );
  });
}
