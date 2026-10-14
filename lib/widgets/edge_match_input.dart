import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'edge_match_guide.dart';
import 'luxe.dart';
import 'offset_stepper_control.dart';

/// Clamps [value] into [min]..[max] while staying a `double` throughout
/// (unlike `num.clamp`, which returns `num` and trips up call sites that
/// need an actual `double`, e.g. `Slider.value`).
double clampD(double value, double min, double max) {
  if (max <= min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// The "line up the edge" control shared by screen calibration and wrist
/// measurement: a Buttons/Slider toggle, the [EdgeMatchGuide], and the
/// control that moves its second line.
///
/// Buttons are the default because a wrist or card resting on the screen
/// can make some phones ignore a dragging finger (see
/// [OffsetStepperControl]). The slider stays available for devices that
/// never had that problem. The caller owns the layout math and passes in
/// an already clamped [offsetPx].
class EdgeMatchInput extends StatefulWidget {
  final double offsetPx;
  final double minPx;
  final double maxPx;
  final double guideHeight;

  /// Millimeters per logical pixel used to size the step buttons (0.2mm and
  /// 2mm). Calibration passes its rough guess, since the real ratio is what
  /// it is solving for.
  final double mmPerPixel;
  final ValueChanged<double> onChanged;

  const EdgeMatchInput({
    super.key,
    required this.offsetPx,
    required this.minPx,
    required this.maxPx,
    required this.guideHeight,
    required this.mmPerPixel,
    required this.onChanged,
  });

  @override
  State<EdgeMatchInput> createState() => _EdgeMatchInputState();
}

class _EdgeMatchInputState extends State<EdgeMatchInput> {
  bool _useSlider = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            luxePill('Buttons',
                selected: !_useSlider,
                onTap: () => setState(() => _useSlider = false)),
            const SizedBox(width: 8),
            luxePill('Slider',
                selected: _useSlider,
                onTap: () => setState(() => _useSlider = true)),
          ],
        ),
        if (_useSlider)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'If something resting on the screen blocks the slider, '
              'switch back to Buttons.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.guideHeight,
          child: EdgeMatchGuide(offsetPx: widget.offsetPx),
        ),
        const SizedBox(height: 8),
        if (_useSlider)
          Slider(
            value: widget.offsetPx,
            min: widget.minPx,
            max: widget.maxPx,
            activeColor: AppTheme.textPrimary,
            inactiveColor: AppTheme.outline,
            onChanged: widget.onChanged,
          )
        else
          OffsetStepperControl(
            offsetPx: widget.offsetPx,
            minPx: widget.minPx,
            maxPx: widget.maxPx,
            // Fixed real-world step sizes rather than a share of the range.
            smallStepPx: 0.2 / widget.mmPerPixel,
            largeStepPx: 2.0 / widget.mmPerPixel,
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}