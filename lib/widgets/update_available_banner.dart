import 'package:flutter/material.dart';

import '../screens/update_screen.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';

/// Home/dashboard-tab banner that reminds the user an update is
/// available and points them at [UpdateScreen] — this is the reminder
/// half of the reliable, in-app replacement for the old one-shot system
/// notification (see UpdateCheckerService).
///
/// Purely reactive: it reflects [UpdateCheckerService.status], whatever
/// check has already run (once per login via AuthGate, or on-demand
/// from [UpdateScreen]'s "Check for Updates" button), rather than
/// hitting the network itself. Dropped into all three home/dashboard
/// tabs identically.
///
/// Dismissing it only hides it for as long as this widget instance
/// stays alive. Each home/dashboard tab is kept alive in its shell's
/// IndexedStack for the whole signed-in session, so in practice that
/// means "dismissed for this session" — it reappears on the next app
/// open, and would also reappear immediately if [status] ever reported
/// a newer version than whatever was available when it was dismissed.
class UpdateAvailableBanner extends StatefulWidget {
  const UpdateAvailableBanner({super.key});

  @override
  State<UpdateAvailableBanner> createState() => _UpdateAvailableBannerState();
}

class _UpdateAvailableBannerState extends State<UpdateAvailableBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateCheckResult?>(
      valueListenable: UpdateCheckerService.instance.status,
      builder: (context, result, _) {
        if (_dismissed || result == null || !result.isUpdateAvailable) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UpdateScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: AppTheme.hairline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update available · v${result.latestVersion}',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to download and install.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _dismissed = true),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        color: AppTheme.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}