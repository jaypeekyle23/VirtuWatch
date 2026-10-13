import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A reusable "edge match" guide: one fixed horizontal reference line
/// near the top of the available area, and a second horizontal line
/// offset below it by [offsetPx] logical pixels. A thin vertical line
/// between them shows the gap being measured.
///
/// Used identically by screen calibration (matching a card's short edge)
/// and wrist measurement (matching a wrist's edge): the object rests
/// above or below the phone, its near edge lined up with the fixed top
/// line, and the bottom line is moved until it matches the object's far
/// edge. Same interaction, same widget, so there is only one place this
/// geometry can go wrong.
///
/// This widget is purely visual. The caller is responsible for bounding
/// [offsetPx] to what will actually fit (see the `LayoutBuilder` pattern in
/// `ScreenCalibrationScreen` and `WristMeasurementScreen`).
class EdgeMatchGuide extends StatelessWidget {
  final double offsetPx;

  const EdgeMatchGuide({super.key, required this.offsetPx});

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
              child: Container(width: 1, color: Colors.white38),
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
        child: Container(height: 2, color: AppTheme.textPrimary),
      ),
    );
  }
}