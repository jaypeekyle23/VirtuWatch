// AR fit: the measured strap-opening numbers that let the mobile app place a
// 3D watch model on the wrist. This is a JavaScript port of
// lib/utils/ar_readiness.dart. Keep the two in sync, because the app decides
// whether a watch appears in AR using the Dart version.
//
// A watch document looks like:
//   modelUrl:   'https://.../watch.glb'
//   has3DModel: true
//   arFit: { modelUrl, holeCx, holeHalfX, holeHalfY, scale? }
//
// arFit carries its own modelUrl. The numbers were measured from one specific
// model file. If a different file is attached later, the old numbers no longer
// describe it, so the watch drops out of AR until new numbers are entered.

// Sanity ranges (model units). Anything outside is treated as a typo.
export const AR_FIT_FIELDS = [
  { key: 'holeCx', label: 'Opening centre (holeCx)', hint: 'e.g. -0.057', min: -0.3, max: 0.3, required: true },
  { key: 'holeHalfX', label: 'Half-thickness (holeHalfX)', hint: 'e.g. 0.25', min: 0.1, max: 0.6, required: true },
  { key: 'holeHalfY', label: 'Half-width (holeHalfY)', hint: 'e.g. 0.435', min: 0.3, max: 0.6, required: true },
  { key: 'scale', label: 'Size multiplier (optional)', hint: 'blank = 1.0', min: 0.7, max: 1.3, required: false },
]

const LIMITS = Object.fromEntries(AR_FIT_FIELDS.map((f) => [f.key, f]))

function inRange(value, key) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null
  const { min, max } = LIMITS[key]
  return value < min || value > max ? null : value
}

// A usable http(s) link that is not a .gltf. A .gltf is usually JSON plus
// separate files, which a single-file upload cannot carry, so the app skips it.
export function isSupportedModelUrl(url) {
  if (typeof url !== 'string') return false
  let parsed
  try {
    parsed = new URL(url)
  } catch {
    return false
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') return false
  return !parsed.pathname.toLowerCase().endsWith('.gltf')
}

// The fit for a watch document, or null if the watch is not AR-ready.
// Never throws on malformed data.
export function parseArFit(watch) {
  if (!watch || watch.has3DModel !== true) return null
  if (!isSupportedModelUrl(watch.modelUrl)) return null

  const raw = watch.arFit
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null
  if (raw.modelUrl !== watch.modelUrl) return null

  const holeCx = inRange(raw.holeCx, 'holeCx')
  const holeHalfX = inRange(raw.holeHalfX, 'holeHalfX')
  const holeHalfY = inRange(raw.holeHalfY, 'holeHalfY')
  if (holeCx === null || holeHalfX === null || holeHalfY === null) return null

  // scale is optional. Missing means 1.0. Present but not a number means bad data.
  let scale = 1
  if (raw.scale != null) {
    if (typeof raw.scale !== 'number' || !Number.isFinite(raw.scale)) return null
    scale = Math.min(LIMITS.scale.max, Math.max(LIMITS.scale.min, raw.scale))
  }

  return { modelUrl: watch.modelUrl, holeCx, holeHalfX, holeHalfY, scale }
}

export function isArReady(watch) {
  return parseArFit(watch) !== null
}

// 'ready'        usable model and valid fit numbers
// 'needs-fit'    has a usable model, but no valid fit for it yet
// 'unsupported'  has a model the app cannot use (a .gltf)
// 'no-model'     no 3D model at all
export function arStatus(watch) {
  if (!watch || watch.has3DModel !== true) return 'no-model'
  if (!isSupportedModelUrl(watch.modelUrl)) return 'unsupported'
  return isArReady(watch) ? 'ready' : 'needs-fit'
}

// ---------- Form helpers ----------

// Text boxes hold strings. Turns a number into the text to show in one.
export function fitText(value) {
  return typeof value === 'number' && Number.isFinite(value) ? String(value) : ''
}

// The error message for one box, or null. Blank is only an error when required.
export function validateFitField(text, key, required) {
  const trimmed = String(text ?? '').trim()
  if (trimmed === '') return required ? 'Required' : null
  const value = Number(trimmed)
  if (!Number.isFinite(value)) return 'Enter a number'
  const { min, max } = LIMITS[key]
  if (value < min || value > max) return `Between ${min} and ${max}`
  return null
}

// Reads pasted JSON such as {"holeCx": -0.058, "holeHalfX": 0.226, "holeHalfY": 0.432}.
// An object wrapped in {"arFit": {...}} also works. Returns numbers, or null.
export function parseFitJson(text) {
  try {
    let decoded = JSON.parse(String(text).trim())
    if (decoded && typeof decoded === 'object' && decoded.arFit && typeof decoded.arFit === 'object') {
      decoded = decoded.arFit
    }
    if (decoded == null || typeof decoded !== 'object' || Array.isArray(decoded)) return null
    const number = (key) =>
      typeof decoded[key] === 'number' && Number.isFinite(decoded[key]) ? decoded[key] : null
    const holeCx = number('holeCx')
    const holeHalfX = number('holeHalfX')
    const holeHalfY = number('holeHalfY')
    if (holeCx === null || holeHalfX === null || holeHalfY === null) return null
    return { holeCx, holeHalfX, holeHalfY, scale: number('scale') }
  } catch {
    return null
  }
}
