import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/recommendation_service.dart';
import '../theme/app_theme.dart';
import '../utils/match_score_color.dart';
import 'network_photo.dart';

/// A compact, tappable preview of one watch, shown under an assistant
/// message in the recommendations chat. Tapping it opens the watch's
/// detail screen (the caller supplies [onTap]).
///
/// Built from a [WatchRecommendation] so the match percent and verdict
/// color are exactly the ones shown on the Recommended For You list.
///
/// When [heroTag] is set, the photo is wrapped in a [Hero] with that tag.
/// The caller passes the same tag to WatchDetailScreen so the photo flies
/// into the detail screen like photos do elsewhere in the app. The tag
/// must be unique among everything on screen in the chat.
class ChatWatchCard extends StatelessWidget {
  final WatchRecommendation rec;
  final VoidCallback onTap;
  final String? heroTag;

  const ChatWatchCard({
    super.key,
    required this.rec,
    required this.onTap,
    this.heroTag,
  });

  static String _formatPrice(num price) {
    final digits = price.round().toString();
    final withCommas = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return 'PHP $withCommas';
  }

  Widget _maybeHero(Widget photo) {
    final tag = heroTag;
    return tag == null ? photo : Hero(tag: tag, child: photo);
  }

  @override
  Widget build(BuildContext context) {
    final data = rec.data;
    final brand = (data['brand'] as String? ?? '').toUpperCase();
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final price = data['price'] as num?;
    final caseDiameter = data['caseDiameterMm'];
    final styleCategory = data['styleCategory'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final detail = [
      if (caseDiameter != null) '${caseDiameter}mm',
      if (styleCategory.isNotEmpty) styleCategory,
    ].join(' · ');

    final match = rec.matchPercent;
    final matchColor = matchScoreColor(match, signalCount: rec.signalCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      // Fixed width (not shrink-to-fit) so every card in a chat is the
      // same size no matter how long its name is.
      width: math.min(MediaQuery.of(context).size.width * 0.85, 360),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: AppTheme.background,
                    child: imageUrl.isNotEmpty
                        ? _maybeHero(
                            NetworkPhoto(
                              url: imageUrl,
                              errorWidget: const Icon(Icons.watch,
                                  color: AppTheme.gold),
                            ),
                          )
                        : const Icon(Icons.watch, color: AppTheme.gold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (brand.isNotEmpty)
                        Text(
                          brand,
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (price != null)
                        Text(
                          _formatPrice(price),
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: matchColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$match%',
                        style: TextStyle(
                          color: matchColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(Icons.chevron_right,
                        color: AppTheme.textSecondary, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}