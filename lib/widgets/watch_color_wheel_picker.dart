import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/watch_colors.dart';
import '../theme/app_theme.dart';

/// Freeform color entry for a watch's primary color: an HSV wheel (hue
/// by angle, saturation by distance from center) plus a brightness
/// slider and a directly-editable hex field, kept in sync both ways.
///
/// This is the escape hatch next to [WatchColorPicker]'s fixed swatches
/// for a watch color that doesn't match any of them — no photo-based
/// guessing involved, just a precise, merchant-driven way to pick one.
class WatchColorWheelPicker extends StatefulWidget {
  final String initialHex;
  final ValueChanged<String> onChanged;

  const WatchColorWheelPicker({
    super.key,
    required this.initialHex,
    required this.onChanged,
  });

  @override
  State<WatchColorWheelPicker> createState() => _WatchColorWheelPickerState();
}

class _WatchColorWheelPickerState extends State<WatchColorWheelPicker> {
  static const _wheelSize = 180.0;

  late HSVColor _hsv;
  late final TextEditingController _hexController;

  // Set while we're writing to _hexController ourselves (because the
  // wheel or brightness slider moved), so the controller's own listener
  // doesn't try to re-parse the value it was just given.
  bool _updatingHexProgrammatically = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(hexToColor(widget.initialHex));
    _hexController = TextEditingController(text: _hexDigits(widget.initialHex));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _hexDigits(String hex) => hex.replaceFirst('#', '').toUpperCase();

  void _applyHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final hex = _hexDigits(_toHex(hsv.toColor()));
    _updatingHexProgrammatically = true;
    _hexController.value = TextEditingValue(
      text: hex,
      selection: TextSelection.collapsed(offset: hex.length),
    );
    _updatingHexProgrammatically = false;
    widget.onChanged('#$hex');
  }

  String _toHex(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    return '${r.toRadixString(16).padLeft(2, '0')}'
            '${g.toRadixString(16).padLeft(2, '0')}'
            '${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  void _handleWheelTouch(Offset localPosition) {
    const radius = _wheelSize / 2;
    var dx = localPosition.dx - radius;
    var dy = localPosition.dy - radius;
    var distance = math.sqrt(dx * dx + dy * dy);
    if (distance > radius) {
      final scale = radius / distance;
      dx *= scale;
      dy *= scale;
      distance = radius;
    }
    final hue = (math.atan2(dy, dx) * 180 / math.pi + 360) % 360;
    final saturation = (distance / radius).clamp(0.0, 1.0);
    _applyHsv(_hsv.withHue(hue).withSaturation(saturation));
  }

  void _handleHexInput(String raw) {
    if (_updatingHexProgrammatically) return;
    final cleaned = raw.trim().replaceFirst('#', '');
    if (cleaned.length != 6 || int.tryParse(cleaned, radix: 16) == null) {
      return; // Wait for a complete, valid hex before updating anything.
    }
    final color = hexToColor('#$cleaned');
    setState(() => _hsv = HSVColor.fromColor(color));
    widget.onChanged('#${cleaned.toUpperCase()}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: GestureDetector(
            onPanDown: (details) => _handleWheelTouch(details.localPosition),
            onPanUpdate: (details) => _handleWheelTouch(details.localPosition),
            child: SizedBox(
              width: _wheelSize,
              height: _wheelSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const CustomPaint(
                    size: Size(_wheelSize, _wheelSize),
                    painter: _ColorWheelPainter(),
                  ),
                  _buildThumb(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'BRIGHTNESS',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.gold,
            thumbColor: AppTheme.gold,
            inactiveTrackColor: AppTheme.surface,
          ),
          child: Slider(
            value: _hsv.value,
            onChanged: (v) => _applyHsv(_hsv.withValue(v)),
          ),
        ),
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.gold.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _hexController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                ],
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  prefixText: '#',
                  prefixStyle: TextStyle(color: AppTheme.textSecondary),
                  labelText: 'HEX CODE',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  counterText: '',
                ),
                onChanged: _handleHexInput,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThumb() {
    const radius = _wheelSize / 2;
    final angle = _hsv.hue * math.pi / 180;
    final distance = _hsv.saturation * radius;
    final dx = distance * math.cos(angle);
    final dy = distance * math.sin(angle);
    return Positioned(
      left: radius + dx - 9,
      top: radius + dy - 9,
      child: IgnorePointer(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hsv.toColor(),
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black45, blurRadius: 3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the static hue/saturation wheel: a full-circle [SweepGradient]
/// for hue (angle), overlaid with a white-to-transparent [RadialGradient]
/// so saturation reads as distance from center (white) to the edge
/// (fully saturated). Brightness isn't represented here — that's the
/// separate slider below the wheel, since a flat wheel alone can't
/// reach black/near-black colors regardless of hue or saturation.
class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final huePaint = Paint()
      ..shader = SweepGradient(
        colors: List.generate(
          361,
          (i) => HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor(),
        ),
      ).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Colors.white, Color(0x00FFFFFF)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, saturationPaint);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) => false;
}