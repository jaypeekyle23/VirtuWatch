import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/watch_colors.dart';
import '../../services/recommendation_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/match_score_color.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/save_heart_button.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/watch_chat_sheet.dart';
import 'ar_try_on_screen.dart';

class WatchDetailScreen extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  /// Hero tag of the photo the user tapped on the previous screen, so it
  /// can fly into this screen's first photo. Null when opened from
  /// somewhere without a matching photo (no animation then).
  final String? heroTag;

  const WatchDetailScreen({
    super.key,
    required this.watchId,
    required this.data,
    this.heroTag,
  });

  @override
  State<WatchDetailScreen> createState() => _WatchDetailScreenState();
}

class _WatchDetailScreenState extends State<WatchDetailScreen> {
  final _userService = UserService();
  final _recommendationService = RecommendationService();

  // VirtuWatch doesn't process purchases in-app. Urbane Time handles
  // inquiries and sales themselves, so every watch routes here regardless
  // of which merchant listed it.
  static final Uri _urbaneTimeFacebookUrl =
      Uri.parse('https://www.facebook.com/urbanetime');

  WatchRecommendation? _match;
  bool _loadingMatch = true;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: recording a view only feeds "Recently Viewed" and
    // should never interrupt someone looking at a watch.
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
      // The match section is a nice-to-have. If scoring fails (e.g.
      // offline), hide it instead of showing an error over the screen.
    } finally {
      if (mounted) setState(() => _loadingMatch = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _inquireViaFacebook() async {
    var launched = false;
    try {
      launched = await launchUrl(_urbaneTimeFacebookUrl,
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!launched) _snack('Could not open Facebook. Please try again.');
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    String text(String key) => data[key] as String? ?? '';

    final name = data['name'] as String? ?? 'Unnamed Watch';
    final price = data['price'];
    final rawHexes = (data['colorHexes'] as List?)?.cast<String>();
    final legacyHex = data['colorHex'] as String?;
    final hexes = (rawHexes != null && rawHexes.isNotEmpty)
        ? rawHexes
        : (legacyHex != null ? [legacyHex] : const <String>[]);
    final imageUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final photos = imageUrls.isNotEmpty
        ? imageUrls
        : (text('imageUrl').isNotEmpty ? [text('imageUrl')] : <String>[]);

    // Same lookup the chatbot uses, so the screen and the AI name a
    // watch's colors the same way.
    final meta = [
      text('styleCategory'),
      text('targetGender'),
      hexes
          .take(3)
          .map((h) => paletteNameForHex(h) ?? describeHexColor(h))
          .join(' / '),
    ].where((s) => s.isNotEmpty).join('  ·  ');

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

    const outlined = TextStyle(fontSize: 13);
    final outlinedStyle = OutlinedButton.styleFrom(
      foregroundColor: AppTheme.textPrimary,
      side: const BorderSide(color: Colors.white24),
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: outlined,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Watch Detail', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userService.currentUserStream(),
            builder: (context, snapshot) {
              final saved = (snapshot.data?.data()?['savedWatches'] as List?)
                      ?.cast<String>() ??
                  [];
              final isSaved = saved.contains(widget.watchId);
              return SaveHeartButton(
                isSaved: isSaved,
                onPressed: () async {
                  try {
                    await _userService.toggleSavedWatch(widget.watchId);
                    _snack(isSaved
                        ? 'Removed from saved watches'
                        : 'Saved to your favorites');
                  } catch (e) {
                    _snack(e.toString());
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
            _WatchPhotoCarousel(imageUrls: photos, heroTag: widget.heroTag),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (text('brand').isNotEmpty)
                    Text(text('brand').toUpperCase(), style: kLabelStyle),
                  const SizedBox(height: 6),
                  Text(name, style: AppTheme.serif(size: 30)),
                  if (price is num) ...[
                    const SizedBox(height: 6),
                    Text(formatPeso(price),
                        style: const TextStyle(
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
                              border: Border.all(color: Colors.white24),
                            ),
                          ),
                        if (hexes.isNotEmpty) const SizedBox(width: 4),
                        Expanded(
                          child: Text(meta,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_loadingMatch)
                    const _MatchSkeleton()
                  else if (_match != null)
                    _matchSection(_match!),
                  if (specs.isNotEmpty)
                    luxeSection(
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
                                      style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(value,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _inquireViaFacebook,
                      icon: const Icon(Icons.facebook),
                      label: const Text('Inquire via Urbane Time'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: outlinedStyle,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ArTryOnScreen(
                                initialWatchId: widget.watchId,
                                initialWatchData: data,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                          label: const Text('Try on in AR'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: outlinedStyle,
                          onPressed: () => showWatchChatSheet(
                            context,
                            watchId: widget.watchId,
                            watchData: data,
                          ),
                          icon:
                              const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('Ask AI'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The match block: a ring with the combined score, a plain verdict (same
  /// bands the chat assistant uses), and which signals (fit/style/color)
  /// actually contributed, so the score never implies more confidence than
  /// the data supports. Gold only when all three signals were used and the
  /// match is genuinely good.
  Widget _matchSection(WatchRecommendation rec) {
    final match = rec.matchPercent;
    final accent = rec.signalCount == 3 && match >= goodMatchThreshold
        ? AppTheme.gold
        : AppTheme.textSecondary;
    // The ring fills and the number counts up together. Skipped if
    // animations are off.
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 1100);

    final signals = [
      if (rec.fitScore != null) 'fit',
      if (rec.styleScore != null) 'style',
      if (rec.colorScore != null) 'color',
    ];
    final subtitle = signals.isEmpty
        ? 'Complete your profile for a personalized match score'
        : 'Based on your ${_joinWithAnd(signals)} '
            '${signals.length == 1 ? 'preference' : 'preferences'}';

    return luxeSection(
      'MATCH',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      matchVerdictLabel(match, signalCount: rec.signalCount),
                      style: AppTheme.serif(size: 26),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    if (rec.confidenceNote != null) ...[
                      const SizedBox(height: 4),
                      Text(rec.confidenceNote!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 76,
                height: 76,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  builder: (context, t, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: rec.combinedScore * t,
                          strokeWidth: 3,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                      Text('${(match * t).round()}%',
                          style: AppTheme.serif(size: 24, color: accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _note(rec.fitScore, rec.fitNote, 0.8),
          const SizedBox(height: 8),
          _note(
            rec.colorScore,
            rec.colorScore != null
                ? (rec.colorNote ?? 'Outfit color compared')
                : 'Outfit color: scan an outfit to compare',
            0.65,
          ),
        ],
      ),
    );
  }

  /// One signal line: check when it scores well, dash when it is only
  /// partial, empty circle when there is no data for it.
  Widget _note(double? score, String text, double goodAt) {
    final color = score == null ? AppTheme.textSecondary : AppTheme.textPrimary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            score == null
                ? Icons.radio_button_unchecked
                : (score >= goodAt ? Icons.check : Icons.remove),
            size: 15,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(color: color, fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }

  String _joinWithAnd(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} & ${items.last}';
  }
}

/// Swipeable photo carousel. Falls back to a generic watch icon if the
/// watch has no photos on file at all.
class _WatchPhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final String? heroTag;

  const _WatchPhotoCarousel({required this.imageUrls, this.heroTag});

  @override
  State<_WatchPhotoCarousel> createState() => _WatchPhotoCarouselState();
}

class _WatchPhotoCarouselState extends State<_WatchPhotoCarousel> {
  static const _fallback =
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
            const ColoredBox(color: AppTheme.surface, child: _fallback)
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
                // Only the first photo takes part in the Hero flight.
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

/// Placeholder shaped like the match block while the score loads.
class _MatchSkeleton extends StatelessWidget {
  const _MatchSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: kTopRule,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 60, height: 10),
          SizedBox(height: 12),
          SkeletonBox(width: 110, height: 40),
          SizedBox(height: 10),
          SkeletonBox(width: 200, height: 12),
          SizedBox(height: 16),
          SkeletonBox(width: double.infinity, height: 13),
          SizedBox(height: 8),
          SkeletonBox(width: double.infinity, height: 13),
        ],
      ),
    );
  }
}