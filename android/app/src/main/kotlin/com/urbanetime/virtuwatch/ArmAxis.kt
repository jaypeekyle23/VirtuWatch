package com.urbanetime.virtuwatch

import android.graphics.Bitmap
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Reads the forearm from the camera image, because the hand landmarks only describe the hand.
 *
 * 1. Skin model: learns this person's skin chroma (Cr/Cb, loose on brightness) from patches that
 *    are certainly skin: the back of the hand between the wrist and the knuckles.
 * 2. Direction: a fan of rays behind the wrist; skin runs far along rays near the arm's axis and
 *    stops early near its edges, so the run-length-weighted mean angle is the arm's axis.
 *    (The hand axis alone drifts off the arm when the wrist is bent / the arm is vertical.)
 * 3. Width: scan sideways, across the arm, at several points just above the wrist, and take the
 *    median distance between the two skin edges, plus how far the arm's centre is from the axis.
 *    The watch is then sized so its strap spans exactly that width ON SCREEN, which cancels any
 *    error in the depth estimate.
 *
 * Everything returns null / flags itself unreliable rather than guessing, so the caller can fall
 * back to hand-only estimates.
 */
object ArmAxis {
    class Result(
        /** True if the direction estimate is trustworthy; otherwise [deltaRad] is 0 (hand axis). */
        val armOk: Boolean,
        /** Forearm direction relative to the hand's "backwards" direction, radians (image coords). */
        val deltaRad: Double,
        val confidence: Double,
        /** Arm width across the wrist as a multiple of the hand's palm length in pixels (NaN if none). */
        val widthRel: Double,
        /** How many scan lines agreed (>= 3 is considered reliable). */
        val widthLines: Int,
        /** Sideways offset of the arm's centre line from the scan axis, as a multiple of palm length. */
        val offsetRel: Double,
    )

    private const val FAN_HALF_DEG = 60
    private const val FAN_STEP_DEG = 6
    private const val MAX_DELTA_RAD = 0.8 // ~46 deg: beyond this it's more likely a mistake than a real bend

    fun estimate(bmp: Bitmap, lm: List<NormalizedLandmark>): Result? {
        val w = bmp.width
        val h = bmp.height
        if (lm.size < 21) return null

        fun px(i: Int) = doubleArrayOf(lm[i].x() * w.toDouble(), lm[i].y() * h.toDouble())
        val wrist = px(0)
        val knuckles = listOf(px(5), px(9), px(13), px(17))
        val palm = doubleArrayOf(knuckles.sumOf { it[0] } / 4.0, knuckles.sumOf { it[1] } / 4.0)

        var dx = wrist[0] - palm[0]
        var dy = wrist[1] - palm[1]
        val len = hypot(dx, dy)
        if (len < 20.0) return null // hand too small / pointing at the lens
        dx /= len
        dy /= len

        // ---- 1. skin colour model from patches on the hand --------------------------------
        val ycc = DoubleArray(3)
        val ys = ArrayList<Double>()
        val crs = ArrayList<Double>()
        val cbs = ArrayList<Double>()
        for (t in doubleArrayOf(0.0, 0.35, 0.7)) {
            val cx = palm[0] + (wrist[0] - palm[0]) * t
            val cy = palm[1] + (wrist[1] - palm[1]) * t
            for (oy in -4..4 step 2) for (ox in -4..4 step 2) {
                val x = (cx + ox).roundToInt()
                val y = (cy + oy).roundToInt()
                if (x < 0 || y < 0 || x >= w || y >= h) continue
                toYcc(bmp.getPixel(x, y), ycc)
                ys.add(ycc[0]); crs.add(ycc[1]); cbs.add(ycc[2])
            }
        }
        if (ys.size < 20) return null
        val mY = ys.average()
        val mCr = crs.average()
        val mCb = cbs.average()
        // Skin has noticeably non-neutral chroma. If the sample is grey (very dark / washed out),
        // chroma can't separate arm from background.
        if (abs(mCr - 128) < 4 && abs(mCb - 128) < 4) return null
        val sdCr = sqrt(crs.sumOf { (it - mCr) * (it - mCr) } / crs.size)
        val sdCb = sqrt(cbs.sumOf { (it - mCb) * (it - mCb) } / cbs.size)
        val tolCr = max(9.0, 2.5 * sdCr)
        val tolCb = max(9.0, 2.5 * sdCb)
        val tolY = 75.0

        fun isSkin(c: Int): Boolean {
            toYcc(c, ycc)
            return abs(ycc[1] - mCr) <= tolCr && abs(ycc[2] - mCb) <= tolCb && abs(ycc[0] - mY) <= tolY
        }

        // ---- 2. forearm direction: fan of rays behind the wrist ----------------------------
        val originX = wrist[0] + dx * 0.1 * len
        val originY = wrist[1] + dy * 0.1 * len
        val rMax = 2.2 * len
        val minRun = 0.6 * len
        val rays = (2 * FAN_HALF_DEG) / FAN_STEP_DEG + 1

        var sumW = 0.0
        var sumPhi = 0.0
        for (k in 0 until rays) {
            val phi = Math.toRadians((-FAN_HALF_DEG + k * FAN_STEP_DEG).toDouble())
            // Rotate the backwards direction by phi (same convention used when applying the result).
            val ux = dx * cos(phi) - dy * sin(phi)
            val uy = dx * sin(phi) + dy * cos(phi)

            var run = 0.0
            var miss = 0
            var r = 0.0
            while (r <= rMax) {
                val x = (originX + ux * r).roundToInt()
                val y = (originY + uy * r).roundToInt()
                if (x < 0 || y < 0 || x >= w || y >= h) {
                    // Arm runs off the edge of the picture: counts as skin all the way.
                    if (miss == 0) run = r
                    break
                }
                if (isSkin(bmp.getPixel(x, y))) {
                    run = r
                    miss = 0
                } else {
                    miss++
                    if (miss > 4) break // ~12 px gap: hair, a tan line, a freckle... tolerated; more = edge
                }
                r += 3.0
            }
            val wgt = max(0.0, run - minRun)
            sumW += wgt
            sumPhi += wgt * phi
        }

        val confidence = sumW / (rays * (rMax - minRun))
        val armOk = sumW > 0.0 && confidence >= 0.06
        val delta = if (armOk) (sumPhi / sumW).coerceIn(-MAX_DELTA_RAD, MAX_DELTA_RAD) else 0.0

        // ---- 3. arm width: scan across the arm just above the wrist -----------------------
        // Arm direction in the image (rotate the backwards direction by delta) and its perpendicular.
        val ax = dx * cos(delta) - dy * sin(delta)
        val ay = dx * sin(delta) + dy * cos(delta)
        val perpX = -ay
        val perpY = ax

        val widths = ArrayList<Double>()
        val offsets = ArrayList<Double>()
        // ~2.4 .. 6.2 cm above the wrist landmark (len ~ palm length ~ 9.5 cm): where a strap sits,
        // and clear of the wide base of the thumb right at the wrist crease.
        for (t in doubleArrayOf(0.25, 0.35, 0.45, 0.55, 0.65)) {
            val cx = wrist[0] + ax * len * t
            val cy = wrist[1] + ay * len * t
            val sx = cx.roundToInt()
            val sy = cy.roundToInt()
            if (sx < 0 || sy < 0 || sx >= w || sy >= h || !isSkin(bmp.getPixel(sx, sy))) continue

            // Distance from (cx,cy) to the skin edge along +-perp; -1 = no usable edge (ran off the
            // picture, or never left skin colour => background looks like skin).
            fun edge(sign: Double): Double {
                var s = 0.0
                var last = 0.0
                var miss = 0
                val maxS = 1.1 * len
                while (s <= maxS) {
                    val x = (cx + perpX * sign * s).roundToInt()
                    val y = (cy + perpY * sign * s).roundToInt()
                    if (x < 0 || y < 0 || x >= w || y >= h) return if (miss == 0) -1.0 else last
                    if (isSkin(bmp.getPixel(x, y))) {
                        last = s
                        miss = 0
                    } else {
                        miss++
                        if (miss > 3) return last // ~6 px gap = the edge
                    }
                    s += 2.0
                }
                return -1.0
            }

            val plus = edge(+1.0)
            val minus = edge(-1.0)
            if (plus < 0 || minus < 0) continue
            val width = plus + minus
            if (width < 0.3 * len || width > 1.2 * len) continue // not a plausible wrist (3 .. 11 cm)
            widths.add(width)
            offsets.add((plus - minus) / 2.0)
        }

        // Stored relative to palm length, so the (slow-changing) result stays valid as the hand
        // moves closer/further between the frames on which we actually re-measure.
        var widthRel = Double.NaN
        var offsetRel = 0.0
        if (widths.size >= 3) {
            widthRel = median(widths) / len
            offsetRel = median(offsets).coerceIn(-0.25 * len, 0.25 * len) / len
        }

        return Result(armOk, delta, confidence, widthRel, widths.size, offsetRel)
    }

    /** [palm length in px, dx, dy]: palm length and the unit direction from the knuckle row back to the wrist. */
    fun handBasis(lm: List<NormalizedLandmark>, w: Int, h: Int): DoubleArray? {
        if (lm.size < 21) return null
        val wx = lm[0].x() * w.toDouble()
        val wy = lm[0].y() * h.toDouble()
        var px = 0.0
        var py = 0.0
        for (i in intArrayOf(5, 9, 13, 17)) {
            px += lm[i].x() * w.toDouble() / 4.0
            py += lm[i].y() * h.toDouble() / 4.0
        }
        val dx = wx - px
        val dy = wy - py
        val len = hypot(dx, dy)
        if (len < 20.0) return null
        return doubleArrayOf(len, dx / len, dy / len)
    }

    private fun median(v: List<Double>): Double {
        val s = v.sorted()
        val m = s.size / 2
        return if (s.size % 2 == 1) s[m] else (s[m - 1] + s[m]) / 2.0
    }

    private fun toYcc(c: Int, out: DoubleArray) {
        val r = (c shr 16) and 0xFF
        val g = (c shr 8) and 0xFF
        val b = c and 0xFF
        val y = 0.299 * r + 0.587 * g + 0.114 * b
        out[0] = y
        out[1] = (r - y) * 0.713 + 128.0
        out[2] = (b - y) * 0.564 + 128.0
    }
}