// Tests for lib/utils/ar_readiness.dart — the single rule deciding whether a
// watch can appear in AR try-on. Plain maps, no Firebase needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:virtuwatch/utils/ar_readiness.dart';

const _url = 'https://res.cloudinary.com/demo/raw/upload/v1700000000/seiko.glb';

Map<String, dynamic> _watch({
  Object? has3DModel = true,
  Object? modelUrl = _url,
  Object? arFit = const _Default(),
}) {
  return {
    'has3DModel': has3DModel,
    'modelUrl': modelUrl,
    if (arFit is _Default)
      'arFit': {
        'modelUrl': _url,
        'holeCx': -0.057,
        'holeHalfX': 0.25,
        'holeHalfY': 0.435,
      }
    else if (arFit != null)
      'arFit': arFit,
  };
}

class _Default {
  const _Default();
}

Map<String, dynamic> _fit({
  Object? modelUrl = _url,
  Object? cx = -0.057,
  Object? halfX = 0.25,
  Object? halfY = 0.435,
  Object? scale,
}) =>
    {
      'modelUrl': modelUrl,
      'holeCx': cx,
      'holeHalfX': halfX,
      'holeHalfY': halfY,
      if (scale != null) 'scale': scale,
    };

void main() {
  group('isArReady', () {
    test('true for a .glb with valid fit for that model', () {
      expect(isArReady(_watch()), isTrue);
    });

    test('false when has3DModel is not true', () {
      expect(isArReady(_watch(has3DModel: false)), isFalse);
      expect(isArReady(_watch(has3DModel: null)), isFalse);
    });

    test('false when there is no model url', () {
      expect(isArReady(_watch(modelUrl: '')), isFalse);
      expect(isArReady(_watch(modelUrl: null)), isFalse);
    });

    test('false for .gltf (single-file upload cannot carry its parts)', () {
      const gltf = 'https://res.cloudinary.com/demo/raw/upload/v1/watch.gltf';
      expect(
        isArReady(_watch(modelUrl: gltf, arFit: _fit(modelUrl: gltf))),
        isFalse,
      );
    });

    test('.glb is detected despite a query string or upper-case extension', () {
      const q = 'https://example.com/m/WATCH.GLB?v=3';
      expect(isArReady(_watch(modelUrl: q, arFit: _fit(modelUrl: q))), isTrue);
    });

    test('false when arFit is missing or not a map', () {
      expect(isArReady(_watch(arFit: null)), isFalse);
      expect(isArReady(_watch(arFit: 'nope')), isFalse);
    });

    test('false when the fit was measured for a different model file', () {
      // Merchant replaced the model: old numbers must not apply to it.
      expect(
        isArReady(_watch(arFit: _fit(modelUrl: 'https://example.com/old.glb'))),
        isFalse,
      );
    });

    test('false when a fit number is missing, non-numeric or non-finite', () {
      expect(isArReady(_watch(arFit: _fit(cx: null))), isFalse);
      expect(isArReady(_watch(arFit: _fit(halfX: '0.25'))), isFalse);
      expect(isArReady(_watch(arFit: _fit(halfY: double.nan))), isFalse);
    });

    test('false when a fit number is outside the sane range (typo guard)', () {
      expect(isArReady(_watch(arFit: _fit(halfY: 4.35))), isFalse);
      expect(isArReady(_watch(arFit: _fit(halfX: 0.0))), isFalse);
      expect(isArReady(_watch(arFit: _fit(cx: 5))), isFalse);
    });

    test('accepts ints from Firestore (e.g. holeCx: 0)', () {
      expect(isArReady(_watch(arFit: _fit(cx: 0))), isTrue);
    });

    test('accepts every measured model from the Tripo table', () {
      const rows = [
        [-0.058, 0.226, 0.432],
        [-0.036, 0.244, 0.424],
        [-0.050, 0.282, 0.436],
        [-0.050, 0.282, 0.428],
        [-0.058, 0.238, 0.438],
        [-0.010, 0.338, 0.422],
        [-0.022, 0.302, 0.422],
      ];
      for (final r in rows) {
        expect(
          isArReady(_watch(arFit: _fit(cx: r[0], halfX: r[1], halfY: r[2]))),
          isTrue,
          reason: 'row $r',
        );
      }
    });
  });

  group('ArFit.tryParse scale', () {
    test('defaults to 1.0 when absent', () {
      expect(ArFit.tryParse(_watch())!.scale, 1.0);
    });

    test('is used when present', () {
      expect(ArFit.tryParse(_watch(arFit: _fit(scale: 1.1)))!.scale, 1.1);
    });

    test('is clamped, not rejected, when out of range', () {
      expect(ArFit.tryParse(_watch(arFit: _fit(scale: 5)))!.scale, arScaleMax);
      expect(ArFit.tryParse(_watch(arFit: _fit(scale: 0.1)))!.scale, arScaleMin);
    });

    test('present but not a number makes the watch not AR-ready', () {
      expect(ArFit.tryParse(_watch(arFit: _fit(scale: 'big'))), isNull);
    });

    test('toChannelMap carries exactly what the renderer needs', () {
      final m = ArFit.tryParse(_watch(arFit: _fit(scale: 1.1)))!.toChannelMap();
      expect(m, {
        'holeCx': -0.057,
        'holeHalfX': 0.25,
        'holeHalfY': 0.435,
        'scale': 1.1,
      });
    });
  });
}
