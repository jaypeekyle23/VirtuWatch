import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';

class OutfitScanScreen extends StatefulWidget {
  const OutfitScanScreen({super.key});

  @override
  State<OutfitScanScreen> createState() => _OutfitScanScreenState();
}

class _OutfitScanScreenState extends State<OutfitScanScreen> {
  final _cloudinaryService = CloudinaryService();
  final _authService = AuthService();

  // Created once and reused — ML Kit segmenters carry real model-loading
  // overhead, so recreating one per scan would slow every single scan.
  // Subject Segmentation (rather than Selfie Segmentation) is used
  // deliberately: the selfie model is tuned for close-up, video-call-style
  // framing and performs noticeably worse on distant full-body shots —
  // exactly the framing outfit photos tend to use. Subject Segmentation is
  // Google's general "prominent subject in a normal photo" model instead.
  final _segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundConfidenceMask: true,
      enableForegroundBitmap: false,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );

  // Background pixels are flagged with this distinctive marker color
  // before palette analysis, then filtered back out of the results below.
  // Real clothing/skin essentially never produces pure magenta, which is
  // what makes it safe to use as a "this pixel was masked out" signal.
  static const _backgroundMarker = Color(0xFFFF00FF);
  static const _backgroundThreshold = 0.5; // ML Kit confidence cutoff

  File? _selectedImage;
  bool _isAnalyzing = false;
  List<({Color color, double percentage})>? _results;
  String? _errorMessage;
  int _step = 1;

  @override
  void dispose() {
    _segmenter.close();
    super.dispose();
  }

  Future<void> _scanOutfit(ImageSource source) async {
    final image = await _cloudinaryService.pickImage(source: source);
    if (image == null) return;

    setState(() {
      _selectedImage = image;
      _isAnalyzing = true;
      _errorMessage = null;
      _results = null;
      _step = 2;
    });

    try {
      final palette = await _analyzeWithSegmentation(image) ??
          await _analyzeWithCenterCrop(image);

      // Drop any swatch that's really just our background marker leaking
      // through (e.g. if segmentation missed a sliver of edge pixels),
      // then re-normalize percentages against only the real swatches.
      final swatches = palette.paletteColors
          .where((s) => !_isBackgroundMarker(s.color))
          .toList()
        ..sort((a, b) => b.population.compareTo(a.population));
      final top = swatches.take(4).toList();
      final totalPopulation =
          top.fold<int>(0, (sum, swatch) => sum + swatch.population);

      final results = top.map((swatch) {
        final percentage = totalPopulation == 0
            ? 0.0
            : (swatch.population / totalPopulation) * 100;
        return (color: swatch.color, percentage: percentage);
      }).toList();

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
                    'hex': _colorToHex(r.color),
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

  /// Runs real person segmentation (ML Kit) and returns a palette built
  /// only from foreground pixels. Returns null if segmentation itself
  /// fails for any reason (model not ready, platform issue, etc.) so the
  /// caller can fall back to the simpler center-crop heuristic instead of
  /// failing the whole scan.
  Future<PaletteGenerator?> _analyzeWithSegmentation(File image) async {
    List<double>? confidences;
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final result = await _segmenter.processImage(inputImage);
      confidences = result.foregroundConfidenceMask;  
    } catch (_) {
      return null;
    }
    if (confidences == null) return null;

    final bytes = await image.readAsBytes();
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final originalWidth = originalFrame.image.width;
    final originalHeight = originalFrame.image.height;
    originalFrame.image.dispose();

    // The foreground confidence mask is the same resolution as the input
    // image, so it maps 1:1 onto originalWidth/originalHeight — no
    // separate mask dimensions to track, unlike Selfie Segmentation's
    // mask object.
    if (confidences.length != originalWidth * originalHeight) return null;

    // Downscale to a small working copy — keeps the per-pixel masking
    // loop below fast regardless of the original photo's resolution.
    const maxDimension = 400;
    final longest =
        originalWidth > originalHeight ? originalWidth : originalHeight;
    final scale = maxDimension / longest;
    final targetWidth = (originalWidth * scale).round();
    final targetHeight = (originalHeight * scale).round();

    final smallCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final smallFrame = await smallCodec.getNextFrame();
    final rgba =
        await smallFrame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    smallFrame.image.dispose();
    if (rgba == null) return null;

    final buffer = Uint8List.fromList(rgba.buffer.asUint8List());
    for (var y = 0; y < targetHeight; y++) {
      final origY =
          (y * originalHeight / targetHeight).floor().clamp(0, originalHeight - 1);
      for (var x = 0; x < targetWidth; x++) {
        final origX =
            (x * originalWidth / targetWidth).floor().clamp(0, originalWidth - 1);
        final confidence = confidences[origY * originalWidth + origX];
        if (confidence < _backgroundThreshold) {
          final i = (y * targetWidth + x) * 4;
          buffer[i] = 255; // R
          buffer[i + 1] = 0; // G
          buffer[i + 2] = 255; // B
          buffer[i + 3] = 255; // A
        }
      }
    }

    return PaletteGenerator.fromByteData(
      EncodedImage(
        buffer.buffer.asByteData(),
        width: targetWidth,
        height: targetHeight,
      ),
      maximumColorCount: 8, // extra headroom since a few get filtered out
    );
  }

  /// Fallback used only if segmentation fails outright: restricts
  /// analysis to a center-weighted region, trimming the outer edges
  /// where background (pavement, bystanders, sky) typically shows.
  Future<PaletteGenerator> _analyzeWithCenterCrop(File image) async {
    final bytes = await image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width.toDouble();
    final height = frame.image.height.toDouble();
    frame.image.dispose();

    final region = Rect.fromLTWH(
      width * 0.15,
      height * 0.05,
      width * 0.70,
      height * 0.90,
    );

    return PaletteGenerator.fromImageProvider(
      FileImage(image),
      size: Size(width, height),
      region: region,
      maximumColorCount: 4,
    );
  }

  bool _isBackgroundMarker(Color color) {
    final dr = (color.r * 255) - _backgroundMarker.r * 255;
    final dg = (color.g * 255) - _backgroundMarker.g * 255;
    final db = (color.b * 255) - _backgroundMarker.b * 255;
    final distanceSquared = dr * dr + dg * dg + db * db;
    return distanceSquared < 40 * 40; // small tolerance for compression noise
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    return '#'
            '${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outfit Color Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stepCircle('1', 'Aim Camera', active: _step == 1),
                _stepConnector(),
                _stepCircle('2', 'Analyze', active: _step == 2),
                _stepConnector(),
                _stepCircle('3', 'Results', active: _step == 3),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_selectedImage != null)
                      Positioned.fill(
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.checkroom_outlined,
                              size: 72, color: AppTheme.textSecondary),
                          SizedBox(height: 12),
                          Text(
                            'No photo yet',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Snap a photo of your outfit to get started',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    if (_isAnalyzing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppTheme.gold),
                            SizedBox(height: 12),
                            Text(
                              'Analyzing colors...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    if (!_isAnalyzing)
                      Positioned(
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _results != null
                                ? 'Scan complete'
                                : 'Point camera at your outfit',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

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
                  const Text(
                    'LIVE COLOR EXTRACTION',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_results != null) ...[
                    Row(
                      children: [
                        for (var i = 0; i < _results!.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          _colorBar(_results![i].color,
                              _results![i].percentage / 100),
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
                                  color: AppTheme.textSecondary,
                                  fontSize: 10)),
                      ],
                    ),
                  ] else
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Scan an outfit to see the color breakdown',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lightbulb_outline,
                        color: AppTheme.textSecondary, size: 14),
                    SizedBox(width: 4),
                    Text('Good lighting helps',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
                Row(
                  children: const [
                    Icon(Icons.grid_view_outlined,
                        color: AppTheme.textSecondary, size: 14),
                    SizedBox(width: 4),
                    Text('Clusters: K=4',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),

            InkWell(
              onTap: _isAnalyzing
                  ? null
                  : () => _scanOutfit(ImageSource.camera),
              borderRadius: BorderRadius.circular(40),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _isAnalyzing
                      ? AppTheme.gold.withValues(alpha: 0.4)
                      : AppTheme.gold,
                  shape: BoxShape.circle,
                ),
                child: _isAnalyzing
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0E1A2B),
                          ),
                        ),
                      )
                    : const Icon(Icons.camera_alt_outlined,
                        color: Color(0xFF0E1A2B), size: 28),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isAnalyzing
                  ? 'Analyzing your outfit...'
                  : _results != null
                      ? 'Tap to scan again'
                      : 'Tap to capture outfit colors',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            TextButton(
              onPressed:
                  _isAnalyzing ? null : () => _scanOutfit(ImageSource.gallery),
              child: const Text(
                'or choose from gallery',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
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
            backgroundColor: active
                ? AppTheme.gold
                : AppTheme.surface,
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
            height: 28,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppTheme.gold : AppTheme.textSecondary,
                fontSize: 10,
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

  Widget _colorBar(Color color, double flexValue) {
    final flex = (flexValue * 100).round().clamp(1, 100);
    return Expanded(
      flex: flex,
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('How Outfit Color Scan Works',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'VirtuWatch analyzes a photo of your outfit to identify its '
          'dominant colors using a clustering technique (K-means-style '
          'color extraction).\n\n'
          'Take or choose a photo of your outfit in good lighting, and '
          'the app detects the main tones you\'re wearing — then uses '
          'those colors to recommend watches with cases, dials, or bands '
          'that complement your look.\n\n'
          'Good, even lighting helps the scan work more accurately.',
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