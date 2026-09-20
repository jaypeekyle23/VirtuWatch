import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_version.dart';
import 'notification_service.dart';

/// Checks GitHub's releases API for a newer VirtuWatch build than the
/// one currently installed, and shows a local notification if one
/// exists. Tapping that notification triggers [downloadAndInstall],
/// which downloads the release's APK asset and hands it to the Android
/// package installer — the same "tap the notification, it grabs the
/// APK for you" flow apps like Metrolist use for GitHub-distributed
/// releases.
///
/// This deliberately doesn't use Firebase Cloud Messaging or any
/// backend: nothing is being pushed here, the app is just polling a
/// public API it already has network access to. [checkForUpdate] is
/// meant to be called once per app open/resume (see AuthGate), not on a
/// background schedule.
class UpdateCheckerService {
  UpdateCheckerService._();
  static final UpdateCheckerService instance = UpdateCheckerService._();

  static const _lastNotifiedVersionKey =
      'update_checker_last_notified_version';

  /// Fetches the latest GitHub release and, if it's newer than
  /// [AppVersion.versionName] and hasn't already been notified about,
  /// shows an "update available" notification. Silently does nothing on
  /// any failure (no connection, rate-limited, no release yet, etc.) —
  /// a failed check should never interrupt app startup.
  Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) return; // APK installs only make sense here.

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/${AppVersion.githubOwner}/'
        '${AppVersion.githubRepo}/releases/latest',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;
      if (latestVersion.isEmpty ||
          !_isNewer(latestVersion, AppVersion.versionName)) {
        return;
      }

      final assets = (data['assets'] as List?) ?? [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (asset) => (asset['name'] as String? ?? '').endsWith('.apk'),
            orElse: () => const {},
          );
      final apkUrl = apkAsset['browser_download_url'] as String?;
      if (apkUrl == null) return; // Release exists but has no APK attached.

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastNotifiedVersionKey) == latestVersion) {
        return; // Already notified about this exact version.
      }

      await NotificationService.instance.showUpdateAvailable(
        versionLabel: 'v$latestVersion',
        apkUrl: apkUrl,
      );
      await prefs.setString(_lastNotifiedVersionKey, latestVersion);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Naive dotted-integer version comparison (1.2.10 > 1.2.9). Falls
  /// back to a plain string comparison if either side isn't purely
  /// dotted numbers — an unusual tag name should never trigger a false
  /// "update available".
  bool _isNewer(String remote, String current) {
    final remoteParts = remote.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();
    if (remoteParts.contains(null) || currentParts.contains(null)) {
      return remote != current && remote.compareTo(current) > 0;
    }
    for (var i = 0; i < remoteParts.length || i < currentParts.length; i++) {
      final r = i < remoteParts.length ? remoteParts[i]! : 0;
      final c = i < currentParts.length ? currentParts[i]! : 0;
      if (r != c) return r > c;
    }
    return false;
  }

  /// Downloads the APK at [apkUrl] to the app's cache directory and
  /// opens it with the system package installer. Requires the
  /// REQUEST_INSTALL_PACKAGES permission and the FileProvider entry
  /// declared in AndroidManifest.xml.
  Future<void> downloadAndInstall(String apkUrl) async {
    final response = await http.get(Uri.parse(apkUrl));
    if (response.statusCode != 200) {
      throw 'Download failed (HTTP ${response.statusCode}).';
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/virtuwatch_update.apk');
    await file.writeAsBytes(response.bodyBytes);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw result.message;
    }
  }
}