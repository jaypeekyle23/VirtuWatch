import { ref } from 'vue'

// The hero photo animation: when a watch is opened (or closed again), its photo
// flies between the list and the detail page instead of the page just swapping.
// The browser does the flying; it matches elements by their "view-transition-name".
// Names must be unique on a page, so only ONE photo carries it at a time: the one
// for the watch in heroWatchId. The router sets that (see router/heroTransition.js).
const HERO_NAME = 'watch-hero'

export const heroWatchId = ref(null)

// Spread this onto a watch's clickable photo: <img v-bind="hero(watch.id)" />
// It does nothing for every watch except the one currently flying.
export function hero(watchId) {
  if (heroWatchId.value !== watchId) return {}
  return {
    'data-hero': '',
    // scrollMarginBlock keeps the photo clear of the top bar when it is scrolled into view.
    style: { viewTransitionName: HERO_NAME, scrollMarginBlock: '6rem' },
  }
}

// The big photo frame on the watch detail page. It always carries the name.
export const heroFrame = {
  'data-hero': '',
  style: { viewTransitionName: HERO_NAME },
}