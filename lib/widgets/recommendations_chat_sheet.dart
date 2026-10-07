import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/customer/ar_try_on_screen.dart';
import '../screens/customer/edit_profile_screen.dart';
import '../screens/customer/outfit_scan_screen.dart';
import '../screens/customer/saved_watches_screen.dart';
import '../screens/customer/watch_detail_screen.dart';
import '../screens/customer/wrist_measurement_screen.dart';
import '../services/chat_service.dart';
import '../services/recommendation_service.dart';
import '../services/user_service.dart';
import 'chat_action_buttons.dart';
import 'chat_sheet.dart';
import 'chat_watch_card.dart';

/// Opens a chat scoped to the user's current recommendation list — lets
/// them ask about, compare, or get advice across any watch already
/// ranked for them, using the same match/fit scores shown on-screen.
///
/// The assistant can attach watch cards and action buttons to its replies.
/// Some buttons (measure wrist, scan outfit, edit preferences) change the
/// data the scores are built from, so when the customer comes back from
/// one, the list is re-scored and the assistant is given the fresh scores.
/// [onProfileChanged] lets the calling screen do that re-scoring itself
/// (so its own list updates too) and hand the result back; without it,
/// the chat loads a fresh list on its own.
Future<void> showRecommendationsChatSheet(
  BuildContext context, {
  required RecommendationResult result,
  Future<RecommendationResult?> Function()? onProfileChanged,
}) {
  // The latest scored list. Starts as the one passed in and is replaced
  // after a profile-changing action.
  var current = result;
  var closed = false;
  ChatService? service;
  // Bumped after a refresh so cards already on screen redraw with the new
  // match percents.
  final refreshTick = ValueNotifier<int>(0);

  Future<void> refreshAfterProfileChange() async {
    try {
      final fresh = onProfileChanged != null
          ? await onProfileChanged()
          : await RecommendationService().getRecommendations();
      if (fresh == null || closed) return;
      current = fresh;
      service?.updateRecommendations(fresh);
      refreshTick.value++;
    } catch (_) {
      // Keep the old scores; the chat still works.
    }
  }

  Future<void> openEditProfile(NavigatorState navigator) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? {};
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          currentUsername: data['username'] as String? ?? 'User',
          currentEmail: data['email'] as String? ?? '',
          currentStylePreferences:
              (data['stylePreferences'] as List?)?.cast<String>() ?? [],
          currentPreferredBrands:
              (data['preferredBrands'] as List?)?.cast<String>() ?? [],
          currentBudgetMin: (data['budgetMin'] as num?)?.toDouble() ?? 0,
          currentBudgetMax: (data['budgetMax'] as num?)?.toDouble() ?? 50000,
          currentPhotoUrl: data['photoUrl'] as String? ?? '',
        ),
      ),
    );
  }

  Future<void> runAction(BuildContext context, ChatAction action) async {
    final navigator = Navigator.of(context);
    try {
      switch (action.type) {
        case ChatAction.measureWrist:
          await navigator.push(MaterialPageRoute(
            builder: (_) => const WristMeasurementScreen(),
          ));
          await refreshAfterProfileChange();
        case ChatAction.scanOutfit:
          await navigator.push(MaterialPageRoute(
            builder: (_) => const OutfitScanScreen(),
          ));
          await refreshAfterProfileChange();
        case ChatAction.editPreferences:
          await openEditProfile(navigator);
          await refreshAfterProfileChange();
        case ChatAction.tryOn:
          final rec = current.recommendations
              .where((r) => r.watchId == action.watchId)
              .firstOrNull;
          if (rec == null) return;
          await navigator.push(MaterialPageRoute(
            builder: (_) => ArTryOnScreen(
              initialWatchId: rec.watchId,
              initialWatchData: rec.data,
            ),
          ));
        case ChatAction.viewSaved:
          await navigator.push(MaterialPageRoute(
            builder: (_) => const SavedWatchesScreen(),
          ));
      }
    } catch (_) {
      // A failed navigation or profile load shouldn't break the chat.
    }
  }

  Widget? buttonFor(
    BuildContext context,
    ChatAction action,
    Map<String, WatchRecommendation> byId,
  ) {
    final rec = action.watchId != null ? byId[action.watchId] : null;
    final watchName = rec?.data['name'] as String? ?? '';

    switch (action.type) {
      case ChatAction.measureWrist:
        return ChatActionButton(
          icon: Icons.straighten,
          label: 'Measure my wrist',
          onPressed: () => runAction(context, action),
        );
      case ChatAction.scanOutfit:
        return ChatActionButton(
          icon: Icons.camera_alt_outlined,
          label: 'Scan my outfit',
          onPressed: () => runAction(context, action),
        );
      case ChatAction.editPreferences:
        return ChatActionButton(
          icon: Icons.tune,
          label: 'Update my preferences',
          onPressed: () => runAction(context, action),
        );
      case ChatAction.viewSaved:
        return ChatActionButton(
          icon: Icons.favorite_border,
          label: 'View saved watches',
          onPressed: () => runAction(context, action),
        );
      case ChatAction.tryOn:
        if (rec == null) return null;
        return ChatActionButton(
          icon: Icons.view_in_ar_outlined,
          label: watchName.isEmpty ? 'Try on in AR' : 'Try on $watchName',
          onPressed: () => runAction(context, action),
        );
      case ChatAction.saveWatch:
        if (rec == null || action.watchId == null) return null;
        return ChatSaveWatchButton(
          watchId: action.watchId!,
          watchName: watchName.isEmpty ? 'this watch' : watchName,
        );
    }
    return null;
  }

  return showChatSheet(
    context,
    title: 'Ask VirtuWatch AI',
    emptyStateHint: 'Ask about your recommended watches — "which fits my '
        'budget best?", "compare the top two", or "what should I get for '
        'a formal look?"',
    threadKey: 'recommendations',
    suggestedQuestions: const [
      'Which fits my budget best?',
      'What matches my style?',
      'Compare the top two',
    ],
    // Watch cards and action buttons the assistant attached to a reply,
    // looked up from the same ranked list the assistant was given, so a
    // card always shows the exact score the customer sees elsewhere. A
    // watch that no longer exists (e.g. deleted since a saved chat) is
    // simply skipped.
    messageExtrasBuilder: (context, message) {
      return ValueListenableBuilder<int>(
        valueListenable: refreshTick,
        builder: (context, _, _) {
          final byId = {for (final r in current.recommendations) r.watchId: r};

          final cards = <Widget>[];
          final seen = <String>{};
          for (final id in message.watchIds) {
            final rec = byId[id];
            if (rec == null || !seen.add(id)) continue;
            // One tag per message and watch: the same watch can show up in
            // several messages of one chat, and two Heroes on screen with
            // the same tag are not allowed.
            final heroTag = 'chat-photo-${identityHashCode(message)}-$id';
            cards.add(ChatWatchCard(
              rec: rec,
              heroTag: heroTag,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WatchDetailScreen(
                    watchId: rec.watchId,
                    data: rec.data,
                    heroTag: heroTag,
                  ),
                ),
              ),
            ));
          }

          final buttons = <Widget>[];
          for (final action in message.actions) {
            final button = buttonFor(context, action, byId);
            if (button != null) buttons.add(button);
          }

          if (cards.isEmpty && buttons.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...cards,
              if (buttons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
                ),
            ],
          );
        },
      );
    },
    createChatService: () async {
      List<Map<String, dynamic>>? savedWatches;
      try {
        savedWatches = await UserService().fetchSavedWatchesBrief();
      } catch (_) {
        // Fall back to chatting without this context rather than
        // blocking the whole feature.
      }
      final created =
          ChatService.forRecommendations(current, savedWatches: savedWatches);
      service = created;
      return created;
    },
  ).whenComplete(() {
    closed = true;
    refreshTick.dispose();
  });
}