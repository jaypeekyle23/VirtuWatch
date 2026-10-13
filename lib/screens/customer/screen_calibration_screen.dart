import 'package:flutter/material.dart';
import '../../services/screen_calibration_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/edge_match_input.dart';
import '../../widgets/luxe.dart';

/// Known-size real-world objects the customer can calibrate against.
/// The card is the ISO/IEC 7810 ID-1 standard. The PHP 20 coin's 30mm
/// diameter comes from Wikipedia, cross-checked against BSP's New
/// Generation Currency coin series announcement.
///
/// Only these two are offered. Older and newer versions of several
/// Philippine coins (PHP 1, 5, 10) differ in size between the 1995-2017
/// series and the current one, and both are still in circulation. A single
/// unlabeled "PHP 5" or "PHP 10" choice could have the customer grab the
/// wrong-sized coin with no way to know, silently corrupting their
/// calibration. The PHP 20 coin has no older version (it replaced a
/// banknote in 2019), so it carries none of that ambiguity.
///
/// The card is the default because it is the largest option, so the same
/// small alignment error is a smaller share of the length being matched.
enum _ReferenceObject {
  card('Card', 53.98,
      'Lay any ID, ATM, or credit/debit card flat above or below your '
      'phone (they are all the same standard size).'),
  coin20('PHP 20 coin', 30.0,
      'Lay a PHP 20 coin flat above or below your phone.');

  final String label;
  final double mm;
  final String instruction;
  const _ReferenceObject(this.label, this.mm, this.instruction);
}

/// A one-time, per-device calibration step: the customer lays a real,
/// known-size object flat above or below the phone, its near edge aligned
/// with a fixed top line, and moves a second line down until it matches the
/// object's far edge. That single distance reveals how many real
/// millimeters correspond to one logical pixel on this device's screen.
/// See [ScreenCalibrationService] for why this is needed instead of
/// trusting reported device specs.
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
      // length. Reset so the guide restarts from a fresh rough guess for
      // the new object instead of carrying over a meaningless pixel value.
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
    const muted = TextStyle(
        color: AppTheme.textSecondary, fontSize: 13, height: 1.4);

    return Scaffold(
      appBar: AppBar(
        title: Text('Calibrate Screen', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, outer) {
            final roughMmPerPixel =
                ScreenCalibrationService.roughGuessMmPerPixel();
            // Hard floor: the guide must always be able to show at least
            // 60mm of gap, however much room the rest of the content needs.
            // The +28 covers EdgeMatchGuide's own top and bottom insets, so
            // a full 60mm gap renders unclipped.
            final minGuidePx = (60 / roughMmPerPixel) + 28;
            final roughlyAvailableForGuide = outer.maxHeight - 380;
            final guideHeight = roughlyAvailableForGuide > minGuidePx
                ? roughlyAvailableForGuide
                : minGuidePx;
            final maxOffsetPx = guideHeight - 28;
            final minOffsetPx = maxOffsetPx * 0.15;
            final offsetPx = clampD(
              _offsetPx ?? _selected.mm / roughMmPerPixel,
              minOffsetPx,
              maxOffsetPx,
            );

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: outer.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'One-time setup so VirtuWatch knows how big things '
                        'really are on this screen.',
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                      const SizedBox(height: 16),
                      const Text('REFERENCE OBJECT', style: kLabelStyle),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final ref in _ReferenceObject.values)
                            luxePill(ref.label,
                                selected: ref == _selected,
                                onTap: () => _selectReference(ref)),
                        ],
                      ),
                      if (_selected != _ReferenceObject.card) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'A card gives the most accurate calibration. The '
                          'PHP 20 coin works too, but a card is recommended '
                          'if you have one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '${_selected.instruction} Line its near edge up with '
                        'the top line, then adjust the second line until it '
                        'matches the far edge.',
                        textAlign: TextAlign.center,
                        style: muted,
                      ),
                      const SizedBox(height: 12),
                      EdgeMatchInput(
                        offsetPx: offsetPx,
                        minPx: minOffsetPx,
                        maxPx: maxOffsetPx,
                        guideHeight: guideHeight,
                        mmPerPixel: roughMmPerPixel,
                        onChanged: (value) =>
                            setState(() => _offsetPx = value),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _confirm(offsetPx),
                          child: const Text('Confirm Calibration'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'You only need to do this once for this device. You '
                        'can redo it any time from the wrist measurement '
                        'screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}