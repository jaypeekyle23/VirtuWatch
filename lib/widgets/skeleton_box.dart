import 'package:flutter/material.dart';

/// A single shimmering placeholder block, the building piece for
/// skeleton-loading UI that mimics the shape of real content while
/// it's still being fetched (e.g. the "Recommended for You" cards on
/// the home tab, before [RecommendationService] returns).
///
/// Hand-rolled with a looping [AnimationController] instead of pulling
/// in the `shimmer` package, so this doesn't add a new dependency to
/// track and version-pin.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  // Slightly lighter than AppTheme.surface (0xFF16263D), so the
  // skeleton reads clearly against both the surface cards and the
  // page background without importing AppTheme's exact palette here.
  static const _base = Color(0xFF223A5C);
  static const _highlight = Color(0xFF35547E);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Sweeps a soft highlight band left to right on a loop. The
          // -1.5..1.5 range (wider than the -1..1 gradient itself)
          // gives the band room to fully enter and exit each pass.
          final slide = _controller.value * 3 - 1.5;
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: const [_base, _highlight, _base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment(-1 + slide, 0),
              end: Alignment(1 + slide, 0),
            ).createShader(bounds),
            // A plain solid rect — ShaderMask paints the sweeping
            // gradient onto its shape via srcIn.
            child: Container(
              width: widget.width,
              height: widget.height,
              color: Colors.white,
            ),
          );
        },
      ),
    );
  }
}