import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A reusable "edge match" guide: one fixed horizontal reference line
/// near the top of the available area, and a second horizontal line
/// offset below it by [offsetPx] logical pixels — a connecting vertical
/// line between them shows the gap being measured.
///
/// Used identically by screen calibration (matching a card's short edge)
/// and wrist measurement (matching a wrist's edge): the object rests
/// above or below the phone, its near edge lined up with the fixed top
/// line, and the bottom line is dragged (via a Slider the caller
/// supplies) until it matches the object's far edge. Same interaction,
/// same widget, so there's only one place this geometry can go wrong.
///
/// This widget is purely visual — it draws the two lines at the offset
/// it's given. The caller is responsible for bounding [offsetPx] to
/// what will actually fit (see the `LayoutBuilder` pattern in
/// `ScreenCalibrationScreen`/`WristMeasurementScreen`).
class EdgeMatchGuide extends StatelessWidget {
  final double offsetPx;
  final String? centerLabel;

  const EdgeMatchGuide({
    super.key,
    required this.offsetPx,
    this.centerLabel,
  });

  static const double _topInset = 8;
  static const double _lineWidthFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          _line(top: _topInset),
          _line(top: _topInset + offsetPx),
          Positioned(
            top: _topInset,
            left: 0,
            right: 0,
            height: offsetPx,
            child: Center(
              child: Container(width: 2, color: AppTheme.gold.withValues(alpha: 0.6)),
            ),
          ),
          if (centerLabel != null)
            Positioned(
              top: _topInset + offsetPx / 2 - 10,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    centerLabel!,
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line({required double top}) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: FractionallySizedBox(
        widthFactor: _lineWidthFraction,
        alignment: Alignment.center,
        child: Container(height: 3, color: AppTheme.gold),
      ),
    );
  }
}