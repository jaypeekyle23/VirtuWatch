import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../constants/watch_colors.dart';
import '../../services/recommendation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recommendations_chat_sheet.dart';
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
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Best Fit', 'Newest', 'Your Style'];

  final _recommendationService = RecommendationService();
  RecommendationResult? _result;
  bool _isLoadingRecommendations = true;
  String? _loadError;

  bool _isLoadingPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _isLoadingRecommendations = true;
      _loadError = null;
    });
    try {
      final result = await _recommendationService.getRecommendations();
      if (!mounted) return;
      setState(() {
        _result = result;
        _isLoadingRecommendations = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load recommendations. Please try again.';
        _isLoadingRecommendations = false;
      });
    }
  }

  List<WatchRecommendation> _filtered(List<WatchRecommendation> all) {
    switch (_selectedFilter) {
      case 'Best Fit':
        final withFit = all.where((r) => r.fitScore != null).toList()
          ..sort((a, b) => b.fitScore!.compareTo(a.fitScore!));
        return withFit;
      case 'Newest':
        final sorted = [...all];
        sorted.sort((a, b) {
          final aTime = a.data['createdAt'];
          final bTime = b.data['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          return 0;
        });
        return sorted;
      case 'Your Style':
        return all.where((r) => r.styleScore == 1.0).toList();
      case 'All':
      default:
        return all;
    }
  }

  Future<void> _openUpdatePreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoadingPreferences = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
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
            currentBudgetMin: (data['budgetMin'] as num?)?.toDouble() ?? 5000,
            currentBudgetMax:
                (data['budgetMax'] as num?)?.toDouble() ?? 50000,
            currentPhotoUrl: data['photoUrl'] as String? ?? '',
          ),
        ),
      );
      // Preferences may have changed — re-score the catalog against them.
      _loadRecommendations();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load your preferences. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingPreferences = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wristWidthMm = _result?.wristWidthMm;
    final stylePreferences = _result?.stylePreferences ?? [];
    final outfitColors = _result?.outfitColors ?? [];
    final filtered = _filtered(_result?.recommendations ?? []);

    return Scaffold(
      appBar: AppBar(title: const Text('For You')),
      floatingActionButton: _result == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showRecommendationsChatSheet(
                context,
                result: _result!,
              ),
              backgroundColor: AppTheme.gold,
              icon: const Icon(Icons.chat_bubble_outline,
                  color: Color(0xFF0E1A2B)),
              label: const Text(
                'Ask VirtuWatch',
                style: TextStyle(
                  color: Color(0xFF0E1A2B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _loadRecommendations,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'BASED ON',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Icon(Icons.info_outline,
                            color: AppTheme.textSecondary, size: 16),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _basisChip(
                          wristWidthMm != null
                              ? 'WRIST: ${wristWidthMm.toStringAsFixed(1)}MM'
                              : 'WRIST: NOT SET',
                          AppTheme.gold,
                        ),
                        if (stylePreferences.isEmpty)
                          _basisChip('NO STYLE PREFS SET', Colors.blueAccent)
                        else
                          for (final style in stylePreferences)
                            _basisChip(style.toUpperCase(), Colors.blueAccent),
                        if (outfitColors.isEmpty)
                          _basisChip('NO OUTFIT SCANNED', Colors.purpleAccent)
                        else
                          _outfitColorChip(outfitColors),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed:
                          _isLoadingPreferences ? null : _openUpdatePreferences,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                      ),
                      child: _isLoadingPreferences
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.gold,
                              ),
                            )
                          : const Text('Update Preferences →',
                              style: TextStyle(
                                  color: AppTheme.gold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OutfitScanScreen(),
                    ),
                  );
                  // A new scan may have changed the user's outfit colors —
                  // re-score the catalog against them.
                  _loadRecommendations();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.photo_camera_outlined,
                          color: AppTheme.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan Today\'s Outfit',
                              style: TextStyle(
                                color: AppTheme.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Text(
                              'Get color-matched recommendations via AI',
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppTheme.gold),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = _selectedFilter == filter;
                    return ChoiceChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedFilter = filter),
                      backgroundColor: AppTheme.surface,
                      selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color:
                            isSelected ? AppTheme.gold : AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppTheme.gold : Colors.transparent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              if (_isLoadingRecommendations)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(_loadError!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loadRecommendations,
                        child: const Text('Retry',
                            style: TextStyle(color: AppTheme.gold)),
                      ),
                    ],
                  ),
                )
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    _selectedFilter == 'Your Style'
                        ? 'No watches match your style preferences yet.'
                        : 'No watches in the catalog yet.',
                    style: const TextStyle(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...filtered.map((rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _recommendationTile(
                        rec,
                        budgetMin: _result?.budgetMin ?? 5000,
                        budgetMax: _result?.budgetMax ?? 50000,
                      ),
                    )),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppTheme.textSecondary, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Recommendations are ranked by wrist fit, outfit '
                        'color, and style match.',
                        style:
                            TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _basisChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _outfitColorChip(List<Map<String, dynamic>> colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.purpleAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'OUTFIT:',
            style: TextStyle(
              color: Colors.purpleAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          for (final entry in colors.take(4))
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: hexToColor(entry['hex'] as String? ?? '#808080'),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recommendationTile(
    WatchRecommendation rec, {
    required double budgetMin,
    required double budgetMax,
  }) {
    final match = rec.matchPercent;
    final matchColor = match >= 90
        ? Colors.greenAccent
        : match >= 80
            ? AppTheme.gold
            : Colors.orangeAccent;

    final data = rec.data;
    final brand = (data['brand'] as String? ?? '').toUpperCase();
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final price = (data['price'] as num?)?.toDouble();
    final priceLabel = price != null ? 'PHP $price' : '';
    final caseDiameter = data['caseDiameterMm'];
    final styleCategory = data['styleCategory'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final tag = [
      if (caseDiameter != null) '${caseDiameter}mm',
      if (styleCategory.isNotEmpty) styleCategory,
    ].join(' · ');
    final noteLine = [
      rec.fitNote,
      if (rec.colorNote != null) rec.colorNote!,
      if (tag.isNotEmpty) tag,
    ].join(' · ');

    String? budgetLabel;
    Color budgetColor = AppTheme.textSecondary;
    if (price != null) {
      if (price > budgetMax) {
        budgetLabel = 'PHP ${(price - budgetMax).toStringAsFixed(0)} over budget';
        budgetColor = Colors.orangeAccent;
      } else if (price < budgetMin) {
        budgetLabel = 'Below your budget range';
        budgetColor = AppTheme.textSecondary;
      } else {
        budgetLabel = 'Within budget';
        budgetColor = Colors.greenAccent;
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                WatchDetailScreen(watchId: rec.watchId, data: data),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: AppTheme.background,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.watch, color: AppTheme.gold),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      )
                    : const Icon(Icons.watch, color: AppTheme.gold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand,
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
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
                  Text(
                    noteLine,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (priceLabel.isNotEmpty)
                    Row(
                      children: [
                        Text(
                          priceLabel,
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (budgetLabel != null) ...[
                          const SizedBox(width: 6),
                          // Flexible + ellipsis: "Below your budget" is
                          // long enough that priceLabel + this combined
                          // can exceed the row's available width (e.g.
                          // on a brand-new account with no fit/style
                          // data shortening everything else above this
                          // row) — without this it throws a RenderFlex
                          // overflow instead of just truncating.
                          Flexible(
                            child: Text(
                              '· $budgetLabel',
                              style: TextStyle(
                                color: budgetColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                if (rec.confidenceNote != null) ...[
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 90,
                    child: Text(
                      rec.confidenceNote!,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}