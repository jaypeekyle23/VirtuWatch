import { ref, watch } from 'vue'

const STORAGE_KEY = 'virtuwatch.catalogView'

// Grid is the default, same as the mobile app.
function readSavedView() {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'list' ? 'list' : 'grid'
  } catch {
    // Storage can be blocked (private mode, strict settings). Fall back quietly.
    return 'grid'
  }
}

// 'grid' or 'list'. It lives at the top level of this file, so every page that
// imports it shares the same value, and the choice carries between
// My Catalog and Watch Management.
export const catalogView = ref(readSavedView())

watch(catalogView, (value) => {
  try {
    localStorage.setItem(STORAGE_KEY, value)
  } catch {
    // Not being able to remember the choice is not worth bothering the user about.
  }
})