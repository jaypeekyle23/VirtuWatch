// IT-03: Recommendation Engine <-> Catalog (listedInCatalog)

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/recommendation_service.dart';
import 'package:virtuwatch/services/watch_service.dart';

import 'support/emulator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-03 Recommendation Engine -> Catalog', () {
    late TestUser merchant;
    late TestUser customer;
    late String watchId;

    Future<List<String>> recommendedNames() async =>
        rankedNames(await RecommendationService().getRecommendations());

    Future<List<String>> catalogNames() async {
      final snap = await WatchService().allListedWatches().first;
      return snap.docs.map((d) => d.data()['name'] as String).toList();
    }

    setUp(() async {
      await TestEnv.reset();
      final seeded = await TestEnv.seedCatalog([
        sampleWatch(name: 'Toggle Watch'),
        sampleWatch(name: 'Always Listed'),
      ]);
      merchant = seeded.merchant;
      watchId = seeded.ids['Toggle Watch']!;
      customer = await TestEnv.registerCustomer();
    });

    Future<void> setListed(bool listed) async {
      await TestEnv.signIn(merchant.email);
      await WatchService().updateWatch(watchId, {'listedInCatalog': listed});
      await TestEnv.signIn(customer.email);
    }

    test(
      'a listed watch appears in both the catalog and recommendations',
      () async {
        expect(
          await recommendedNames(),
          containsAll(['Toggle Watch', 'Always Listed']),
        );
        expect(
          await catalogNames(),
          containsAll(['Toggle Watch', 'Always Listed']),
        );
      },
    );

    test(
      'unlisting a watch removes it from the catalog and recommendations',
      () async {
        await setListed(false);

        expect(await recommendedNames(), isNot(contains('Toggle Watch')));
        expect(await catalogNames(), isNot(contains('Toggle Watch')));
        expect(await recommendedNames(), contains('Always Listed'));
      },
    );

    test('listing it again brings it back', () async {
      await setListed(false);
      await setListed(true);

      expect(await recommendedNames(), contains('Toggle Watch'));
      expect(await catalogNames(), contains('Toggle Watch'));
    });
  });
}
