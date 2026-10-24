// How many units of a watch are left, and what that means for the UI. This is a
// JavaScript port of lib/utils/stock.dart. Keep the two in sync, because the app
// shows customers the same labels and decides "low" and "out" with the Dart version.
//
// This is the ONE definition of "low" and "out of stock" in the portal. The cards,
// the detail page, the alerts, the filter and the analytics all call the functions
// here, so they can never disagree.
//
// A watch document keeps its count in one whole-number field:
//
//   stock: 5
//
// A missing or null `stock` means the seller has not entered a count yet. That is
// NOT the same as zero. Watches listed before this feature existed have no `stock`,
// and they must not suddenly show as sold out.
//
// There is no checkout in VirtuWatch, so nothing lowers the count by itself. The
// merchant types it in, or uses the stock dialog, and edits it as they sell.

// At this many units or fewer (but more than zero), a watch counts as low.
export const LOW_STOCK_THRESHOLD = 3

// The largest count the form and the stock dialog accept (five digits, like the app).
export const MAX_STOCK = 99999

export const StockStatus = Object.freeze({
  UNTRACKED: 'untracked', // the seller has not entered a count
  IN_STOCK: 'inStock',
  LOW: 'low',
  OUT: 'out',
})

// The saved count, or null when none is on file. A negative number (which the form
// never writes) is read as zero. A decimal is cut to a whole number, like Dart's toInt().
export function stockOf(watch) {
  const value = watch?.stock
  if (typeof value !== 'number' || !Number.isFinite(value)) return null
  const count = Math.trunc(value)
  return count < 0 ? 0 : count
}

export function stockStatus(watch) {
  const count = stockOf(watch)
  if (count === null) return StockStatus.UNTRACKED
  if (count === 0) return StockStatus.OUT
  if (count <= LOW_STOCK_THRESHOLD) return StockStatus.LOW
  return StockStatus.IN_STOCK
}

export const isOutOfStock = (watch) => stockStatus(watch) === StockStatus.OUT

export const isLowStock = (watch) => stockStatus(watch) === StockStatus.LOW

// True when the seller says there is at least one unit on hand (in stock or low).
// A watch with no count on file is NOT counted, since its availability is unknown.
export function isInStock(watch) {
  const status = stockStatus(watch)
  return status === StockStatus.IN_STOCK || status === StockStatus.LOW
}

// True for a watch the merchant should look at: low or out.
export function needsStockAttention(watch) {
  const status = stockStatus(watch)
  return status === StockStatus.LOW || status === StockStatus.OUT
}

// What a customer reads: "12 in stock", "Only 2 left" or "Out of stock".
// Null when no count is on file, so the UI shows nothing instead of guessing.
export function customerStockLabel(watch) {
  const count = stockOf(watch)
  switch (stockStatus(watch)) {
    case StockStatus.OUT:
      return 'Out of stock'
    case StockStatus.LOW:
      return count === 1 ? 'Only 1 left' : `Only ${count} left`
    case StockStatus.IN_STOCK:
      return `${count} in stock`
    default:
      return null
  }
}

// What a merchant reads: the real number.
export function merchantStockLabel(watch) {
  const count = stockOf(watch)
  switch (stockStatus(watch)) {
    case StockStatus.OUT:
      return 'Out of stock'
    case StockStatus.LOW:
      return `Low: ${count} left`
    case StockStatus.IN_STOCK:
      return `${count} in stock`
    default:
      return null
  }
}

// How many of [watches] are out of stock and how many are running low.
export function stockAlertCounts(watches) {
  let out = 0
  let low = 0
  for (const watch of watches) {
    const status = stockStatus(watch)
    if (status === StockStatus.OUT) out++
    else if (status === StockStatus.LOW) low++
  }
  return { out, low }
}

// Sort comparator for alert lists: out of stock first, then the fewest left.
export function compareByStockUrgency(a, b) {
  return (stockOf(a) ?? 0) - (stockOf(b) ?? 0)
}

// Inventory totals for a list of watches. This is the number the merchant
// analytics page shows.
//
//  - value: the sum of price x units on hand. NOT the sum of the prices: ten
//    units of a 5,000 watch are worth 50,000, and a watch with none left is worth 0.
//  - A watch with no stock count yet is left out of the value (not counted as zero),
//    and `untracked` says how many were skipped, so the total is never silently
//    understated. A watch with a count but no price cannot be valued either.
//  - valued: how many watches made it into `value` (0 means there is nothing to show).
//  - units: all units on hand, whether or not the watch has a price.
export function inventoryTotals(watches) {
  let value = 0
  let valued = 0
  let units = 0
  let untracked = 0
  for (const watch of watches) {
    const count = stockOf(watch)
    if (count === null) {
      untracked++
      continue
    }
    units += count
    if (typeof watch.price === 'number' && Number.isFinite(watch.price)) {
      value += watch.price * count
      valued++
    }
  }
  return { value, valued, units, untracked }
}
