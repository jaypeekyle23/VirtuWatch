import 'package:flutter/material.dart';
import '../constants/watch_colors.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'luxe.dart';
import 'network_photo.dart';

/// Photo URLs for a watch: its gallery, or the single cover image.
List<String> watchPhotos(Map<String, dynamic> data) {
  final gallery = (data['imageUrls'] as List?)?.cast<String>() ?? [];
  final cover = data['imageUrl'] as String? ?? '';
  return gallery.isNotEmpty ? gallery : (cover.isNotEmpty ? [cover] : []);
}

/// Color hexes for a watch, falling back to the older single `colorHex`.
List<String> watchColorHexes(Map<String, dynamic> data) {
  final hexes = (data['colorHexes'] as List?)?.cast<String>();
  final legacy = data['colorHex'] as String?;
  if (hexes != null && hexes.isNotEmpty) return hexes;
  return legacy != null ? [legacy] : const [];
}

/// Brand, name, price, and a line of style, gender and color names. Colors
/// use the same lookup as the chatbot, so the screen and the AI name a
/// watch's colors the same way.
class WatchHeadline extends StatelessWidget {
  final Map<String, dynamic> data;

  const WatchHeadline(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    String text(String key) => data[key] as String? ?? '';
    final price = data['price'];
    final hexes = watchColorHexes(data);
    final meta = [
      text('styleCategory'),
      text('targetGender'),
      hexes
          .take(3)
          .map((h) => paletteNameForHex(h) ?? describeHexColor(h))
          .join(' / '),
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text('brand').isNotEmpty)
          Text(text('brand').toUpperCase(), style: kLabelStyle),
        const SizedBox(height: 6),
        Text(data['name'] as String? ?? 'Unnamed Watch',
            style: AppTheme.serif(size: 30)),
        if (price is num) ...[
          const SizedBox(height: 6),
          Text(formatPeso(price),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              for (final hex in hexes.take(3))
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: hexToColor(hex),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.outline),
                  ),
                ),
              if (hexes.isNotEmpty) const SizedBox(width: 4),
              Expanded(
                child: Text(meta,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The SPECIFICATIONS section, listing only the specs a watch has.
/// Empty when it has none.
Widget watchSpecsSection(Map<String, dynamic> data) {
  String text(String key) => data[key] as String? ?? '';
  final specs = <(String, String)>[
    for (final (label, key) in const [
      ('Case diameter', 'caseDiameterMm'),
      ('Case thickness', 'caseThicknessMm'),
      ('Lug-to-lug', 'lugToLugMm'),
      ('Band width', 'bandWidthMm'),
    ])
      if (data[key] != null) (label, '${data[key]}mm'),
    for (final (label, key) in const [
      ('Band material', 'bandMaterial'),
      ('Case material', 'caseMaterial'),
      ('Movement', 'movementType'),
      ('Water resistance', 'waterResistance'),
    ])
      if (text(key).isNotEmpty) (label, text(key)),
  ];
  if (specs.isEmpty) return const SizedBox.shrink();

  return luxeSection(
    'SPECIFICATIONS',
    Column(
      children: [
        for (final (label, value) in specs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Swipeable photo carousel. Falls back to a generic watch icon if the
/// watch has no photos on file at all. Only the first photo takes part in a
/// Hero flight from [heroTag].
class WatchPhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final String? heroTag;

  const WatchPhotoCarousel({super.key, required this.imageUrls, this.heroTag});

  @override
  State<WatchPhotoCarousel> createState() => _WatchPhotoCarouselState();
}

class _WatchPhotoCarouselState extends State<WatchPhotoCarousel> {
  static Widget get _fallback =>
      Center(child: Icon(Icons.watch, size: 100, color: AppTheme.textSecondary));

  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.imageUrls;

    return AspectRatio(
      aspectRatio: 1.1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            ColoredBox(color: AppTheme.surface, child: _fallback)
          else
            PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final photo = ColoredBox(
                  color: AppTheme.surface,
                  child:
                      NetworkPhoto(url: photos[index], errorWidget: _fallback),
                );
                return index == 0 && widget.heroTag != null
                    ? Hero(tag: widget.heroTag!, child: photo)
                    : photo;
              },
            ),
          if (photos.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _currentPage ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: i == _currentPage ? 0.9 : 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}