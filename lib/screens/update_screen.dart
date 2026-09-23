import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';

/// The reliable, checkable replacement for the one-shot "update
/// available" system notification (see UpdateCheckerService). One
/// screen shared by all three roles — the logic is identical for
/// customer, merchant, and admin, so there's no reason to build it
/// three times. Reachable from each role's profile tab, and from
/// [UpdateAvailableBanner] on each home/dashboard tab.
///
/// Reads and writes [UpdateCheckerService.status], the same
/// [ValueNotifier] the home-screen banner listens to, so this screen
/// and the banner can never disagree about whether an update is
/// available — "Check for Updates" here updates state everyone shares.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final _service = UpdateCheckerService.instance;

  bool _checking = false;
  bool _downloading = false;
  double? _progress;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    // Covers the edge case of opening this screen before AuthGate's
    // fire-and-forget post-login check has resolved — without this, a
    // very early open would just sit on a null status with nothing to
    // show until something else happened to trigger a check.
    if (_service.status.value == null) {
      _checkNow();
    }
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    await _service.refreshStatus();
    if (!mounted) return;
    setState(() => _checking = false);
  }

  Future<void> _download(String apkUrl) async {
    setState(() {
      _downloading = true;
      _progress = null;
      _downloadError = null;
    });
    try {
      await _service.downloadAndInstall(
        apkUrl,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _downloading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: ValueListenableBuilder<UpdateCheckResult?>(
        valueListenable: _service.status,
        builder: (context, result, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionCard(
                  title: 'Current Version',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'v${AppVersion.versionName}',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _checking || _downloading ? null : _checkNow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.gold,
                          side: const BorderSide(color: AppTheme.gold),
                        ),
                        icon: _checking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.gold,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: Text(
                            _checking ? 'Checking...' : 'Check for Updates'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildStatusSection(result),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusSection(UpdateCheckResult? result) {
    if (result == null) {
      return _sectionCard(
        title: 'Status',
        child: const Text(
          'Checking for updates...',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    if (result.checkFailed) {
      return _sectionCard(
        title: 'Status',
        child: const Text(
          "Couldn't check for updates. Check your connection and try "
          'again.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    if (!result.isUpdateAvailable) {
      return _sectionCard(
        title: 'Status',
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.gold, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're on the latest version.",
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // An update is available.
    final notes = result.releaseNotes?.trim() ?? '';
    return _sectionCard(
      title: 'Update Available — v${result.latestVersion}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notes.isNotEmpty) ...[
            Text(
              notes,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!Platform.isAndroid) ...[
            const Text(
              'In-app install is only supported on Android. Open this '
              "release's page on an Android device to download it.",
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ] else if (_downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 6,
                backgroundColor: AppTheme.background,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _progress != null
                  ? 'Downloading... ${(_progress! * 100).round()}%'
                  : 'Downloading...',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Keep the app open until this finishes.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ] else ...[
            if (_downloadError != null) ...[
              Text(
                'Update failed: $_downloadError',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _download(result.apkUrl!),
                child: Text(
                  _downloadError != null
                      ? 'Retry Download'
                      : 'Download & Install',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.gold,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}