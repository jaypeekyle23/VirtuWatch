import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_model_cache.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ar_readiness.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/tryon_camera_view.dart';
import 'watch_detail_screen.dart';

/// Live AR Try-On. The camera, hand tracking and 3D rendering all run in
/// a native Android view (see TryOnCameraView / TryOnPlatformView.kt);
/// this screen only hosts it and owns the carousel, size slider and
/// camera controls.
///
/// Only AR-ready watches are listed (see isArReady in utils/ar_readiness.dart):
/// a .glb model plus valid fit numbers measured for that model. Anything
/// else is hidden here, and the camera doesn't start if there are none.
///
/// Selecting a watch downloads its .glb (cached on the device) and hands it to
/// the native renderer together with that model's fit numbers.
enum _ModelStatus { idle, loading, error }

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
  final _tryOn = TryOnController();
  final _modelCache = WatchModelCache();

  // Created once. A new stream on every build made the carousel reset to a
  // spinner each time the slider moved or a watch was selected.
  late final _watchesStream = _watchService.allListedWatches();

  String? _selectedWatchId;
  Map<String, dynamic>? _selectedWatchData;
  double _userScaleAdjust = 0;

  // Model loading. Only one load runs at a time; if the selection changes
  // meanwhile, the loop in _syncModel picks up the latest choice afterwards.
  ArFit? _appliedFit; // what the native view is showing
  _ModelStatus _modelStatus = _ModelStatus.idle;
  bool _syncing = false;
  bool _resync = false;

  @override
  void initState() {
    super.initState();
    _selectedWatchId = widget.initialWatchId;
    _selectedWatchData = widget.initialWatchData;
    // A watch opened from its detail page is already selected, so nothing else
    // would trigger its first load. (If it isn't AR-ready this is a no-op and
    // _ensureSelection picks the first valid watch instead.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncModel();
    });
  }

  @override
  void dispose() {
    _modelCache.dispose();
    super.dispose();
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _watchesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _emptyState(
              title: "Couldn't load watches",
              message: 'Check your connection and try again.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }

          // Only watches that can actually be rendered are offered.
          final docs = [
            for (final d in snapshot.data!.docs)
              if (isArReady(d.data())) d,
          ];
          if (docs.isEmpty) {
            return _emptyState(
              title: 'No AR watches yet',
              message: 'Watches appear here once they have a 3D model '
                  'set up for AR try-on.',
            );
          }

          _ensureSelection(docs);
          return Column(
            children: [
              Expanded(child: _buildCameraArea()),
              _buildControlPanel(docs),
            ],
          );
        },
      ),
    );
  }

  /// Keeps the selection pointing at a watch that is still AR-ready. Covers
  /// the first load, a watch opened from elsewhere that has no AR model
  /// (initialWatchId), a selected watch that gets unlisted or loses its model,
  /// and a selected watch whose model or fit numbers change while the screen
  /// is open.
  void _ensureSelection(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final current = docs.where((d) => d.id == _selectedWatchId).firstOrNull;
    if (current != null) {
      if (ArFit.tryParse(current.data()) !=
          ArFit.tryParse(_selectedWatchData ?? const {})) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _selectWatch(current.id, current.data());
        });
      }
      return;
    }
    final first = docs.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectWatch(first.id, first.data());
    });
  }

  void _selectWatch(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedWatchId = id;
      _selectedWatchData = data;
    });
    _syncModel();
  }

  /// Makes the native view show the selected watch's model. Downloads it first
  /// (or takes it from the cache). Safe to call repeatedly: calls made while a
  /// load is running just ask it to re-check the latest selection afterwards.
  Future<void> _syncModel({bool force = false}) async {
    if (_syncing) {
      _resync = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _resync = false;
        final fit = ArFit.tryParse(_selectedWatchData ?? const {});
        if (fit == null) break;
        if (!force && fit == _appliedFit) {
          if (_modelStatus != _ModelStatus.idle) {
            setState(() => _modelStatus = _ModelStatus.idle);
          }
          break;
        }
        force = false;

        setState(() => _modelStatus = _ModelStatus.loading);
        var ok = false;
        try {
          final file = await _modelCache.getModel(fit.modelUrl);
          ok = await _tryOn.loadModel(file.path, fit);
        } catch (_) {
          // ModelDownloadException, or anything unexpected: show the retry pill.
          ok = false;
        }
        if (!mounted) return;
        if (ok) _appliedFit = fit;
        // If the selection changed meanwhile, the loop goes round again, so don't
        // flash a result for a watch that is no longer selected.
        if (!_resync) {
          setState(
              () => _modelStatus = ok ? _ModelStatus.idle : _ModelStatus.error);
        }
      } while (_resync);
    } finally {
      _syncing = false;
    }
  }

  Widget _statusPill() {
    final Widget content;
    VoidCallback? onTap;
    switch (_modelStatus) {
      case _ModelStatus.idle:
        return const SizedBox.shrink();
      case _ModelStatus.loading:
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 10),
            Text('Loading watch…',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        );
      case _ModelStatus.error:
        onTap = () => _syncModel(force: true);
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Flexible(
              child: Text("Couldn't load this watch. Tap to retry",
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: content,
      ),
    );
  }

  Widget _emptyState({required String title, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_in_ar_outlined,
                size: 40, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTheme.serif(size: 24)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        TryOnCameraView(controller: _tryOn),
        Positioned(
          left: 16,
          right: 72, // clear of the camera buttons
          top: 16,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _statusPill(),
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              _floatingIcon(
                Icons.cameraswitch_outlined,
                tooltip: 'Switch camera',
                onTap: _tryOn.switchCamera,
              ),
              const SizedBox(height: 10),
              // MediaPipe's left/right label can be inverted; this flips the
              // wrist the watch is placed on if it lands on the wrong side.
              _floatingIcon(
                Icons.swap_horiz,
                tooltip: 'Swap wrist',
                onTap: _tryOn.swapHand,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: kTopRule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FINE-TUNE SIZE', style: kLabelStyle),
              const Spacer(),
              Text(
                '${_userScaleAdjust >= 0 ? '+' : ''}${_userScaleAdjust.toInt()}%',
                style: TextStyle(
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
              onChanged: (v) {
                setState(() => _userScaleAdjust = v);
                _tryOn.setWatchScale(1 + v / 100);
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: docs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final doc = docs[index];
                return _ArWatchCard(
                  data: doc.data(),
                  selected: doc.id == _selectedWatchId,
                  onTap: () => _selectWatch(doc.id, doc.data()),
                );
              },
            ),
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

  Widget _floatingIcon(IconData icon,
      {required VoidCallback onTap, required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  void _showShareInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Share your try-on', style: AppTheme.serif(size: 22)),
        content: Text(
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
    final fallback = Center(
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
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                        letterSpacing: 1.2),
                  ),
                  Text(
                    data['name'] as String? ?? 'Watch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
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