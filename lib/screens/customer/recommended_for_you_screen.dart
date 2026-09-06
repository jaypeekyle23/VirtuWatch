import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'outfit_scan_screen.dart';

class RecommendedForYouScreen extends StatefulWidget {
  const RecommendedForYouScreen({super.key});

  @override
  State<RecommendedForYouScreen> createState() =>
      _RecommendedForYouScreenState();
}

class _RecommendedForYouScreenState extends State<RecommendedForYouScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Best Fit', 'Trending', 'Your Style'];

  final List<Map<String, dynamic>> _mockRecommendations = const [
    {
      'brand': 'SEIKO',
      'name': 'Seiko Prospex SPB143',
      'match': 94,
      'price': 'PHP 15,500',
      'fitNote': 'Fits your 62.3mm wrist',
      'tag': '42mm · Sport',
    },
    {
      'brand': 'ORIENT',
      'name': 'Orient Bambino V2',
      'match': 88,
      'price': 'PHP 8,200',
      'fitNote': 'Matches outfit tones',
      'tag': '40.5mm · Classic',
    },
    {
      'brand': 'TISSOT',
      'name': 'Tissot PRX Powermatic',
      'match': 82,
      'price': 'PHP 29,500',
      'fitNote': 'Fits your 62.3mm wrist',
      'tag': '39.5mm · Luxury',
    },
    {
      'brand': 'CASIO',
      'name': 'Casio G-Shock GA-2100',
      'match': 77,
      'price': 'PHP 6,800',
      'fitNote': 'Matches outfit tones',
      'tag': '45.4mm · Sport',
    },
    {
      'brand': 'CITIZEN',
      'name': 'Citizen Eco-Drive BM8550',
      'match': 91,
      'price': 'PHP 11,500',
      'fitNote': 'Fits your 62.3mm wrist',
      'tag': '40mm · Classic',
    },
    {
      'brand': 'SEIKO',
      'name': 'Seiko 5 Sports SRPD51',
      'match': 85,
      'price': 'PHP 9,500',
      'fitNote': 'Matches outfit tones',
      'tag': '42.5mm · Casual',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('For You')),
      body: SingleChildScrollView(
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
                      _basisChip('WRIST: 62.3MM', AppTheme.gold),
                      _basisChip('CLASSIC', Colors.blueAccent),
                      _basisChip('LUXURY', Colors.purpleAccent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Update Preferences coming soon')),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('Update Preferences →',
                        style: TextStyle(color: AppTheme.gold, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OutfitScanScreen(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_outlined, color: AppTheme.gold),
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
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = _selectedFilter == filter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedFilter = filter),
                    backgroundColor: AppTheme.surface,
                    selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
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

            ..._mockRecommendations.map((watch) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _recommendationTile(watch),
                )),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These are placeholder recommendations. Real AI-based '
                      'matching (wrist size + outfit color) is coming soon.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
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

  Widget _recommendationTile(Map<String, dynamic> watch) {
    final match = watch['match'] as int;
    final matchColor = match >= 90
        ? Colors.greenAccent
        : match >= 80
            ? AppTheme.gold
            : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.watch, color: AppTheme.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watch['brand'] as String,
                  style: TextStyle(
                    color: AppTheme.gold,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  watch['name'] as String,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${watch['fitNote']} · ${watch['tag']}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  watch['price'] as String,
                  style: const TextStyle(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        ],
      ),
    );
  }
}