import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/watch_colors.dart';
import '../../services/auth_service.dart';
import '../../services/recommendation_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/match_score_color.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/recommendations_chat_sheet.dart';
import '../../widgets/skeleton_box.dart';
import 'edit_profile_screen.dart';
import 'outfit_scan_screen.dart';
import 'watch_detail_screen.dart';

class RecommendedForYouScreen extends StatefulWidget {
  const RecommendedForYouScreen({super.key});

  @override
  State<RecommendedForYouScreen> createState() =>
      _RecommendedForYouScreenState();
}

class _RecommendedForYouScreenState extends State<RecommendedForYouScreen> {
  static const _filters = ['All', 'Best Fit', 'Newest', 'Your Style'];
  static BoxDecoration get _rowDivider =>
      BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.hairline)));

  final _recommendationService = RecommendationService();
  final _authService = AuthService();
  String _selectedFilter = 'All';
  RecommendationResult? _result;
  bool _isLoading = true;
  bool _isLoadingPreferences = false;
  bool _isClearingOutfit = false;
  String? _loadError;
  StreamSubscription<RecommendationResult>? _recommendationSub;

  @override
  void initState() {
    super.initState();
    // Live listener: re-scores by itself whenever wrist width, outfit
    // colors, style or budget change, from any screen.
    _recommendationSub =
        _recommendationService.watchRecommendations().listen(
      (result) {
        if (!mounted) return;
        setState(() {
          _result = result;
          _isLoading = false;
          _loadError = null;
        });
      },
      onError: (_) {
        if (!mounted) return;
        // Keep showing the last good result if there is one.
        if (_result == null) {
          setState(() {
            _loadError = 'Could not load recommendations. Please try again.';
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _recommendationSub?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Manual one-time reload, used by pull to refresh, the retry button, and
  /// the chat sheet as a backup to the live listener.
  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final result = await _recommendationService.getRecommendations();
      if (!mounted) return;
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load recommendations. Please try again.';
        _isLoading = false;
      });
    }
  }

  List<WatchRecommendation> _filtered(List<WatchRecommendation> all) {
    switch (_selectedFilter) {
      case 'Best Fit':
        return all.where((r) => r.fitScore != null).toList()
          ..sort((a, b) => b.fitScore!.compareTo(a.fitScore!));
      case 'Newest':
        return [...all]..sort((a, b) {
            final x = a.data['createdAt'], y = b.data['createdAt'];
            return x is Timestamp && y is Timestamp ? y.compareTo(x) : 0;
          });
      case 'Your Style':
        return all.where((r) => r.styleScore == 1.0).toList();
      default:
        return all;
    }
  }

  Future<void> _scanOutfit() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const OutfitScanScreen()));
  }

  Future<void> _openUpdatePreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoadingPreferences = true);
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditProfileScreen(
            currentUsername: data['username'] as String? ?? 'User',
            currentEmail: data['email'] as String? ?? '',
            currentStylePreferences:
                (data['stylePreferences'] as List?)?.cast<String>() ?? [],
            currentPreferredBrands:
                (data['preferredBrands'] as List?)?.cast<String>() ?? [],
            currentBudgetMin: (data['budgetMin'] as num?)?.toDouble() ?? 0,
            currentBudgetMax:
                (data['budgetMax'] as num?)?.toDouble() ?? 50000,
            currentPhotoUrl: data['photoUrl'] as String? ?? '',
            currentGender: data['gender'] as String?,
          ),
        ),
      );
    } catch (_) {
      _snack('Could not load your preferences. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoadingPreferences = false);
    }
  }

  Future<void> _confirmClearOutfitColors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Remove outfit colors?', style: AppTheme.serif(size: 22)),
        content: Text(
          'Recommendations will stop factoring in outfit color until you '
          'scan an outfit again.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isClearingOutfit = true);
    try {
      await _authService.clearOutfitColors();
      _snack('Outfit colors removed.');
    } catch (e) {
      _snack('Could not remove outfit colors: $e');
    } finally {
      if (mounted) setState(() => _isClearingOutfit = false);
    }
  }

  void _openChat() => showRecommendationsChatSheet(
        context,
        result: _result!,
        // Lets the chat's action buttons re-score this list too, then hand
        // the fresh result back to the chat.
        onProfileChanged: () async {
          await _loadRecommendations();
          return _result;
        },
      );

  void _showHowItWorks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('How matches are scored', style: AppTheme.serif(size: 22)),
        content: Text(
          'Fit compares your wrist width with each watch\'s lug-to-lug size.\n\n'
          'Style checks your saved preferences against the watch\'s category.\n\n'
          'Color compares your latest outfit scan with the watch\'s colors.\n\n'
          'Anything missing is skipped, so a match is built from the signals '
          'you have. Matches with limited data are shown in gray.',
          style:
              TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered(_result?.recommendations ?? []);
    return Scaffold(
      appBar: AppBar(
        title: Text('For You', style: AppTheme.serif(size: 28)),
        actions: [
          if (_result != null)
            TextButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Ask AI'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.gold),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            _summary(),
            const SizedBox(height: 24),
            _filterTabs(),
            Divider(height: 1, color: AppTheme.hairline),
            if (_isLoading)
              ...List.generate(4, (_) => const _RowSkeleton())
            else if (_loadError != null)
              _message(_loadError!, retry: true)
            else if (list.isEmpty)
              _message(_selectedFilter == 'Your Style'
                  ? 'No watches match your style preferences yet.'
                  : 'No watches in the catalog yet.')
            else
              for (final rec in list) _row(rec),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final wrist = _result?.wristWidthMm;
    final styles = _result?.stylePreferences ?? [];
    final colors = _result?.outfitColors ?? [];
    final line = [
      wrist != null
          ? 'Tailored to your ${wrist.toStringAsFixed(1)}mm wrist'
          : 'Add your wrist size for better fit',
      if (styles.isNotEmpty) styles.join(', '),
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line,
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            _link('PREFERENCES',
                _isLoadingPreferences ? null : _openUpdatePreferences),
            const SizedBox(width: 20),
            _link('OUTFIT', _scanOutfit),
            if (colors.isNotEmpty) ...[
              const SizedBox(width: 8),
              for (final c in colors.take(4))
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: hexToColor(c['hex'] as String? ?? '#808080'),
                    shape: BoxShape.circle,
                  ),
                ),
              InkWell(
                onTap: _isClearingOutfit ? null : _confirmClearOutfitColors,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close,
                      size: 14, color: AppTheme.textSecondary),
                ),
              ),
            ],
            const Spacer(),
            InkWell(
              onTap: _showHowItWorks,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.info_outline,
                    size: 16, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _link(String label, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: onTap == null
                  ? AppTheme.textSecondary
                  : AppTheme.textPrimary,
              fontSize: 11,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );

  Widget _filterTabs() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in _filters)
              InkWell(
                onTap: () => setState(() => _selectedFilter = f),
                child: Container(
                  margin: const EdgeInsets.only(right: 24),
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: f == _selectedFilter
                            ? AppTheme.gold
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      color: f == _selectedFilter
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _message(String text, {bool retry = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary)),
            if (retry)
              TextButton(
                onPressed: _loadRecommendations,
                child: const Text('Retry'),
              ),
          ],
        ),
      );

  Widget _row(WatchRecommendation rec) {
    final d = rec.data;
    final brand = (d['brand'] as String? ?? '').toUpperCase();
    final price = (d['price'] as num?)?.toDouble();
    final imageUrl = d['imageUrl'] as String? ?? '';
    final style = d['styleCategory'] as String? ?? '';
    final sub = [
      if (d['caseDiameterMm'] != null) '${d['caseDiameterMm']}mm',
      if (style.isNotEmpty) style,
    ].join(' · ');
    final over = price != null ? price - (_result?.budgetMax ?? 50000) : 0;
    final fullData = rec.signalCount == 3;
    final heroTag =
        'recommended-${identityHashCode(ModalRoute.of(context))}-photo-${rec.watchId}';
    final fallback = Icon(Icons.watch, color: AppTheme.textSecondary);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WatchDetailScreen(
              watchId: rec.watchId, data: d, heroTag: heroTag),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: _rowDivider,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 72,
                height: 72,
                child: ColoredBox(
                  color: AppTheme.surface,
                  child: imageUrl.isEmpty
                      ? fallback
                      : Hero(
                          tag: heroTag,
                          child: NetworkPhoto(
                              url: imageUrl, errorWidget: fallback),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(brand,
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            letterSpacing: 1.4)),
                  const SizedBox(height: 2),
                  Text(d['name'] as String? ?? 'Unnamed Watch',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  if (price != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(formatPeso(price),
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        if (over > 0)
                          Flexible(
                            child: Text(
                              '  ·  ${formatPeso(over)} over budget',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${rec.matchPercent}%',
                    style: AppTheme.serif(
                        size: 24,
                        color: fullData &&
                                rec.matchPercent >= goodMatchThreshold
                            ? AppTheme.gold
                            : AppTheme.textSecondary)),
                if (!fullData)
                  Text('limited data',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder matching the shape of a list row.
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: _RecommendedForYouScreenState._rowDivider,
      child: const Row(
        children: [
          SkeletonBox(
              width: 72,
              height: 72,
              borderRadius: BorderRadius.all(Radius.circular(4))),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 50, height: 8),
                SizedBox(height: 8),
                SkeletonBox(width: 150, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}