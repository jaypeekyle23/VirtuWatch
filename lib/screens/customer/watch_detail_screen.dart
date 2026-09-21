import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/watch_colors.dart';
import '../../services/recommendation_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/match_score_color.dart';
import '../../widgets/watch_chat_sheet.dart';
import 'ar_try_on_screen.dart';

class WatchDetailScreen extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const WatchDetailScreen({
    super.key,
    required this.watchId,
    required this.data,
  });

  @override
  State<WatchDetailScreen> createState() => _WatchDetailScreenState();
}

class _WatchDetailScreenState extends State<WatchDetailScreen> {
  final _userService = UserService();
  final _recommendationService = RecommendationService();

  // VirtuWatch doesn't process purchases in-app — Urbane Time handles
  // inquiries and sales themselves, so every watch routes here regardless
  // of which merchant listed it.
  static final Uri _urbaneTimeFacebookUrl =
      Uri.parse('https://www.facebook.com/urbanetime');

  WatchRecommendation? _match;
  bool _loadingMatch = true;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: recording a view is a nice-to-have for the
    // "Recently Viewed" section and should never block or interrupt
    // someone looking at a watch's details, so failures are swallowed.
    _userService.recordRecentlyViewed(widget.watchId).catchError((_) {});
    _loadMatch();
  }

  Future<void> _loadMatch() async {
    try {
      final rec = await _recommendationService.scoreWatch(
        watchId: widget.watchId,
        data: widget.data,
      );
      if (mounted) setState(() => _match = rec);
    } catch (_) {
      // Match card is a nice-to-have, not core to viewing the watch — if
      // scoring fails (e.g. offline), just hide it rather than showing an
      // error over the whole screen.
    } finally {
      if (mounted) setState(() => _loadingMatch = false);
    }
  }

  Future<void> _inquireViaFacebook(BuildContext context) async {
    try {
      final launched = await launchUrl(
        _urbaneTimeFacebookUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Facebook. Please try again.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Facebook. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchId = widget.watchId;
    final data = widget.data;
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final targetGender = data['targetGender'] as String?;
    final colorHexesRaw = (data['colorHexes'] as List?)?.cast<String>();
    final legacyColorHex = data['colorHex'] as String?;
    final colorHexes = (colorHexesRaw != null && colorHexesRaw.isNotEmpty)
        ? colorHexesRaw
        : (legacyColorHex != null ? [legacyColorHex] : const <String>[]);
    final caseDiameter = data['caseDiameterMm'];
    final caseThickness = data['caseThicknessMm'];
    final lugToLug = data['lugToLugMm'];
    final bandWidth = data['bandWidthMm'];
    final movementType = data['movementType'] as String? ?? '';
    final waterResistance = data['waterResistance'] as String? ?? '';
    final bandMaterial = data['bandMaterial'] as String? ?? '';
    final caseMaterial = data['caseMaterial'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final imageUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final photoUrls = imageUrls.isNotEmpty
        ? imageUrls
        : (imageUrl.isNotEmpty ? [imageUrl] : <String>[]);

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userService.currentUserStream(),
            builder: (context, snapshot) {
              final saved = (snapshot.data?.data()?['savedWatches'] as List?)
                      ?.cast<String>() ??
                  [];
              final isSaved = saved.contains(watchId);

              return IconButton(
                icon: Icon(
                  isSaved ? Icons.favorite : Icons.favorite_border,
                  color: isSaved ? Colors.redAccent : null,
                ),
                onPressed: () async {
                  try {
                    await _userService.toggleSavedWatch(watchId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isSaved
                                ? 'Removed from saved watches'
                                : 'Saved to your favorites',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WatchPhotoCarousel(imageUrls: photoUrls),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontSize: 20),
                        ),
                      ),
                      if (price != null)
                        Text(
                          'PHP $price',
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_match?.fitScore != null && _match!.fitScore! >= 0.8)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.greenAccent, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'RECOMMENDED FIT',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (style.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            style.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (targetGender != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            targetGender.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (colorHexes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final hex in colorHexes.take(3))
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: hexToColor(hex),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white24,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              // Plain-language name(s) alongside the
                              // swatches, using the same lookup the
                              // chatbot uses (palette name, or a
                              // hue-based description for a custom
                              // color) — so the screen and the AI
                              // describe a watch's color the same way,
                              // instead of leaving the customer to read
                              // a colored dot on their own.
                              Text(
                                colorHexes
                                    .take(3)
                                    .map((hex) =>
                                        paletteNameForHex(hex) ??
                                        describeHexColor(hex))
                                    .join(' / '),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_loadingMatch)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        height: 88,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  else if (_match != null) ...[
                    _matchCard(_match!),
                    const SizedBox(height: 16),
                  ],

                  Text(
                    'Specifications',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (caseDiameter != null)
                          _specRow('Case Diameter', '${caseDiameter}mm'),
                        if (caseThickness != null)
                          _specRow('Case Thickness', '${caseThickness}mm'),
                        if (lugToLug != null)
                          _specRow('Lug-to-Lug', '${lugToLug}mm'),
                        if (bandWidth != null)
                          _specRow('Band Width', '${bandWidth}mm'),
                        if (bandMaterial.isNotEmpty)
                          _specRow('Band Material', bandMaterial),
                        if (caseMaterial.isNotEmpty)
                          _specRow('Case Material', caseMaterial),
                        if (movementType.isNotEmpty)
                          _specRow('Movement', movementType),
                        if (waterResistance.isNotEmpty)
                          _specRow('Water Resistance', waterResistance,
                              isLast: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: const Color(0xFF0E1A2B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _inquireViaFacebook(context),
                      icon: const Icon(Icons.facebook),
                      label: const Text('Inquire via Urbane Time'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.gold,
                        side: const BorderSide(color: AppTheme.gold),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArTryOnScreen(
                              initialWatchId: watchId,
                              initialWatchData: data,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.view_in_ar_outlined),
                      label: const Text('Try On in AR'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.gold,
                        side: const BorderSide(color: AppTheme.gold),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => showWatchChatSheet(
                        context,
                        watchId: watchId,
                        watchData: data,
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Ask About This Watch'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The "AI Style Match" card: shows [rec]'s combined match score, a
  /// plain-language verdict label (Great/Good/Fair/Weak/Poor match, same
  /// bands the chat assistant uses), and which signals (fit/style/color)
  /// actually contributed to it, so the percentage never implies more
  /// confidence than the data supports.
  Widget _matchCard(WatchRecommendation rec) {
    final match = rec.matchPercent;
    final matchColor = matchScoreColor(match, signalCount: rec.signalCount);

    final activeSignals = [
      if (rec.fitScore != null) 'fit',
      if (rec.styleScore != null) 'style',
      if (rec.colorScore != null) 'color',
    ];
    final subtitle = activeSignals.isEmpty
        ? 'Complete your profile for a personalized match score'
        : 'Based on your ${_joinWithAnd(activeSignals)} ${activeSignals.length == 1 ? 'preference' : 'preferences'}';

    final hasOutfitColor = rec.colorScore != null;
    final colorMatches = hasOutfitColor && rec.colorScore! >= 0.65;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI STYLE MATCH',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$match%',
                          style: TextStyle(
                            color: matchColor,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: matchColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            matchVerdictLabel(match, signalCount: rec.signalCount),
                            style: TextStyle(
                              color: matchColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        value: rec.combinedScore,
                        strokeWidth: 5,
                        backgroundColor: matchColor.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation(matchColor),
                      ),
                    ),
                    Text(
                      '$match%',
                      style: TextStyle(
                        color: matchColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rec.confidenceNote != null) ...[
            const SizedBox(height: 10),
            Text(
              rec.confidenceNote!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                rec.fitScore != null
                    ? (rec.fitScore! >= 0.8
                        ? Icons.check_box
                        : Icons.indeterminate_check_box)
                    : Icons.check_box_outline_blank,
                size: 16,
                color: rec.fitScore != null
                    ? (rec.fitScore! >= 0.8
                        ? Colors.greenAccent
                        : Colors.orangeAccent)
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rec.fitNote,
                  style: TextStyle(
                    color: rec.fitScore != null
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasOutfitColor
                    ? (colorMatches
                        ? Icons.check_box
                        : Icons.indeterminate_check_box)
                    : Icons.check_box_outline_blank,
                size: 16,
                color: hasOutfitColor
                    ? (colorMatches ? Colors.greenAccent : Colors.orangeAccent)
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasOutfitColor
                      ? (rec.colorNote ?? 'Outfit color compared')
                      : 'Outfit color match — scan an outfit to compare',
                  style: TextStyle(
                    color: hasOutfitColor
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _joinWithAnd(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} & ${items.last}';
  }

  Widget _specRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/// Swipeable photo carousel for a watch's detail screen. Falls back to
/// the generic watch icon if the watch has no photos on file at all.
class _WatchPhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;

  const _WatchPhotoCarousel({required this.imageUrls});

  @override
  State<_WatchPhotoCarousel> createState() => _WatchPhotoCarouselState();
}

class _WatchPhotoCarouselState extends State<_WatchPhotoCarousel> {
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
            Container(
              color: AppTheme.surface,
              child: const Center(
                child: Icon(Icons.watch, size: 100, color: AppTheme.gold),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                return Container(
                  color: AppTheme.surface,
                  child: Image.network(
                    photos[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.watch, size: 100, color: AppTheme.gold),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                );
              },
            ),
          if (photos.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(photos.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.gold
                          : Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}