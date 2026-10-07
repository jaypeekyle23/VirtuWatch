import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';

/// One action button shown under an assistant message (e.g. "Measure my
/// wrist"). Styled as a gold outlined pill so it reads as tappable and
/// stays visually distinct from the watch cards above it.
class ChatActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Filled look, used for a completed state like "Saved".
  final bool highlighted;

  const ChatActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width * 0.85, 360),
      ),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.gold,
          backgroundColor:
              highlighted ? AppTheme.gold.withValues(alpha: 0.15) : null,
          side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.6)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Save-watch button that follows the customer's live saved list, so
/// it shows "Saved" once saved (and never gets out of sync with the heart
/// on the watch detail screen). Tapping it again removes the watch.
class ChatSaveWatchButton extends StatelessWidget {
  static final _userService = UserService();

  final String watchId;
  final String watchName;

  const ChatSaveWatchButton({
    super.key,
    required this.watchId,
    required this.watchName,
  });

  Future<void> _toggle(BuildContext context) async {
    try {
      await _userService.toggleSavedWatch(watchId);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your saved watches.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userService.currentUserStream(),
      builder: (context, snapshot) {
        final saved =
            (snapshot.data?.data()?['savedWatches'] as List?)?.contains(watchId) ??
                false;
        return ChatActionButton(
          icon: saved ? Icons.favorite : Icons.favorite_border,
          label: saved ? 'Saved $watchName' : 'Save $watchName',
          highlighted: saved,
          // Wait for the first snapshot so a tap can't act on a guess.
          onPressed: snapshot.hasData ? () => _toggle(context) : null,
        );
      },
    );
  }
}