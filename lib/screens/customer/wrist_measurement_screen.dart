import 'dart:async';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import '../../services/auth_service.dart';
import '../../services/wrist_detection_service.dart';
import '../../theme/app_theme.dart';

class WristMeasurementScreen extends StatefulWidget {
  const WristMeasurementScreen({super.key});

  @override
  State<WristMeasurementScreen> createState() =>
      _WristMeasurementScreenState();
}

class _WristMeasurementScreenState extends State<WristMeasurementScreen> {
  String _selectedReference = 'ID Card';
  final List<String> _referenceOptions = [
    'ID Card',
    'Credit Card',
    '1-Peso Coin',
    '5-Peso Coin',
  ];

  final _authService = AuthService();
  double? _savedWristWidthMm;

  // --- Camera-based wrist detection state ---
  CameraController? _cameraController;
  HandLandmarkerPlugin? _handPlugin;
  StreamSubscription<List<Hand>>? _handSub;
  List<Hand> _lastHands = [];
  bool _cameraReady = false;
  String? _cameraError;
  String? _captureError;
  Timer? _captureErrorTimer;

  // Detected width (in raw sensor pixels) of the reference object in the
  // current frame, measured directly from pixel data rather than assumed
  // from screen geometry — see `_detectReferenceObjectWidthPx`. Null means
  // "not currently detected".
  double? _detectedObjectWidthSensorPx;
  bool get _referenceLikelyPresent => _detectedObjectWidthSensorPx != null;
  int _frameCounter = 0;

  // Tuning constants for the edge-detection heuristic below. All three are
  // rough starting points — NEED on-device recalibration once you can test
  // against real lighting, skin tones, and object contrast.
  static const double _edgeLumaDelta = 25;
  static const double _minObjectWidthFraction = 0.15;
  static const double _maxObjectWidthFraction = 0.92;

  @override
  void initState() {
    super.initState();
    _loadSavedMeasurement();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _cameraError = 'No camera found on this device.');
        }
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      // A single hand is all we need; higher confidence threshold reduces
      // false positives from background clutter behind the wrist.
      _handPlugin = HandLandmarkerPlugin.create(
        numHands: 1,
        minHandDetectionConfidence: 0.6,
        delegate: HandLandmarkerDelegate.gpu,
      );

      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_onCameraFrame);

      _handSub = _handPlugin!.landmarkStream.listen((hands) {
        if (mounted) setState(() => _lastHands = hands);
      });

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      // Covers camera-permission denial, no camera hardware, and any
      // native MediaPipe init failure. Manual entry stays available either
      // way, so this is non-fatal for the feature as a whole.
      if (mounted) {
        setState(() =>
            _cameraError = 'Camera unavailable. You can still enter your '
                'wrist width manually below.');
      }
    }
  }

  void _onCameraFrame(CameraImage image) {
    if (_handPlugin == null || _cameraController == null) return;
    try {
      _handPlugin!.processFrame(
        image,
        _cameraController!.description.sensorOrientation,
      );
    } catch (_) {
      // Drop the occasional bad frame rather than crashing the stream.
    }

    // Throttle the pixel scan — it doesn't need to run on every frame.
    _frameCounter++;
    if (_frameCounter % 5 == 0) {
      final widthPx = _detectReferenceObjectWidthPx(image);
      if (mounted && widthPx != _detectedObjectWidthSensorPx) {
        setState(() => _detectedObjectWidthSensorPx = widthPx);
      }
    }
  }

  /// Measures the reference object's *actual* width in the current frame,
  /// in raw sensor pixels — this is what makes the mm-per-pixel
  /// calibration reflect the real scene instead of a fixed screen-geometry
  /// constant that never changes with distance.
  ///
  /// Approach: average a horizontal band of rows near the vertical center
  /// of a generous search region (reduces single-row noise), estimate
  /// "background" luma from that band's far left/right edges (assumed to
  /// be skin/table, since the object should be smaller than the search
  /// region), then scan inward from both sides to find where luma first
  /// diverges meaningfully from that background — those are the object's
  /// left/right edges.
  ///
  /// CAVEATS: this is a brightness-contrast heuristic, not true object
  /// recognition. It assumes the object contrasts with its background and
  /// sits within the search region; it can be fooled by shadows, a
  /// similarly-toned background, or something else in frame. The tuning
  /// constants above are rough defaults that will need adjusting once
  /// this actually runs on a device.
  double? _detectReferenceObjectWidthPx(CameraImage image) {
    try {
      final plane = image.planes[0];
      final width = image.width;
      final height = image.height;
      final stride = plane.bytesPerRow;
      final bytes = plane.bytes;

      // Generous search region — wider than the on-screen guide box so
      // the object doesn't need to be pixel-perfectly aligned to it.
      final roiW = (width * 0.75).toInt();
      final roiH = (height * 0.55).toInt();
      final roiX = (width - roiW) ~/ 2;
      final roiY = (height - roiH) ~/ 2;

      final bandHeight = (roiH * 0.12).clamp(4, roiH).toInt();
      final bandStartY = roiY + (roiH - bandHeight) ~/ 2;

      const colStep = 2; // subsample columns for performance
      final columnCount = (roiW / colStep).ceil();
      final colMeans = List<double>.filled(columnCount, 0);

      for (int ci = 0; ci < columnCount; ci++) {
        final x = (roiX + ci * colStep).clamp(0, width - 1);
        double sum = 0;
        int count = 0;
        for (int y = bandStartY; y < bandStartY + bandHeight; y++) {
          final clampedY = y.clamp(0, height - 1);
          final index = clampedY * stride + x;
          if (index < 0 || index >= bytes.length) continue;
          sum += bytes[index];
          count++;
        }
        colMeans[ci] = count == 0 ? 0 : sum / count;
      }

      // Background estimate from the outer 10% of columns on each side.
      final edgeSampleCount =
          (columnCount * 0.1).clamp(1, columnCount ~/ 2).toInt();
      double backgroundSum = 0;
      int backgroundCount = 0;
      for (int i = 0; i < edgeSampleCount; i++) {
        backgroundSum += colMeans[i];
        backgroundSum += colMeans[columnCount - 1 - i];
        backgroundCount += 2;
      }
      final background =
          backgroundCount == 0 ? 0 : backgroundSum / backgroundCount;

      int? leftIdx;
      int? rightIdx;
      for (int i = 0; i < columnCount; i++) {
        if ((colMeans[i] - background).abs() > _edgeLumaDelta) {
          leftIdx = i;
          break;
        }
      }
      for (int i = columnCount - 1; i >= 0; i--) {
        if ((colMeans[i] - background).abs() > _edgeLumaDelta) {
          rightIdx = i;
          break;
        }
      }

      if (leftIdx == null || rightIdx == null || rightIdx <= leftIdx) {
        return null;
      }

      final widthPx = (rightIdx - leftIdx) * colStep.toDouble();
      final widthFraction = widthPx / roiW;
      if (widthFraction < _minObjectWidthFraction ||
          widthFraction > _maxObjectWidthFraction) {
        // Too small to trust as a real detection, or spans almost the
        // whole search region (more likely a lighting gradient across the
        // frame than an actual object edge).
        return null;
      }

      return widthPx;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _captureErrorTimer?.cancel();
    _handSub?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _handPlugin?.dispose();
    super.dispose();
  }

  /// Sets (or clears) the capture error banner. Non-null messages
  /// auto-dismiss after 5 seconds so the banner doesn't linger over the
  /// camera preview indefinitely.
  void _setCaptureError(String? message) {
    _captureErrorTimer?.cancel();
    setState(() => _captureError = message);
    if (message != null) {
      _captureErrorTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _captureError = null);
      });
    }
  }

  /// Samples the current live camera frame's hand landmarks, converts the
  /// on-screen reference-object guide into a millimeters-per-pixel ratio,
  /// and estimates + saves the wrist width.
  Future<void> _captureWrist(BuildContext context) async {
    _setCaptureError(null);

    if (!_cameraReady || _cameraController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is still starting up.')),
      );
      return;
    }
    if (_lastHands.isEmpty) {
      _setCaptureError(
          'No hand detected. Make sure your wrist is clearly in frame.');
      return;
    }
    if (_detectedObjectWidthSensorPx == null) {
      _setCaptureError(
          'Could not measure the $_selectedReference. Hold it directly '
          'against your wrist, against a plain background, then try again.');
      return;
    }

    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) {
      _setCaptureError('Camera still calibrating — try again.');
      return;
    }

    // mm-per-pixel is now derived from the object's actual measured width
    // in this frame, not a fixed on-screen guide box — this is what makes
    // it adapt correctly regardless of how far away the camera is.
    final referenceWidthMm = ReferenceObject.widthMm[_selectedReference]!;
    final mmPerPixel = referenceWidthMm / _detectedObjectWidthSensorPx!;

    final result = WristDetectionService.estimate(
      hand: _lastHands.first,
      imageWidth: previewSize.width.toInt(),
      imageHeight: previewSize.height.toInt(),
      mmPerPixel: mmPerPixel,
    );

    if (result == null) {
      _setCaptureError(
          'Could not get a reliable measurement. Make sure your wrist and '
          'the $_selectedReference are both clearly visible, then try again.');
      return;
    }

    try {
      await _authService.saveWristMeasurement(result.wristWidthMm,
          method: 'camera');
      if (context.mounted) {
        setState(() => _savedWristWidthMm = result.wristWidthMm);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrist measurement saved')),
        );
      }
    } catch (e) {
      if (context.mounted) _setCaptureError(e.toString());
    }
  }

  Future<void> _loadSavedMeasurement() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final existing = (doc.data()?['wristWidthMm'] as num?)?.toDouble();
      if (mounted) setState(() => _savedWristWidthMm = existing);
    } catch (_) {
      // Non-fatal — the "AWAITING SCAN" placeholder just stays visible.
    }
  }

  Future<void> _showManualEntryDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: _savedWristWidthMm?.toStringAsFixed(1) ?? '',
    );
    String? errorText;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Enter Wrist Width',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Measure with a ruler across your wrist bone, or wrap a '
                'tape measure around your wrist and divide the circumference '
                'by 3.14 (π). Most adult wrists fall between 50–70mm.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  suffixText: 'mm',
                  errorText: errorText,
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setDialogState(() => errorText = null),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final value = double.tryParse(controller.text.trim());
                if (value == null || value < 30 || value > 120) {
                  setDialogState(
                      () => errorText = 'Enter a value between 30–120mm');
                  return;
                }
                try {
                  await _authService.saveWristMeasurement(value);
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  setDialogState(() => errorText = e.toString());
                }
              },
              child: const Text('Save', style: TextStyle(color: AppTheme.gold)),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final value = double.tryParse(controller.text.trim());
      if (context.mounted && value != null) {
        setState(() => _savedWristWidthMm = value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrist measurement saved')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Measure Your Wrist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen camera preview fills the entire body.
          _buildCameraArea(),

          // Step indicator, floating just below the (transparent) app bar.
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 12,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.black.withValues(alpha: 0.35),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepCircle('1', 'Place\nReference', active: !_cameraReady),
                  _stepConnector(),
                  _stepCircle('2', 'Position\nWrist',
                      active: _cameraReady && _lastHands.isEmpty),
                  _stepConnector(),
                  _stepCircle('3', 'Capture',
                      active: _cameraReady &&
                          _lastHands.isNotEmpty &&
                          _referenceLikelyPresent),
                ],
              ),
            ),
          ),

          // Bottom control panel — the same controls as before, now
          // overlaid on the full-screen camera feed with a dark scrim
          // behind them so they stay legible over live video.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(context).padding.bottom + 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.background.withValues(alpha: 0),
                    AppTheme.background.withValues(alpha: 0.97),
                  ],
                  stops: const [0.0, 0.22],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _referenceOptions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final option = _referenceOptions[i];
                        final isSelected = _selectedReference == option;
                        return ChoiceChip(
                          label: Text(option),
                          selected: isSelected,
                          onSelected: (_) =>
                              setState(() => _selectedReference = option),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppTheme.surface,
                          selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppTheme.gold
                                : AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? AppTheme.gold
                                : Colors.transparent,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () => _captureWrist(context),
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          color: Color(0xFF0E1A2B), size: 24),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _showManualEntryDialog(context),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'or enter manually instead',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 6),

                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _savedWristWidthMm != null
                              ? '${_savedWristWidthMm!.toStringAsFixed(1)} mm'
                              : '— mm',
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.textSecondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _savedWristWidthMm != null
                                ? 'SAVED'
                                : 'AWAITING SCAN',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _setCaptureError(null),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.gold,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Retake', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_off_outlined,
                  size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text(_cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.gold),
      );
    }

    final previewSize = _cameraController!.value.previewSize!;
    // The sensor is natively landscape; displayed portrait width maps to
    // previewSize.height and vice versa (mirrors the plugin's own example).
    final targetAspect = previewSize.height / previewSize.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        double displayedWidth = constraints.maxWidth;
        double displayedHeight = displayedWidth / targetAspect;
        if (displayedHeight > constraints.maxHeight) {
          displayedHeight = constraints.maxHeight;
          displayedWidth = displayedHeight * targetAspect;
        }
        // The guide box is now just a visual placement aid — actual
        // calibration comes from `_detectReferenceObjectWidthPx`, which
        // scans a more generous region than this box, so the object
        // doesn't need to align to it pixel-perfectly.
        final guideWidth = displayedWidth * 0.55;
        final aspect = ReferenceObject.aspectRatioFor(_selectedReference);
        final guideHeight = guideWidth / aspect;
        final isCoin = aspect == 1.0;

        return Center(
          child: SizedBox(
            width: displayedWidth,
            height: displayedHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                // Everything — status badges, the guide box, and the
                // instruction/error text — is grouped into one column
                // anchored a bit above dead-center. Keeping it as one
                // contextual group (rather than separate screen-corner
                // overlays) is what keeps it clear of both the step
                // indicator up top and the control panel down below.
                Align(
                  alignment: const Alignment(0, -0.15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _statusBadge(
                            active: _lastHands.isNotEmpty,
                            label: _lastHands.isNotEmpty
                                ? 'Wrist Detected'
                                : 'No Hand',
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(
                            active: _referenceLikelyPresent,
                            label: _referenceLikelyPresent
                                ? 'Object Detected'
                                : 'No Object',
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: guideWidth,
                        height: guideHeight,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: (_lastHands.isNotEmpty &&
                                    _referenceLikelyPresent)
                                ? Colors.greenAccent
                                : AppTheme.gold,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(
                              isCoin ? guideWidth / 2 : 10),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        constraints:
                            BoxConstraints(maxWidth: displayedWidth * 0.75),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Hold your $_selectedReference against your wrist '
                          'over a plain background, both inside the box',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                      if (_captureError != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          constraints: BoxConstraints(
                              maxWidth: displayedWidth * 0.75),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _captureError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusBadge({required bool active, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              color: active ? Colors.greenAccent : Colors.redAccent, size: 8),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('How Wrist Measurement Works',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'VirtuWatch uses your phone\'s camera to estimate your wrist '
          'width automatically.\n\n'
          'Hold a reference object of known size (like an ID card or coin) '
          'directly against your wrist, over a plain background. The app '
          'measures the object\'s actual size in the live camera frame and '
          'uses that to work out a pixels-to-millimeters ratio, then '
          'applies it to your wrist — no tape measure needed.\n\n'
          'Holding the object against your wrist (rather than elsewhere in '
          'frame) keeps both at the same distance from the camera, which '
          'is what keeps the measurement accurate regardless of how far '
          'away you\'re holding the phone.\n\n'
          'This helps VirtuWatch recommend watches that will actually fit '
          'your wrist comfortably.',
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

  Widget _stepCircle(String number, String label, {required bool active}) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: active ? AppTheme.gold : AppTheme.surface,
            child: Text(
              number,
              style: TextStyle(
                color: active ? const Color(0xFF0E1A2B) : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 26,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppTheme.gold : AppTheme.textSecondary,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepConnector() {
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        width: 24,
        height: 1,
        color: AppTheme.textSecondary.withValues(alpha: 0.3),
      ),
    );
  }
}