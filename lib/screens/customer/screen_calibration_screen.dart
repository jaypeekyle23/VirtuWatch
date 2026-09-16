import 'package:flutter/material.dart';
import '../../services/screen_calibration_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/edge_match_guide.dart';

/// Known-size real-world objects the customer can calibrate against.
/// Diameter for the card is the ISO/IEC 7810 ID-1 standard; the ₱20
/// coin's 30mm diameter is sourced from Wikipedia (cross-checked
/// against BSP's New Generation Currency Coin Series announcement).
///
/// Deliberately limited to just these two. Older and newer versions of
/// several Philippine coin denominations (\u20b11, \u20b15, \u20b110) turned out to
/// differ in size between the 1995-2017 BSP Series and the current New
/// Generation Currency series — both eras are still realistically in
/// circulation side by side, and offering a single unlabeled "\u20b15" or
/// "\u20b110" choice risks the customer grabbing the wrong-sized coin
/// without any way to know, silently corrupting their calibration. The
/// ₱20 coin has no older version at all (it replaced a banknote in
/// 2019), so it carries none of that ambiguity — that's why it's the
/// only coin offered here, not the smaller/more common denominations.
///
/// Card is still the default: it's the largest option, so the same
/// small amount of human eye/slider alignment error is a smaller
/// percentage of the total length being matched.
enum _ReferenceObject {
  card('Card', 53.98,
      'Lay any ID, ATM, or credit/debit card flat above or below your '
      'phone (they\'re all the same standard size).'),
  coin20('\u20b120', 30.0, 'Lay a \u20b120 coin flat above or below your phone.');

  final String label;
  final double mm;
  final String instruction;
  const _ReferenceObject(this.label, this.mm, this.instruction);
}

/// Clamps [value] into [min]..[max] while staying a `double` throughout
/// (unlike `num.clamp`, which returns `num` and trips up call sites that
/// need an actual `double`, e.g. `Slider.value`).
double _clampD(double value, double min, double max) {
  if (max <= min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// A one-time, per-device calibration step: the customer lays a real,
/// known-size object flat above or below the phone, its near edge
/// aligned with a fixed top reference line, and drags a slider to move
/// a second line down until it matches the object's far edge. That
/// single distance reveals exactly how many real millimeters correspond
/// to one logical pixel on *this* device's screen — see
/// [ScreenCalibrationService] for why this is necessary instead of
/// trusting reported device specs.
///
/// A card is the default reference (most precise, since it's the
/// largest option), with the ₱20 coin offered as the sole alternative
/// for people without a card handy — see [_ReferenceObject] for why
/// only that one coin is offered rather than the more commonly-carried
/// smaller denominations.
///
/// Pops with the resulting mm-per-pixel value once confirmed, or null if
/// the user backs out without confirming.
class ScreenCalibrationScreen extends StatefulWidget {
  const ScreenCalibrationScreen({super.key});

  @override
  State<ScreenCalibrationScreen> createState() =>
      _ScreenCalibrationScreenState();
}

class _ScreenCalibrationScreenState extends State<ScreenCalibrationScreen> {
  _ReferenceObject _selected = _ReferenceObject.card;
  double? _offsetPx;

  void _selectReference(_ReferenceObject ref) {
    if (ref == _selected) return;
    setState(() {
      _selected = ref;
      // A previous offset was calibrated against a different physical
      // length — reset so the guide restarts from a fresh rough guess
      // for the newly selected object rather than carrying over a
      // now-meaningless pixel value.
      _offsetPx = null;
    });
  }

  Future<void> _confirm(double offsetPx) async {
    if (offsetPx <= 0) return;
    final mmPerPixel = _selected.mm / offsetPx;
    await ScreenCalibrationService.saveMmPerPixel(mmPerPixel);
    if (mounted) Navigator.of(context).pop(mmPerPixel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibrate Your Screen'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'One-time setup, so VirtuWatch knows exactly how big '
                'things really are on this screen.',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'WHAT ARE YOU USING?',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _ReferenceObject.values.map((ref) {
                  final isSelected = ref == _selected;
                  return ChoiceChip(
                    label: Text(ref.label),
                    selected: isSelected,
                    onSelected: (_) => _selectReference(ref),
                    selectedColor: AppTheme.gold.withValues(alpha: 0.25),
                    backgroundColor: AppTheme.surface,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppTheme.gold
                          : AppTheme.textSecondary.withValues(alpha: 0.3),
                    ),
                  );
                }).toList(),
              ),
              if (_selected != _ReferenceObject.card) ...[
                const SizedBox(height: 6),
                const Text(
                  'A card gives the most accurate calibration. The '
                  '\u20b120 coin works too, but a card is recommended if you '
                  'have one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '${_selected.instruction} Line its near edge up with the '
                'top line, then drag the slider until the bottom line '
                'matches the object\'s far edge.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxOffsetPx = constraints.maxHeight * 0.85;
                    final minOffsetPx = maxOffsetPx * 0.15;
                    final roughGuessPx = _selected.mm /
                        ScreenCalibrationService.roughGuessMmPerPixel();
                    final offsetPx = _clampD(
                      _offsetPx ?? roughGuessPx,
                      minOffsetPx,
                      maxOffsetPx,
                    );

                    return Column(
                      children: [
                        Expanded(
                          child: EdgeMatchGuide(offsetPx: offsetPx),
                        ),
                        Slider(
                          value: offsetPx,
                          min: minOffsetPx,
                          max: maxOffsetPx,
                          activeColor: AppTheme.gold,
                          onChanged: (value) =>
                              setState(() => _offsetPx = value),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _confirm(offsetPx),
                            child: const Text('Confirm Calibration'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You only need to do this once for this device. You can '
                'redo it any time from the wrist measurement screen if it '
                'ever feels off.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}