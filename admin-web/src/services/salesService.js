import {
  collection,
  doc,
  query,
  where,
  orderBy,
  limit,
  onSnapshot,
  runTransaction,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore'
import { auth, db } from '../firebase'
import { logActivity } from './activityLogService'
import { MAX_STOCK, stockOf } from '../utils/stock'
import { saleTotal, formatMoney, SaleStatus } from '../utils/sales'

const salesRef = collection(db, 'sales')

// An error whose message is safe to show to the merchant as it is ("Only 2 in stock.").
// Anything else (a network failure, a denied write) is shown as a generic message.
export class SaleError extends Error {
  constructor(message) {
    super(message)
    this.name = 'SaleError'
  }
}

// What to tell the merchant for a failed save or void.
export function saleErrorMessage(error, fallback) {
  return error instanceof SaleError ? error.message : fallback
}

// Listens to one merchant's sales, newest first. Calls onData(list) now and again
// whenever the data changes. Returns a function that stops listening.
// Pass { max } to read only the latest few (the dashboard does).
export function listenToMySales(merchantId, onData, onError, { max = null } = {}) {
  const constraints = [where('merchantId', '==', merchantId), orderBy('soldAt', 'desc')]
  if (max) constraints.push(limit(max))
  return onSnapshot(
    query(salesRef, ...constraints),
    (snapshot) => onData(snapshot.docs.map((d) => ({ id: d.id, ...d.data() }))),
    onError,
  )
}

const watchLabel = (watch) => (watch.brand ? `${watch.brand} ${watch.name}` : watch.name) || 'Unnamed watch'

// Records a sale the merchant made OFF the platform, and takes the units out of stock.
//
// The sale and the stock change are written in ONE transaction, so they can never drift
// apart: either both happen or neither does. The watch is read again inside the
// transaction, so the stock check uses the real count, not what the page last showed.
//
// A watch with no stock count (null) can still be sold; its count is simply left alone,
// and the sale remembers that (stockAdjusted: false) so voiding it later does not
// invent stock either.
//
// input: { quantity, unitPrice, soldAt (Date), paymentMethod, buyerName?, notes? }
// Returns { id, total, stockLeft } (stockLeft is null for an untracked watch).
export async function recordSale(watchId, input) {
  const uid = auth.currentUser?.uid
  if (!uid) throw new SaleError('You must be logged in to record a sale.')

  const watchRef = doc(db, 'watches', watchId)
  const saleRef = doc(salesRef) // the id is known now, so the transaction can retry safely
  const { quantity, unitPrice } = input
  const total = saleTotal(unitPrice, quantity)

  let label = ''
  let stockLeft = null

  await runTransaction(db, async (tx) => {
    // The callback can run more than once if another write gets in first.
    stockLeft = null
    const snap = await tx.get(watchRef)
    if (!snap.exists()) throw new SaleError('This watch no longer exists.')
    const watch = snap.data()
    if (watch.merchantId !== uid) throw new SaleError('You can only record sales for your own watches.')

    const stock = stockOf(watch)
    if (stock !== null && quantity > stock) {
      throw new SaleError(stock === 0 ? 'This watch is out of stock.' : `Only ${stock} in stock.`)
    }

    label = watchLabel(watch)
    const image = watch.imageUrls?.[0] || watch.imageUrl || ''

    const sale = {
      merchantId: uid,
      watchId,
      // A snapshot, so the history survives the watch being edited or deleted.
      watchName: watch.name || 'Unnamed watch',
      ...(watch.brand ? { watchBrand: watch.brand } : {}),
      ...(image ? { watchImageUrl: image } : {}),
      quantity,
      unitPrice,
      totalAmount: total,
      soldAt: Timestamp.fromDate(input.soldAt),
      paymentMethod: input.paymentMethod,
      ...(input.buyerName?.trim() ? { buyerName: input.buyerName.trim() } : {}),
      ...(input.notes?.trim() ? { notes: input.notes.trim() } : {}),
      status: SaleStatus.COMPLETED,
      stockAdjusted: stock !== null,
      createdAt: serverTimestamp(),
    }

    tx.set(saleRef, sale)
    if (stock !== null) {
      stockLeft = stock - quantity
      tx.update(watchRef, { stock: stockLeft, updatedAt: serverTimestamp() })
    }
  })

  await logActivity(
    'sale_recorded',
    `Sale recorded: ${quantity} × ${label} (${formatMoney(total)})`,
  )
  return { id: saleRef.id, total, stockLeft, label }
}

// Voids a sale recorded by mistake. The record stays in the history, marked as voided
// and left out of every total, and the units go back into stock (only if this sale
// took them out in the first place, and only if the watch still exists).
// Returns { restored } - whether stock was put back.
export async function voidSale(saleId, reason = '') {
  const uid = auth.currentUser?.uid
  if (!uid) throw new SaleError('You must be logged in to void a sale.')

  const saleRef = doc(db, 'sales', saleId)
  let restored = false
  let summary = ''

  await runTransaction(db, async (tx) => {
    restored = false // the callback can run more than once
    const saleSnap = await tx.get(saleRef)
    if (!saleSnap.exists()) throw new SaleError('This sale could not be found.')
    const sale = saleSnap.data()
    if (sale.merchantId !== uid) throw new SaleError('You can only void your own sales.')
    if (sale.status !== SaleStatus.COMPLETED) throw new SaleError('This sale is already voided.')

    // All reads before any write.
    const watchRef = doc(db, 'watches', sale.watchId)
    const watchSnap = await tx.get(watchRef)

    tx.update(saleRef, {
      status: SaleStatus.VOIDED,
      voidedAt: serverTimestamp(),
      ...(reason.trim() ? { voidReason: reason.trim() } : {}),
    })

    if (sale.stockAdjusted === true && watchSnap.exists()) {
      const stock = stockOf(watchSnap.data())
      if (stock !== null) {
        tx.update(watchRef, {
          stock: Math.min(stock + sale.quantity, MAX_STOCK),
          updatedAt: serverTimestamp(),
        })
        restored = true
      }
    }
    summary = `${sale.quantity} × ${sale.watchBrand ? `${sale.watchBrand} ` : ''}${sale.watchName}`
  })

  await logActivity('sale_voided', `Sale voided: ${summary}`)
  return { restored }
}
