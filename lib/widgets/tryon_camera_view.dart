import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/ar_readiness.dart';

/// Typed handle to the native AR try-on view (Android only).
///
/// The native side (TryOnPlatformView.kt) runs CameraX -> MediaPipe hand
/// tracking -> Filament rendering entirely on-device. This controller is the
/// only thing the rest of the app needs to talk to it, so no screen has to
/// deal with raw MethodChannels. Calls made before the view exists are
/// safely ignored (the scale is remembered and applied once it attaches).
class TryOnController {
  MethodChannel? _channel;
  double _scale = 1.0;

  /// The most recent loadModel request. A native view that gets recreated
  /// (e.g. after retrying the camera permission) starts with no watch, so
  /// this is re-sent on every attach.
  Map<String, Object?>? _lastModel;

  /// Completed when the native view first attaches, for a loadModel call
  /// that was made before the view existed.
  Completer<void>? _attachWaiter;

  void _attach(MethodChannel channel) {
    _channel = channel;
    if (_scale != 1.0) _invoke<void>('setWatchScale', _scale);
    final waiter = _attachWaiter;
    _attachWaiter = null;
    if (waiter != null) {
      waiter.complete();
    } else if (_lastModel != null) {
      _invoke<bool>('loadModel', _lastModel);
    }
  }

  void _detach() => _channel = null;

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

  /// Shows the .glb at [path] on the wrist, placed using [fit]. If the native
  /// view isn't ready yet this waits for it. Returns false if the file could
  /// not be loaded (the previous watch stays on screen) or if a newer
  /// request replaced this one while it waited.
  Future<bool> loadModel(String path, ArFit fit) async {
    final args = <String, Object?>{'path': path, 'fit': fit.toChannelMap()};
    _lastModel = args;
    if (_channel == null) {
      await (_attachWaiter ??= Completer<void>()).future;
    }
    if (!identical(_lastModel, args)) return false;
    return await _invoke<bool>('loadModel', args) ?? false;
  }

  /// Toggle between front and back camera.
  Future<void> switchCamera() => _invoke<void>('switchCamera');

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
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    var granted = false;
    try {
      granted = await _permissions.invokeMethod<bool>('requestCamera') ?? false;
    } on PlatformException {
      granted = false;
    }
    if (!mounted) return;
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
