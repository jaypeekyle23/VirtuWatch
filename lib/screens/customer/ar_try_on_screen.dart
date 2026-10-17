import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/watch_model_cache.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ar_readiness.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/tryon_camera_view.dart';
import '../../widgets/tryon_photo_preview.dart';
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
enum _Stage { idle, downloading, preparing, error }

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
  // App-wide cache: a download keeps going, and is kept, after this screen
  // is closed, so leaving and coming back never restarts it from zero.
  final _modelCache = WatchModelCache.instance;

  // Created once. A new stream on every build made the carousel reset to a
  // spinner each time the slider moved or a watch was selected.
  late final _watchesStream = _watchService.allListedWatches();

  String? _selectedWatchId;
  Map<String, dynamic>? _selectedWatchData;
  double _userScaleAdjust = 0;

  // Photo capture.
  bool _capturing = false;
  bool _flash = false; // brief white flash so the shutter feels responsive

  // Model loading. Each _syncModel call takes a new ticket (_loadToken); a
  // call that has been overtaken by a newer one (another watch picked, the
  // camera view became ready, a retry) stands down at its next checkpoint.
  // Nothing ever waits in line behind an older download.
  ArFit? _appliedFit; // what the native view is showing
  _Stage _stage = _Stage.idle;
  double? _downloadFraction; // 0..1 while downloading; null = unknown
  String? _errorMessage;
  int _loadToken = 0;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _arDocs = const [];

  // Changing this key makes Flutter build a brand-new camera view, which asks
  // for the permission and starts the native view again (used by "retry").
  Key _cameraKey = UniqueKey();

  // The photo currently shown in the post-capture preview, if any.
  TryOnPhoto? _photo;

  @override
  void initState() {
    super.initState();
    _selectedWatchId = widget.initialWatchId;
    _selectedWatchData = widget.initialWatchData;
    _tryOn.phase.addListener(_onViewPhase);
    // A watch opened from its detail page is already selected, so nothing else
    // would trigger its first load. (If it isn't AR-ready this is a no-op and
    // _ensureSelection picks the first valid watch instead.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncModel();
    });
  }

  @override
  void dispose() {
    _tryOn.phase.removeListener(_onViewPhase);
    _tryOn.dispose();
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
            tooltip: 'About photos',
            icon: const Icon(Icons.info_outline),
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
    _arDocs = docs;
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

  void _log(String message) => debugPrint('[ArTryOn] $message');

  /// The native view just started (or restarted). It shows no watch yet, so
  /// the selected one is sent to it; the file is normally already on disk by
  /// now, which makes this instant. Any other phase only needs a new pill.
  void _onViewPhase() {
    if (!mounted) return;
    setState(() {});
    if (_tryOn.phase.value == TryOnViewPhase.ready) {
      _appliedFit = null;
      _syncModel();
    }
  }

  void _setLoad(_Stage stage, {String? message}) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _errorMessage = message;
      _downloadFraction = null;
    });
  }

  /// Makes the native view show the selected watch's model: fetches the file
  /// (from the cache, resuming a partial download, or fresh), then hands it
  /// to the renderer. Safe to call repeatedly; a newer call overtakes an
  /// older one. The pill shows the real stage, and every failure says which
  /// stage failed.
  Future<void> _syncModel({bool force = false}) async {
    final fit = ArFit.tryParse(_selectedWatchData ?? const {});
    if (fit == null) return;

    final token = ++_loadToken;
    bool current() => mounted && token == _loadToken;

    if (!force && fit == _appliedFit) {
      _setLoad(_Stage.idle);
      return;
    }
    if (_tryOn.phase.value == TryOnViewPhase.unsupported) return;

    final clock = Stopwatch()..start();
    try {
      // 1) The file.
      _setLoad(_Stage.downloading);
      final download = _modelCache.start(fit.modelUrl);
      void onProgress() {
        if (current()) {
          setState(
              () => _downloadFraction = download.progress.value.fraction);
        }
      }

      download.progress.addListener(onProgress);
      final File file;
      try {
        file = await download.file;
      } on ModelDownloadException catch (e) {
        _log('download failed after ${clock.elapsedMilliseconds} ms: '
            '${e.message}');
        if (current()) _setLoad(_Stage.error, message: e.message);
        return;
      } finally {
        download.progress.removeListener(onProgress);
      }
      if (!current()) return;
      _log('model on disk after ${clock.elapsedMilliseconds} ms');

      // 2) The native view. If it isn't up yet there is nothing to wait on:
      // _onViewPhase starts this again the moment it is, and by then the file
      // is on disk.
      if (_tryOn.phase.value != TryOnViewPhase.ready) {
        _log('camera view not ready (${_tryOn.phase.value.name}); '
            'will load when it is');
        _setLoad(_Stage.idle);
        return;
      }

      // 3) The renderer.
      _setLoad(_Stage.preparing);
      final result = await _tryOn.loadModel(file.path, fit);
      _log('loadModel -> ${result.name}, '
          '${clock.elapsedMilliseconds} ms in total');
      // Record what the view really shows, even if the user has moved on.
      if (result == TryOnLoadResult.loaded) _appliedFit = fit;
      if (!current()) return;

      switch (result) {
        case TryOnLoadResult.loaded:
          _setLoad(_Stage.idle);
          _prefetchNeighbours();
        case TryOnLoadResult.rejected:
          // Don't keep serving a file the renderer can't read.
          unawaited(_modelCache.remove(fit.modelUrl));
          _setLoad(_Stage.error,
              message: "This watch's 3D model couldn't be read.");
        case TryOnLoadResult.noResponse:
          _setLoad(_Stage.error,
              message: 'The AR view stopped responding.');
        case TryOnLoadResult.viewNotReady:
          // The view went away mid-call; _onViewPhase retries when it's back.
          _setLoad(_Stage.idle);
      }
    } catch (e, st) {
      _log('unexpected error: $e\n$st');
      if (current()) {
        _setLoad(_Stage.error, message: "Couldn't load this watch.");
      }
    }
  }

  /// Warms the cache for the watches either side of the selected one, so
  /// flicking through the carousel is instant. Only runs once the selected
  /// watch is on screen, so it never competes with it for bandwidth.
  void _prefetchNeighbours() {
    final i = _arDocs.indexWhere((d) => d.id == _selectedWatchId);
    if (i < 0) return;
    for (final j in [i - 1, i + 1]) {
      if (j < 0 || j >= _arDocs.length) continue;
      final fit = ArFit.tryParse(_arDocs[j].data());
      if (fit != null) _modelCache.prefetch(fit.modelUrl);
    }
  }

  void _restartCameraView() => setState(() => _cameraKey = UniqueKey());

  /// The native view is up and the selected watch is actually on screen, so a
  /// photo would show the watch.
  bool get _canCapture =>
      _tryOn.phase.value == TryOnViewPhase.ready &&
      _appliedFit != null &&
      _stage == _Stage.idle;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _capturePhoto() async {
    if (_capturing) return;
    if (!_canCapture) {
      _snack('Wait for the watch to finish loading, then try again.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _capturing = true;
      _flash = true;
    });
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _flash = false);
    });

    final capture = await _tryOn.capturePhoto();
    if (!mounted) return;
    setState(() {
      _capturing = false;
      // The preview replaces the "saved" message; it only appears when there
      // is a photo to show.
      if (capture.photo != null) _photo = capture.photo;
    });
    if (capture.photo != null) return;
    _snack(switch (capture.result) {
      TryOnCaptureResult.saved => 'Photo saved to your gallery.',
      TryOnCaptureResult.storageDenied =>
        'Allow storage access to save photos to your device.',
      TryOnCaptureResult.failed => "Couldn't save the photo. Please try again.",
      TryOnCaptureResult.viewNotReady => 'The camera isn\'t ready yet.',
    });
  }

  /// Opens the system share sheet, which lists whatever the person has
  /// installed (Facebook, Instagram, Telegram, email, ...).
  Future<void> _sharePhoto(TryOnPhoto photo) async {
    final data = _selectedWatchData;
    final watch = [
      (data?['brand'] as String?)?.trim() ?? '',
      (data?['name'] as String?)?.trim() ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    final text = watch.isEmpty
        ? 'Trying on a watch with VirtuWatch'
        : 'Trying on the $watch with VirtuWatch';
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(photo.path, mimeType: 'image/jpeg')],
        text: text,
        subject: 'My VirtuWatch try-on',
      ));
    } catch (_) {
      _snack("Couldn't open the share sheet. Please try again.");
    }
  }

  /// Deletes the photo from the gallery. Returns true if it is gone.
  Future<bool> _deletePhoto(TryOnPhoto photo) async {
    final deleted = await TryOnController.deletePhoto(photo);
    _snack(deleted
        ? 'Photo deleted.'
        : "Couldn't delete the photo. You can remove it from your gallery "
            '(Pictures/VirtuWatch).');
    return deleted;
  }

  Widget _shutterButton() {
    return Opacity(
      opacity: _canCapture ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: _capturePhoto,
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.25),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white),
            child: _capturing
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _downloadText() {
    final f = _downloadFraction;
    return f == null
        ? 'Downloading watch…'
        : 'Downloading watch ${(f * 100).floor()}%';
  }

  /// One pill that says what the screen is actually waiting for: the camera,
  /// the download (with a percentage), or the renderer. Failures name the
  /// stage that failed and can be tapped to retry.
  Widget _statusPill() {
    final phase = _tryOn.phase.value;
    // No pill when the camera view itself already explains the situation.
    if (phase == TryOnViewPhase.unsupported ||
        phase == TryOnViewPhase.permissionDenied) {
      return const SizedBox.shrink();
    }

    final String text;
    VoidCallback? onTap;
    var busy = true;
    if (phase == TryOnViewPhase.failed) {
      text = "The camera view didn't start. Tap to retry";
      busy = false;
      onTap = _restartCameraView;
    } else if (_stage == _Stage.error) {
      text = '${_errorMessage ?? "Couldn't load this watch."} Tap to retry';
      busy = false;
      onTap = () => _syncModel(force: true);
    } else {
      final parts = <String>[
        if (phase == TryOnViewPhase.waitingForPermission ||
            phase == TryOnViewPhase.starting)
          'Starting camera…',
        if (_stage == _Stage.downloading) _downloadText(),
        if (_stage == _Stage.preparing) 'Preparing watch…',
      ];
      if (parts.isEmpty) return const SizedBox.shrink();
      text = parts.join('  ·  ');
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              const Icon(Icons.refresh, size: 16, color: Colors.white),
            const SizedBox(width: 10),
            Flexible(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
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
        TryOnCameraView(key: _cameraKey, controller: _tryOn),
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
        if (_tryOn.phase.value == TryOnViewPhase.ready)
          Positioned(
            right: 16,
            bottom: 16,
            child: _shutterButton(),
          ),
        if (_photo case final photo?)
          Positioned.fill(
            child: TryOnPhotoPreview(
              // A new photo gets a fresh preview with its own animation.
              key: ValueKey(photo.path),
              photo: photo,
              onShare: () => _sharePhoto(photo),
              onDelete: () => _deletePhoto(photo),
              onDismissed: () {
                if (mounted && _photo?.path == photo.path) {
                  setState(() => _photo = null);
                }
              },
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flash ? 0.7 : 0.0,
              duration: const Duration(milliseconds: 120),
              child: const ColoredBox(color: Colors.white),
            ),
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
        title: Text('Save your try-on', style: AppTheme.serif(size: 22)),
        content: Text(
          'Tap the round camera button to take a photo of the watch on your '
          'wrist. It is saved to your gallery (Pictures/VirtuWatch) and a '
          'preview pops up: tap it to share the photo with a friend, delete '
          'it, or close it. Handy for comparing a few favorites before '
          'deciding.',
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