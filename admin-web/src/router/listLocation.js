// Remembers the address of each watch list page, including its search and filters,
// so that leaving a watch (Back link, cancel, save, delete) returns to the list
// exactly as it was, rather than to the unfiltered list.
//
// Only used for those "return" links. A fresh visit, such as clicking My Catalog
// in the sidebar, still opens the list unfiltered.

const lastQuery = new Map()

// Router afterEach hook. List pages are the ones marked heroList in the router.
export function rememberListLocation(to, from, failure) {
  if (failure || !to.meta.heroList) return
  lastQuery.set(to.path, { ...to.query })
}

// Where to send someone back to: the list's path plus whatever filters it had.
export function listLocation(path) {
  return { path, query: { ...(lastQuery.get(path) ?? {}) } }
}

// Called on sign out, so the next person to sign in never inherits these.
export function clearListLocations() {
  lastQuery.clear()
}