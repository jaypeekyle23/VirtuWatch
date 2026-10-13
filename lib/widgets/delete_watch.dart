import 'package:flutter/material.dart';
import '../services/watch_service.dart';
import '../theme/app_theme.dart';

/// Asks for confirmation, then deletes the watch. Returns whether it was
/// deleted, so the caller can show a message or leave a screen that was
/// showing it.
Future<bool> confirmDeleteWatch(
  BuildContext context, {
  required String watchId,
  required String name,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Delete watch?', style: AppTheme.serif(size: 22)),
      content: Text(
        'This will permanently remove "$name" from the catalog.',
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child:
              const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  await WatchService().deleteWatch(watchId, watchLabel: name);
  return true;
}