/// Index positions within MediaPipe's 21-point hand landmark model.
/// Landmarks 1 (thumb CMC) and 17 (pinky MCP) sit at the base of the hand,
/// bracketing the wrist crease on either side.
///
/// Still used by [ArAnchorService] for live AR try-on tracking. The
/// camera-based wrist *measurement* feature that used to live alongside
/// this (via `WristDetectionService` and `ReferenceObject`, both removed)
/// was replaced by a screen-calibration-based approach — see
/// `ScreenCalibrationService` and `WristMeasurementScreen`.
class HandLandmarkIndex {
  static const int wrist = 0;
  static const int thumbCmc = 1;
  static const int pinkyMcp = 17;
}