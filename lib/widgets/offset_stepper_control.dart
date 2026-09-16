import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A discrete, tap/hold-based alternative to a dragging [Slider], used
/// to adjust an [EdgeMatchGuide]'s offset.
///
/// WHY NOT A SLIDER: this control is operated with one hand while an
/// object (a wrist or a card) rests statically on the screen elsewhere,
/// held there by the other hand. On many devices, an unusually large,
/// stationary contact area (like a wrist) is treated by the touch
/// controller/OS as a "palm," and its anti-mistouch filtering can
/// suppress *other* simultaneous touches too — especially ones
/// involving continuous movement, which is exactly what dragging a
/// Slider thumb is. That filtering happens below Flutter, at the
/// OS/touch-controller level, so there's no way to override it from
/// app code directly.
///
/// A stationary tap or held-press, performed well away from where the
/// object rests, is a fundamentally different kind of input — no
/// movement, no proximity to the large contact area — and survives
/// that filtering far more reliably than a drag does. Small buttons
/// step by [smallStepPx]; large buttons step by [largeStepPx]. Holding
/// a button repeats the step on a timer instead of requiring repeated
/// taps.
class OffsetStepperControl extends StatefulWidget {
  final double offsetPx;
  final double minPx;
  final double maxPx;
  final double smallStepPx;
  final double largeStepPx;
  final ValueChanged<double> onChanged;

  const OffsetStepperControl({
    super.key,
    required this.offsetPx,
    required this.minPx,
    required this.maxPx,
    required this.smallStepPx,
    required this.largeStepPx,
    required this.onChanged,
  });

  @override
  State<OffsetStepperControl> createState() => _OffsetStepperControlState();
}

class _OffsetStepperControlState extends State<OffsetStepperControl> {
  Timer? _repeatTimer;

  void _step(double deltaPx) {
    final next = widget.offsetPx + deltaPx;
    final clamped = next < widget.minPx
        ? widget.minPx
        : (next > widget.maxPx ? widget.maxPx : next);
    widget.onChanged(clamped);
  }

  void _startRepeating(double deltaPx) {
    _step(deltaPx);
    _repeatTimer?.cancel();
    _repeatTimer =
        Timer.periodic(const Duration(milliseconds: 130), (_) => _step(deltaPx));
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  Widget _button(IconData icon, double deltaPx, {required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTapDown: (_) => _startRepeating(deltaPx),
        onTapUp: (_) => _stopRepeating(),
        onTapCancel: _stopRepeating,
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.6)),
          ),
          child: Icon(icon, color: AppTheme.gold, size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // "+" grows the offset, which moves the guide's bottom line further
    // down — so down-pointing icons increase, up-pointing decrease.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _button(Icons.keyboard_double_arrow_up, -widget.largeStepPx,
            tooltip: 'Move up (large step)'),
        const SizedBox(width: 8),
        _button(Icons.keyboard_arrow_up, -widget.smallStepPx,
            tooltip: 'Move up (small step)'),
        const SizedBox(width: 20),
        _button(Icons.keyboard_arrow_down, widget.smallStepPx,
            tooltip: 'Move down (small step)'),
        const SizedBox(width: 8),
        _button(Icons.keyboard_double_arrow_down, widget.largeStepPx,
            tooltip: 'Move down (large step)'),
      ],
    );
  }
}