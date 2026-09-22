import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_version.dart';
import '../utils/version_compare.dart';
import 'notification_service.dart';

/// Checks GitHub's releases API for a newer VirtuWatch build than the
/// one currently installed, and shows a local notification if one
/// exists. Tapping that notification triggers [downloadAndInstall],
/// which downloads the release's APK asset and hands it to the Android
/// package installer.
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

  // If no new bytes arrive within this window during a download, the
  // connection is treated as stalled and the download is aborted with
  // an error, instead of hanging with no feedback (this is what caused
  // the "closed the app, still old version" issue: the download had
  // no timeout at all, so a dead connection just sat there silently).
  static const Duration _stallTimeout = Duration(seconds: 20);

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
          !isNewerVersion(latestVersion, AppVersion.versionName)) {
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

  /// Downloads the APK at [apkUrl] to the app's cache directory and
  /// opens it with the system package installer. Requires the
  /// REQUEST_INSTALL_PACKAGES permission and the FileProvider entry
  /// declared in AndroidManifest.xml.
  ///
  /// Streams the response straight to disk instead of buffering the
  /// whole file in memory, and reports progress through [onProgress] as
  /// a 0.0 to 1.0 value (or null if the server didn't report a content
  /// length, so progress can't be computed). If no new data arrives for
  /// [_stallTimeout], the download is aborted and this throws, instead
  /// of hanging with no feedback.
  ///
  /// The app needs to stay open for this to finish. Nothing here runs
  /// as a background service, so closing or swiping the app away will
  /// still interrupt an in-progress download.
  Future<void> downloadAndInstall(
    String apkUrl, {
    void Function(double? progress)? onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    Timer? stallTimer;

    try {
      final request = http.Request('GET', Uri.parse(apkUrl));
      final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw 'Could not connect to download the update.',
          );

      if (streamedResponse.statusCode != 200) {
        throw 'Download failed (HTTP ${streamedResponse.statusCode}).';
      }

      final total = streamedResponse.contentLength;
      var received = 0;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/virtuwatch_update.apk');
      sink = file.openWrite();

      final completer = Completer<void>();

      void resetStallTimer() {
        stallTimer?.cancel();
        stallTimer = Timer(_stallTimeout, () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              'Download stalled (no data received for ${_stallTimeout.inSeconds}s).',
            );
          }
        });
      }

      resetStallTimer();

      subscription = streamedResponse.stream.listen(
        (chunk) {
          sink!.add(chunk);
          received += chunk.length;
          resetStallTimer();
          if (total != null && total > 0) {
            onProgress?.call(received / total);
          } else {
            onProgress?.call(null);
          }
        },
        onDone: () {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          stallTimer?.cancel();
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;
      await sink.flush();
      await sink.close();
      sink = null;

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw result.message;
      }
    } finally {
      stallTimer?.cancel();
      await subscription?.cancel();
      await sink?.close();
      client.close();
    }
  }
}