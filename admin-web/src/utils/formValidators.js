import { MAX_STOCK } from './stock'

// Each validator returns an error message string, or null if the value is fine.

// For required numeric fields that must be positive (Price, Lug-to-Lug).
export function requiredPositiveNumber(value) {
  const text = String(value ?? '').trim()
  if (text === '') return 'Required'
  const parsed = Number(text)
  if (Number.isNaN(parsed)) return 'Enter a valid number'
  if (parsed <= 0) return 'Must be greater than 0'
  return null
}

// For optional numeric fields (Case Diameter, Case Thickness, Band Width).
// Blank is fine, but anything entered must be a valid positive number.
export function optionalPositiveNumber(value) {
  const text = String(value ?? '').trim()
  if (text === '') return null
  const parsed = Number(text)
  if (Number.isNaN(parsed)) return 'Enter a valid number'
  if (parsed <= 0) return 'Must be greater than 0'
  return null
}

// For the stock count when it is required (a watch being published). A whole number,
// zero or more. Zero is fine: it marks the watch out of stock. Decimals and
// negatives are rejected. Port of requiredStockCount in lib/utils/form_validators.dart.
export function requiredStockCount(value) {
  if (String(value ?? '').trim() === '') return 'Required'
  return optionalStockCount(value)
}

// Same rule, but blank is allowed. Used for drafts, and when editing an older
// listing that has no stock count yet, so a merchant can still change other fields first.
export function optionalStockCount(value) {
  const text = String(value ?? '').trim()
  if (text === '') return null
  if (!/^[+-]?\d+$/.test(text)) return 'Enter a whole number'
  const parsed = Number(text)
  if (parsed < 0) return 'Cannot be negative'
  if (parsed > MAX_STOCK) return `Cannot be more than ${MAX_STOCK.toLocaleString('en-PH')}`
  return null
}

// For required text fields (Name, Brand).
export function requiredText(value) {
  return String(value ?? '').trim() === '' ? 'Required' : null
}