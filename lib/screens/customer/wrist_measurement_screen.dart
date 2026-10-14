import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/screen_calibration_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/edge_match_input.dart';
import '../../widgets/luxe.dart';
import 'screen_calibration_screen.dart';

/// Plausible adult wrist width range in millimeters. Mirrors the manual
/// entry validation range, and bounds the step control and the default
/// starting guess.
const double _minPlausibleMm = 30;
const double _maxPlausibleMm = 120;
const double _defaultGuessMm = 60;

/// Wrist measurement by direct on-screen comparison, no camera involved.
///
/// WHY THIS REPLACED THE CAMERA APPROACH: a single camera has no inherent
/// sense of real-world distance, so estimating a physical size from a photo
/// always needs some calibration reference, and getting that reference from
/// a photo (edge detection across lighting, skin tones, and camera
/// distance) proved unreliable in practice.
///
/// This screen sidesteps the problem: the user rests their wrist above or
/// below the phone, lines its near edge up with a fixed top line, and moves
/// a second line down until it matches the wrist's far edge. The only
/// unknown is how many real millimeters one logical pixel covers on this
/// device, which [ScreenCalibrationScreen] measures once against a real
/// card and [ScreenCalibrationService] stores locally. Both screens share
/// [EdgeMatchInput], so the geometry lives in one place.
///
/// HONEST LIMITATION: this doesn't eliminate measurement error, it
/// relocates it. Accuracy now depends on how precisely someone can align
/// their wrist against the line by eye. That is a more forgiving and
/// consistent failure mode than the camera approach, but it is not
/// perfectly precise.
class WristMeasurementScreen extends StatefulWidget {
  const WristMeasurementScreen({super.key});

  @override
  State<WristMeasurementScreen> createState() =>
      _WristMeasurementScreenState();
}

class _WristMeasurementScreenState extends State<WristMeasurementScreen> {
  final _authService = AuthService();

  double? _savedWristWidthMm;
  double? _mmPerPixel;
  double _offsetPx = 0;
  bool _checkingCalibration = true;

  @override
  void initState() {
    super.initState();
    _loadSavedMeasurement();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCalibrated());
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      // Non-fatal. The saved-value row just shows "Not saved yet".
    }
  }

  Future<void> _ensureCalibrated({bool forceRecalibrate = false}) async {
    if (!forceRecalibrate) {
      final existing = await ScreenCalibrationService.getMmPerPixel();
      if (existing != null) {
        _applyCalibration(existing);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _checkingCalibration = true);
    final result = await Navigator.of(context).push<double>(
      MaterialPageRoute(builder: (_) => const ScreenCalibrationScreen()),
    );
    if (result != null) {
      _applyCalibration(result);
    } else if (mounted) {
      // User backed out without calibrating. Manual entry stays available.
      setState(() => _checkingCalibration = false);
    }
  }

  void _applyCalibration(double mmPerPixel) {
    if (!mounted) return;
    final startMm = clampD(
        _savedWristWidthMm ?? _defaultGuessMm, _minPlausibleMm, _maxPlausibleMm);
    setState(() {
      _mmPerPixel = mmPerPixel;
      _offsetPx = startMm / mmPerPixel;
      _checkingCalibration = false;
    });
  }

  double get _currentMm => _mmPerPixel == null ? 0 : _offsetPx * _mmPerPixel!;

  Future<void> _saveMeasurement() async {
    final mm = _currentMm;
    if (mm < _minPlausibleMm || mm > _maxPlausibleMm) return;
    try {
      await _authService.saveWristMeasurement(mm, method: 'screen');
      if (mounted) setState(() => _savedWristWidthMm = mm);
      _snack('Wrist measurement saved');
    } catch (e) {
      _snack(e.toString());
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
          title: Text('Enter wrist width', style: AppTheme.serif(size: 22)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Measure with a ruler across your wrist bone, or wrap a '
                'tape measure around your wrist and divide the circumference '
                'by 3.14. Most adult wrists fall between 50 and 70mm.',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 15),
                decoration: luxeFieldDecoration()
                    .copyWith(suffixText: 'mm', errorText: errorText),
                onChanged: (_) => setDialogState(() => errorText = null),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final value = double.tryParse(controller.text.trim());
                if (value == null ||
                    value < _minPlausibleMm ||
                    value > _maxPlausibleMm) {
                  setDialogState(() => errorText =
                      'Enter a value between ${_minPlausibleMm.toInt()} and ${_maxPlausibleMm.toInt()}mm');
                  return;
                }
                try {
                  await _authService.saveWristMeasurement(value,
                      method: 'manual');
                  if (context.mounted) Navigator.of(context).pop(true);
                } catch (e) {
                  setDialogState(() => errorText = e.toString());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final value = double.tryParse(controller.text.trim());
      if (value != null) {
        setState(() => _savedWristWidthMm = value);
        _snack('Wrist measurement saved');
      }
    }
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('How it works', style: AppTheme.serif(size: 22)),
        content: Text(
          'VirtuWatch measures your wrist by direct comparison against your '
          'screen. No camera needed.\n\n'
          'Rest your wrist above or below your phone, line its near edge up '
          'with the top line, then adjust the second line (with the step '
          'buttons or the slider, whichever works better on your phone) '
          'until it matches your wrist\'s far edge.\n\n'
          'This works because your screen was calibrated once against a real '
          'card, so VirtuWatch knows how many real millimeters each '
          'on-screen pixel covers on this device.\n\n'
          'It helps VirtuWatch recommend watches that fit your wrist '
          'comfortably.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Measure Wrist', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Recalibrate screen',
            icon: const Icon(Icons.straighten),
            onPressed: () => _ensureCalibrated(forceRecalibrate: true),
          ),
          IconButton(
            tooltip: 'How it works',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: _checkingCalibration
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _mmPerPixel == null
                ? _buildCalibrationRequiredState(context)
                : _buildMeasurementUi(context),
      ),
    );
  }

  Widget _buildCalibrationRequiredState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Calibrate first', style: AppTheme.serif(size: 26)),
          const SizedBox(height: 8),
          Text(
            'Your screen needs a one-time calibration before you can measure '
            'this way.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _ensureCalibrated(forceRecalibrate: true),
              child: const Text('Calibrate Now'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _showManualEntryDialog(context),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary),
            child: const Text('or enter manually instead'),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementUi(BuildContext context) {
    final mmPerPixel = _mmPerPixel!;
    // Hard floor: the guide must always be able to show at least 60mm of
    // gap, however much room the rest of the content needs. The +28 covers
    // EdgeMatchGuide's own top and bottom insets, so a full 60mm gap
    // renders unclipped.
    final minGuidePx = (60 / mmPerPixel) + 28;
    final minOffsetPx = _minPlausibleMm / mmPerPixel;
    final maxPlausibleOffsetPx = _maxPlausibleMm / mmPerPixel;

    return LayoutBuilder(
      builder: (context, outer) {
        // Give the guide as much height as it can, but never less than the
        // 60mm floor. If the rest of the content doesn't fit alongside it,
        // the page scrolls instead of the guide shrinking below usable size.
        final roughlyAvailableForGuide = outer.maxHeight - 300;
        final guideHeight = roughlyAvailableForGuide > minGuidePx
            ? roughlyAvailableForGuide
            : minGuidePx;
        final maxOffsetPxRaw = guideHeight - 28;
        final maxOffsetPx = maxOffsetPxRaw > maxPlausibleOffsetPx
            ? maxPlausibleOffsetPx
            : maxOffsetPxRaw;
        final boundedMax =
            maxOffsetPx <= minOffsetPx ? minOffsetPx + 1 : maxOffsetPx;
        final offsetPx = clampD(_offsetPx, minOffsetPx, boundedMax);

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: outer.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Rest your wrist above or below your phone, line its near '
                    'edge up with the top line, then adjust the second line '
                    'until it matches your wrist\'s far edge.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Text('${_currentMm.toStringAsFixed(1)}mm',
                      style: AppTheme.serif(size: 44)),
                  const SizedBox(height: 8),
                  EdgeMatchInput(
                    offsetPx: offsetPx,
                    minPx: minOffsetPx,
                    maxPx: boundedMax,
                    guideHeight: guideHeight,
                    mmPerPixel: mmPerPixel,
                    onChanged: (value) => setState(() => _offsetPx = value),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveMeasurement,
                      child: const Text('Save Measurement'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => _showManualEntryDialog(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('or enter manually instead',
                        style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(top: 12),
                    decoration: kTopRule,
                    child: Row(
                      children: [
                        Text('SAVED', style: kLabelStyle),
                        const Spacer(),
                        Text(
                          _savedWristWidthMm != null
                              ? '${_savedWristWidthMm!.toStringAsFixed(1)}mm'
                              : 'Not saved yet',
                          style: AppTheme.serif(
                            size: _savedWristWidthMm != null ? 22 : 16,
                            color: _savedWristWidthMm != null
                                ? AppTheme.textPrimary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}