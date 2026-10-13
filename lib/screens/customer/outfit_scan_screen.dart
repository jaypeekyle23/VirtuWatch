import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/color_extraction_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_icon_loader.dart';
import '../../widgets/luxe.dart';

class OutfitScanScreen extends StatefulWidget {
  const OutfitScanScreen({super.key});

  @override
  State<OutfitScanScreen> createState() => _OutfitScanScreenState();
}

class _OutfitScanScreenState extends State<OutfitScanScreen> {
  final _cloudinaryService = CloudinaryService();
  final _authService = AuthService();
  final _colorExtractionService = ColorExtractionService();

  File? _selectedImage;
  bool _isAnalyzing = false;
  List<({Color color, double percentage})>? _results;
  String? _errorMessage;
  int _step = 1;

  // --- Embedded live camera preview state ---
  // Unlike WristMeasurementScreen, this doesn't need a continuous frame
  // stream or any live detection — just a live preview to aim with and a
  // single still capture on demand, so there's no HandLandmarkerPlugin-
  // style pipeline here, just CameraController.takePicture().
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
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
      await _cameraController!.initialize();

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      // Covers camera-permission denial, no camera hardware, etc. Gallery
      // selection stays available either way, so this is non-fatal for
      // the feature as a whole.
      if (mounted) {
        setState(() => _cameraError =
            'Camera unavailable. You can still choose a photo from your '
            'gallery below.');
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _colorExtractionService.dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final photo = await _cameraController!.takePicture();
      await _analyzeImage(File(photo.path));
    } catch (e) {
      if (mounted) {
        setState(() =>
            _errorMessage = 'Could not capture a photo. Please try again.');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final image =
        await _cloudinaryService.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    await _analyzeImage(image);
  }

  void _retake() {
    setState(() {
      _selectedImage = null;
      _results = null;
      _errorMessage = null;
      _step = 1;
    });
  }

  Future<void> _analyzeImage(File image) async {
    setState(() {
      _selectedImage = image;
      _isAnalyzing = true;
      _errorMessage = null;
      _results = null;
      _step = 2;
    });

    try {
      final results =
          await _colorExtractionService.extractDominantColors(image);

      if (!mounted) return;
      setState(() {
        _results = results;
        _isAnalyzing = false;
        _step = 3;
      });

      // Persist for the future recommendations engine to use. Non-fatal —
      // the scan result still displays even if this write fails.
      try {
        await _authService.saveOutfitColors(
          results
              .map((r) => {
                    'hex': colorToHex(r.color),
                    'percentage': r.percentage,
                  })
              .toList(),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Scan complete, but could not save to your profile.'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _step = 1;
        _errorMessage =
            'Could not analyze this photo. Please try a clearer shot of your outfit.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Outfit Scan', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen camera preview (or the captured photo, once one
          // exists) fills the entire body.
          _buildCameraArea(),

          // Step labels, floating just below the transparent app bar.
          Positioned(
            top: padding.top + kToolbarHeight + 8,
            left: 0,
            right: 0,
            child: _stepBar(),
          ),

          // Bottom controls, over the camera feed with a dark scrim behind
          // them so they stay legible over live video.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 16, 20, padding.bottom + 12),
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
                  if (_results != null) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('DOMINANT COLORS', style: kLabelStyle),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < _results!.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          _colorBar(
                              _results![i].color, _results![i].percentage / 100),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final r in _results!)
                          Text('${r.percentage.round()}%',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  _shutter(),
                  const SizedBox(height: 10),
                  Text(
                    _isAnalyzing
                        ? 'Analyzing your outfit...'
                        : _step == 3
                            ? 'Tap to scan again'
                            : 'Tap to capture outfit colors',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                  ),
                  if (_step != 3)
                    InkWell(
                      onTap: _isAnalyzing ? null : _pickFromGallery,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('OR CHOOSE FROM GALLERY',
                            style: kLabelStyle),
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

  /// "AIM  ANALYZE  RESULTS", with the current step in white.
  Widget _stepBar() {
    const labels = ['AIM', 'ANALYZE', 'RESULTS'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.black.withValues(alpha: 0.35),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Container(
                width: 24,
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white24,
              ),
            Text(
              labels[i],
              style: kLabelStyle.copyWith(
                color: _step == i + 1 ? AppTheme.textPrimary : Colors.white54,
                fontWeight:
                    _step == i + 1 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The main button: a gold shutter while aiming, and a quiet outlined
  /// "scan again" once results are showing.
  Widget _shutter() {
    final done = _step == 3;
    return InkWell(
      onTap: done
          ? _retake
          : (_isAnalyzing || !_cameraReady ? null : _captureFromCamera),
      customBorder: const CircleBorder(),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done
              ? null
              : (_isAnalyzing
                  ? AppTheme.gold.withValues(alpha: 0.4)
                  : AppTheme.gold),
          border: done ? Border.all(color: Colors.white54, width: 1.5) : null,
        ),
        child: _isAnalyzing
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.background),
                ),
              )
            : Icon(
                done ? Icons.refresh : Icons.camera_alt_outlined,
                color: done ? AppTheme.textPrimary : AppTheme.background,
                size: 28,
              ),
      ),
    );
  }

  Widget _buildCameraArea() {
    // Once there's a captured photo (mid-analysis or showing results),
    // freeze on that instead of the live feed.
    if (_selectedImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Image.file(_selectedImage!, fit: BoxFit.cover),
          ),
          if (_isAnalyzing)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: const Center(
                child: AnimatedIconLoader(
                  icon: Icons.search,
                  label: 'Analyzing colors...',
                ),
              ),
            ),
        ],
      );
    }

    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Camera unavailable', style: AppTheme.serif(size: 26)),
              const SizedBox(height: 8),
              Text(_cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      );
    }

    if (!_cameraReady || _cameraController == null) {
      return const Center(
        child: AnimatedIconLoader(
          icon: Icons.photo_camera_outlined,
          label: 'Starting camera...',
          motion: IconLoaderMotion.pulse,
        ),
      );
    }

    final previewSize = _cameraController!.value.previewSize!;
    // The sensor is natively landscape; displayed portrait width maps to
    // previewSize.height and vice versa.
    final targetAspect = previewSize.height / previewSize.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        double displayedWidth = constraints.maxWidth;
        double displayedHeight = displayedWidth / targetAspect;
        if (displayedHeight > constraints.maxHeight) {
          displayedHeight = constraints.maxHeight;
          displayedWidth = displayedHeight * targetAspect;
        }

        // The framing guide: a tall rounded rectangle sized for a
        // shoulders-to-waist outfit shot. Outfits need much more of the
        // frame than a small object would.
        final guideWidth = displayedWidth * 0.62;
        final guideHeight = displayedHeight * 0.66;

        return Center(
          child: SizedBox(
            width: displayedWidth,
            height: displayedHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                Align(
                  alignment: const Alignment(0, -0.05),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: guideWidth,
                        height: guideHeight,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white70, width: 1.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        constraints:
                            BoxConstraints(maxWidth: displayedWidth * 0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Fit your outfit inside the frame, shoulders to waist',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
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

  Widget _colorBar(Color color, double flexValue) {
    final flex = (flexValue * 100).round().clamp(1, 100);
    return Expanded(
      flex: flex,
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('How it works', style: AppTheme.serif(size: 22)),
        content: const Text(
          'VirtuWatch analyzes a photo of your outfit to find its dominant '
          'colors, using a clustering technique (K-means-style color '
          'extraction).\n\n'
          'Fit your outfit inside the on-screen guide, in good lighting. The '
          'app detects the main tones you are wearing, then uses them to '
          'recommend watches with cases, dials, or bands that complement '
          'your look.\n\n'
          'Good, even lighting helps the scan work more accurately.',
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