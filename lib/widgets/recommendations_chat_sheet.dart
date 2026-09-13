import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/recommendation_service.dart';
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
    createChatService: () async => ChatService.forRecommendations(result),
  );
}