package com.urbanetime.virtuwatch

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import kotlin.math.max

/**
 * Landmark overlay for demos and debugging, in three modes:
 *  - [MODE_OFF]: clean camera view, only the watch shows.
 *  - [MODE_LANDMARKS]: the MediaPipe hand skeleton (21 points). The five points the wrist pose is
 *    built from (wrist + the four knuckles) are highlighted and labelled. When the hand is lost,
 *    or some of those five points leave the frame, the Flutter screen shows a notice (the native
 *    side reports it through TryOnPlatformView; see [outsideKeyCount]).
 *  - [MODE_DETAILS]: everything above, plus the estimated wrist frame (R=across, G=forearm,
 *    B=normal), the RAW wrist point (grey, to visualise jitter) and a HUD.
 */
class TryOnOverlayView(context: Context) : View(context) {
    companion object {
        const val MODE_OFF = 0
        const val MODE_LANDMARKS = 1
        const val MODE_DETAILS = 2

        // MediaPipe hand landmark indices that WristPose uses, with their on-screen labels.
        private val KEY_POINTS = intArrayOf(0, 5, 9, 13, 17)
        private val KEY_LABELS = arrayOf("Wrist", "Index", "Middle", "Ring", "Pinky")
        const val KEY_POINT_COUNT = 5

        /** How many of the five key landmarks lie outside the camera image (0 = all in frame). */
        fun outsideKeyCount(lm: FloatArray): Int {
            var outside = 0
            for (k in KEY_POINTS) {
                if (k * 2 + 1 >= lm.size) continue
                val x = lm[k * 2]
                val y = lm[k * 2 + 1]
                if (x < 0f || x > 1f || y < 0f || y > 1f) outside++
            }
            return outside
        }
    }

    @Volatile private var frame: TrackingFrame? = null
    @Volatile var mode = MODE_OFF

    private val d = context.resources.displayMetrics.density

    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(170, 255, 255, 255); style = Paint.Style.FILL }
    private val keyDot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(232, 192, 106); style = Paint.Style.FILL }
    private val keyRing = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 2f * d }
    private val bone = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(160, 0, 255, 120); strokeWidth = 4f }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 8f; strokeCap = Paint.Cap.ROUND }
    private val rawDot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.LTGRAY; style = Paint.Style.FILL }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 34f; setShadowLayer(4f, 0f, 0f, Color.BLACK) }
    /** Supplies the live FPS line (set by the platform view); drawn first in the details HUD. */
    @Volatile var fpsLine: (() -> String)? = null
    private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; textSize = 12f * d; setShadowLayer(4f, 0f, 0f, Color.BLACK)
    }

    private val axisLenM = 0.05 // 5 cm axes

    fun update(f: TrackingFrame) {
        frame = f
        postInvalidateOnAnimation()
    }

    /** Forget the last frame (tracking switched off), so a frozen skeleton is never left on screen. */
    fun clear() {
        frame = null
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        val m = mode
        if (m == MODE_OFF) return
        val f = frame ?: return
        if (f.imgW == 0) return

        // Same mapping as PreviewView FILL_CENTER (analysis + preview are both 4:3).
        val scale = max(width.toFloat() / f.imgW, height.toFloat() / f.imgH)
        val offX = (width - f.imgW * scale) / 2f
        val offY = (height - f.imgH * scale) / 2f
        fun mx(u: Float) = (if (f.mirror) f.imgW - u else u) * scale + offX
        fun my(v: Float) = v * scale + offY

        val lm = f.landmarks
        if (lm != null) {
            for (c in HandLandmarker.HAND_CONNECTIONS) {
                canvas.drawLine(
                    mx(lm[c.start() * 2] * f.imgW), my(lm[c.start() * 2 + 1] * f.imgH),
                    mx(lm[c.end() * 2] * f.imgW), my(lm[c.end() * 2 + 1] * f.imgH), bone
                )
            }
            val isKey = BooleanArray(lm.size / 2)
            for (k in KEY_POINTS) if (k < isKey.size) isKey[k] = true
            for (i in 0 until lm.size / 2) {
                if (!isKey[i]) canvas.drawCircle(mx(lm[i * 2] * f.imgW), my(lm[i * 2 + 1] * f.imgH), 4f * d, dot)
            }
            // Key points last, so they sit on top of the plain dots.
            for ((n, k) in KEY_POINTS.withIndex()) {
                if (k >= isKey.size) continue
                val px = mx(lm[k * 2] * f.imgW)
                val py = my(lm[k * 2 + 1] * f.imgH)
                canvas.drawCircle(px, py, 7f * d, keyDot)
                canvas.drawCircle(px, py, 7f * d, keyRing)
                canvas.drawText(KEY_LABELS[n], px + 10f * d, py - 8f * d, label)
            }
        }

        if (m < MODE_DETAILS) return

        f.rawPose?.let {
            val p = it.project(it.origin)
            canvas.drawCircle(mx(p[0]), my(p[1]), 9f, rawDot)
        }

        f.pose?.let { pose ->
            val o = pose.project(pose.origin)
            fun axis(dir: DoubleArray, color: Int) {
                val end = doubleArrayOf(
                    pose.origin[0] + dir[0] * axisLenM,
                    pose.origin[1] + dir[1] * axisLenM,
                    pose.origin[2] + dir[2] * axisLenM,
                )
                val e = pose.project(end)
                axisPaint.color = color
                canvas.drawLine(mx(o[0]), my(o[1]), mx(e[0]), my(e[1]), axisPaint)
            }
            axis(pose.xAxis, Color.RED)
            axis(pose.yAxis, Color.GREEN)
            axis(pose.zAxis, Color.BLUE)
        }

        var y = 56f
        fpsLine?.invoke()?.let {
            canvas.drawText(it, 24f, y, text)
            y += 42f
        }
        for (line in f.hud.split("\n")) {
            canvas.drawText(line, 24f, y, text)
            y += 42f
        }
    }
}
