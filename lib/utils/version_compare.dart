/// Naive dotted-integer version comparison (1.2.10 > 1.2.9), used by
/// [UpdateCheckerService] to decide whether a GitHub release tag is newer
/// than the currently installed build. Pulled out into its own file so
/// the comparison rules can be unit tested directly.
///
/// Falls back to a plain string comparison if either side isn't purely
/// dotted numbers — an unusual tag name should never trigger a false
/// "update available".
bool isNewerVersion(String remote, String current) {
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