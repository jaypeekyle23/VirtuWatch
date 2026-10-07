import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'skeleton_box.dart';

/// A watch / product photo loaded from a URL: shimmering [SkeletonBox] while
/// it downloads, a quick cross-fade into the photo when it's ready, and the
/// error widget if it fails. Fills the space it's given.
///
/// Photos Flutter already has in memory (e.g. scrolling back to a card, or
/// the detail screen after tapping a card) appear instantly with no fade.
class NetworkPhoto extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget? errorWidget;

  const NetworkPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.errorWidget,
  });

  /// Ask Cloudinary for a resized copy of each photo (see [_optimized])
  /// instead of the full-size original. Off by default: it's untested
  /// against the live account, and the first request for each resized copy
  /// can be slower while Cloudinary generates it. Turn it on, fully restart
  /// and open the same screens twice to see whether it helps.
  static const bool _resizeOnServer = false;

  static const int _maxWidth = 1000;

  /// Adds a Cloudinary transformation to a plain versioned upload URL so it
  /// comes back no wider than [_maxWidth] (`c_limit` never upscales) with
  /// automatic quality. Any other URL is returned unchanged.
  static String _optimized(String url) {
    if (!_resizeOnServer) return url;

    const marker = '/image/upload/';
    final i = url.indexOf(marker);
    if (i == -1 || !url.contains('res.cloudinary.com')) return url;

    final rest = url.substring(i + marker.length);
    // A version segment (v123456/) right after "upload/" means no
    // transformation has been applied yet.
    if (!RegExp(r'^v\d+/').hasMatch(rest)) return url;

    return '${url.substring(0, i + marker.length)}'
        'c_limit,w_$_maxWidth,q_auto/$rest';
  }

  /// Image provider for avatars (`CircleAvatar.backgroundImage` etc.), so
  /// they follow the same URL handling as [NetworkPhoto].
  static ImageProvider provider(String url) => NetworkImage(_optimized(url));

  static const Widget _skeleton = SkeletonBox(
    width: double.infinity,
    height: double.infinity,
    borderRadius: BorderRadius.zero,
  );

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _optimized(url),
      fit: fit,
      // `frame` stays null until the first decoded frame is ready, so the
      // skeleton covers the whole wait (download + decode) with no blank
      // flash in between, then cross-fades into the photo.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          // Fill the box (the default layout would loosen the constraints
          // and let the photo shrink to its own size).
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, ?current],),
          child: frame == null
              ? const KeyedSubtree(key: ValueKey('loading'), child: _skeleton)
              : KeyedSubtree(key: const ValueKey('photo'), child: child),
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          errorWidget ??
          const Center(child: Icon(Icons.watch, color: AppTheme.gold)),
    );
  }
}