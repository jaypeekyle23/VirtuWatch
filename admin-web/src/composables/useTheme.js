import { ref, computed } from 'vue'

// The look the user picked (Default, Dark or Light). It mirrors the mobile app's
// ThemeController: the choice applies right away, is remembered on this device
// (not in the user's account) and falls back to Default if nothing usable is saved.
//
// The look is applied as <html data-theme="default|dark|light">. All colors come
// from CSS variables keyed on that attribute (see style.css), so nothing else
// needs to react to a change.
//
// index.html runs a tiny copy of the "read and apply" step before the first paint,
// so there is no flash of the wrong look. Keep the two in step.

export const THEME_MODES = [
  { value: 'defaultMode', attr: 'default', label: 'Default', description: 'The original navy look' },
  { value: 'dark', attr: 'dark', label: 'Dark', description: 'A deeper, darker background' },
  { value: 'light', attr: 'light', label: 'Light', description: 'A lighter background' },
]

// Same key and values as the mobile app, so a saved choice means the same thing there.
const STORAGE_KEY = 'app_theme_mode'
const DEFAULT_MODE = 'defaultMode'

// Color of the browser's own bar on phones (the page background of each look).
const BROWSER_BAR = { default: '#0e1a2b', dark: '#070b12', light: '#f5f6f8' }

function isMode(value) {
  return THEME_MODES.some((m) => m.value === value)
}

function readSaved() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return isMode(saved) ? saved : DEFAULT_MODE
  } catch {
    return DEFAULT_MODE
  }
}

function apply(mode) {
  const attr = THEME_MODES.find((m) => m.value === mode).attr
  document.documentElement.setAttribute('data-theme', attr)
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', BROWSER_BAR[attr])
}

export const themeMode = ref(readSaved())

export const themeInfo = computed(() => THEME_MODES.find((m) => m.value === themeMode.value))

// The logo whose lettering reads on the current background.
export const logoSrc = computed(() => (themeMode.value === 'light' ? '/logo-light.png' : '/logo.png'))

// Switches the look right away, then saves it. If saving fails the look still
// applies for this session.
export function setThemeMode(mode) {
  if (!isMode(mode) || mode === themeMode.value) return
  themeMode.value = mode
  apply(mode)
  try {
    localStorage.setItem(STORAGE_KEY, mode)
  } catch {
    // Not saved, but the look is already applied.
  }
}

apply(themeMode.value)

// Keep other open tabs of the portal in step.
window.addEventListener('storage', (event) => {
  if (event.key !== STORAGE_KEY) return
  const next = isMode(event.newValue) ? event.newValue : DEFAULT_MODE
  themeMode.value = next
  apply(next)
})
