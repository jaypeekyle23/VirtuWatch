import 'package:flutter/material.dart';
import '../screens/customer/watch_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'network_photo.dart';
import 'skeleton_box.dart';

/// Lays [tiles] out two per row. Rows size to their content, so there is
/// no guessed aspect ratio and no blank space under tiles on any screen
/// width.
List<Widget> watchGridRows(List<Widget> tiles) => [
      for (var i = 0; i < tiles.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: 14),
              Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
    ];

/// Opens [onTap] with the photo's Hero tag, or the customer detail screen
/// when no override is given.
void _openWatch(BuildContext context, String watchId, Map<String, dynamic> data,
    String heroTag, void Function(String heroTag)? onTap) {
  if (onTap != null) return onTap(heroTag);
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          WatchDetailScreen(watchId: watchId, data: data, heroTag: heroTag),
    ),
  );
}

/// One watch as a filled card: square photo flush at the top, then brand,
/// name and optionally price and size. Takes the width its parent gives it
/// (a fixed-width slot in the horizontal rows, half the screen in the grid).
class WatchTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  /// Keeps this tile's photo Hero tag unique when the same watch appears
  /// in more than one section on this screen.
  final String heroScope;
  final bool showPrice;

  /// Replaces the default tap (the customer detail screen), e.g. for merchants.
  final void Function(String heroTag)? onTap;

  /// Extra row under the details, such as merchant status and actions.
  final Widget? footer;

  const WatchTile({
    super.key,
    required this.watchId,
    required this.data,
    required this.heroScope,
    this.showPrice = false,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = data['imageUrl'] as String? ?? '';
    final price = data['price'];
    final size = data['caseDiameterMm'];
    final heroTag = '$heroScope-photo-$watchId';
    final fallback = Center(
      child: Icon(Icons.watch, size: 30, color: AppTheme.textSecondary),
    );

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openWatch(context, watchId, data, heroTag, onTap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ColoredBox(
                color: AppTheme.background,
                child: imageUrl.isEmpty
                    ? fallback
                    : Hero(
                        tag: heroTag,
                        child: NetworkPhoto(
                            url: imageUrl, errorWidget: fallback),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The brand line and the 2-line name box are always
                  // rendered at a fixed height, so a missing brand or a
                  // short name never leaves a card shorter than its
                  // neighbors.
                  Text(
                    (data['brand'] as String? ?? '').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 32,
                    child: Text(
                      data['name'] as String? ?? 'Unnamed Watch',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (showPrice)
                    SizedBox(
                      height: 18,
                      child: price is num
                          ? Text.rich(
                              TextSpan(
                                text: formatPeso(price),
                                style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                                children: [
                                  if (size != null)
                                    TextSpan(
                                      text: '  ·  ${size}mm',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w400),
                                    ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                    ),
                  if (footer != null) ...[const SizedBox(height: 6), footer!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder with the same layout as [WatchTile], shown while data loads.
class WatchTileSkeleton extends StatelessWidget {
  final bool showPrice;

  /// Reserves the height of a [WatchTile.footer].
  final bool showFooter;

  const WatchTileSkeleton({
    super.key,
    this.showPrice = false,
    this.showFooter = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 1,
            child: SkeletonBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.zero,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  height: 12,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(width: 40, height: 8),
                  ),
                ),
                const SizedBox(height: 2),
                const SizedBox(
                  height: 32,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 90, height: 11),
                      SizedBox(height: 5),
                      SkeletonBox(width: 60, height: 11),
                    ],
                  ),
                ),
                if (showPrice)
                  const SizedBox(
                    height: 18,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SkeletonBox(width: 70, height: 12),
                    ),
                  ),
                if (showFooter) const SizedBox(height: 34),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Height of a list row without a footer. The photo is a square of this size,
/// and the row is tall enough for a 2-line name, size and style, and price.
const double _listRowHeight = 120;

/// Extra row height for a footer: the 6px gap plus a 28px footer.
const double _listFooterHeight = 34;

/// Single-column row: a filled card with the photo flush on the left and the
/// details beside it. Takes the same [onTap] and [footer] as [WatchTile].
class WatchListTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final String heroScope;
  final void Function(String heroTag)? onTap;
  final Widget? footer;

  const WatchListTile({
    super.key,
    required this.watchId,
    required this.data,
    required this.heroScope,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = '$heroScope-photo-$watchId';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final price = data['price'];
    final size = data['caseDiameterMm'];
    final style = data['styleCategory'] as String? ?? '';
    final sub = [if (size != null) '${size}mm', if (style.isNotEmpty) style]
        .join(' · ');
    final fallback = Center(
      child: Icon(Icons.watch, size: 32, color: AppTheme.textSecondary),
    );

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openWatch(context, watchId, data, heroTag, onTap),
        child: SizedBox(
          height: _listRowHeight + (footer == null ? 0 : _listFooterHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _listRowHeight,
                child: ColoredBox(
                  color: AppTheme.background,
                  child: imageUrl.isEmpty
                      ? fallback
                      : Hero(
                          tag: heroTag,
                          child:
                              NetworkPhoto(url: imageUrl, errorWidget: fallback),
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (data['brand'] as String? ?? '').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data['name'] as String? ?? 'Unnamed Watch',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                      if (price is num) ...[
                        const SizedBox(height: 6),
                        Text(formatPeso(price),
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: 6),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shaped like [WatchListTile].
class WatchListTileSkeleton extends StatelessWidget {
  final bool showFooter;

  const WatchListTileSkeleton({super.key, this.showFooter = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _listRowHeight + (showFooter ? _listFooterHeight : 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SkeletonBox(
              width: _listRowHeight,
              height: double.infinity,
              borderRadius: BorderRadius.zero),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 9),
                  SizedBox(height: 8),
                  SkeletonBox(width: 140, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 70, height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}