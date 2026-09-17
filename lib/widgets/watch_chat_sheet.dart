import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/recommendation_service.dart';
import '../services/user_service.dart';
import 'chat_sheet.dart';

/// Opens the "Ask about this watch" chat, scoped to one watch's data
/// plus the current user's profile (wrist width, style, budget).
Future<void> showWatchChatSheet(
  BuildContext context, {
  required String watchId,
  required Map<String, dynamic> watchData,
}) {
  final name = watchData['name'] as String? ?? 'this watch';

  return showChatSheet(
    context,
    title: 'Ask about $name',
    emptyStateHint: 'Ask anything about $name — fit, materials, style, or '
        'how to wear it.',
    threadKey: 'watch_$watchId',
    suggestedQuestions: const [
      'Will this fit my wrist?',
      'What outfit suits this watch?',
      'How do I care for it?',
    ],
    createChatService: () async {
      // Load the current user's profile so the assistant can answer
      // fit/style questions using data the user already saved, instead
      // of asking for it again.
      Map<String, dynamic>? userProfile;
      List<Map<String, dynamic>>? savedWatches;
      WatchRecommendation? recommendation;
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          userProfile = doc.data();
        }
        savedWatches = await UserService().fetchSavedWatchesBrief();
        // Same fit/color/style/match-score breakdown as the on-screen
        // match card, so the chatbot's answers about this watch's score
        // never disagree with what the customer already sees.
        recommendation = await RecommendationService().scoreWatch(
          watchId: watchId,
          data: watchData,
        );
      } catch (_) {
        // Fall back to chatting without profile/score context rather
        // than blocking the whole feature.
      }
      return ChatService.forWatch(
        watchData: watchData,
        userProfile: userProfile,
        savedWatches: savedWatches,
        recommendation: recommendation,
      );
    },
  );
}