package com.urbanetime.virtuwatch

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.View

/**
 * Where the soft contact shadow goes, in view pixels. The shadow is an ellipse: [rAlong] is its
 * half-size along the forearm, [rAcross] across the wrist, and [angleDeg] turns the "along" axis to
 * the forearm's direction on screen. [alpha] is the darkest point's opacity (0..1).
 */
class ShadowSpot(
    val cx: Float,
    val cy: Float,
    val angleDeg: Float,
    val rAlong: Float,
    val rAcross: Float,
    val alpha: Float,
)

/**
 * A transparent layer between the camera picture and the watch that darkens the skin around the
 * watch a little, so the watch looks like it sits on the wrist instead of floating over it. The watch
 * itself is drawn on top, so only the soft edge of this shadow is ever seen.
 *
 * It is a plain 2D gradient (not a Filament material) on purpose: it needs nothing but the position
 * and size the renderer already works out every frame.
 */
class ShadowView(context: Context) : View(context) {
    @Volatile var spot: ShadowSpot? = null
        private set

    /** Main thread. Pass null to hide the shadow. */
    fun update(s: ShadowSpot?) {
        spot = s
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        spot?.let { paintSpot(canvas, it, 1f) }
    }

    companion object {
        /** Draws [s] onto [canvas], scaled by [k] (used to put the shadow into saved photos, which can differ in size from the view). */
        fun paintSpot(canvas: Canvas, s: ShadowSpot, k: Float) {
            if (s.alpha <= 0.01f || s.rAlong <= 1f || s.rAcross <= 1f) return
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            // A unit circle that fades from dark in the middle to nothing at the edge; the canvas
            // scale below stretches it into the ellipse. A warm dark tone looks more natural on skin than pure black.
            val dark = Color.rgb(35, 22, 18)
            val clear = Color.argb(0, 35, 22, 18)
            paint.shader = RadialGradient(
                0f, 0f, 1f,
                intArrayOf(dark, Color.argb(150, 35, 22, 18), clear),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
            paint.alpha = (s.alpha.coerceIn(0f, 1f) * 255f).toInt()
            canvas.save()
            canvas.translate(s.cx * k, s.cy * k)
            canvas.rotate(s.angleDeg)
            canvas.scale(s.rAlong * k, s.rAcross * k)
            canvas.drawCircle(0f, 0f, 1f, paint)
            canvas.restore()
        }
    }
}
