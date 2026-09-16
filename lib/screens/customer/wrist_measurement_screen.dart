import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/screen_calibration_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/edge_match_guide.dart';
import 'screen_calibration_screen.dart';

/// Plausible adult wrist width range in millimeters — mirrors the manual
/// entry validation range, used here to bound the slider and the default
/// starting guess.
const double _minPlausibleMm = 30;
const double _maxPlausibleMm = 120;
const double _defaultGuessMm = 60;

/// Clamps [value] into [min]..[max] while staying a `double` throughout
/// (unlike `num.clamp`, which returns `num` and trips up call sites that
/// need an actual `double`, e.g. `Slider.value`).
double _clampD(double value, double min, double max) {
  if (max <= min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Wrist measurement via direct on-screen comparison, no camera involved.
///
/// WHY THIS REPLACED THE CAMERA-BASED APPROACH: a single camera has no
/// inherent sense of real-world distance, so estimating a physical size
/// from a photo always needs *some* calibration reference, and getting
/// that reference right from a photo (edge detection against varying
/// lighting, skin tones, and camera distance) turned out to be genuinely
/// unreliable in practice.
///
/// This screen sidesteps the whole problem: the user rests their wrist
/// above or below the phone, lines its near edge up with a fixed
/// reference line, and drags a slider to move a second line down until
/// it matches the wrist's far edge — a direct physical comparison, zero
/// camera, zero distance ambiguity. The only unknown is how many real
/// millimeters correspond to one logical pixel on this specific device's
/// screen, which [ScreenCalibrationScreen] measures once, empirically,
/// against a real card, and [ScreenCalibrationService] stores locally.
/// Both screens share the same [EdgeMatchGuide] widget for this
/// interaction, so there's only one place the geometry can go wrong.
///
/// HONEST LIMITATION: this doesn't eliminate measurement error, it
/// relocates it. Instead of camera/lighting/edge-detection error, accuracy
/// now depends on how precisely someone can align their wrist against the
/// reference line and drag a slider by eye. That's a more forgiving and
/// consistent failure mode than the camera approach (no lighting or
/// distance dependency), but it is not perfectly precise — worth stating
/// plainly rather than overselling it.
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

  Future<void> _loadSavedMeasurement() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final existing = (doc.data()?['wristWidthMm'] as num?)?.toDouble();
      if (mounted) setState(() => _savedWristWidthMm = existing);
    } catch (_) {
      // Non-fatal — the "AWAITING MEASUREMENT" placeholder just stays visible.
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
      // User backed out without calibrating — manual entry stays
      // available below, same non-fatal fallback philosophy as the old
      // camera-unavailable case.
      setState(() => _checkingCalibration = false);
    }
  }

  void _applyCalibration(double mmPerPixel) {
    if (!mounted) return;
    final startMm = _clampD(
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
      if (mounted) {
        setState(() => _savedWristWidthMm = mm);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrist measurement saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                if (value == null ||
                    value < _minPlausibleMm ||
                    value > _maxPlausibleMm) {
                  setDialogState(() => errorText =
                      'Enter a value between ${_minPlausibleMm.toInt()}–${_maxPlausibleMm.toInt()}mm');
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

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('How Wrist Measurement Works',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'VirtuWatch measures your wrist by direct comparison against '
          'your screen — no camera needed.\n\n'
          'Rest your wrist above or below your phone, line its near edge '
          'up with the top line, then drag the slider until the bottom '
          'line matches your wrist\'s far edge.\n\n'
          'This works because your screen was calibrated once against a '
          'real card, so VirtuWatch knows exactly how many real '
          'millimeters each on-screen pixel represents on this specific '
          'device.\n\n'
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Measure Your Wrist'),
        actions: [
          IconButton(
            tooltip: 'Recalibrate screen',
            icon: const Icon(Icons.straighten),
            onPressed: () => _ensureCalibrated(forceRecalibrate: true),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: SafeArea(
        child: _checkingCalibration
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.gold))
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
          const Icon(Icons.straighten, size: 48, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text(
            'Screen calibration is needed once before measuring this way.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _ensureCalibrated(forceRecalibrate: true),
            child: const Text('Calibrate Now'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _showManualEntryDialog(context),
            child: const Text(
              'or enter manually instead',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementUi(BuildContext context) {
    final mmPerPixel = _mmPerPixel!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          const Text(
            'Rest your wrist above or below your phone, line its near '
            'edge up with the top line, then drag the slider until the '
            'bottom line matches your wrist\'s far edge.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text(
            '${_currentMm.toStringAsFixed(1)} mm',
            style: const TextStyle(
              color: AppTheme.gold,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxOffsetPx = constraints.maxHeight * 0.9;
                final minOffsetPx = _minPlausibleMm / mmPerPixel;
                final maxPlausibleOffsetPx = _maxPlausibleMm / mmPerPixel;
                final effectiveMaxOffsetPx = maxPlausibleOffsetPx > maxOffsetPx
                    ? maxOffsetPx
                    : maxPlausibleOffsetPx;
                final boundedMax = effectiveMaxOffsetPx <= minOffsetPx
                    ? minOffsetPx + 1
                    : effectiveMaxOffsetPx;
                final offsetPx = _clampD(_offsetPx, minOffsetPx, boundedMax);

                return Column(
                  children: [
                    Expanded(child: EdgeMatchGuide(offsetPx: offsetPx)),
                    Slider(
                      value: offsetPx,
                      min: minOffsetPx,
                      max: boundedMax,
                      activeColor: AppTheme.gold,
                      onChanged: (value) => setState(() => _offsetPx = value),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveMeasurement,
              child: const Text('Save Measurement'),
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
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _savedWristWidthMm != null ? 'SAVED' : 'AWAITING MEASUREMENT',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}