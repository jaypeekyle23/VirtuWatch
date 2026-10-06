import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The favorite / save heart for the watch detail app bar.
///
/// On tap it gives immediate feedback instead of waiting for Firestore to
/// confirm: a light haptic tap plus a quick scale animation. Saving "pops"
/// the heart (grows, overshoots, settles); un-saving gives a small shrink
/// and release. The filled / outline icon itself still follows [isSaved],
/// which comes from the user's live document, so the UI can never show a
/// state that differs from what's stored.
///
/// With the device's "remove animations" setting on, only the haptic runs.
class SaveHeartButton extends StatefulWidget {
  final bool isSaved;
  final VoidCallback onPressed;

  const SaveHeartButton({
    super.key,
    required this.isSaved,
    required this.onPressed,
  });

  @override
  State<SaveHeartButton> createState() => _SaveHeartButtonState();
}

class _SaveHeartButtonState extends State<SaveHeartButton>
    with SingleTickerProviderStateMixin {
  static final _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 1.35)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.35, end: 0.92)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.92, end: 1.0),
      weight: 30,
    ),
  ]);

  static final _shrink = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 1.0, end: 0.75),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween<double>(begin: 0.75, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 60,
    ),
  ]);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  bool _saving = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    final saving = !widget.isSaved;

    if (saving) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    if (!MediaQuery.of(context).disableAnimations) {
      setState(() => _saving = saving);
      _controller.forward(from: 0);
    }

    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _handleTap,
      icon: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: (_saving ? _pop : _shrink).evaluate(_controller),
          child: child,
        ),
        child: Icon(
          widget.isSaved ? Icons.favorite : Icons.favorite_border,
          color: widget.isSaved ? Colors.redAccent : null,
        ),
      ),
    );
  }
}