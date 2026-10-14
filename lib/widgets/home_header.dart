import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'network_photo.dart';

/// Top of a role's home tab: logo with a profile avatar, then a time-of-day
/// greeting and a one-line [subtitle]. Matches the customer home layout.
class HomeHeader extends StatelessWidget {
  final String username;
  final String photoUrl;
  final String subtitle;
  final VoidCallback onAvatarTap;

  const HomeHeader({
    super.key,
    required this.username,
    required this.photoUrl,
    required this.subtitle,
    required this.onAvatarTap,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 84,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -48,
                top: -48,
                child: Image.asset(AppTheme.logoAsset,
                    height: 180, fit: BoxFit.contain),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: onAvatarTap,
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.outline),
                      ),
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: AppTheme.surface,
                        backgroundImage: photoUrl.isNotEmpty
                            ? NetworkPhoto.provider(photoUrl)
                            : null,
                        child: photoUrl.isEmpty
                            ? Text(initials.isEmpty ? '?' : initials,
                                style: AppTheme.serif(size: 16))
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('$_greeting,\n$username',
            style: AppTheme.serif(size: 32).copyWith(height: 1.1)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 24),
      ],
    );
  }
}