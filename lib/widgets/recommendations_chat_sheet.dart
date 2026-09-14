import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/recommendation_service.dart';
import '../services/user_service.dart';
import 'chat_sheet.dart';

/// Opens a chat scoped to the user's current recommendation list — lets
/// them ask about, compare, or get advice across any watch already
/// ranked for them, using the same match/fit scores shown on-screen.
Future<void> showRecommendationsChatSheet(
  BuildContext context, {
  required RecommendationResult result,
}) {
  return showChatSheet(
    context,
    title: 'Ask VirtuWatch',
    emptyStateHint: 'Ask about your recommended watches — "which fits my '
        'budget best?", "compare the top two", or "what should I get for '
        'a formal look?"',
    threadKey: 'recommendations',
    suggestedQuestions: const [
      'Which fits my budget best?',
      'What matches my style?',
      'Compare the top two',
    ],
    createChatService: () async {
      List<Map<String, dynamic>>? savedWatches;
      try {
        savedWatches = await UserService().fetchSavedWatchesBrief();
      } catch (_) {
        // Fall back to chatting without this context rather than
        // blocking the whole feature.
      }
      return ChatService.forRecommendations(result, savedWatches: savedWatches);
    },
  );
}