import { ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { catalogQueryFromState, catalogStateFromQuery } from '../utils/catalogFilters'

// Search, sort, filters and the page number for a watch list page, kept in sync with the page
// address (see catalogQueryFromState in utils/catalogFilters.js).
//
// The refs behave exactly like plain ones, so the page and the toolbar use them
// as before. Changing one updates the address; changing the address (a pasted
// link, or clicking the page's own link in the sidebar) updates them.

// Two queries are equal if they hold the same keys and values, in any order.
function sameQuery(a, b) {
  const key = (q) => JSON.stringify(Object.entries(q).sort(([x], [y]) => (x < y ? -1 : 1)))
  return key(a) === key(b)
}

// An address without its page number, to tell "went to another page" apart from
// "searched or filtered".
function withoutPage(query) {
  const rest = { ...query }
  delete rest.page
  return rest
}

export function useCatalogQuery() {
  const route = useRoute()
  const router = useRouter()
  // The page's own path. Once the person navigates elsewhere, this page is on its
  // way out and must not touch the address or its own state any more.
  const listPath = route.path

  const initial = catalogStateFromQuery(route.query)
  const search = ref(initial.search)
  const sort = ref(initial.sort)
  const filters = ref(initial.filters)
  const needsInfoOnly = ref(initial.needsInfoOnly)
  const stockAlertOnly = ref(initial.stockAlertOnly)
  const page = ref(initial.page)

  const currentQuery = () =>
    catalogQueryFromState({
      search: search.value,
      sort: sort.value,
      filters: filters.value,
      needsInfoOnly: needsInfoOnly.value,
      stockAlertOnly: stockAlertOnly.value,
      page: page.value,
    })

  // The controls changed: update the address. "replace" rather than "push", so
  // typing in the search box doesn't fill the Back button's history.
  watch([search, sort, filters, needsInfoOnly, stockAlertOnly, page], () => {
    if (route.path !== listPath) return
    const next = currentQuery()
    const inAddress = catalogQueryFromState(catalogStateFromQuery(route.query))

    // A new search, sort or filter shows a different set of watches, so it starts
    // again from page 1. (Changing the page itself leaves the rest of the address
    // alone, and an address that was just applied to the controls already matches.)
    if (page.value !== 1 && !sameQuery(withoutPage(next), withoutPage(inAddress))) {
      page.value = 1 // this runs the watcher again, which then updates the address
      return
    }

    if (sameQuery(next, inAddress)) return
    router.replace({ query: next })
  })

  // The address changed: update the controls.
  watch(
    () => route.query,
    (query) => {
      if (route.path !== listPath) return
      const incoming = catalogStateFromQuery(query)
      if (sameQuery(catalogQueryFromState(incoming), currentQuery())) return
      search.value = incoming.search
      sort.value = incoming.sort
      filters.value = incoming.filters
      needsInfoOnly.value = incoming.needsInfoOnly
      stockAlertOnly.value = incoming.stockAlertOnly
      page.value = incoming.page
    },
  )

  return { search, sort, filters, needsInfoOnly, stockAlertOnly, page }
}