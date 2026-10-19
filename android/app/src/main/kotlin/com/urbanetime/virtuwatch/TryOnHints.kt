package com.urbanetime.virtuwatch

import android.graphics.Bitmap
import android.os.SystemClock

/** What the person should be told to do to keep the watch steady. Sent to Flutter by name. */
enum class TryOnHint { NONE, LOW_LIGHT, HAND_NOT_VISIBLE, TOO_CLOSE }

/** Cheap statistics of one camera frame: mean brightness (0..255) and the share of skin-coloured samples (0..1). */
class FrameStats(val luma: Double, val skin: Double)

object FrameSampler {
    /** Samples a coarse grid (300 pixels), so this costs next to nothing even every few frames. */
    fun sample(bmp: Bitmap): FrameStats {
        val w = bmp.width
        val h = bmp.height
        if (w < 8 || h < 8) return FrameStats(255.0, 0.0)
        val cols = 20
        val rows = 15
        var sumY = 0.0
        var skin = 0
        var n = 0
        for (r in 0 until rows) {
            val y = (((r + 0.5) / rows) * h).toInt().coerceIn(0, h - 1)
            for (c in 0 until cols) {
                val x = (((c + 0.5) / cols) * w).toInt().coerceIn(0, w - 1)
                val p = bmp.getPixel(x, y)
                val rr = (p shr 16) and 0xFF
                val gg = (p shr 8) and 0xFF
                val bb = p and 0xFF
                val yy = 0.299 * rr + 0.587 * gg + 0.114 * bb
                sumY += yy
                n++
                val cr = (rr - yy) * 0.713 + 128.0
                val cb = (bb - yy) * 0.564 + 128.0
                if (yy > 35.0 && cr in 133.0..175.0 && cb in 77.0..127.0) skin++
            }
        }
        return FrameStats(sumY / n, skin.toDouble() / n)
    }
}

/**
 * Turns per-frame measurements into ONE steady guidance message. A message only appears after its
 * condition has held for a moment and only goes away after the condition has been gone for a moment,
 * so it never flickers. Called from the analysis and MediaPipe threads, hence @Synchronized.
 *
 * Priority: too close > low light > hand not (fully) visible.
 *
 * The thresholds are first guesses and are the numbers to tune on real phones.
 */
class HintMonitor(private val onChange: (TryOnHint) -> Unit) {
    private companion object {
        const val LOW_ON = 65.0          // mean brightness below this = dark (camera auto-exposure already lifts it)
        const val LOW_OFF = 80.0         // ...and it must climb above this to count as bright again
        const val EDGE = 0.012f          // a landmark this close to the frame edge = the hand is cut off
        const val CLOSE_SPAN = 0.70f     // a cut-off hand spanning this much of the frame = too close
        const val FILLS_FRAME = 0.90f    // an uncut hand spanning this much = still too close
        const val SKIN_FILLS = 0.50      // share of the frame that is skin when only the arm is in view
        const val NO_HAND_MS = 2500L
        const val SHOW_MS = 1300L
        const val SHOW_CLOSE_MS = 1000L
        const val CLEAR_MS = 800L
    }

    private var luma = 255.0
    private var lumaInit = false
    private var skin = 0.0
    private var low = false

    private var shown = TryOnHint.NONE
    private var candidate = TryOnHint.NONE
    private var candidateSince = 0L
    private var lastHandAt = 0L
    private var noHandSince = 0L

    @Synchronized
    fun onFrameStats(s: FrameStats) {
        luma = if (!lumaInit) s.luma else luma * 0.8 + s.luma * 0.2
        skin = if (!lumaInit) s.skin else skin * 0.6 + s.skin * 0.4
        lumaInit = true
        if (!low && luma < LOW_ON) low = true else if (low && luma > LOW_OFF) low = false
    }

    /** [landmarks]: 21 normalized (x, y) pairs, or null when no hand was found. */
    @Synchronized
    fun onResult(landmarks: FloatArray?) {
        val now = SystemClock.elapsedRealtime()
        var raw = TryOnHint.NONE
        if (landmarks != null && landmarks.size >= 42) {
            lastHandAt = now
            noHandSince = 0L
            var minX = Float.MAX_VALUE; var maxX = -Float.MAX_VALUE
            var minY = Float.MAX_VALUE; var maxY = -Float.MAX_VALUE
            for (i in 0 until landmarks.size / 2) {
                val x = landmarks[i * 2]
                val y = landmarks[i * 2 + 1]
                if (x < minX) minX = x
                if (x > maxX) maxX = x
                if (y < minY) minY = y
                if (y > maxY) maxY = y
            }
            val cut = minX < EDGE || maxX > 1f - EDGE || minY < EDGE || maxY > 1f - EDGE
            val span = maxOf(maxX - minX, maxY - minY)
            raw = when {
                cut && span >= CLOSE_SPAN -> TryOnHint.TOO_CLOSE
                cut -> TryOnHint.HAND_NOT_VISIBLE
                span >= FILLS_FRAME -> TryOnHint.TOO_CLOSE
                else -> TryOnHint.NONE
            }
        } else {
            if (noHandSince == 0L) noHandSince = now
            val lostFor = now - noHandSince
            raw = when {
                // A hand was tracked earlier and now the picture is mostly skin: only the wrist/arm is in view.
                lastHandAt != 0L && skin >= SKIN_FILLS && lostFor > 300L -> TryOnHint.TOO_CLOSE
                lostFor > NO_HAND_MS -> TryOnHint.HAND_NOT_VISIBLE
                else -> TryOnHint.NONE
            }
        }
        val cand = when {
            raw == TryOnHint.TOO_CLOSE -> TryOnHint.TOO_CLOSE
            low -> TryOnHint.LOW_LIGHT
            else -> raw
        }
        settle(cand, now)
    }

    @Synchronized
    fun reset() {
        lastHandAt = 0L
        noHandSince = 0L
        candidate = TryOnHint.NONE
        candidateSince = 0L
        if (shown != TryOnHint.NONE) {
            shown = TryOnHint.NONE
            onChange(TryOnHint.NONE)
        }
    }

    private fun settle(cand: TryOnHint, now: Long) {
        if (cand != candidate) {
            candidate = cand
            candidateSince = now
        }
        if (cand == shown) return
        val needed = when (cand) {
            TryOnHint.NONE -> CLEAR_MS
            TryOnHint.TOO_CLOSE -> SHOW_CLOSE_MS
            else -> SHOW_MS
        }
        if (now - candidateSince >= needed) {
            shown = cand
            onChange(cand)
        }
    }
}
