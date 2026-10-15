package com.urbanetime.virtuwatch

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import kotlin.math.max

/**
 * Debug overlay: hand skeleton, the estimated wrist frame (R=across, G=forearm, B=normal),
 * the RAW wrist point (grey, to visualise jitter) and a HUD.
 *
 * TODO (next step): replace the axes with the Filament watch model, using
 * TrackingFrame.pose as its transform.
 */
class TryOnOverlayView(context: Context) : View(context) {
    @Volatile private var frame: TrackingFrame? = null
    @Volatile var debugVisible = false // clean view: only the watch shows

    private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; style = Paint.Style.FILL }
    private val bone = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(160, 0, 255, 120); strokeWidth = 4f }
    private val axisPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeWidth = 8f; strokeCap = Paint.Cap.ROUND }
    private val rawDot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.LTGRAY; style = Paint.Style.FILL }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 34f; setShadowLayer(4f, 0f, 0f, Color.BLACK) }

    private val axisLenM = 0.05 // 5 cm axes

    fun update(f: TrackingFrame) {
        frame = f
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        val f = frame ?: return
        if (f.imgW == 0) return

        // Same mapping as PreviewView FILL_CENTER (analysis + preview are both 4:3).
        val scale = max(width.toFloat() / f.imgW, height.toFloat() / f.imgH)
        val offX = (width - f.imgW * scale) / 2f
        val offY = (height - f.imgH * scale) / 2f
        fun mx(u: Float) = (if (f.mirror) f.imgW - u else u) * scale + offX
        fun my(v: Float) = v * scale + offY

        if (!debugVisible) return

        f.landmarks?.let { lm ->
            for (c in HandLandmarker.HAND_CONNECTIONS) {
                canvas.drawLine(
                    mx(lm[c.start() * 2] * f.imgW), my(lm[c.start() * 2 + 1] * f.imgH),
                    mx(lm[c.end() * 2] * f.imgW), my(lm[c.end() * 2 + 1] * f.imgH), bone
                )
            }
            for (i in 0 until lm.size / 2) {
                canvas.drawCircle(mx(lm[i * 2] * f.imgW), my(lm[i * 2 + 1] * f.imgH), 6f, dot)
            }
        }

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
        for (line in f.hud.split("\n")) {
            canvas.drawText(line, 24f, y, text)
            y += 42f
        }
    }
}