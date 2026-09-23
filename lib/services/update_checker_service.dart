import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_version.dart';
import '../utils/version_compare.dart';
import 'notification_service.dart';

/// Result of checking GitHub for the latest VirtuWatch release.
///
/// This is the single source of truth for "is an update available" —
/// both the one-shot post-login check (AuthGate) and the on-demand
/// "Check for Updates" button (UpdateScreen) go through the same
/// fetch/parse logic and produce one of these, so a home-screen banner
/// and the Updates screen can never disagree about current status.
@immutable
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    this.latestVersion,
    this.apkUrl,
    this.releaseNotes,
    this.checkFailed = false,
  });

  /// The version baked into the app that's currently running (i.e.
  /// [AppVersion.versionName] at the moment this check ran).
  final String currentVersion;

  /// The version tag of the latest GitHub release, with any leading
  /// 'v' stripped. Null if the check failed, or the release had no
  /// usable tag.
  final String? latestVersion;

  /// Direct download URL for that release's .apk asset. Null if the
  /// check failed, or the release has no .apk attached.
  final String? apkUrl;

  /// The release's description/body text, shown as-is in UpdateScreen.
  final String? releaseNotes;

  /// True if the GitHub API call itself failed (network error, rate
  /// limited, non-200 response, malformed JSON). Distinct from "no
  /// update available" — that's a successful check with nothing newer.
  final bool checkFailed;

  /// True only when the check succeeded, a release exists with an
  /// attached APK, and its version is genuinely newer than what's
  /// currently installed — never just "a release exists."
  bool get isUpdateAvailable =>
      !checkFailed &&
      latestVersion != null &&
      apkUrl != null &&
      isNewerVersion(latestVersion!, currentVersion);
}

/// Checks GitHub's releases API for a newer VirtuWatch build than the
/// one currently installed, exposes the result to any screen that wants
/// it via [status], and can download + install an available update.
///
/// This deliberately doesn't use Firebase Cloud Messaging or any
/// backend: nothing is being pushed here, the app is just polling a
/// public API it already has network access to.
class UpdateCheckerService {
  UpdateCheckerService._();
  static final UpdateCheckerService instance = UpdateCheckerService._();

  static const _lastNotifiedVersionKey =
      'update_checker_last_notified_version';

  // If no new bytes arrive within this window during a download, the
  // connection is treated as stalled and the download is aborted with
  // an error, instead of hanging with no feedback.
  static const Duration _stallTimeout = Duration(seconds: 20);

  /// The most recent check result, broadcast app-wide so home-screen
  /// banners and UpdateScreen can reflect current status without each
  /// independently hitting the GitHub API. Null means no check has run
  /// yet this session. Updated by both [checkForUpdate] and
  /// [refreshStatus].
  final ValueNotifier<UpdateCheckResult?> status = ValueNotifier(null);

  Future<UpdateCheckResult> _fetchLatestRelease() async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/${AppVersion.githubOwner}/'
        '${AppVersion.githubRepo}/releases/latest',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          currentVersion: AppVersion.versionName,
          checkFailed: true,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?) ?? '';
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;

      final assets = (data['assets'] as List?) ?? [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (asset) => (asset['name'] as String? ?? '').endsWith('.apk'),
            orElse: () => const {},
          );

      return UpdateCheckResult(
        currentVersion: AppVersion.versionName,
        latestVersion: latestVersion.isEmpty ? null : latestVersion,
        apkUrl: apkAsset['browser_download_url'] as String?,
        releaseNotes: data['body'] as String?,
      );
    } catch (_) {
      return UpdateCheckResult(
        currentVersion: AppVersion.versionName,
        checkFailed: true,
      );
    }
  }

  /// Runs a check, updates [status] for any listening UI, and — if this
  /// is a genuinely newer version we haven't already notified about —
  /// shows a local "update available" notification.
  ///
  /// Meant to be called once per app open/resume (see AuthGate). Never
  /// throws; a failed check just leaves [status] reflecting the
  /// failure, and the notification step is skipped without affecting
  /// [status] either way.
  Future<void> checkForUpdate() async {
    final result = await _fetchLatestRelease();
    status.value = result;

    if (!result.isUpdateAvailable || !Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastNotifiedVersionKey) == result.latestVersion) {
        return; // Already notified about this exact version.
      }
      await NotificationService.instance.showUpdateAvailable(
        versionLabel: 'v${result.latestVersion}',
        apkUrl: result.apkUrl!,
      );
      await prefs.setString(_lastNotifiedVersionKey, result.latestVersion!);
    } catch (_) {
      // The notification is a nice-to-have on top of `status` — the
      // home banner and Updates screen still work without it.
    }
  }

  /// Re-runs the check on demand — e.g. the "Check for Updates" button
  /// in UpdateScreen — and updates [status]. Unlike [checkForUpdate],
  /// this never shows a system notification: the user is already
  /// looking at the Updates screen, so one would be redundant.
  Future<UpdateCheckResult> refreshStatus() async {
    final result = await _fetchLatestRelease();
    status.value = result;
    return result;
  }

  /// Downloads the APK at [apkUrl] to the app's cache directory and
  /// opens it with the system package installer. Requires the
  /// REQUEST_INSTALL_PACKAGES permission and the FileProvider entry
  /// declared in AndroidManifest.xml.
  ///
  /// Streams the response straight to disk instead of buffering the
  /// whole file in memory, and reports progress through [onProgress] as
  /// a 0.0 to 1.0 value (or null if the server didn't report a content
  /// length). If no new data arrives for [_stallTimeout], the download
  /// is aborted and this throws, instead of hanging with no feedback.
  ///
  /// The app needs to stay open for this to finish — nothing here runs
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