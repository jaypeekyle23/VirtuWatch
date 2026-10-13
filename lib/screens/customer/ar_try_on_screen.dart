import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import 'watch_detail_screen.dart';

/// Placeholder for AR Try-On while the real camera + MediaPipe hand
/// tracking + three_js implementation is being built and tested in a
/// separate Flutter project.
///
/// Keeps the same watch-selection carousel and scale slider so the tab
/// still looks and feels complete, but has no camera/ML/3D code. Nothing
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

  // Created once. A new stream on every build made the carousel reset to a
  // spinner each time the slider moved or a watch was selected.
  late final _watchesStream = _watchService.allListedWatches();

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
        title: Text('AR Try-On', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'About sharing',
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
        ColoredBox(
          color: AppTheme.surface,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('AR preview coming soon',
                      textAlign: TextAlign.center,
                      style: AppTheme.serif(size: 26)),
                  const SizedBox(height: 8),
                  const Text(
                    'Point your camera at your wrist to try on watches.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                  ),
                ],
              ),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: kTopRule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('FINE-TUNE SIZE', style: kLabelStyle),
              const Spacer(),
              Text(
                '${_userScaleAdjust >= 0 ? '+' : ''}${_userScaleAdjust.toInt()}%',
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.textPrimary,
              thumbColor: AppTheme.textPrimary,
              inactiveTrackColor: Colors.white24,
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
            stream: _watchesStream,
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

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const SizedBox(
                  height: 130,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (docs.isEmpty) {
                return const SizedBox(
                  height: 130,
                  child: Center(
                    child: Text(
                      'No watches available yet.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _ArWatchCard(
                      data: doc.data(),
                      selected: doc.id == _selectedWatchId,
                      onTap: () => setState(() {
                        _selectedWatchId = doc.id;
                        _selectedWatchData = doc.data();
                      }),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedWatchId == null || _selectedWatchData == null)
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WatchDetailScreen(
                            watchId: _selectedWatchId!,
                            data: _selectedWatchData!,
                          ),
                        ),
                      ),
              child: const Text('View Details'),
            ),
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
        title: Text('Share your try-on', style: AppTheme.serif(size: 22)),
        content: const Text(
          'This button lets you save or share a photo of the watch overlaid '
          'on your wrist, so you can send it to a friend, post it, or compare '
          'a few favorites before deciding.',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// One selectable watch in the carousel. The selected card gets a bright
/// outline, no extra color.
class _ArWatchCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool selected;
  final VoidCallback onTap;

  const _ArWatchCard({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = data['imageUrl'] as String? ?? '';
    final hasModel = data['has3DModel'] as bool? ?? false;
    const fallback = Center(
      child: Icon(Icons.watch, color: AppTheme.textSecondary, size: 32),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 110,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.textPrimary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: AppTheme.background,
                    child: imageUrl.isEmpty
                        ? fallback
                        : NetworkPhoto(url: imageUrl, errorWidget: fallback),
                  ),
                  if (!hasModel)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('No AR model',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 8)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (data['brand'] as String? ?? '').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                        letterSpacing: 1.2),
                  ),
                  Text(
                    data['name'] as String? ?? 'Watch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}