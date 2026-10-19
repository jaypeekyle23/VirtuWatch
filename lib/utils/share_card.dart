import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The watch's brand and name as they appear on a share card. Never includes
/// the price. If the name already starts with the brand ("Seiko Presage" under
/// "SEIKO"), the repeated brand is dropped from the name line.
class ShareCardText {
  final String brand;
  final String name;

  const ShareCardText._(this.brand, this.name);

  factory ShareCardText.from(Map<String, dynamic>? data) {
    final brand = (data?['brand'] as String?)?.trim() ?? '';
    var name = (data?['name'] as String?)?.trim() ?? '';
    if (brand.isNotEmpty &&
        name.length > brand.length &&
        name.toLowerCase().startsWith(brand.toLowerCase())) {
      name = name.substring(brand.length).trim();
    }
    return ShareCardText._(brand, name);
  }

  bool get isEmpty => brand.isEmpty && name.isEmpty;
}

/// The white VirtuWatch logo shown on the card, loaded once and kept.
/// Null if it can't be loaded, in which case the card uses plain text instead.
class ShareCardLogo {
  static Future<ui.Image?>? _cache;

  static Future<ui.Image?> load() => _cache ??= _load();

  static Future<ui.Image?> _load() async {
    try {
      final data =
          await rootBundle.load('assets/images/branding/logo_white.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image; // shared for the life of the app: never disposed
    } catch (_) {
      return null;
    }
  }
}

/// Draws the slim details strip along the bottom edge of a photo: the brand in
/// small spaced capitals with the white VirtuWatch logo on the same row, and
/// the watch name below it across the full width. The name is made smaller
/// only as much as it needs to fit on one line; a very long name wraps onto a
/// second line at the smallest size. Everything is sized from the width, so the
/// strip looks the same on the in-app preview and on the shared image.
class ShareCardPainter extends CustomPainter {
  final ShareCardText text;
  final ui.Image? logo;

  const ShareCardPainter(this.text, {this.logo});

  static const _nameSize = 0.05; // of the photo's width: the size used when the name fits
  static const _nameMinSize = 0.03; // never smaller than this; wraps instead

  TextPainter _layout(String s, TextStyle style, double maxWidth,
      {int maxLines = 1}) {
    return TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '\u2026',
    )..layout(maxWidth: maxWidth);
  }

  TextPainter _fitName(String s, double w, double maxWidth) {
    TextStyle style(double fs) => TextStyle(
          color: Colors.white,
          fontSize: fs,
          fontWeight: FontWeight.w600,
          height: 1.1,
        );
    final size = w * _nameSize;
    final natural = TextPainter(
      text: TextSpan(text: s, style: style(size)),
      textDirection: TextDirection.ltr,
    )..layout();
    if (natural.width <= maxWidth) return _layout(s, style(size), maxWidth);
    // Text width grows in step with the font size, so scale it down to fit
    // (with a little room to spare), but not below the minimum.
    final fitted = size * maxWidth / natural.width * 0.97;
    final fs = fitted < w * _nameMinSize ? w * _nameMinSize : fitted;
    return _layout(s, style(fs), maxWidth, maxLines: fitted < w * _nameMinSize ? 2 : 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final pad = w * 0.055;
    final bottomPad = w * 0.045;
    final gap = w * 0.014;
    final maxWidth = w - 2 * pad;

    final name = text.name.isEmpty ? null : _fitName(text.name, w, maxWidth);
    final brand = text.brand.isEmpty
        ? null
        : _layout(
            text.brand.toUpperCase(),
            TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: w * 0.026,
              letterSpacing: w * 0.005,
              fontWeight: FontWeight.w500,
            ),
            maxWidth * 0.6,
          );

    // The logo on the right of the brand row; plain text if it didn't load.
    final logoImage = logo;
    final logoH = w * 0.07;
    final logoW = logoImage == null
        ? 0.0
        : logoH * logoImage.width / logoImage.height;
    final fallbackMark = logoImage != null
        ? null
        : _layout(
            'VIRTUWATCH',
            TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: w * 0.02,
              letterSpacing: w * 0.004,
              fontWeight: FontWeight.w500,
            ),
            maxWidth * 0.4,
          );

    final nameH = name?.height ?? 0.0;
    final rowH = logoImage != null
        ? logoH
        : [brand?.height ?? 0.0, fallbackMark?.height ?? 0.0]
            .reduce((a, b) => a > b ? a : b);
    final contentH = nameH + (name != null ? gap : 0) + rowH;
    final bandHeight = contentH + bottomPad + w * 0.07;

    // A soft fade into dark, so the text reads on any photo without a hard bar.
    final band = Rect.fromLTWH(0, h - bandHeight, w, bandHeight);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xB3000000)],
        ).createShader(band),
    );

    final nameTop = h - bottomPad - nameH;
    final rowTop = nameTop - (name != null ? gap : 0) - rowH;
    name?.paint(canvas, Offset(pad, nameTop));
    if (brand != null) {
      brand.paint(canvas, Offset(pad, rowTop + (rowH - brand.height) / 2));
    }
    if (logoImage != null) {
      canvas.drawImageRect(
        logoImage,
        Rect.fromLTWH(
            0, 0, logoImage.width.toDouble(), logoImage.height.toDouble()),
        Rect.fromLTWH(w - pad - logoW, rowTop + (rowH - logoH) / 2, logoW, logoH),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else if (fallbackMark != null) {
      fallbackMark.paint(canvas,
          Offset(w - pad - fallbackMark.width, rowTop + (rowH - fallbackMark.height) / 2));
    }
  }

  @override
  bool shouldRepaint(ShareCardPainter old) =>
      old.text.brand != text.brand ||
      old.text.name != text.name ||
      old.logo != logo;
}

/// Makes a copy of the photo at [photoPath] with the details strip on it and
/// returns the new file's path. The copy goes next to the original (the app's
/// photo cache, which is cleared out regularly); the original is untouched.
Future<String> buildShareCard({
  required String photoPath,
  required ShareCardText text,
}) async {
  final bytes = await File(photoPath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final photo = frame.image;
  codec.dispose();

  final size = Size(photo.width.toDouble(), photo.height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(photo, Offset.zero, Paint());
  final logo = await ShareCardLogo.load();
  ShareCardPainter(text, logo: logo).paint(canvas, size);
  final picture = recorder.endRecording();
  final result = await picture.toImage(photo.width, photo.height);
  final data = await result.toByteData(format: ui.ImageByteFormat.png);

  photo.dispose();
  picture.dispose();
  result.dispose();
  if (data == null) throw StateError('Could not encode the share card');

  final dir = File(photoPath).parent.path;
  final out = File(
      '$dir${Platform.pathSeparator}tryon_card_${DateTime.now().millisecondsSinceEpoch}.png');
  await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  return out.path;
}
