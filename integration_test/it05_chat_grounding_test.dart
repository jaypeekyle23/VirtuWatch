// IT-05: Chat assistant grounding, plus chat history persistence.
//
// The assistant's reply comes from Gemini over the network and is not
// deterministic, so it is checked manually. What IS checked here is the data
// the assistant is grounded on: the system prompt it receives must carry the
// same scores the customer sees on screen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:virtuwatch/services/auth_service.dart';
import 'package:virtuwatch/services/chat_history_service.dart';
import 'package:virtuwatch/services/chat_service.dart';
import 'package:virtuwatch/services/recommendation_service.dart';

import 'support/emulator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(TestEnv.ensureReady);

  group('IT-05 Chat Assistant Grounding', () {
    late TestUser customer;
    late Map<String, String> ids;

    setUp(() async {
      await TestEnv.reset();
      final seeded = await TestEnv.seedCatalog([
        sampleWatch(name: 'Grounded Watch', lugToLugMm: 48),
        sampleWatch(
          name: 'Other Watch',
          lugToLugMm: 70,
          colorHexes: const ['#FFFFFF'],
        ),
      ]);
      ids = seeded.ids;
      customer = await TestEnv.registerCustomer();
      await AuthService().saveWristMeasurement(60.0, method: 'screen');
      await AuthService().saveOutfitColors(const [
        {'hex': '#000000', 'percentage': 100.0},
      ]);
    });

    test(
      'a watch-scoped chat is grounded on the on-screen match score',
      () async {
        final watchData = await TestEnv.watchDoc(ids['Grounded Watch']!);
        final rec = await RecommendationService().scoreWatch(
          watchId: ids['Grounded Watch']!,
          data: watchData,
        );

        final chat = ChatService.forWatch(
          watchData: watchData,
          userProfile: await TestEnv.userDoc(customer.uid),
          recommendation: rec,
        );
        final prompt = chat.systemPromptForTesting;

        expect(prompt, contains('Overall match score: ${rec.matchPercent}%'));
        expect(prompt, contains('Fit: ${rec.fitNote}'));
        if (rec.colorNote != null) {
          expect(prompt, contains('Color match: ${rec.colorNote}'));
        }
        expect(prompt, contains('Name: Grounded Watch'));
      },
    );

    test(
      'a recommendations chat lists every ranked watch with its score',
      () async {
        final result = await RecommendationService().getRecommendations();
        final prompt = ChatService.forRecommendations(result)
            .systemPromptForTesting;

        for (final rec in result.recommendations) {
          expect(prompt, contains('[id: ${rec.watchId}]'));
          expect(prompt, contains('Match score: ${rec.matchPercent}%'));
          expect(prompt, contains('Fit: ${rec.fitNote}'));
        }
        expect(prompt, contains('Wrist width: 60.0mm'));

        // Best match is listed before the worst, as the prompt promises.
        final ranked = result.recommendations;
        expect(
          prompt.indexOf('[id: ${ranked.first.watchId}]'),
          lessThan(prompt.indexOf('[id: ${ranked.last.watchId}]')),
        );
      },
    );

    test(
      'after the profile changes, the assistant receives the new scores',
      () async {
        final first = await RecommendationService().getRecommendations();
        final chat = ChatService.forRecommendations(first);

        await AuthService().saveWristMeasurement(75.0, method: 'screen');
        final second = await RecommendationService().getRecommendations();
        chat.updateRecommendations(second);
        final prompt = chat.systemPromptForTesting;

        expect(prompt, contains('Wrist width: 75.0mm'));
        expect(prompt, isNot(contains('Wrist width: 60.0mm')));
        for (final rec in second.recommendations) {
          expect(prompt, contains('Match score: ${rec.matchPercent}%'));
        }
      },
    );

    test('chat history is saved per user and reloaded intact', () async {
      final key = 'watch_${ids['Grounded Watch']}';
      final messages = [
        const ChatMessage(role: 'user', text: 'Will this fit my wrist?'),
        ChatMessage(
          role: 'model',
          text: 'Yes, it is well proportioned.',
          watchIds: [ids['Grounded Watch']!],
        ),
      ];
      await ChatHistoryService().save(key, messages);

      final loaded = await ChatHistoryService().load(key);
      expect(loaded.map((m) => m.role), ['user', 'model']);
      expect(loaded.map((m) => m.text), messages.map((m) => m.text));
      expect(loaded.last.watchIds, [ids['Grounded Watch']]);

      final stored = await FirebaseFirestore.instance
          .collection('users')
          .doc(customer.uid)
          .collection('chatThreads')
          .doc(key)
          .get();
      expect(stored.exists, isTrue);
    });
  });
}
