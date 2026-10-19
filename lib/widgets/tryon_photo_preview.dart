import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/share_card.dart';
import 'tryon_camera_view.dart';

enum _Mode {
  /// Created, waiting for the picture to be decoded so it never pops in blank.
  hidden,

  /// The photo fills the camera area for a beat, like a screenshot.
  landing,

  /// Shrunk to a small thumbnail in the bottom-left corner.
  thumb,

  /// Enlarged into a card with the Share / Delete / close buttons.
  expanded,

  /// Sliding out of the screen.
  gone,
}

/// Screenshot-style preview shown right after an AR try-on photo is taken.
///
/// The photo appears full-size, then shrinks into a thumbnail in the bottom-
/// left corner. The thumbnail slides away on its own after a few seconds, can
/// be swiped away, or tapped to open a larger card with Share, Delete and a
/// close (X) button.
///
/// Place it with [Positioned.fill] over the camera area, and give it a
/// `ValueKey(photo.path)` so a new photo restarts the animation. It sizes
/// itself from the area it is given.
///
/// The photo is already in the gallery when this appears; dismissing the
/// preview leaves it there. Only [onDelete] removes it.
class TryOnPhotoPreview extends StatefulWidget {
  final TryOnPhoto photo;

  /// The watch's brand and name, for the optional details strip on the photo.
  final ShareCardText cardText;

  /// Opens the system share sheet for the photo. [withDetails] is true when
  /// the person left "Watch details" on, so the shared copy carries the strip.
  final Future<void> Function(bool withDetails) onShare;

  /// Deletes the photo. Return true if it is gone; on false the preview stays
  /// open (the caller is expected to explain what went wrong).
  final Future<bool> Function() onDelete;

  /// Called after the exit animation, when the preview can be removed.
  final VoidCallback onDismissed;

  const TryOnPhotoPreview({
    super.key,
    required this.photo,
    required this.cardText,
    required this.onShare,
    required this.onDelete,
    required this.onDismissed,
  });

  @override
  State<TryOnPhotoPreview> createState() => _TryOnPhotoPreviewState();
}

class _TryOnPhotoPreviewState extends State<TryOnPhotoPreview> {
  static const _thumbWidth = 88.0;
  static const _margin = 16.0;
  static const _barHeight = 48.0;
  static const _barGap = 14.0;
  static const _landingHold = Duration(milliseconds: 300);
  static const _autoDismiss = Duration(seconds: 5);
  static const _move = Duration(milliseconds: 380);
  static const _curve = Curves.easeInOutCubic;

  // Decoded at screen resolution rather than the camera's full size.
  late final ImageProvider _image =
      ResizeImage(FileImage(File(widget.photo.path)), width: 1080);

  _Mode _mode = _Mode.hidden;
  bool _showButtons = false;
  bool _busy = false;
  // "Watch details" strip: on by default, and only offered if the watch has a name.
  bool _withDetails = true;
  ui.Image? _logo; // the white logo on the strip; arrives a moment after the preview opens
  Timer? _autoTimer;
  Timer? _buttonsTimer;

  @override
  void initState() {
    super.initState();
    ShareCardLogo.load().then((img) {
      if (mounted && img != null) setState(() => _logo = img);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _buttonsTimer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    if (!mounted) return;
    try {
      await precacheImage(_image, context);
    } catch (_) {
      // Show what we can; the Image widget has its own error handling.
    }
    if (!mounted) return;
    setState(() => _mode = _Mode.landing);
    await Future<void>.delayed(_landingHold);
    if (!mounted || _mode != _Mode.landing) return;
    setState(() => _mode = _Mode.thumb);
    _autoTimer = Timer(_autoDismiss, () {
      if (mounted && _mode == _Mode.thumb) _dismiss();
    });
  }

  void _expand() {
    if (_mode != _Mode.thumb) return;
    _autoTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() => _mode = _Mode.expanded);
    // The buttons fade in once the card has mostly settled.
    _buttonsTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _mode == _Mode.expanded) {
        setState(() => _showButtons = true);
      }
    });
  }

  void _dismiss() {
    if (_mode == _Mode.gone) return;
    _autoTimer?.cancel();
    _buttonsTimer?.cancel();
    setState(() {
      _mode = _Mode.gone;
      _showButtons = false;
    });
    Future<void>.delayed(_move, () {
      if (mounted) widget.onDismissed();
    });
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onShare(_withDetails && !widget.cardText.isEmpty);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final deleted = await widget.onDelete();
    if (!mounted) return;
    setState(() => _busy = false);
    if (deleted) _dismiss();
  }

  // --- geometry -----------------------------------------------------------

  Rect _thumbRect(Size area) {
    final h = _thumbWidth * area.height / area.width;
    return Rect.fromLTWH(_margin, area.height - _margin - h, _thumbWidth, h);
  }

  /// The enlarged photo. Keeps the camera area's proportions and leaves room
  /// underneath for the button row.
  Rect _cardRect(Size area) {
    final aspect = area.height / area.width;
    final maxHeight = area.height - 2 * _margin - _barGap - _barHeight;
    var w = area.width * 0.78;
    var h = w * aspect;
    if (h > maxHeight) {
      h = maxHeight;
      w = h / aspect;
    }
    final total = h + _barGap + _barHeight;
    return Rect.fromLTWH(
      (area.width - w) / 2,
      (area.height - total) / 2,
      w,
      h,
    );
  }

  Rect _rectFor(Size area) {
    switch (_mode) {
      case _Mode.hidden:
      case _Mode.landing:
        return Offset.zero & area;
      case _Mode.thumb:
        return _thumbRect(area);
      case _Mode.expanded:
        return _cardRect(area);
      case _Mode.gone:
        return _thumbRect(area).shift(const Offset(-_thumbWidth - 32, 0));
    }
  }

  double get _radius => switch (_mode) {
        _Mode.hidden || _Mode.landing => 0,
        _Mode.expanded => 18,
        _Mode.thumb || _Mode.gone => 12,
      };

  // --- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final expanded = _mode == _Mode.expanded;
    return PopScope(
      // Back closes the card instead of leaving the AR screen.
      canPop: !expanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && expanded) _dismiss();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.biggest;
          final rect = _rectFor(area);
          final card = _cardRect(area);
          final visible = _mode != _Mode.hidden && _mode != _Mode.gone;
          return Stack(
            children: [
              // Dimmed backdrop behind the card; tapping it closes the preview.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !expanded,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _dismiss,
                    child: AnimatedOpacity(
                      opacity: expanded ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _move,
                curve: _curve,
                left: rect.left,
                top: rect.top,
                width: rect.width,
                height: rect.height,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: GestureDetector(
                    onTap: _mode == _Mode.thumb ? _expand : null,
                    onHorizontalDragEnd: _mode == _Mode.thumb
                        ? (d) {
                            if ((d.primaryVelocity ?? 0) < -200) _dismiss();
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: _move,
                      curve: _curve,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                                alpha: _mode == _Mode.landing ? 0 : 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      // Painted over the photo so it doesn't shrink it.
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        border: Border.all(
                          color: Colors.white.withValues(
                              alpha: _mode == _Mode.landing ? 0 : 1),
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: _image,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: Colors.black54,
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: Colors.white54),
                            ),
                          ),
                          // The same strip that goes onto the shared copy, so
                          // what you see here is what you share.
                          if (expanded && _withDetails)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: ShareCardPainter(widget.cardText,
                                      logo: _logo),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: card.left,
                top: card.bottom + _barGap,
                width: card.width,
                height: _barHeight,
                child: _fadeButtons(
                  Row(
                    children: [
                      Expanded(
                        child: _pill(
                          icon: Icons.ios_share,
                          label: 'Share',
                          filled: true,
                          onTap: _busy ? null : _share,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _pill(
                          icon: Icons.delete_outline,
                          label: 'Delete',
                          filled: false,
                          onTap: _busy ? null : _delete,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.cardText.isEmpty)
                Positioned(
                  left: card.left + 10,
                  top: card.top + 10,
                  height: 40,
                  child: _fadeButtons(
                    Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _busy
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                setState(() => _withDetails = !_withDetails);
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _withDetails
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Watch details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: card.right - 40 - 10,
                top: card.top + 10,
                width: 40,
                height: 40,
                child: _fadeButtons(
                  Tooltip(
                    message: 'Close',
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _busy ? null : _dismiss,
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fadeButtons(Widget child) {
    return IgnorePointer(
      ignoring: !_showButtons,
      child: AnimatedOpacity(
        opacity: _showButtons ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    final fg = filled ? Colors.black : Colors.white;
    return AnimatedOpacity(
      opacity: onTap == null ? 0.6 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: filled ? Colors.white : Colors.black.withValues(alpha: 0.5),
        shape: StadiumBorder(
          side: filled
              ? BorderSide.none
              : const BorderSide(color: Colors.white54),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
