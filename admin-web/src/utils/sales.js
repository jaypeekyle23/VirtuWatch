// Sales history: the rules for what a recorded sale is, and the maths over a list of them.
//
// VirtuWatch has no checkout, payment processing or shipping (see utils/stock.js and the
// Terms of Service). A sale happens OFF the platform, so a merchant records it by hand
// afterwards. Each record keeps a snapshot of the watch's name, brand, photo and price at
// the time, so editing or deleting a watch later never changes the history.
//
// A sale is never deleted. A mistake is VOIDED: it stays in the history, marked as voided,
// and is left out of every total.
//
// Keep MAX values and PAYMENT_METHODS in step with the sales block in firestore.rules.

import { MAX_STOCK } from './stock'

export const SaleStatus = Object.freeze({
  COMPLETED: 'completed',
  VOIDED: 'voided',
})

// How the buyer paid, outside the app. Same list as firestore.rules.
export const PAYMENT_METHODS = ['Cash', 'GCash', 'Maya', 'Bank transfer', 'Card', 'Other']

export const MAX_SALE_QUANTITY = MAX_STOCK
export const MAX_UNIT_PRICE = 100000000
export const MAX_BUYER_LENGTH = 120
export const MAX_NOTES_LENGTH = 500
export const MAX_VOID_REASON_LENGTH = 300

export const isVoided = (sale) => sale?.status === SaleStatus.VOIDED
export const isCompleted = (sale) => sale?.status === SaleStatus.COMPLETED

// price x quantity, rounded to centavos so 3 x 1,999.99 never shows a float tail.
export function saleTotal(unitPrice, quantity) {
  const total = Number(unitPrice) * Number(quantity)
  return Number.isFinite(total) ? Math.round(total * 100) / 100 : 0
}

// "PHP 12,500". Centavos only appear when there are some.
export function formatMoney(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return '–'
  const hasCentavos = Math.round(value * 100) % 100 !== 0
  return (
    'PHP ' +
    value.toLocaleString('en-PH', {
      minimumFractionDigits: hasCentavos ? 2 : 0,
      maximumFractionDigits: 2,
    })
  )
}

// ---------- Dates ----------

// A Date from a Firestore Timestamp (or a Date). Null when there is none yet.
export function saleDate(sale) {
  const value = sale?.soldAt
  if (!value) return null
  if (value instanceof Date) return value
  return typeof value.toDate === 'function' ? value.toDate() : null
}

const pad = (n) => String(n).padStart(2, '0')

// "2026-11-16" in the viewer's own time zone (what a date box reads and writes).
export function toDayString(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

// The moment a sale is stamped with, from the date the merchant picked. Today keeps the
// current time, so sales made on the same day stay in the order they were recorded. Any
// other day is noon, so a time zone shift can never move it onto a different date.
// Null for a missing or impossible date.
export function soldAtFromDay(dayString, now = new Date()) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayString ?? '')
  if (!match) return null
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])]
  const date = new Date(year, month - 1, day, 12, 0, 0, 0)
  // new Date rolls 2026-02-31 over to March, so check it came back as the same day.
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return null
  }
  if (toDayString(date) === toDayString(now)) return new Date(now)
  return date
}

// Start (00:00:00.000) or end (23:59:59.999) of a "YYYY-MM-DD" day. Null when blank/invalid.
function dayBoundary(dayString, end) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayString ?? '')
  if (!match) return null
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])]
  const date = end
    ? new Date(year, month - 1, day, 23, 59, 59, 999)
    : new Date(year, month - 1, day, 0, 0, 0, 0)
  return Number.isNaN(date.getTime()) ? null : date
}

export const DATE_PRESETS = [
  { value: 'all', label: 'All time' },
  { value: 'month', label: 'This month' },
  { value: 'last30', label: 'Last 30 days' },
  { value: 'year', label: 'This year' },
]

// The from / to day strings a quick-range button fills in. 'all' leaves both blank.
export function presetRange(preset, now = new Date()) {
  const today = toDayString(now)
  switch (preset) {
    case 'month':
      return { from: toDayString(new Date(now.getFullYear(), now.getMonth(), 1)), to: today }
    case 'last30': {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 29)
      return { from: toDayString(start), to: today }
    }
    case 'year':
      return { from: toDayString(new Date(now.getFullYear(), 0, 1)), to: today }
    default:
      return { from: '', to: '' }
  }
}

// ---------- Validation ----------

// Checks what the "Record a sale" form collected. Returns { field: message }; an empty
// object means it is good to save. [stock] is the watch's current count, or null when the
// merchant has not entered one (an untracked watch can always be sold).
export function validateSaleInput(input, stock, now = new Date()) {
  const errors = {}

  const { quantity, unitPrice, soldAt, paymentMethod, buyerName, notes } = input

  if (!Number.isInteger(quantity) || quantity < 1) {
    errors.quantity = 'Enter at least 1.'
  } else if (quantity > MAX_SALE_QUANTITY) {
    errors.quantity = `Enter ${MAX_SALE_QUANTITY.toLocaleString('en-PH')} or fewer.`
  } else if (stock !== null && stock !== undefined && quantity > stock) {
    errors.quantity = stock === 0 ? 'This watch is out of stock.' : `Only ${stock} in stock.`
  }

  if (typeof unitPrice !== 'number' || !Number.isFinite(unitPrice) || unitPrice <= 0) {
    errors.unitPrice = 'Enter the price it sold for.'
  } else if (unitPrice > MAX_UNIT_PRICE) {
    errors.unitPrice = 'That price is too high.'
  }

  if (!(soldAt instanceof Date) || Number.isNaN(soldAt.getTime())) {
    errors.soldAt = 'Pick the date it was sold.'
  } else if (soldAt.getTime() > dayBoundary(toDayString(now), true).getTime()) {
    errors.soldAt = 'The date cannot be in the future.'
  }

  if (!PAYMENT_METHODS.includes(paymentMethod)) {
    errors.paymentMethod = 'Choose how it was paid.'
  }

  if ((buyerName ?? '').length > MAX_BUYER_LENGTH) {
    errors.buyerName = `Keep it under ${MAX_BUYER_LENGTH} characters.`
  }
  if ((notes ?? '').length > MAX_NOTES_LENGTH) {
    errors.notes = `Keep it under ${MAX_NOTES_LENGTH} characters.`
  }

  return errors
}

// ---------- Filtering and totals ----------

// Applies the sales page's search and filters. All are optional.
//   search         matches the watch, brand, buyer or notes
//   from, to       "YYYY-MM-DD", both ends included
//   paymentMethod  one of PAYMENT_METHODS, or '' for any
//   includeVoided  false hides voided sales
export function filterSales(sales, { search = '', from = '', to = '', paymentMethod = '', includeVoided = false } = {}) {
  const query = search.trim().toLowerCase()
  const start = dayBoundary(from, false)
  const end = dayBoundary(to, true)

  return sales.filter((sale) => {
    if (!includeVoided && isVoided(sale)) return false
    if (paymentMethod && sale.paymentMethod !== paymentMethod) return false

    if (start || end) {
      const date = saleDate(sale)
      if (!date) return false
      if (start && date < start) return false
      if (end && date > end) return false
    }

    if (query) {
      const haystack = [sale.watchName, sale.watchBrand, sale.buyerName, sale.notes]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
      if (!haystack.includes(query)) return false
    }
    return true
  })
}

// Newest sale first. Sales on the same day keep the order they were recorded in.
export function sortSalesNewestFirst(sales) {
  const time = (value) => (value && typeof value.toMillis === 'function' ? value.toMillis() : 0)
  return [...sales].sort(
    (a, b) =>
      (saleDate(b)?.getTime() ?? 0) - (saleDate(a)?.getTime() ?? 0) ||
      time(b.createdAt) - time(a.createdAt),
  )
}

// Totals for a list of sales. Voided sales are left out of revenue, units and count, and
// are only counted in `voided`, so a mistake never inflates the numbers.
export function salesTotals(sales) {
  let revenue = 0
  let units = 0
  let count = 0
  let voided = 0
  for (const sale of sales) {
    if (isVoided(sale)) {
      voided++
      continue
    }
    revenue += typeof sale.totalAmount === 'number' ? sale.totalAmount : 0
    units += Number.isInteger(sale.quantity) ? sale.quantity : 0
    count++
  }
  return { revenue: Math.round(revenue * 100) / 100, units, count, voided }
}

// ---------- CSV export ----------

// A cell that starts with = + - @ (or a tab / CR) is read as a formula by Excel and
// Sheets, and a buyer's name or a note is typed by hand. A leading quote makes it text.
function csvCell(value) {
  let text = value == null ? '' : String(value)
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export const CSV_HEADERS = [
  'Date sold',
  'Watch',
  'Brand',
  'Quantity',
  'Unit price (PHP)',
  'Total (PHP)',
  'Payment method',
  'Buyer',
  'Notes',
  'Status',
  'Void reason',
]

// The sales as CSV text. Starts with a byte order mark so Excel reads the peso-era
// names and accents correctly. Numbers are written bare so a spreadsheet can add them up.
export function salesToCsv(sales) {
  const lines = [CSV_HEADERS.map(csvCell).join(',')]
  for (const sale of sales) {
    const date = saleDate(sale)
    lines.push(
      [
        csvCell(date ? toDayString(date) : ''),
        csvCell(sale.watchName),
        csvCell(sale.watchBrand),
        sale.quantity ?? '',
        sale.unitPrice ?? '',
        sale.totalAmount ?? '',
        csvCell(sale.paymentMethod),
        csvCell(sale.buyerName),
        csvCell(sale.notes),
        csvCell(isVoided(sale) ? 'Voided' : 'Completed'),
        csvCell(sale.voidReason),
      ].join(','),
    )
  }
  return '\uFEFF' + lines.join('\r\n') + '\r\n'
}
