/// Whether a watch can be shown in AR try-on, and the per-model fit numbers
/// the renderer needs to place it on the wrist.
///
/// This is the ONE definition of "AR-ready". The AR carousel, the Try On
/// buttons, the catalog's "AR only" filter and the merchant dashboards all
/// call [isArReady] so they can never disagree.
///
/// A watch document looks like:
///
///   modelUrl:    "https://.../watch.glb"
///   has3DModel:  true
///   arFit: {
///     modelUrl:   "https://.../watch.glb",   // must equal modelUrl above
///     holeCx:     -0.057,   // strap-opening centre, model units
///     holeHalfX:   0.25,    // opening half-thickness, model units
///     holeHalfY:   0.435,   // opening half-width, model units
///     scale:       1.0,     // optional size multiplier (clamped)
///   }
///
/// Why arFit carries its own modelUrl: the fit numbers were measured from one
/// specific model file. If a merchant later uploads a different file, the old
/// numbers no longer describe it, so the watch drops out of AR until new
/// numbers are entered for the new file. No cleanup code is needed.
library;

/// Sanity ranges (model units). Measured models sit well inside these
/// (holeCx -0.058..-0.010, halfX 0.226..0.338, halfY 0.422..0.438); anything
/// outside is treated as a typo, not clamped, because a silently "corrected"
/// hole size would render a wrong-looking watch.
const double _cxMin = -0.3, _cxMax = 0.3;
const double _halfXMin = 0.1, _halfXMax = 0.6;
const double _halfYMin = 0.3, _halfYMax = 0.6;

/// Optional per-watch size multiplier. Out-of-range values are clamped.
const double arScaleMin = 0.7;
const double arScaleMax = 1.3;

class ArFit {
  final String modelUrl;
  final double holeCx;
  final double holeHalfX;
  final double holeHalfY;
  final double scale;

  const ArFit({
    required this.modelUrl,
    required this.holeCx,
    required this.holeHalfX,
    required this.holeHalfY,
    this.scale = 1.0,
  });

  /// Returns the fit for [watchData], or null if the watch is not AR-ready.
  /// Never throws on malformed data (this runs on every Firestore snapshot).
  static ArFit? tryParse(Map<String, dynamic> watchData) {
    if (watchData['has3DModel'] != true) return null;

    final modelUrl = watchData['modelUrl'];
    if (modelUrl is! String || !_isGlbUrl(modelUrl)) return null;

    final raw = watchData['arFit'];
    if (raw is! Map) return null;

    // The fit must have been measured for the model that is attached now.
    if (raw['modelUrl'] != modelUrl) return null;

    final cx = _num(raw['holeCx'], _cxMin, _cxMax);
    final halfX = _num(raw['holeHalfX'], _halfXMin, _halfXMax);
    final halfY = _num(raw['holeHalfY'], _halfYMin, _halfYMax);
    if (cx == null || halfX == null || halfY == null) return null;

    // scale is optional: missing means 1.0. Present-but-not-a-number is
    // malformed data, so the watch is not AR-ready.
    var scale = 1.0;
    final rawScale = raw['scale'];
    if (rawScale != null) {
      if (rawScale is! num || !rawScale.isFinite) return null;
      scale = rawScale.toDouble().clamp(arScaleMin, arScaleMax).toDouble();
    }

    return ArFit(
      modelUrl: modelUrl,
      holeCx: cx,
      holeHalfX: halfX,
      holeHalfY: halfY,
      scale: scale,
    );
  }

  /// Plain map for the native renderer's method channel.
  Map<String, double> toChannelMap() => {
        'holeCx': holeCx,
        'holeHalfX': holeHalfX,
        'holeHalfY': holeHalfY,
        'scale': scale,
      };
}

/// True when [watchData] has a usable .glb AND valid fit numbers for it.
bool isArReady(Map<String, dynamic> watchData) =>
    ArFit.tryParse(watchData) != null;

/// Only .glb is supported: a .gltf is usually JSON plus separate .bin/texture
/// files, which a single-file upload cannot carry. Checks the URL's path so a
/// query string (?v=...) doesn't hide the extension.
bool _isGlbUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  return uri.path.toLowerCase().endsWith('.glb');
}

double? _num(Object? v, double min, double max) {
  if (v is! num || !v.isFinite) return null;
  final d = v.toDouble();
  return (d < min || d > max) ? null : d;
}
