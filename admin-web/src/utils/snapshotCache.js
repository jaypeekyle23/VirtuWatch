// Remembers the last lists the live listeners delivered, so that a page can draw
// itself instantly when the user comes back to it from a watch's detail page.
// The hero photo animation needs the destination photo on screen straight away.
//
// Cached data is only handed out while a hero transition is under way (see
// allowSeed). Every other visit still starts from a loading state and shows
// fresh data, so nobody sees an out-of-date price after editing a watch.

const store = new Map()
let seedingAllowed = false

export function remember(key, value) {
  store.set(key, value)
}

export function allowSeed(allowed) {
  seedingAllowed = allowed
}

// The remembered value for a key, or null (always null outside a hero transition).
export function seed(key) {
  return seedingAllowed ? (store.get(key) ?? null) : null
}

// Looks through every remembered watch list for one watch.
function findWatch(id) {
  for (const [key, value] of store) {
    if (!key.startsWith('watches:')) continue
    const match = value.find((w) => w.id === id)
    if (match) return match
  }
  return null
}

// Is this watch in memory? (Used to decide whether a hero transition can work.)
export function isWatchKnown(id) {
  return findWatch(id) !== null
}

// The remembered watch, or null (always null outside a hero transition).
export function seedWatch(id) {
  return seedingAllowed ? findWatch(id) : null
}

// Drops a deleted watch, so a page never animates into a card that is gone.
export function forgetWatch(id) {
  for (const [key, value] of store) {
    if (key.startsWith('watches:')) store.set(key, value.filter((w) => w.id !== id))
  }
}

// Called on sign out, so the next person to sign in never sees this one's data.
export function clearCache() {
  store.clear()
}