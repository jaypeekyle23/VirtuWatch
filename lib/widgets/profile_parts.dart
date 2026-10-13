import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'luxe.dart';
import 'network_photo.dart';

void pushScreen(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

/// Small letter-spaced text button. Gold only when it is the main action.
Widget profileLink(String label, VoidCallback onTap, {bool accent = false}) =>
    InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          label,
          style: kLabelStyle.copyWith(
            color: accent ? AppTheme.gold : AppTheme.textPrimary,
          ),
        ),
      ),
    );

PreferredSizeWidget profileAppBar(BuildContext context) => AppBar(
      title: Text('Profile', style: AppTheme.serif(size: 28)),
      actions: [
        TextButton(
          onPressed: () => confirmLogout(context),
          style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
          child: const Text('Log out'),
        ),
        const SizedBox(width: 8),
      ],
    );

/// Avatar, name and email, with an EDIT PROFILE link.
class ProfileHeader extends StatelessWidget {
  final String username;
  final String email;
  final String photoUrl;
  final VoidCallback onEdit;

  const ProfileHeader({
    super.key,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final initials = username
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e[0])
        .take(2)
        .join()
        .toUpperCase();

    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundColor: AppTheme.surface,
          backgroundImage:
              photoUrl.isNotEmpty ? NetworkPhoto.provider(photoUrl) : null,
          child: photoUrl.isEmpty
              ? Text(initials.isEmpty ? '?' : initials,
                  style: AppTheme.serif(size: 24))
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(size: 26)),
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              profileLink('EDIT PROFILE', onEdit),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hairline-separated menu rows: (title, screen to open, optional trailing text).
Widget profileMenu(
        BuildContext context, List<(String, Widget, String?)> items) =>
    Column(
      children: [
        for (final (title, screen, trailing) in items)
          InkWell(
            onTap: () => pushScreen(context, screen),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: kTopRule,
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                  ),
                  if (trailing != null)
                    Text(trailing,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
      ],
    );

Future<void> confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Log out?', style: AppTheme.serif(size: 22)),
      content: const Text(
        'Are you sure you want to log out of your VirtuWatch account?',
        style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await AuthService().logout();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }
}