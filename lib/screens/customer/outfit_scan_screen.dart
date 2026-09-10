import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/color_extraction_service.dart';
import '../../theme/app_theme.dart';

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

  @override
  void dispose() {
    _colorExtractionService.dispose();
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