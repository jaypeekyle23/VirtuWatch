// IT-02: Outfit Scan -> Firestore -> Recommendation Engine

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/recommendation_service.dart';

import 'support/emulator.dart';

const _black = [
  {'hex': '#000000', 'percentage': 100.0},
];
const _white = [
  {'hex': '#FFFFFF', 'percentage': 100.0},
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-02 Outfit Scan -> Recommendations', () {
    late TestUser customer;

    setUp(() async {
      await TestEnv.reset();
      await TestEnv.seedCatalog([
        sampleWatch(name: 'Black Watch', colorHexes: const ['#000000']),
        sampleWatch(name: 'White Watch', colorHexes: const ['#FFFFFF']),
      ]);
      customer = await TestEnv.registerCustomer();
    });

    test(
      'scanned outfitColors are saved and drive the next scoring pass',
      () async {
        final before = await RecommendationService().getRecommendations();
        expect(recFor(before, 'Black Watch').colorScore, isNull);
        expect(recFor(before, 'White Watch').colorScore, isNull);

        await AuthService().saveOutfitColors(_black);

        final doc = await TestEnv.userDoc(customer.uid);
        expect((doc['outfitColors'] as List).length, 1);
        expect(doc['lastOutfitScanAt'], isA<Timestamp>());

        final after = await RecommendationService().getRecommendations();
        expect(recFor(after, 'Black Watch').colorScore, closeTo(1.0, 0.01));
        expect(recFor(after, 'White Watch').colorScore, closeTo(0.0, 0.05));
        expect(rankedNames(after).first, 'Black Watch');
      },
    );

    test('a new scan re-ranks the catalog', () async {
      await AuthService().saveOutfitColors(_black);
      expect(
        rankedNames(await RecommendationService().getRecommendations()).first,
        'Black Watch',
      );

      await AuthService().saveOutfitColors(_white);
      expect(
        rankedNames(await RecommendationService().getRecommendations()).first,
        'White Watch',
      );
    });

    test('clearing the outfit removes colors and the scan timestamp', () async {
      await AuthService().saveOutfitColors(_black);
      await AuthService().clearOutfitColors();

      final doc = await TestEnv.userDoc(customer.uid);
      expect(doc['outfitColors'], isEmpty);
      expect(doc.containsKey('lastOutfitScanAt'), isFalse);

      final result = await RecommendationService().getRecommendations();
      expect(recFor(result, 'Black Watch').colorScore, isNull);
    });

    test(
      'the live recommendation stream re-scores when the outfit changes',
      () async {
        final results = <RecommendationResult>[];
        final sub = RecommendationService().watchRecommendations().listen(
          results.add,
        );
        addTearDown(sub.cancel);

        await TestEnv.waitUntil(() => results.isNotEmpty);
        expect(recFor(results.last, 'Black Watch').colorScore, isNull);

        await AuthService().saveOutfitColors(_black);

        await TestEnv.waitUntil(() => results.length >= 2);
        expect(
          recFor(results.last, 'Black Watch').colorScore,
          closeTo(1.0, 0.01),
        );
      },
    );
  });
}
