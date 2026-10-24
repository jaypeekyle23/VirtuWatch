import { nextTick } from 'vue'
import { heroWatchId } from '../composables/useHeroTransition'
import { allowSeed, isWatchKnown } from '../utils/snapshotCache'

// Wraps the navigation between a watch list and a watch detail page in a browser
// View Transition, so the clicked photo glides from one page to the other.
//
// How it fits together:
//  1. Before the page changes, the photo of the watch involved gets its
//     transition name (heroWatchId), and the browser takes a "before" picture.
//  2. The router then swaps the page. The new page draws itself instantly from
//     remembered data (utils/snapshotCache), so its photo is already there.
//  3. Once that new page is on screen, the browser takes the "after" picture
//     and animates the named photo from one place to the other.
// Browsers without View Transitions, and people who prefer reduced motion,
// just get a normal page change.

const DETAIL_ROUTES = ['admin-watch-detail', 'merchant-watch-detail']
const IMAGE_WAIT_MS = 300

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')

// { direction: 'open' | 'back', id } while a hero transition is in progress.
let pending = null
let finishUpdate = null

function heroTarget(to, from) {
  const opening = DETAIL_ROUTES.includes(to.name) && from.name && !DETAIL_ROUTES.includes(from.name)
  if (opening && isWatchKnown(to.params.id)) return { direction: 'open', id: to.params.id }

  // Pages marked heroList in the router are the ones that show watch photos.
  const closing = DETAIL_ROUTES.includes(from.name) && to.meta.heroList
  if (closing && isWatchKnown(from.params.id)) return { direction: 'back', id: from.params.id }

  return null
}

// Gives the photos a moment to finish decoding, so the "after" picture isn't blank.
async function photosReady() {
  const images = document.querySelectorAll('img[data-hero], [data-hero] img')
  const decoded = Array.from(images, (img) => img.decode().catch(() => {}))
  const timeout = new Promise((resolve) => setTimeout(resolve, IMAGE_WAIT_MS))
  await Promise.race([Promise.all(decoded), timeout])
  // One more turn of the event loop, so the router's own scrolling has run first.
  await new Promise((resolve) => setTimeout(resolve))
}

// Used by the router's scrollBehavior. When going back to a list, bring the
// watch's card into view, so the photo has somewhere visible to land.
// Returns a scroll position, false (don't scroll), or null (not a hero trip).
export function scrollForHero() {
  if (pending?.direction !== 'back') return null
  const card = document.querySelector('[data-hero]')
  if (!card) return null

  const margin = 96
  const rect = card.getBoundingClientRect()
  const visible = rect.top >= margin && rect.bottom <= window.innerHeight - 24
  if (visible) return false
  return { top: Math.max(window.scrollY + rect.top - margin, 0), behavior: 'auto' }
}

export function installHeroTransition(router) {
  router.beforeResolve(async (to, from) => {
    if (!document.startViewTransition || reducedMotion.matches) return

    const target = heroTarget(to, from)
    if (!target) return

    pending = target
    heroWatchId.value = target.id
    allowSeed(true)
    await nextTick() // lets the photo pick up its transition name before the "before" picture

    await new Promise((resolve) => {
      const transition = document.startViewTransition(() => {
        // The browser now holds the old picture: let the navigation carry on, and
        // keep the transition waiting until the new page is on screen (afterEach).
        resolve()
        return new Promise((done) => {
          finishUpdate = done
        })
      })
      // A skipped transition rejects these. The page change itself still works.
      transition.ready.catch(() => {})
      transition.finished.catch(() => {}).then(resolve)
    })
  })

  // Runs after every navigation, including cancelled ones.
  router.afterEach(async () => {
    if (!pending) return
    const done = finishUpdate
    finishUpdate = null

    await nextTick() // the new page has now been drawn
    await photosReady()

    pending = null
    allowSeed(false)
    done?.()
  })
}