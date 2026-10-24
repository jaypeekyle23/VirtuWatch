import { initializeApp, deleteApp } from 'firebase/app'
import {
  getAuth,
  createUserWithEmailAndPassword,
  sendEmailVerification,
  signOut,
} from 'firebase/auth'
import {
  collection,
  doc,
  query,
  orderBy,
  limit,
  onSnapshot,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore'
import { app, db } from '../firebase'
import { logActivity } from './activityLogService'
import { remember, seed } from '../utils/snapshotCache'

const VALID_ROLES = ['customer', 'merchant', 'admin']

// Each listen function below calls onData(list) now and again whenever the
// data changes, and returns a function that stops listening (call it when
// the page is closed).

// Every user account. Admins only (see firestore.rules).
export function listenToAllUsers(onData, onError) {
  return onSnapshot(
    collection(db, 'users'),
    (snapshot) => {
      const list = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }))
      remember('users:all', list)
      onData(list)
    },
    onError,
  )
}

// The last user list, for drawing a page instantly during a hero photo
// transition. Null at any other time (see utils/snapshotCache).
export function seedAllUsers() {
  return seed('users:all')
}

// Every watch from every merchant.
export function listenToAllWatches(onData, onError) {
  return onSnapshot(
    collection(db, 'watches'),
    (snapshot) => {
      const list = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }))
      remember('watches:all', list)
      onData(list)
    },
    onError,
  )
}

// Same idea as seedAllUsers, for the full watch list.
export function seedAllWatches() {
  return seed('watches:all')
}

// The newest activity log entries, newest first. Admins only.
export function listenToRecentActivity(onData, onError, maxEntries = 20) {
  const q = query(
    collection(db, 'activityLog'),
    orderBy('timestamp', 'desc'),
    limit(maxEntries),
  )
  return onSnapshot(
    q,
    (snapshot) => {
      onData(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })))
    },
    onError,
  )
}

// --- Account actions (admins only, enforced by firestore.rules) ---
// accountLabel is a readable name for the activity log, e.g. "Jane (jane@x.com)".

// Blocks future logins for this account.
export async function suspendAccount(uid, accountLabel) {
  await updateDoc(doc(db, 'users', uid), { accountStatus: 'suspended' })
  await logActivity('account_disabled', `Account disabled: ${accountLabel || uid}`)
}

// Lets a suspended account log in again.
export async function reactivateAccount(uid, accountLabel) {
  await updateDoc(doc(db, 'users', uid), { accountStatus: 'active' })
  await logActivity('account_enabled', `Account re-enabled: ${accountLabel || uid}`)
}

// Changes an account between customer, merchant and admin.
export async function updateUserRole(uid, newRole, accountLabel, previousRole) {
  if (!VALID_ROLES.includes(newRole)) throw `Invalid role: ${newRole}`
  await updateDoc(doc(db, 'users', uid), { role: newRole })
  await logActivity(
    'role_changed',
    `Role changed: ${accountLabel || uid}` +
      `${previousRole ? ` from ${previousRole.toUpperCase()}` : ''}` +
      ` to ${newRole.toUpperCase()}`,
  )
}

// Deletes the user's profile document. Their Firebase login still exists,
// but they can no longer use the apps, since login needs a profile.
export async function deleteAccountProfile(uid, accountLabel) {
  await deleteDoc(doc(db, 'users', uid))
  await logActivity('account_deleted', `Account deleted by admin: ${accountLabel || uid}`)
}

function mapCreateError(code) {
  switch (code) {
    case 'auth/email-already-in-use':
      return 'An account with that email already exists.'
    case 'auth/invalid-email':
      return 'That email address is not valid.'
    case 'auth/weak-password':
      return 'That password is too weak. Use at least 6 characters.'
    case 'auth/network-request-failed':
      return 'Network error. Check your connection.'
    default:
      return 'Could not create the account. Please try again.'
  }
}

// Creates a customer, merchant or admin account without signing the current
// admin out. The login is created on a temporary second Firebase app, so the
// admin's own session on the main app is untouched. The profile document is
// then saved with the admin's session, since new accounts can't write their own
// role. The new person gets a verification email and must verify before
// their first sign in.
export async function createAccountForRole({
  email,
  password,
  username,
  role,
  stylePreferences = [],
}) {
  if (!VALID_ROLES.includes(role)) throw 'Invalid role specified.'

  const cleanEmail = email.trim()
  const cleanName = username.trim()

  const secondaryApp = initializeApp(app.options, `AdminCreateUser_${Date.now()}`)
  const secondaryAuth = getAuth(secondaryApp)

  try {
    let newUser
    try {
      const credential = await createUserWithEmailAndPassword(
        secondaryAuth,
        cleanEmail,
        password,
      )
      newUser = credential.user
    } catch (e) {
      throw mapCreateError(e.code)
    }

    await setDoc(doc(db, 'users', newUser.uid), {
      uid: newUser.uid,
      email: cleanEmail,
      username: cleanName,
      role,
      stylePreferences,
      accountStatus: 'active',
      createdAt: serverTimestamp(),
    })

    await sendEmailVerification(newUser)

    await logActivity(
      'account_created',
      `${role.charAt(0).toUpperCase()}${role.slice(1)} account created: ${cleanName} (${cleanEmail})`,
    )

    await signOut(secondaryAuth)
  } finally {
    await deleteApp(secondaryApp)
  }
}