import { collection, addDoc, serverTimestamp } from 'firebase/firestore'
import { auth, db } from '../firebase'

const logsRef = collection(db, 'activityLog')

// Records an activity log entry. Failures are ignored on purpose:
// logging should never block the action it describes.
export async function logActivity(type, message) {
  try {
    const user = auth.currentUser
    await addDoc(logsRef, {
      type,
      message,
      actorUid: user?.uid ?? null,
      actorEmail: user?.email ?? null,
      timestamp: serverTimestamp(),
    })
  } catch {
    // Intentionally ignored.
  }
}