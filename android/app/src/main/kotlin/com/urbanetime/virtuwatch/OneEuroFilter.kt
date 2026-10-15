package com.urbanetime.virtuwatch

import kotlin.math.PI
import kotlin.math.abs

/**
 * One Euro filter (Casiez et al. 2012): heavy smoothing when the signal is
 * nearly still (kills jitter), light smoothing when it moves fast (low lag).
 *
 *  - minCutoff: lower = smoother when still (more lag at rest)
 *  - beta:      higher = less lag during fast motion (more jitter leaks through)
 *
 * Tune beta relative to the signal's units: for positions in metres use a
 * large beta (speeds are small numbers), for unit-vector components use a
 * smaller one.
 */
class OneEuroFilter(
    private val minCutoff: Double,
    private val beta: Double,
    private val dCutoff: Double = 1.0,
) {
    private var xPrev = 0.0
    private var dxPrev = 0.0
    private var tPrev = -1.0

    fun reset() {
        tPrev = -1.0
    }

    fun filter(x: Double, tSec: Double): Double {
        if (tPrev < 0) {
            tPrev = tSec
            xPrev = x
            dxPrev = 0.0
            return x
        }
        val dt = (tSec - tPrev).coerceAtLeast(1e-3)
        tPrev = tSec
        val dx = (x - xPrev) / dt
        val aD = alpha(dCutoff, dt)
        val dxHat = aD * dx + (1 - aD) * dxPrev
        val cutoff = minCutoff + beta * abs(dxHat)
        val a = alpha(cutoff, dt)
        val xHat = a * x + (1 - a) * xPrev
        xPrev = xHat
        dxPrev = dxHat
        return xHat
    }

    private fun alpha(cutoff: Double, dt: Double): Double {
        val tau = 1.0 / (2 * PI * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }
}
