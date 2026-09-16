import 'dart:math' as math;

import 'package:hand_landmarker/hand_landmarker.dart';

import 'wrist_detection_service.dart' show HandLandmarkIndex;

/// Where and how to draw the 3D watch model for the current frame, in
/// normalized screen space (0..1) plus rotation/scale.
///
/// This is the piece that actually makes it "AR" rather than a static
/// sticker: every value here is recomputed from the live hand landmarks,
/// so the watch follows the wrist as it moves instead of sitting at a
/// fixed spot on screen.
class ArAnchor {
  /// Normalized (0..1) position of the watch's center, in the same
  /// coordinate space CameraPreview/hand_landmarker use (origin top-left).
  final double x;
  final double y;

  /// In-plane rotation, radians, so the watch band aligns with the
  /// wrist's actual orientation in frame instead of always sitting
  /// upright.
  final double rotationRadians;

  /// Multiplier applied to the model's authored scale. Derived from the
  /// physical case-diameter-to-wrist-width ratio (both in mm), applied
  /// against however large the wrist bones currently appear on screen —
  /// so it stays correctly proportioned as the hand moves closer/farther
  /// from the camera, without needing a fresh calibration every frame.
  final double scale;

  const ArAnchor({
    required this.x,
    required this.y,
    required this.rotationRadians,
    required this.scale,
  });
}

class ArAnchorService {
  /// Smooths anchor values across frames — raw per-frame landmarks jitter
  /// visibly even when the hand is nearly still, since hand_landmarker
  /// re-detects independently on every frame with no built-in tracking
  /// continuity. Exponential smoothing trades a little lag for a much
  /// steadier-looking overlay. 0 = no smoothing (raw), 1 = frozen.
  static const double _smoothing = 0.6;

  ArAnchor? _previous;

  /// Computes this frame's anchor from [hand]'s landmarks.
  ///
  /// [caseDiameterMm] is the selected watch's real case size (Firestore
  /// field `caseDiameterMm`); [wristWidthMm] is the user's saved
  /// measurement (`wristWidthMm`, from screen calibration or manual
  /// entry). If either is missing, [fallbackScale] is used instead so the
  /// watch still renders at a reasonable size rather than not at all.
  ArAnchor? computeAnchor({
    required Hand hand,
    double? caseDiameterMm,
    double? wristWidthMm,
    double fallbackScale = 1.0,
  }) {
    if (hand.landmarks.length <= HandLandmarkIndex.pinkyMcp) return null;

    final thumb = hand.landmarks[HandLandmarkIndex.thumbCmc];
    final pinky = hand.landmarks[HandLandmarkIndex.pinkyMcp];

    // Anchor point: midpoint between the two wrist-bone landmarks — this
    // is roughly where a watch case sits once actually worn, rather than
    // the wrist-crease landmark itself (index 0), which sits a bit
    // further down the arm.
    final anchorX = (thumb.x + pinky.x) / 2;
    final anchorY = (thumb.y + pinky.y) / 2;

    // In-plane rotation: align to the vector between the two bone
    // landmarks, so turning your wrist turns the watch face with it.
    final rotation = math.atan2(pinky.y - thumb.y, pinky.x - thumb.x);

    // On-screen span between the two wrist-bone landmarks, in the same
    // normalized units as x/y above — this is our per-frame "ruler" for
    // how large the wrist currently appears.
    final wristSpanOnScreen = math.sqrt(
      math.pow(thumb.x - pinky.x, 2) + math.pow(thumb.y - pinky.y, 2),
    );

    double scale;
    if (caseDiameterMm != null && wristWidthMm != null && wristWidthMm > 0) {
      // Physical ratio (unitless) times how big the wrist looks right
      // now — no depth/mm-per-pixel bookkeeping needed per frame, since
      // this ratio alone keeps the watch's apparent size consistent with
      // its real-world size relative to this specific wrist.
      final caseToWristRatio = caseDiameterMm / wristWidthMm;
      scale = wristSpanOnScreen * caseToWristRatio;
    } else {
      scale = wristSpanOnScreen * fallbackScale;
    }

    final raw = ArAnchor(
      x: anchorX,
      y: anchorY,
      rotationRadians: rotation,
      scale: scale,
    );

    final smoothed = _previous == null
        ? raw
        : ArAnchor(
            x: _lerp(_previous!.x, raw.x),
            y: _lerp(_previous!.y, raw.y),
            rotationRadians: _lerpAngle(_previous!.rotationRadians, raw.rotationRadians),
            scale: _lerp(_previous!.scale, raw.scale),
          );

    _previous = smoothed;
    return smoothed;
  }

  /// Call when the hand drops out of frame, so the next detection starts
  /// fresh instead of smoothing from a stale position.
  void reset() => _previous = null;

  double _lerp(double from, double to) => from + (to - from) * (1 - _smoothing);

  double _lerpAngle(double from, double to) {
    // Shortest-path angle interpolation so the watch doesn't spin the
    // long way around when the angle wraps past +-pi.
    var diff = to - from;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    return from + diff * (1 - _smoothing);
  }
}