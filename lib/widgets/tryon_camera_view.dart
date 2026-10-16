import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/ar_readiness.dart';

/// Where the native camera view is in its start-up. The AR screen uses this
/// to tell the user what it is actually waiting for.
enum TryOnViewPhase {
  /// Asking for (or about to ask for) the camera permission.
  waitingForPermission,

  /// The user said no. The view itself explains how to fix it.
  permissionDenied,

  /// Permission granted; the native view is being created.
  starting,

  /// The native view exists and can be sent a watch.
  ready,

  /// The native view did not come up in time.
  failed,

  /// Not an Android device, so there is no native view at all.
  unsupported,
}

/// What happened to a [TryOnController.loadModel] request.
enum TryOnLoadResult {
  /// The watch is on screen.
  loaded,

  /// The renderer refused the file (corrupt or unsupported model).
  rejected,

  /// The native view never answered within [TryOnController.nativeLoadTimeout].
  noResponse,

  /// There is no native view right now (still starting, or it was torn down).
  viewNotReady,
}

/// What happened to a [TryOnController.capturePhoto] request.
enum TryOnCaptureResult {
  /// The photo is in the gallery (Pictures/VirtuWatch).
  saved,

  /// The user refused the storage permission (Android 7-9 only).
  storageDenied,

  /// The photo couldn't be taken or written.
  failed,

  /// There is no native view right now.
  viewNotReady,
}

/// Typed handle to the native AR try-on view (Android only).
///
/// The native side (TryOnPlatformView.kt) runs CameraX -> MediaPipe hand
/// tracking -> Filament rendering entirely on-device. This controller is the
/// only thing the rest of the app needs to talk to it, so no screen has to
/// deal with raw MethodChannels. Calls made before the view exists are
/// safely ignored (the scale is remembered and applied once it attaches).
class TryOnController {
  /// How long the native view gets to appear once the camera permission is
  /// granted before [phase] becomes [TryOnViewPhase.failed].
  static const viewStartTimeout = Duration(seconds: 25);

  /// How long a loadModel call may take before it is reported as not answered.
  static const nativeLoadTimeout = Duration(seconds: 30);

  /// How long taking and saving a photo may take.
  static const captureTimeout = Duration(seconds: 20);

  static const _permissions = MethodChannel('tryon/permissions');

  MethodChannel? _channel;
  double _scale = 1.0;
  bool _disposed = false;
  Timer? _startTimer;

  /// Start-up state of the native view. Listeners are never notified in the
  /// middle of a build, so it is safe to call setState from one.
  final ValueNotifier<TryOnViewPhase> phase =
      ValueNotifier(TryOnViewPhase.waitingForPermission);

  void _setPhase(TryOnViewPhase next) {
    // These calls come from the camera view's initState/build. Notifying
    // right there would make listeners rebuild widgets mid-build, so the
    // change is delivered on a microtask (in order) instead.
    scheduleMicrotask(() {
      if (!_disposed) phase.value = next;
    });
  }

  void _permissionRequested() {
    _startTimer?.cancel();
    _setPhase(TryOnViewPhase.waitingForPermission);
  }

  void _permissionResult(bool granted) {
    _startTimer?.cancel();
    if (!granted) {
      _setPhase(TryOnViewPhase.permissionDenied);
      return;
    }
    _setPhase(TryOnViewPhase.starting);
    _startTimer = Timer(viewStartTimeout, () {
      if (!_disposed && _channel == null) _setPhase(TryOnViewPhase.failed);
    });
  }

  void _markUnsupported() => _setPhase(TryOnViewPhase.unsupported);

  void _attach(MethodChannel channel) {
    _startTimer?.cancel();
    _channel = channel;
    if (_scale != 1.0) _invoke<void>('setWatchScale', _scale);
    _setPhase(TryOnViewPhase.ready);
  }

  void _detach() {
    _startTimer?.cancel();
    _channel = null;
  }

  /// Call once, when the owning screen is disposed.
  void dispose() {
    _disposed = true;
    _startTimer?.cancel();
    phase.dispose();
  }

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    final ch = _channel;
    if (ch == null) return null;
    try {
      return await ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // View was torn down between the call and its delivery.
      return null;
    }
  }

  /// Multiplier on the watch size. 1.0 = true-to-wrist size.
  Future<void> setWatchScale(double scale) {
    _scale = scale;
    return _invoke<void>('setWatchScale', scale);
  }

  /// Shows the .glb at [path] on the wrist, placed using [fit].
  ///
  /// Does not wait for the native view: when it is not there yet this returns
  /// [TryOnLoadResult.viewNotReady] immediately, and the caller tries again
  /// when [phase] becomes [TryOnViewPhase.ready]. On [TryOnLoadResult.rejected]
  /// or [TryOnLoadResult.noResponse] the previous watch (if any) stays on
  /// screen.
  Future<TryOnLoadResult> loadModel(String path, ArFit fit) async {
    final ch = _channel;
    if (ch == null) return TryOnLoadResult.viewNotReady;
    final args = <String, Object?>{'path': path, 'fit': fit.toChannelMap()};
    try {
      final ok =
          await ch.invokeMethod<bool>('loadModel', args).timeout(nativeLoadTimeout);
      return ok == true ? TryOnLoadResult.loaded : TryOnLoadResult.rejected;
    } on TimeoutException {
      return TryOnLoadResult.noResponse;
    } on PlatformException {
      return TryOnLoadResult.rejected;
    } on MissingPluginException {
      // View was torn down between the call and its delivery.
      return TryOnLoadResult.viewNotReady;
    }
  }

  /// Saves a photo of the camera picture with the watch on it to the gallery.
  /// Only the back camera is used, so the picture is never mirrored.
  Future<TryOnCaptureResult> capturePhoto() async {
    final ch = _channel;
    if (ch == null) return TryOnCaptureResult.viewNotReady;
    try {
      final allowed =
          await _permissions.invokeMethod<bool>('requestStorage') ?? false;
      if (!allowed) return TryOnCaptureResult.storageDenied;
      final ok = await ch
          .invokeMethod<bool>('capturePhoto')
          .timeout(captureTimeout);
      return ok == true ? TryOnCaptureResult.saved : TryOnCaptureResult.failed;
    } on TimeoutException {
      return TryOnCaptureResult.failed;
    } on PlatformException {
      return TryOnCaptureResult.failed;
    } on MissingPluginException {
      // View was torn down between the call and its delivery.
      return TryOnCaptureResult.viewNotReady;
    }
  }

  /// Flip which wrist the watch is placed on. MediaPipe's left/right label can
  /// be inverted on some cameras. Returns the new swapped state.
  Future<bool?> swapHand() => _invoke<bool>('swapHand');
}

/// Live AR try-on camera view. Handles the camera permission itself and falls
/// back to a message on non-Android platforms.
class TryOnCameraView extends StatefulWidget {
  final TryOnController controller;

  const TryOnCameraView({super.key, required this.controller});

  @override
  State<TryOnCameraView> createState() => _TryOnCameraViewState();
}

class _TryOnCameraViewState extends State<TryOnCameraView> {
  static const _permissions = MethodChannel('tryon/permissions');

  bool _requesting = true;
  bool _granted = false;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_supported) {
      _requestPermission();
    } else {
      _requesting = false;
      widget.controller._markUnsupported();
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    widget.controller._permissionRequested();
    setState(() => _requesting = true);
    var granted = false;
    try {
      granted = await _permissions.invokeMethod<bool>('requestCamera') ?? false;
    } on PlatformException {
      granted = false;
    }
    if (!mounted) return;
    widget.controller._permissionResult(granted);
    setState(() {
      _granted = granted;
      _requesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return _message(
        'AR try-on is only available on Android for now.',
      );
    }
    if (_requesting) {
      return ColoredBox(
        color: AppTheme.surface,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!_granted) {
      return _message(
        'Camera access is needed to try watches on your wrist. '
        'If you chose "Don\'t allow", enable it in Android Settings > Apps > '
        'VirtuWatch > Permissions.',
        action: TextButton(
          onPressed: _requestPermission,
          child: const Text('Try again'),
        ),
      );
    }
    return AndroidView(
      viewType: 'tryon/camera_view',
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) =>
          widget.controller._attach(MethodChannel('tryon/camera_view_$id')),
    );
  }

  Widget _message(String text, {Widget? action}) {
    return ColoredBox(
      color: AppTheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              if (action != null) ...[const SizedBox(height: 12), action],
            ],
          ),
        ),
      ),
    );
  }
}
