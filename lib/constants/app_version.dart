/// Single source of truth for the app's current version/build, plus the
/// GitHub repo the in-app update checker (see UpdateCheckerService)
/// polls for new releases.
///
/// Kept as plain constants read by hand, rather than via a package like
/// package_info_plus, matching VersionInfoScreen's existing tradeoff of
/// avoiding a new dependency for a couple of static strings. Update
/// [versionName] and [buildNumber] here (not in VersionInfoScreen) when
/// cutting a new release, since VersionInfoScreen now reads from here.
class AppVersion {
  AppVersion._();

  static const String versionName = '1.1.5';
  static const String buildNumber = '1';

  /// The GitHub owner/repo the update checker polls via
  /// `GET /repos/<githubOwner>/<githubRepo>/releases/latest`.
  ///
  /// Make sure each release you cut there is tagged `v<versionName>`
  /// (e.g. `v1.1.0`) with a `.apk` file attached as a release asset —
  /// the update checker looks for both.
  static const String githubOwner = 'jaypeekyle23';
  static const String githubRepo = 'VirtuWatch';
}
