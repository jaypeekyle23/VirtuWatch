import { ref } from 'vue'

// App-wide toasts: small confirmations and errors that appear in the corner of the
// screen, wherever the person is scrolled to and whichever page they are on, even
// after a redirect. Call showToast from anywhere; <ToastHost /> (mounted once in
// App.vue) draws them.
//
//   showToast('success', 'Watch deleted.')
//   showToast('error', 'Could not save.', { key: 'listing:abc' })
//
// A toast with a "key" replaces an earlier toast with the same key instead of
// stacking up, so flipping one switch back and forth shows only the latest result.

const DURATION_MS = { success: 4000, error: 7000 } // errors stay longer: they need reading
const MIN_RESUME_MS = 1000 // after hovering, a toast never vanishes in less than this
const MAX_TOASTS = 4

export const toasts = ref([])

let nextId = 1
// Dismiss timers live outside the reactive list. id -> { handle, startedAt, remaining }
const timers = new Map()

function startTimer(id, ms) {
  clearTimeout(timers.get(id)?.handle)
  timers.set(id, {
    handle: setTimeout(() => dismissToast(id), ms),
    startedAt: Date.now(),
    remaining: ms,
  })
}

export function dismissToast(id) {
  clearTimeout(timers.get(id)?.handle)
  timers.delete(id)
  toasts.value = toasts.value.filter((t) => t.id !== id)
}

// Hovering or focusing a toast holds it on screen, so it can be read in peace.
export function pauseToast(id) {
  const timer = timers.get(id)
  if (!timer?.handle) return
  clearTimeout(timer.handle)
  timer.handle = null
  timer.remaining = Math.max(timer.remaining - (Date.now() - timer.startedAt), MIN_RESUME_MS)
}

export function resumeToast(id) {
  const timer = timers.get(id)
  if (!timer || timer.handle) return
  startTimer(id, timer.remaining)
}

// kind: 'success' | 'error'
export function showToast(kind, text, { key = null } = {}) {
  // The same key, or the exact same message, refreshes the toast already showing.
  const existing = toasts.value.find((t) => (key ? t.key === key : !t.key && t.kind === kind && t.text === text))
  if (existing) {
    existing.kind = kind
    existing.text = text
    startTimer(existing.id, DURATION_MS[kind] ?? DURATION_MS.success)
    return existing.id
  }

  const id = nextId++
  toasts.value = [...toasts.value, { id, kind, text, key }]
  startTimer(id, DURATION_MS[kind] ?? DURATION_MS.success)

  // Never let them pile up: the oldest makes way.
  while (toasts.value.length > MAX_TOASTS) dismissToast(toasts.value[0].id)
  return id
}