import 'dart:math' as math;

import 'package:hand_landmarker/hand_landmarker.dart';

/// Known real-world widths (in millimeters) of the reference objects a user
/// can choose from during camera-based wrist measurement.
///
/// Sources:
/// - ID Card / Credit Card: ISO/IEC 7810 ID-1 standard width (85.6mm).
/// - 1-Peso / 5-Peso Coin: Bangko Sentral ng Pilipinas (BSP) New Generation
///   Currency coin series diameters.
class ReferenceObject {
  static const Map<String, double> widthMm = {
    'ID Card': 85.6,
    'Credit Card': 85.6,
    '1-Peso Coin': 24.0,
    '5-Peso Coin': 25.0,
  };

  /// Width-to-height ratio used to draw the on-screen alignment guide.
  /// Coins use 1:1 (circle); cards use the ISO ID-1 ratio.
  static double aspectRatioFor(String option) {
    if (option.contains('Coin')) return 1.0;
    return 85.6 / 53.98;
  }
}

/// Index positions within MediaPipe's 21-point hand landmark model.
/// Landmarks 1 (thumb CMC) and 17 (pinky MCP) sit at the base of the hand,
/// bracketing the wrist crease on either side.
class HandLandmarkIndex {
  static const int wrist = 0;
  static const int thumbCmc = 1;
  static const int pinkyMcp = 17;
}

class WristDetectionResult {
  final double wristWidthMm;
  const WristDetectionResult(this.wristWidthMm);
}

/// Estimates wrist width from a single detected [Hand].
///
/// LIMITATIONS (documented here for transparency in the capstone writeup):
/// - This approximates wrist width as the pixel distance between the
///   thumb-CMC and pinky-MCP landmarks, rather than a true perpendicular
///   silhouette/edge measurement. It's a common approximation in AR sizing
///   tools, but is less precise than segmentation-based edge detection.
/// - It assumes the wrist and the reference object are roughly the same
///   distance from the camera (same focal plane). Accuracy degrades if one
///   is noticeably closer to the lens than the other.
class WristDetectionService {
  static const double minPlausibleMm = 30;
  static const double maxPlausibleMm = 120;

  /// [imageWidth]/[imageHeight] are the camera sensor frame dimensions in
  /// pixels, used to convert hand_landmarker's normalized (0..1) landmark
  /// coordinates into pixel space. [mmPerPixel] comes from the reference
  /// object calibration (see [ReferenceObject]).
  static WristDetectionResult? estimate({
    required Hand hand,
    required int imageWidth,
    required int imageHeight,
    required double mmPerPixel,
  }) {
    if (hand.landmarks.length <= HandLandmarkIndex.pinkyMcp) return null;

    final thumb = hand.landmarks[HandLandmarkIndex.thumbCmc];
    final pinky = hand.landmarks[HandLandmarkIndex.pinkyMcp];

    final dx = (thumb.x - pinky.x) * imageWidth;
    final dy = (thumb.y - pinky.y) * imageHeight;
    final widthPx = math.sqrt(dx * dx + dy * dy);

    final widthMm = widthPx * mmPerPixel;
    if (widthMm < minPlausibleMm || widthMm > maxPlausibleMm) return null;

    return WristDetectionResult(widthMm);
  }
}