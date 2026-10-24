import { STYLE_OPTIONS, GENDER_OPTIONS } from '../constants/watchOptions'
import { isArReady } from './arFit'
import { isInStock, needsStockAttention, stockOf } from './stock'

// How many watches one page of the catalog shows. 15 fills whole rows at the
// 3 and 5 column widths.
export const PAGE_SIZE = 15

// How many pages a list of this many watches needs. There is always at least one.
export function pageCount(total, pageSize = PAGE_SIZE) {
  return Math.max(1, Math.ceil(total / pageSize))
}

export const SORT_OPTIONS = [
  { value: 'newest', label: 'Newest first' },
  { value: 'oldest', label: 'Oldest first' },
  { value: 'priceLow', label: 'Price: Low to High' },
  { value: 'priceHigh', label: 'Price: High to Low' },
  { value: 'nameAZ', label: 'Name: A to Z' },
]

// A watch is only visible to customers when listedInCatalog is exactly true.
export function isListed(watch) {
  return watch.listedInCatalog === true
}

// Which important fields a watch is missing: the ones the recommendation
// engine and chatbot rely on (gender, color, lug-to-lug), plus the stock count,
// because customers see availability on every listing and a watch with no count
// shows none. Same list as missingWatchFields in the app's merchant catalog.
export function missingWatchFields(watch) {
  const missing = []
  if (watch.targetGender == null) missing.push('Gender')
  const hasColor = watch.colorHex != null || (watch.colorHexes?.length ?? 0) > 0
  if (!hasColor) missing.push('Color')
  if (watch.lugToLugMm == null) missing.push('Lug-to-Lug')
  if (stockOf(watch) === null) missing.push('Stock')
  return missing
}

// Which field of the edit form fixes each missing item. The form reads ?focus= and
// scrolls to that field. Keys match the field ids in WatchForm (wf-<key>).
const FIX_FOCUS = {
  Gender: 'gender',
  Color: 'colors',
  'Lug-to-Lug': 'lugToLugMm',
  Stock: 'stock',
}

// A link to the edit page that opens with the field for one missing item
// (a label from missingWatchFields) scrolled into view and focused.
export function fixLocation(editPath, label) {
  const focus = FIX_FOCUS[label]
  return focus ? { path: editPath, query: { focus } } : editPath
}

// ---------- Search, sort, filters and page <-> the page address ----------
// So a filtered list survives opening a watch and coming back, and can be shared
// as a link, e.g. /merchant/catalog?q=seiko&style=Sport&sort=priceLow
// Anything left at its default is left out, which keeps addresses short.

// A price is only kept if it is a plain number, so the address and the input
// can never disagree about it.
function cleanPrice(value) {
  const text = String(value ?? '').trim()
  return /^\d+(\.\d+)?$/.test(text) ? text : ''
}

// A page number is only kept if it is a whole number from 1 up.
function cleanPage(value) {
  const number = Number(value)
  return Number.isInteger(number) && number >= 1 ? number : 1
}

// The address query (an object of strings) for the current search, sort, filters and page.
export function catalogQueryFromState({
  search,
  sort,
  filters,
  needsInfoOnly,
  stockAlertOnly = false,
  page = 1,
}) {
  const query = {}
  const text = search.trim()
  if (text) query.q = text
  if (sort !== 'newest') query.sort = sort
  if (filters.style !== 'All') query.style = filters.style
  if (filters.gender !== 'All') query.gender = filters.gender
  if (filters.brand !== 'All') query.brand = filters.brand
  if (filters.listingStatus !== 'All') query.status = filters.listingStatus
  if (cleanPrice(filters.minPrice)) query.min = cleanPrice(filters.minPrice)
  if (cleanPrice(filters.maxPrice)) query.max = cleanPrice(filters.maxPrice)
  if (filters.arOnly) query.ar = '1'
  if (filters.inStockOnly) query.inStock = '1'
  if (needsInfoOnly) query.needsInfo = '1'
  if (stockAlertOnly) query.stockAlert = '1'
  if (page > 1) query.page = String(page)
  return query
}

// The reverse. An address can be typed or edited by hand, so every value is
// checked and anything unrecognised falls back to its default.
export function catalogStateFromQuery(query) {
  const read = (key) => {
    const value = Array.isArray(query[key]) ? query[key][0] : query[key]
    return typeof value === 'string' ? value : ''
  }
  const oneOf = (key, allowed, fallback) => (allowed.includes(read(key)) ? read(key) : fallback)

  return {
    search: read('q'),
    sort: oneOf('sort', SORT_OPTIONS.map((o) => o.value), 'newest'),
    needsInfoOnly: read('needsInfo') === '1',
    stockAlertOnly: read('stockAlert') === '1',
    page: cleanPage(read('page')),
    filters: {
      style: oneOf('style', STYLE_OPTIONS, 'All'),
      gender: oneOf('gender', GENDER_OPTIONS, 'All'),
      brand: read('brand') || 'All',
      arOnly: read('ar') === '1',
      inStockOnly: read('inStock') === '1',
      minPrice: cleanPrice(read('min')),
      maxPrice: cleanPrice(read('max')),
      listingStatus: oneOf('status', ['Active', 'Draft'], 'All'),
    },
  }
}

export function defaultFilters() {
  return {
    style: 'All',
    gender: 'All',
    brand: 'All',
    arOnly: false,
    // Only watches with at least one unit on hand. A watch with no stock count is
    // left out once this is on, since its availability is unknown.
    inStockOnly: false,
    minPrice: '',
    maxPrice: '',
    listingStatus: 'All', // 'All' | 'Active' | 'Draft'
  }
}

// How many filters are narrowing the list (for the badge on the filter button).
export function activeFilterCount(filters) {
  let count = 0
  if (filters.style !== 'All') count++
  if (filters.gender !== 'All') count++
  if (filters.brand !== 'All') count++
  if (filters.arOnly) count++
  if (filters.inStockOnly) count++
  if (filters.minPrice !== '' || filters.maxPrice !== '') count++
  if (filters.listingStatus !== 'All') count++
  return count
}

// stockAlertOnly is the merchant's "review low and out of stock" shortcut. Like
// needsInfoOnly it sits outside the filters panel, because it is a tool for the
// seller, not something a shopper would filter by.
export function filterWatches(
  watches,
  filters,
  searchText = '',
  needsInfoOnly = false,
  stockAlertOnly = false,
) {
  const search = searchText.trim().toLowerCase()
  const min = filters.minPrice === '' ? null : Number(filters.minPrice)
  const max = filters.maxPrice === '' ? null : Number(filters.maxPrice)

  return watches.filter((w) => {
    if (needsInfoOnly && missingWatchFields(w).length === 0) return false
    if (stockAlertOnly && !needsStockAttention(w)) return false
    if (filters.style !== 'All' && w.styleCategory !== filters.style) return false
    if (filters.brand !== 'All' && w.brand !== filters.brand) return false
    if (filters.gender !== 'All' && w.targetGender !== filters.gender) return false
    if (filters.arOnly && !isArReady(w)) return false
    if (filters.inStockOnly && !isInStock(w)) return false
    if (filters.listingStatus === 'Active' && !isListed(w)) return false
    if (filters.listingStatus === 'Draft' && isListed(w)) return false

    if (min !== null || max !== null) {
      if (typeof w.price !== 'number') return false
      if (min !== null && w.price < min) return false
      if (max !== null && w.price > max) return false
    }

    if (search) {
      const haystack = [w.name, w.brand, w.styleCategory]
        .map((v) => (v ?? '').toLowerCase())
        .join(' ')
      if (!haystack.includes(search)) return false
    }
    return true
  })
}

// When a watch was added, in milliseconds, so watches can be compared.
//  - A watch just added has createdAt = null until the server fills in the time,
//    so it counts as the newest.
//  - An old watch with no createdAt at all counts as the oldest.
function createdMillis(watch) {
  const c = watch.createdAt
  if (c === null) return Infinity
  if (c === undefined) return -Infinity
  if (typeof c.toMillis === 'function') return c.toMillis()
  if (c instanceof Date) return c.getTime()
  if (typeof c.seconds === 'number') return c.seconds * 1000 + (c.nanoseconds ?? 0) / 1e6
  if (typeof c === 'number') return c
  return -Infinity
}

// Sorts a copy of the list. Newest and oldest go by the time the watch was added.
// (The list from Firestore is not guaranteed to be in that order, so it is sorted here.)
export function sortWatches(watches, sortValue) {
  const list = [...watches]
  const priceOf = (w) => (typeof w.price === 'number' ? w.price : null)

  if (sortValue === 'newest' || sortValue === 'oldest') {
    const dir = sortValue === 'newest' ? -1 : 1
    // Compare with < and > (not subtraction) because Infinity - Infinity is NaN.
    list.sort((a, b) => {
      const ta = createdMillis(a)
      const tb = createdMillis(b)
      if (ta === tb) return 0
      return (ta < tb ? -1 : 1) * dir
    })
  } else if (sortValue === 'priceLow' || sortValue === 'priceHigh') {
    const dir = sortValue === 'priceLow' ? 1 : -1
    list.sort((a, b) => {
      const pa = priceOf(a)
      const pb = priceOf(b)
      if (pa === null && pb === null) return 0
      if (pa === null) return 1 // watches without a price go last
      if (pb === null) return -1
      return (pa - pb) * dir
    })
  } else if (sortValue === 'nameAZ') {
    list.sort((a, b) => (a.name ?? '').localeCompare(b.name ?? '', undefined, { sensitivity: 'base' }))
  }
  return list
}