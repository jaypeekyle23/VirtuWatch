import {
  collection,
  doc,
  query,
  where,
  orderBy,
  onSnapshot,
  addDoc,
  getDoc,
  updateDoc,
  deleteDoc,
  deleteField,
  writeBatch,
  arrayRemove,
  serverTimestamp,
} from 'firebase/firestore'
import { auth, db } from '../firebase'
import { logActivity } from './activityLogService'
import { remember, seed, forgetWatch } from '../utils/snapshotCache'

const watchesRef = collection(db, 'watches')

const myWatchesKey = (merchantId) => `watches:merchant:${merchantId}`

// Listens to one merchant's watches, newest first.
// Calls onData(list) now and again whenever the data changes.
// Returns a function that stops listening.
export function listenToMyWatches(merchantId, onData, onError) {
  const q = query(
    watchesRef,
    where('merchantId', '==', merchantId),
    orderBy('createdAt', 'desc'),
  )
  return onSnapshot(
    q,
    (snapshot) => {
      const list = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }))
      remember(myWatchesKey(merchantId), list)
      onData(list)
    },
    onError,
  )
}

// The last list listenToMyWatches delivered, for drawing a page instantly
// during a hero photo transition. Null at any other time (see utils/snapshotCache).
export function seedMyWatches(merchantId) {
  return seed(myWatchesKey(merchantId))
}

// Loads one watch by ID. Returns null if it doesn't exist.
export async function getWatch(watchId) {
  const snap = await getDoc(doc(db, 'watches', watchId))
  return snap.exists() ? { id: snap.id, ...snap.data() } : null
}

// The admin form sends arFit: null to mean "no AR fit". Leaving the key out
// means "don't touch it", which is what the merchant form does. Only admins can
// write arFit at all (see firestore.rules).
function withoutNullArFit(data) {
  const { arFit, ...rest } = data
  return arFit == null ? rest : data
}

// Creates a new watch listing. It belongs to the signed-in user, unless an
// admin passes merchantIdOverride to assign it to a specific merchant.
export async function addWatch(data, merchantIdOverride = null) {
  const uid = merchantIdOverride ?? auth.currentUser?.uid
  if (!uid) throw 'You must be logged in to add a watch.'

  await addDoc(watchesRef, {
    ...withoutNullArFit(data),
    merchantId: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  })

  const name = data.name || 'Unnamed watch'
  const brand = data.brand || ''
  await logActivity('watch_added', `Watch added: ${brand ? `${brand} ${name}` : name}`)
}

// Updates an existing watch listing.
export async function updateWatch(watchId, data) {
  // arFit: null removes a saved fit (cleared, or stale after a model change).
  const fields = data.arFit === null ? { ...data, arFit: deleteField() } : data
  await updateDoc(doc(db, 'watches', watchId), {
    ...fields,
    updatedAt: serverTimestamp(),
  })
}

// Deletes a watch listing, its engagement summary, and (best effort) any
// references to it in customers' saved / recently viewed lists.
export async function deleteWatch(watchId, watchLabel = null) {
  const engagementRef = doc(db, 'watches', watchId, 'engagement', 'summary')

  // Read this BEFORE deleting: it tells us which customers reference the watch.
  let affectedUserIds = []
  try {
    const snap = await getDoc(engagementRef)
    const d = snap.data() ?? {}
    affectedUserIds = [...new Set([...(d.saverIds ?? []), ...(d.viewerIds ?? [])])]
  } catch (e) {
    console.warn('Could not read engagement summary:', e)
  }

  await deleteDoc(doc(db, 'watches', watchId))
  forgetWatch(watchId) // so no page animates into a card that no longer exists
  await deleteDoc(engagementRef)

  // Firestore only allows admins to edit other users' documents, so this
  // cleanup can be denied for merchants. That must not break the delete.
  try {
    for (let i = 0; i < affectedUserIds.length; i += 400) {
      const batch = writeBatch(db)
      for (const uid of affectedUserIds.slice(i, i + 400)) {
        batch.update(doc(db, 'users', uid), {
          savedWatches: arrayRemove(watchId),
          recentlyViewedWatches: arrayRemove(watchId),
        })
      }
      await batch.commit()
    }
  } catch (e) {
    console.warn('Could not clean up customer references:', e)
  }

  await logActivity('watch_deleted', `Watch deleted: ${watchLabel ?? watchId}`)
}

// Customer-engagement stats for a list of watch IDs, read from each watch's
// engagement summary doc. A watch with no summary yet simply counts as zero.
// Covers saves and views, plus the AR try-on numbers the app records
// (see recordTryOnEvent in lib/services/user_service.dart).
export async function fetchEngagementStats(watchIds) {
  const savedCounts = {}
  const viewedCounts = {}
  const uniqueSavers = new Set()
  const tryOnerCounts = {} // distinct customers who tried the watch on
  const tryOnCounts = {} // total try-ons (trying it twice counts twice)
  const photoCounts = {} // try-on photos captured
  const shareCounts = {} // try-on photos shared
  const uniqueTryOners = new Set()

  const summaries = await Promise.all(
    watchIds.map((id) => getDoc(doc(db, 'watches', id, 'engagement', 'summary'))),
  )

  watchIds.forEach((id, i) => {
    const data = summaries[i].data() ?? {}
    const saverIds = data.saverIds ?? []
    const viewerIds = data.viewerIds ?? []
    const tryOnerIds = data.tryOnerIds ?? []
    savedCounts[id] = saverIds.length
    viewedCounts[id] = viewerIds.length
    saverIds.forEach((uid) => uniqueSavers.add(uid))
    tryOnerCounts[id] = tryOnerIds.length
    tryOnCounts[id] = count(data.tryOnCount)
    photoCounts[id] = count(data.photoCount)
    shareCounts[id] = count(data.shareCount)
    tryOnerIds.forEach((uid) => uniqueTryOners.add(uid))
  })

  const sum = (counts) => Object.values(counts).reduce((a, b) => a + b, 0)
  return {
    savedCounts,
    viewedCounts,
    uniqueSaverCount: uniqueSavers.size,
    totalSaves: sum(savedCounts),
    tryOnerCounts,
    tryOnCounts,
    photoCounts,
    shareCounts,
    uniqueTryOnerCount: uniqueTryOners.size,
    totalTryOns: sum(tryOnCounts),
    totalPhotos: sum(photoCounts),
    totalShares: sum(shareCounts),
  }
}

// A counter field from the summary doc. Missing or not a number reads as zero.
function count(value) {
  return typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : 0
}