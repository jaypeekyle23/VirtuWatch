/// A binary glTF (.glb) always starts with the ASCII magic "glTF".
///
/// Used at upload time (to catch a renamed or corrupt file before it reaches
/// Cloudinary) and after download (so a server error page saved under a .glb
/// name is never handed to the renderer).
bool isGlbHeader(List<int> firstBytes) =>
    firstBytes.length >= 4 &&
    firstBytes[0] == 0x67 && // g
    firstBytes[1] == 0x6C && // l
    firstBytes[2] == 0x54 && // T
    firstBytes[3] == 0x46; //   F

/// The total file length a .glb declares in its 12-byte header (bytes 8-11,
/// little-endian), or null when [firstBytes] is shorter than 12 bytes or
/// isn't a .glb at all.
///
/// A finished download should be at least this long. If it is shorter, the
/// transfer was cut off (or the file was truncated when it was uploaded).
int? glbDeclaredLength(List<int> firstBytes) {
  if (firstBytes.length < 12 || !isGlbHeader(firstBytes)) return null;
  return firstBytes[8] |
      (firstBytes[9] << 8) |
      (firstBytes[10] << 16) |
      (firstBytes[11] << 24);
}
