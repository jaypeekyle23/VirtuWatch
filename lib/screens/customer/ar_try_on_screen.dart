import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'watch_detail_screen.dart';

/// Placeholder for AR Try-On while the real camera + MediaPipe hand
/// tracking + three_js implementation is being built and tested in a
/// separate Flutter project.
///
/// Keeps the same watch-selection carousel and scale slider so the tab
/// still looks and feels complete, but has no camera/ML/3D code — nothing
/// here starts a camera, runs inference, or renders a 3D scene, so it's
/// safe to keep mounted without any performance or crash risk.
class ArTryOnScreen extends StatefulWidget {
  final String? initialWatchId;
  final Map<String, dynamic>? initialWatchData;

  const ArTryOnScreen({
    super.key,
    this.initialWatchId,
    this.initialWatchData,
  });

  @override
  State<ArTryOnScreen> createState() => _ArTryOnScreenState();
}

class _ArTryOnScreenState extends State<ArTryOnScreen> {
  final _watchService = WatchService();

  String? _selectedWatchId;
  Map<String, dynamic>? _selectedWatchData;
  double _userScaleAdjust = 0;

  @override
  void initState() {
    super.initState();
    _selectedWatchId = widget.initialWatchId;
    _selectedWatchData = widget.initialWatchData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Try-On'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _showShareInfoDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildPlaceholderArea()),
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildPlaceholderArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          color: AppTheme.surface,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.view_in_ar_outlined,
                    size: 72, color: AppTheme.textSecondary),
                SizedBox(height: 12),
                Text(
                  'AR camera preview coming soon',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  'Point your camera at your wrist to try on watches',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              _floatingIcon(Icons.flash_off_outlined),
              const SizedBox(height: 10),
              _floatingIcon(Icons.cameraswitch_outlined),
              const SizedBox(height: 10),
              _floatingIcon(Icons.photo_camera_outlined),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fine-tune size',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text(
                '${_userScaleAdjust >= 0 ? '+' : ''}${_userScaleAdjust.toInt()}%',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.gold,
              thumbColor: AppTheme.gold,
              inactiveTrackColor: AppTheme.background,
            ),
            child: Slider(
              value: _userScaleAdjust,
              min: -20,
              max: 20,
              onChanged: (v) => setState(() => _userScaleAdjust = v),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _watchService.allListedWatches(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];

              if (_selectedWatchId == null && docs.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedWatchId == null) {
                    setState(() {
                      _selectedWatchId = docs.first.id;
                      _selectedWatchData = docs.first.data();
                    });
                  }
                });
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 130,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (docs.isEmpty) {
                return const SizedBox(
                  height: 130,
                  child: Center(
                    child: Text(
                      'No watches available yet.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final isSelected = doc.id == _selectedWatchId;
                    final brand = data['brand'] as String? ?? '';
                    final name = data['name'] as String? ?? 'Watch';
                    final imageUrl = data['imageUrl'] as String? ?? '';
                    final hasModel = data['has3DModel'] as bool? ?? false;

                    return InkWell(
                      onTap: () => setState(() {
                        _selectedWatchId = doc.id;
                        _selectedWatchData = data;
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 110,
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.gold : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surface,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const Center(
                                              child: Icon(Icons.watch,
                                                  color: AppTheme.gold, size: 32),
                                            ),
                                          )
                                        : const Center(
                                            child: Icon(Icons.watch,
                                                color: AppTheme.gold, size: 32),
                                          ),
                                  ),
                                  if (!hasModel)
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'No AR model',
                                          style: TextStyle(
                                              color: Colors.white70, fontSize: 8),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (brand.isNotEmpty)
                                    Text(brand,
                                        style: const TextStyle(
                                            color: AppTheme.gold,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  Text(name,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
            ),
            onPressed: (_selectedWatchId == null || _selectedWatchData == null)
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WatchDetailScreen(
                          watchId: _selectedWatchId!,
                          data: _selectedWatchData!,
                        ),
                      ),
                    );
                  },
            child: const Text('Interested? View Details'),
          ),
        ],
      ),
    );
  }

  Widget _floatingIcon(IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  void _showShareInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Share Your Try-On',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This button lets you save or share a photo of the watch '
          'overlaid on your wrist — so you can send it to a friend, post '
          'it, or compare a few favorites before deciding.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it', style: TextStyle(color: AppTheme.gold)),
          ),
        ],
      ),
    );
  }
}