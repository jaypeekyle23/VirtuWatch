import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/ar_preferences_service.dart';
import '../../services/user_service.dart';
import '../../services/watch_model_cache.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ar_readiness.dart';
import '../../utils/share_card.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/save_heart_button.dart';
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

/// What the single fit slider is currently changing.
enum _FitMode { size, position }

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
  final _userService = UserService();
  final _tryOn = TryOnController();
  // App-wide cache: a download keeps going, and is kept, after this screen
  // is closed, so leaving and coming back never restarts it from zero.
  final _modelCache = WatchModelCache.instance;

  // Created once. A new stream on every build made the carousel reset to a
  // spinner each time the slider moved or a watch was selected.
  late final _watchesStream = _watchService.allListedWatches();

  // The person's own profile, for the saved-watches heart. Also created once.
  late final _userStream = _userService.currentUserStream();

  // First-time "how to hold your hand" tips.
  bool _showTips = false;

  String? _selectedWatchId;
  Map<String, dynamic>? _selectedWatchData;
  double _userScaleAdjust = 0;

  // Size and position share ONE slider so the panel stays as compact as it
  // was: the two small tabs above it choose what the slider changes.
  _FitMode _fitMode = _FitMode.size;
  double _positionAdjustCm = 0; // 0 = default spot; + toward elbow, - toward hand

  // Wrist tracking. Off = the watch is shown whole and can be turned and
  // zoomed by hand, with no jitter from the tracker.
  bool _trackingOn = true;

  // Lets the search pick scroll the carousel to the chosen watch.
  final _carouselController = ScrollController();
  static const _carouselItemExtent = 110.0 + 10.0; // card width + separator

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

  // The photo currently shown in the post-capture preview, if any, and the
  // watch it was taken with (kept so switching watches while the preview is
  // open doesn't change the name on the share card).
  TryOnPhoto? _photo;
  Map<String, dynamic>? _photoWatchData;

  @override
  void initState() {
    super.initState();
    _selectedWatchId = widget.initialWatchId;
    _selectedWatchData = widget.initialWatchData;
    _tryOn.phase.addListener(_onViewPhase);
    _loadPrefs();
    // A watch opened from its detail page is already selected, so nothing else
    // would trigger its first load. (If it isn't AR-ready this is a no-op and
    // _ensureSelection picks the first valid watch instead.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncModel();
    });
  }

  /// Restores the size correction this person chose last time and decides
  /// whether to show the first-time tips.
  Future<void> _loadPrefs() async {
    final adjust = await ArPreferences.loadSizeAdjust();
    final position = await ArPreferences.loadPositionAdjust();
    final seenTips = await ArPreferences.hasSeenTips();
    if (!mounted) return;
    setState(() {
      _userScaleAdjust = adjust;
      _positionAdjustCm = position;
      _showTips = !seenTips;
    });
    // The controller remembers these and applies them when the camera view is up.
    if (adjust != 0) _tryOn.setWatchScale(1 + adjust / 100);
    if (position != 0) _applyPosition(position);
  }

  void _applyPosition(double cm) => _tryOn.setForearmOffset(
      TryOnController.defaultForearmOffsetM + cm / 100);

  void _onFitChanged(double v) {
    setState(() {
      if (_fitMode == _FitMode.size) {
        _userScaleAdjust = v;
      } else {
        _positionAdjustCm = v;
      }
    });
    if (_fitMode == _FitMode.size) {
      _tryOn.setWatchScale(1 + v / 100);
    } else {
      _applyPosition(v);
    }
  }

  void _onFitChangeEnd(double v) {
    if (_fitMode == _FitMode.size) {
      ArPreferences.saveSizeAdjust(v);
    } else {
      ArPreferences.savePositionAdjust(v);
    }
  }

  /// Puts the slider that is currently showing back to its default.
  void _resetFit() {
    HapticFeedback.selectionClick();
    _onFitChanged(0);
    _onFitChangeEnd(0);
  }

  /// "+5%" for size; "Default" or "1.2 cm toward elbow" for position.
  String _fitValueText() {
    if (_fitMode == _FitMode.size) {
      return '${_userScaleAdjust >= 0 ? '+' : ''}${_userScaleAdjust.toInt()}%';
    }
    final cm = _positionAdjustCm;
    if (cm.abs() < 0.05) return 'Default';
    return '${cm.abs().toStringAsFixed(1)} cm '
        '${cm > 0 ? 'toward elbow' : 'toward hand'}';
  }

  Widget _fitTab(String label, _FitMode mode) {
    final selected = _fitMode == mode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        setState(() => _fitMode = mode);
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 18, top: 4, bottom: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppTheme.textPrimary : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Text(
            label,
            style: kLabelStyle.copyWith(
              color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  void _dismissTips() {
    setState(() => _showTips = false);
    ArPreferences.markTipsSeen();
  }

  /// Saves or un-saves the watch on screen, same as the heart on its detail page.
  Future<void> _toggleSaved(bool isSaved) async {
    final id = _selectedWatchId;
    if (id == null) return;
    try {
      await _userService.toggleSavedWatch(id);
      _snack(isSaved ? 'Removed from saved watches' : 'Saved to your favorites');
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  void dispose() {
    _tryOn.phase.removeListener(_onViewPhase);
    _tryOn.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The camera view must never be squeezed by the keyboard (search opens it).
      resizeToAvoidBottomInset: false,
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

  void _toggleTracking() {
    HapticFeedback.selectionClick();
    setState(() => _trackingOn = !_trackingOn);
    _tryOn.setTrackingEnabled(_trackingOn);
  }

  /// Search by name, brand or style in a sheet, so the carousel doesn't have
  /// to be scrolled sideways to find a watch.
  Future<void> _openSearch() async {
    final picked = await showModalBottomSheet<
        QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WatchSearchSheet(
        docs: _arDocs,
        selectedId: _selectedWatchId,
      ),
    );
    if (picked == null || !mounted) return;
    _selectWatch(picked.id, picked.data());
    _scrollCarouselTo(picked.id);
  }

  void _scrollCarouselTo(String id) {
    final i = _arDocs.indexWhere((d) => d.id == id);
    if (i < 0 || !_carouselController.hasClients) return;
    final target = (i * _carouselItemExtent)
        .clamp(0.0, _carouselController.position.maxScrollExtent);
    _carouselController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// A small dark pill with an icon, used for status and guidance.
  Widget _pill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }

  /// Plain-language guidance under the status pill: what to change so the
  /// watch stays steady. While tracking is off it explains the touch controls.
  Widget _guidance() {
    if (_tryOn.phase.value != TryOnViewPhase.ready) {
      return const SizedBox.shrink();
    }
    if (!_trackingOn) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _pill(
          icon: Icons.touch_app_outlined,
          text: 'Tracking is off. Drag to turn the watch, pinch to zoom, '
              'double-tap to reset.',
        ),
      );
    }
    return ValueListenableBuilder<TryOnHint>(
      valueListenable: _tryOn.hint,
      builder: (context, hint, _) {
        final (IconData, String)? content = switch (hint) {
          TryOnHint.none => null,
          TryOnHint.lowLight => (
              Icons.light_mode_outlined,
              "It's a bit dark here. Move somewhere brighter so the watch "
                  'stays steady.'
            ),
          TryOnHint.handNotVisible => (
              Icons.back_hand_outlined,
              'Keep your whole hand in view, fingertips included, so the '
                  'watch stays steady.'
            ),
          TryOnHint.tooClose => (
              Icons.zoom_out,
              "You're too close. Move your phone back until your whole hand "
                  'is in view.'
            ),
        };
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: content == null
              ? const SizedBox.shrink(key: ValueKey('no-hint'))
              : Padding(
                  key: ValueKey(hint),
                  padding: const EdgeInsets.only(top: 8),
                  child: _pill(icon: content.$1, text: content.$2),
                ),
        );
      },
    );
  }

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
      if (capture.photo != null) {
        _photo = capture.photo;
        _photoWatchData = _selectedWatchData;
      }
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
  Future<void> _sharePhoto(TryOnPhoto photo, bool withDetails) async {
    final data = _photoWatchData ?? _selectedWatchData;
    final watch = [
      (data?['brand'] as String?)?.trim() ?? '',
      (data?['name'] as String?)?.trim() ?? '',
    ].where((s) => s.isNotEmpty).join(' ');
    final text = watch.isEmpty
        ? 'Trying on a watch with VirtuWatch'
        : 'Trying on the $watch with VirtuWatch';
    // With "Watch details" on, share a copy with the brand and name strip.
    // If making it fails, the plain photo is still shared.
    var path = photo.path;
    var mime = 'image/jpeg';
    if (withDetails) {
      try {
        path = await buildShareCard(
          photoPath: photo.path,
          text: ShareCardText.from(data),
        );
        mime = 'image/png';
      } catch (_) {
        _snack("Couldn't add the watch details, sharing the plain photo.");
      }
    }
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path, mimeType: mime)],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statusPill(),
              _guidance(),
            ],
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: Column(
            children: [
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userStream,
                builder: (context, snapshot) {
                  final saved =
                      (snapshot.data?.data()?['savedWatches'] as List?)
                              ?.cast<String>() ??
                          const <String>[];
                  final isSaved =
                      _selectedWatchId != null && saved.contains(_selectedWatchId);
                  return SaveHeartButton(
                    overCamera: true,
                    isSaved: isSaved,
                    onPressed: () => _toggleSaved(isSaved),
                  );
                },
              ),
              const SizedBox(height: 12),
              // MediaPipe's left/right label can be inverted; this flips the
              // wrist the watch is placed on if it lands on the wrong side.
              // Meaningless while tracking is off, so it hides then.
              if (_trackingOn) ...[
                _floatingIcon(
                  Icons.swap_horiz,
                  tooltip: 'Swap wrist',
                  onTap: _tryOn.swapHand,
                ),
                const SizedBox(height: 12),
              ],
              // Lit up while tracking is OFF, so it's clear the watch is
              // in inspect mode and that this button turns tracking back on.
              _floatingIcon(
                _trackingOn ? Icons.sensors : Icons.sensors_off,
                tooltip: _trackingOn ? 'Turn off tracking' : 'Turn on tracking',
                highlighted: !_trackingOn,
                onTap: () {
                  if (_tryOn.phase.value == TryOnViewPhase.ready) {
                    _toggleTracking();
                  }
                },
              ),
              const SizedBox(height: 12),
              _floatingIcon(
                Icons.search,
                tooltip: 'Search watches',
                onTap: () {
                  if (_arDocs.isNotEmpty) _openSearch();
                },
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
              cardText: ShareCardText.from(_photoWatchData),
              onShare: (withDetails) => _sharePhoto(photo, withDetails),
              onDelete: () => _deletePhoto(photo),
              onDismissed: () {
                if (mounted && _photo?.path == photo.path) {
                  setState(() => _photo = null);
                }
              },
            ),
          ),
        if (_showTips)
          Positioned.fill(child: _FirstTimeTips(onDismiss: _dismissTips)),
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
              _fitTab('SIZE', _FitMode.size),
              _fitTab('POSITION', _FitMode.position),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _fitValueText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ),
              ),
              // Only shows when there is something to undo.
              if (_fitMode == _FitMode.size
                  ? _userScaleAdjust != 0
                  : _positionAdjustCm != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: _resetFit,
                    child: Tooltip(
                      message: 'Reset',
                      child: Icon(Icons.restart_alt,
                          size: 18, color: AppTheme.textSecondary),
                    ),
                  ),
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
              value: _fitMode == _FitMode.size
                  ? _userScaleAdjust
                  : _positionAdjustCm,
              min: _fitMode == _FitMode.size
                  ? ArPreferences.sizeAdjustMin
                  : ArPreferences.positionAdjustMin,
              max: _fitMode == _FitMode.size
                  ? ArPreferences.sizeAdjustMax
                  : ArPreferences.positionAdjustMax,
              // While tracking is off, pinching the watch sets its size
              // instead, and there is no wrist to slide along.
              onChanged: !_trackingOn ? null : _onFitChanged,
              // Remembered for next time (saved once, when the finger lifts).
              onChangeEnd: _onFitChangeEnd,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: ListView.separated(
              controller: _carouselController,
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
      {required VoidCallback onTap,
      required String tooltip,
      bool highlighted = false}) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: highlighted
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: highlighted ? Colors.black : Colors.white, size: 20),
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

/// One-time card over the camera explaining how to hold the hand, which is
/// what keeps the watch steady. Shown once per account.
class _FirstTimeTips extends StatelessWidget {
  final VoidCallback onDismiss;

  const _FirstTimeTips({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppTheme.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        );

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For the best fit', style: AppTheme.serif(size: 24)),
              const SizedBox(height: 16),
              tip(Icons.straighten,
                  "Hold your hand about an arm's length from the camera."),
              tip(Icons.back_hand_outlined,
                  'Face the back of your hand toward the camera.'),
              tip(Icons.light_mode_outlined,
                  'Keep your whole hand in view, in good light.'),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onDismiss,
                  child: const Text('Got it'),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that finds an AR watch by name, brand or style. Pops with the
/// chosen watch's document.
class _WatchSearchSheet extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String? selectedId;

  const _WatchSearchSheet({required this.docs, required this.selectedId});

  @override
  State<_WatchSearchSheet> createState() => _WatchSearchSheetState();
}

class _WatchSearchSheetState extends State<_WatchSearchSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> data) {
    if (_query.isEmpty) return true;
    bool has(String key) =>
        (data[key] as String? ?? '').toLowerCase().contains(_query);
    return has('name') || has('brand') || has('styleCategory');
  }

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final d in widget.docs)
        if (_matches(d.data())) d,
    ];
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        // Lift the sheet above the keyboard.
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(fontSize: 15),
                decoration: luxeFieldDecoration(
                  hint: 'Search by name, brand, or style',
                  prefixIcon: Icon(Icons.search,
                      size: 20, color: AppTheme.textSecondary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: AppTheme.textSecondary,
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        'No AR watches match your search.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final doc = results[i];
                        final data = doc.data();
                        final imageUrl = data['imageUrl'] as String? ?? '';
                        final fallback = Icon(Icons.watch,
                            color: AppTheme.textSecondary, size: 24);
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: ColoredBox(
                                color: AppTheme.background,
                                child: imageUrl.isEmpty
                                    ? Center(child: fallback)
                                    : NetworkPhoto(
                                        url: imageUrl,
                                        errorWidget: Center(child: fallback)),
                              ),
                            ),
                          ),
                          title: Text(
                            data['name'] as String? ?? 'Watch',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            (data['brand'] as String? ?? '').toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10,
                                letterSpacing: 1.2),
                          ),
                          trailing: doc.id == widget.selectedId
                              ? Icon(Icons.check,
                                  size: 20, color: AppTheme.textPrimary)
                              : null,
                          onTap: () => Navigator.of(context).pop(doc),
                        );
                      },
                    ),
            ),
          ],
        ),
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