import { ref } from 'vue'
import { onAuthStateChanged } from 'firebase/auth'
import { doc, getDoc } from 'firebase/firestore'
import { auth, db } from '../firebase'
import { clearCache } from '../utils/snapshotCache'
import { clearListLocations } from '../router/listLocation'

const ALLOWED_ROLES = ['admin', 'merchant']

// The signed-in user's profile (uid, role, name...), or null if signed out.
export const currentUser = ref(null)

// A promise that finishes once Firebase has told us whether
// someone is already signed in (e.g. after a page refresh).
let markReady
export const authReady = new Promise((resolve) => {
  markReady = resolve
})

onAuthStateChanged(auth, async (firebaseUser) => {
  if (!firebaseUser) {
    currentUser.value = null
  } else {
    try {
      const snap = await getDoc(doc(db, 'users', firebaseUser.uid))
      const data = snap.exists() ? snap.data() : null
      const allowed =
        data && ALLOWED_ROLES.includes(data.role) && data.accountStatus !== 'suspended'
      currentUser.value = allowed ? { uid: firebaseUser.uid, ...data } : null
    } catch {
      currentUser.value = null
    }
  }
  // Signed out (or not allowed in): forget remembered lists and filters, so they
  // can't show up for whoever signs in next.
  if (!currentUser.value) {
    clearCache()
    clearListLocations()
  }
  markReady()
})