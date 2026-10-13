import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/app_version.dart';
import '../services/update_checker_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

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

  static const _small =
      TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5);

  @override
  Widget build(BuildContext context) {
    final busy = _checking || _downloading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Updates', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: ValueListenableBuilder<UpdateCheckResult?>(
        valueListenable: _service.status,
        builder: (context, result, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              luxeSection(
                'CURRENT VERSION',
                Text('v${AppVersion.versionName}',
                    style: AppTheme.serif(size: 22)),
                trailing: InkWell(
                  onTap: busy ? null : _checkNow,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _checking ? 'CHECKING...' : 'CHECK FOR UPDATES',
                      style: kLabelStyle.copyWith(
                          color: busy
                              ? AppTheme.textSecondary
                              : AppTheme.textPrimary),
                    ),
                  ),
                ),
              ),
              _buildStatusSection(result),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(UpdateCheckResult? result) {
    if (result == null || result.checkFailed || !result.isUpdateAvailable) {
      return luxeSection(
        'STATUS',
        Text(
          result == null
              ? 'Checking for updates...'
              : result.checkFailed
                  ? "Couldn't check for updates. Check your connection and "
                      'try again.'
                  : "You're on the latest version.",
          style: result != null && !result.checkFailed
              ? _small.copyWith(color: AppTheme.textPrimary)
              : _small,
        ),
      );
    }

    // An update is available.
    final notes = result.releaseNotes?.trim() ?? '';
    const caption = TextStyle(color: AppTheme.textSecondary, fontSize: 12);
    return luxeSection(
      'UPDATE AVAILABLE',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text('v${result.latestVersion}', style: AppTheme.serif(size: 22)),
          if (notes.isNotEmpty) Text(notes, style: _small),
          if (!Platform.isAndroid)
            const Text(
              'In-app install is only supported on Android. Open this '
              "release's page on an Android device to download it.",
              style: caption,
            )
          else if (_downloading) ...[
            LinearProgressIndicator(
              value: _progress,
              minHeight: 4,
              backgroundColor: Colors.white24,
              color: AppTheme.textPrimary,
            ),
            Text(
              _progress != null
                  ? 'Downloading... ${(_progress! * 100).round()}%'
                  : 'Downloading...',
              style: caption,
            ),
            const Text('Keep the app open until this finishes.',
                style: caption),
          ] else ...[
            if (_downloadError != null)
              Text('Update failed: $_downloadError',
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _download(result.apkUrl!),
                child: Text(_downloadError != null
                    ? 'Retry Download'
                    : 'Download & Install'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}