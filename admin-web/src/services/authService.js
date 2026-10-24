import {
  signInWithEmailAndPassword,
  signOut,
  EmailAuthProvider,
  reauthenticateWithCredential,
  updatePassword,
  sendPasswordResetEmail,
} from 'firebase/auth'
import { doc, getDoc, updateDoc } from 'firebase/firestore'
import { auth, db } from '../firebase'

const ALLOWED_ROLES = ['admin', 'merchant']

function mapAuthError(code) {
  switch (code) {
    case 'auth/invalid-email':
      return 'That email address is not valid.'
    case 'auth/user-disabled':
      return 'This account has been disabled.'
    case 'auth/user-not-found':
    case 'auth/wrong-password':
    case 'auth/invalid-credential':
      return 'Incorrect email or password.'
    case 'auth/too-many-requests':
      return 'Too many attempts. Please try again later.'
    case 'auth/network-request-failed':
      return 'Network error. Check your connection.'
    case 'auth/weak-password':
      return 'That password is too weak. Use at least 6 characters.'
    case 'auth/requires-recent-login':
      return 'Please sign out and sign in again before doing this.'
    default:
      return 'Something went wrong. Please try again.'
  }
}

// Signs in, then checks the account is allowed to use this website.
// Returns the user's profile data, or throws an error message string.
export async function loginWithEmail(email, password) {
  let credential
  try {
    credential = await signInWithEmailAndPassword(auth, email.trim(), password)
  } catch (e) {
    throw mapAuthError(e.code)
  }

  const user = credential.user
  await user.reload()

  if (!auth.currentUser.emailVerified) {
    await signOut(auth)
    throw 'Please verify your email before signing in.'
  }

  const snap = await getDoc(doc(db, 'users', user.uid))
  if (!snap.exists()) {
    await signOut(auth)
    throw 'No profile found for this account. Please contact support.'
  }

  const data = snap.data()

  if (data.accountStatus === 'suspended') {
    await signOut(auth)
    throw 'This account has been suspended. Please contact support.'
  }

  if (!ALLOWED_ROLES.includes(data.role)) {
    await signOut(auth)
    throw 'This website is for admin and merchant accounts only. Please use the mobile app.'
  }

  return { uid: user.uid, ...data }
}

export async function logout() {
  await signOut(auth)
}

// Sends a password reset email. Works without being signed in.
// Throws an error message string if it fails.
export async function resetPassword(email) {
  try {
    await sendPasswordResetEmail(auth, email.trim())
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      throw 'No account found with that email.'
    }
    throw mapAuthError(e.code)
  }
}

// Changes the signed-in user's display name.
export async function updateUsername(newName) {
  const uid = auth.currentUser?.uid
  if (!uid) throw 'You must be logged in.'
  const name = newName.trim()
  if (name === '') throw 'Name cannot be empty.'
  await updateDoc(doc(db, 'users', uid), { username: name })
  return name
}

// Changes the signed-in user's profile photo URL.
export async function updatePhotoUrl(photoUrl) {
  const uid = auth.currentUser?.uid
  if (!uid) throw 'You must be logged in.'
  await updateDoc(doc(db, 'users', uid), { photoUrl })
}

// Changes the password. Firebase requires re-entering the current password first.
export async function changePassword(currentPassword, newPassword) {
  const user = auth.currentUser
  if (!user || !user.email) throw 'You must be logged in.'

  try {
    const credential = EmailAuthProvider.credential(user.email, currentPassword)
    await reauthenticateWithCredential(user, credential)
    await updatePassword(user, newPassword)
  } catch (e) {
    if (e.code === 'auth/wrong-password' || e.code === 'auth/invalid-credential') {
      throw 'Your current password is incorrect.'
    }
    throw mapAuthError(e.code)
  }
}