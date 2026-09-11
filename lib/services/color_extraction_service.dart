import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

/// Extracts dominant colors from a photo, filtering out the background
/// where possible.
///
/// Used by OutfitScanScreen to determine what colors someone is
/// wearing, feeding the "isolate the subject, then cluster its colors"
/// result into the recommendation engine's color-matching step.
///
/// Watch product photos previously went through this same pipeline to
/// suggest a primary color on the merchant add/edit forms, but that was
/// removed: a watch's case/bezel/band is usually reflective metal
/// (Silver/Gold/Rose Gold), and specular highlights make average-pixel
/// color unreliable for exactly those tones — the suggestion would
/// confidently pick the wrong one. Merchants now enter a watch's color
/// directly (fixed swatches, or a color wheel + hex field for anything
/// that doesn't match). This service is kept outfit-only.
class ColorExtractionService {
  // Created once and reused — ML Kit segmenters carry real model-loading
  // overhead, so recreating one per call would slow every single scan.
  //
  // Subject Segmentation (rather than Selfie Segmentation) is used
  // deliberately: the selfie model is tuned for close-up, video-call-style
  // framing and performs noticeably worse on distant full-body shots —
  // exactly the framing outfit photos tend to use. Subject Segmentation
  // is Google's general "prominent subject in a normal photo" model
  // instead. Tradeoff: it's Android-only, with no iOS support at all.
  final _segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(
      enableForegroundConfidenceMask: true,
      enableForegroundBitmap: false,
      enableMultipleSubjects: SubjectResultOptions(
        enableConfidenceMask: false,
        enableSubjectBitmap: false,
      ),
    ),
  );

  // Background pixels are flagged with this distinctive marker color
  // before palette analysis, then filtered back out of the results
  // below. Real clothing/skin materials essentially never produce pure
  // magenta, which is what makes it safe to use as a "this pixel was
  // masked out" signal.
  static const _backgroundMarker = Color(0xFFFF00FF);
  static const _backgroundThreshold = 0.5; // ML Kit confidence cutoff

  void dispose() {
    _segmenter.close();
  }

  /// Returns up to [maxColors] dominant colors with their approximate
  /// share of the image (background excluded where segmentation
  /// succeeds), sorted largest first.
  Future<List<({Color color, double percentage})>> extractDominantColors(
    File image, {
    int maxColors = 4,
  }) async {
    final palette = await _analyzeWithSegmentation(image) ??
        await _analyzeWithCenterCrop(image, maxColors: maxColors);

    // Drop any swatch that's really just our background marker leaking
    // through (e.g. if segmentation missed a sliver of edge pixels),
    // then re-normalize percentages against only the real swatches.
    final swatches = palette.paletteColors
        .where((s) => !_isBackgroundMarker(s.color))
        .toList()
      ..sort((a, b) => b.population.compareTo(a.population));
    final top = swatches.take(maxColors).toList();
    final totalPopulation =
        top.fold<int>(0, (sum, swatch) => sum + swatch.population);

    return top.map((swatch) {
      final percentage = totalPopulation == 0
          ? 0.0
          : (swatch.population / totalPopulation) * 100;
      return (color: swatch.color, percentage: percentage);
    }).toList();
  }

  /// Runs real subject segmentation (ML Kit) and returns a palette built
  /// only from foreground pixels. Returns null if segmentation itself
  /// fails for any reason (model not ready, platform issue, etc.) so the
  /// caller can fall back to the simpler center-crop heuristic instead of
  /// failing the whole extraction.
  Future<PaletteGenerator?> _analyzeWithSegmentation(File image) async {
    List<double>? confidences;
    try {
      final inputImage = InputImage.fromFilePath(image.path);
      final result = await _segmenter.processImage(inputImage);
      confidences = result.foregroundConfidenceMask;
    } catch (_) {
      return null;
    }
    if (confidences == null) return null;

    final bytes = await image.readAsBytes();
    final originalCodec = await ui.instantiateImageCodec(bytes);
    final originalFrame = await originalCodec.getNextFrame();
    final originalWidth = originalFrame.image.width;
    final originalHeight = originalFrame.image.height;
    originalFrame.image.dispose();

    // The foreground confidence mask is the same resolution as the input
    // image, so it maps 1:1 onto originalWidth/originalHeight — no
    // separate mask dimensions to track, unlike Selfie Segmentation's
    // mask object.
    if (confidences.length != originalWidth * originalHeight) return null;

    // Downscale to a small working copy — keeps the per-pixel masking
    // loop below fast regardless of the original photo's resolution.
    const maxDimension = 400;
    final longest =
        originalWidth > originalHeight ? originalWidth : originalHeight;
    final scale = maxDimension / longest;
    final targetWidth = (originalWidth * scale).round();
    final targetHeight = (originalHeight * scale).round();

    final smallCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final smallFrame = await smallCodec.getNextFrame();
    final rgba =
        await smallFrame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    smallFrame.image.dispose();
    if (rgba == null) return null;

    final buffer = Uint8List.fromList(rgba.buffer.asUint8List());
    for (var y = 0; y < targetHeight; y++) {
      final origY =
          (y * originalHeight / targetHeight).floor().clamp(0, originalHeight - 1);
      for (var x = 0; x < targetWidth; x++) {
        final origX =
            (x * originalWidth / targetWidth).floor().clamp(0, originalWidth - 1);
        final confidence = confidences[origY * originalWidth + origX];
        if (confidence < _backgroundThreshold) {
          final i = (y * targetWidth + x) * 4;
          buffer[i] = 255; // R
          buffer[i + 1] = 0; // G
          buffer[i + 2] = 255; // B
          buffer[i + 3] = 255; // A
        }
      }
    }

    return PaletteGenerator.fromByteData(
      EncodedImage(
        buffer.buffer.asByteData(),
        width: targetWidth,
        height: targetHeight,
      ),
      maximumColorCount: 8, // extra headroom since a few get filtered out
    );
  }

  /// Fallback used only if segmentation fails outright: restricts
  /// analysis to a center-weighted region, trimming the outer edges
  /// where background (pavement, a plain backdrop, table surface, etc.)
  /// typically shows.
  Future<PaletteGenerator> _analyzeWithCenterCrop(
    File image, {
    required int maxColors,
  }) async {
    final bytes = await image.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width.toDouble();
    final height = frame.image.height.toDouble();
    frame.image.dispose();

    final region = Rect.fromLTWH(
      width * 0.15,
      height * 0.05,
      width * 0.70,
      height * 0.90,
    );

    return PaletteGenerator.fromImageProvider(
      FileImage(image),
      size: Size(width, height),
      region: region,
      maximumColorCount: maxColors,
    );
  }

  bool _isBackgroundMarker(Color color) {
    final dr = (color.r * 255) - _backgroundMarker.r * 255;
    final dg = (color.g * 255) - _backgroundMarker.g * 255;
    final db = (color.b * 255) - _backgroundMarker.b * 255;
    final distanceSquared = dr * dr + dg * dg + db * db;
    return distanceSquared < 40 * 40; // small tolerance for compression noise
  }
}

/// Converts a [Color] to a '#RRGGBB' hex string.
String colorToHex(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#'
          '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}