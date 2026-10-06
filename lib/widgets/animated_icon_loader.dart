import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How [AnimatedIconLoader] moves its icon.
enum IconLoaderMotion {
  /// Icon sweeps in a slow figure-eight with a slight zoom pulse, like a
  /// magnifying glass inspecting something.
  sweep,

  /// Icon stays put and "breathes" while soft gold rings expand out from it
  /// and fade, like a signal being sent.
  pulse,

  /// Like [pulse], but the icon also floats up and down with a slight tilt,
  /// as if it's waiting for something to arrive (e.g. an email).
  bob,
}

/// A gold icon with a looping animation and an optional label underneath —
/// used in place of a bare spinner on full-screen waits (outfit scan
/// analyzing and camera startup, verify-email waiting, etc.).
///
/// One icon, one looping controller, so it's cheap. With the device's
/// "remove animations" setting on, the icon is shown still.
class AnimatedIconLoader extends StatefulWidget {
  final IconData icon;
  final String? label;
  final IconLoaderMotion motion;
  final double iconSize;

  const AnimatedIconLoader({
    super.key,
    required this.icon,
    this.label,
    this.motion = IconLoaderMotion.sweep,
    this.iconSize = 56,
  });

  @override
  State<AnimatedIconLoader> createState() => _AnimatedIconLoaderState();
}

class _AnimatedIconLoaderState extends State<AnimatedIconLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.motion == IconLoaderMotion.sweep ? 2400 : 2000,
      ),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _ring(double progress) {
    return Opacity(
      opacity: (1 - progress) * 0.6,
      child: Transform.scale(
        scale: 0.7 + 0.9 * progress,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.gold, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _animated(BuildContext context, Widget? icon) {
    final t = _controller.value;
    final angle = t * 2 * math.pi;

    if (widget.motion == IconLoaderMotion.sweep) {
      return Transform.translate(
        // Figure-eight: wide side to side, short up and down at double speed.
        offset: Offset(math.cos(angle) * 16, math.sin(2 * angle) * 7),
        child: Transform.scale(
          scale: 1 + 0.08 * math.sin(angle),
          child: icon,
        ),
      );
    }

    final isBob = widget.motion == IconLoaderMotion.bob;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        _ring(t),
        _ring((t + 0.5) % 1.0),
        if (isBob)
          Transform.translate(
            offset: Offset(0, math.sin(angle) * 4),
            child: Transform.rotate(angle: math.sin(angle) * 0.06, child: icon),
          )
        else
          Transform.scale(scale: 1 + 0.06 * math.sin(angle), child: icon),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final icon = Icon(widget.icon, size: widget.iconSize, color: AppTheme.gold);
    final isSweep = widget.motion == IconLoaderMotion.sweep;
    final isBob = widget.motion == IconLoaderMotion.bob;
    // The rings may spill past this box (they fade out as they grow), so the
    // box only needs to fit the icon itself in the bob case.
    final boxWidth = isSweep ? 96.0 : (isBob ? 72.0 : 120.0);
    final boxHeight = isSweep ? 72.0 : (isBob ? 72.0 : 120.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: boxWidth,
          height: boxHeight,
          child: Center(
            child: reduceMotion
                ? icon
                : AnimatedBuilder(
                    animation: _controller,
                    builder: _animated,
                    child: icon,
                  ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 12),
          Text(widget.label!, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}