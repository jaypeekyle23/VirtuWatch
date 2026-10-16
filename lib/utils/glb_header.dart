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
