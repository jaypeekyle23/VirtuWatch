package com.urbanetime.virtuwatch

import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File

/**
 * Housekeeping for AR try-on photos: the cache copy used for the in-app preview and sharing, and
 * deleting a photo again (gallery entry + cache copy).
 */
object PhotoFiles {
    private const val TAG = "PhotoFiles"
    private const val CACHE_SUBDIR = "tryon_photos"
    private const val MAX_AGE_MS = 60L * 60L * 1000L

    fun cacheDir(context: Context): File =
        File(context.cacheDir, CACHE_SUBDIR).apply { mkdirs() }

    /** Removes cached photo copies older than an hour. */
    fun purgeOld(dir: File) {
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        dir.listFiles()?.forEach { if (it.isFile && it.lastModified() < cutoff) it.delete() }
    }

    /**
     * Deletes the gallery entry [uri] (if any) and the cache copy at [path] (if any; only files inside
     * the app's own photo cache are ever touched). Returns true when the photo is gone from the
     * gallery; false if Android refused (for example the photo was saved by an earlier install of the
     * app, which no longer owns it).
     */
    fun delete(context: Context, uri: String?, path: String?): Boolean {
        var galleryGone = true
        if (uri != null) {
            galleryGone = try {
                context.contentResolver.delete(Uri.parse(uri), null, null)
                true // 0 rows means it was already gone, which is also fine
            } catch (e: SecurityException) {
                Log.w(TAG, "gallery delete refused: ${e.message}")
                false
            } catch (e: Throwable) {
                Log.e(TAG, "gallery delete failed: ${e.message}", e)
                false
            }
        }
        // If Android refused to remove the gallery entry the photo still exists, so keep the cache copy
        // too: the preview (and its Share button) keep working.
        if (path != null && galleryGone) {
            try {
                val dir = cacheDir(context).canonicalFile
                val file = File(path).canonicalFile
                if (file.parentFile == dir) file.delete()
            } catch (e: Throwable) {
                Log.e(TAG, "cache delete failed: ${e.message}", e)
            }
        }
        return galleryGone
    }
}
