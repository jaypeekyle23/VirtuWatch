package com.urbanetime.virtuwatch

import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Wrist pose in CAMERA space (OpenCV convention: +x right, +y down, +z forward
 * out of the lens), in metres. All vectors are DoubleArray(3).
 *
 *  - xAxis: across the hand (index MCP -> pinky MCP direction)
 *  - yAxis: along the forearm (middle-finger MCP -> wrist, i.e. toward the elbow)
 *  - zAxis: xAxis x yAxis (hand/palm normal; sign depends on which side faces
 *           the camera, see TODO in the README)
 */
class WristPose(
    val origin: DoubleArray,
    val xAxis: DoubleArray,
    val yAxis: DoubleArray,
    val zAxis: DoubleArray,
    val focalPx: Double,
    val imgW: Int,
    val imgH: Int,
) {
    /** Project a camera-space point to upright-image pixel coords. */
    fun project(p: DoubleArray): FloatArray {
        val z = p[2].coerceAtLeast(1e-3)
        return floatArrayOf(
            (imgW / 2.0 + focalPx * p[0] / z).toFloat(),
            (imgH / 2.0 + focalPx * p[1] / z).toFloat(),
        )
    }
}

object PoseMath {
    // MediaPipe hand landmark indices
    const val WRIST = 0
    const val INDEX_MCP = 5
    const val MIDDLE_MCP = 9
    const val RING_MCP = 13
    const val PINKY_MCP = 17

    /** Wrist -> middle-finger knuckle, adult average. Tune per user later (e.g. from a calibration step). */
    const val TYPICAL_PALM_LENGTH_M = 0.095

    fun sub(a: DoubleArray, b: DoubleArray) = doubleArrayOf(a[0] - b[0], a[1] - b[1], a[2] - b[2])
    fun dot(a: DoubleArray, b: DoubleArray) = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
    fun cross(a: DoubleArray, b: DoubleArray) = doubleArrayOf(
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )

    fun norm(a: DoubleArray): DoubleArray {
        val l = sqrt(dot(a, a)).coerceAtLeast(1e-9)
        return doubleArrayOf(a[0] / l, a[1] / l, a[2] / l)
    }

    /** Gram-Schmidt: returns orthonormal (x, y, z) from approximate x and y. */
    fun orthonormalize(x: DoubleArray, y: DoubleArray): Array<DoubleArray> {
        val yN = norm(y)
        val xo = norm(doubleArrayOf(
            x[0] - dot(x, yN) * yN[0],
            x[1] - dot(x, yN) * yN[1],
            x[2] - dot(x, yN) * yN[2],
        ))
        val zN = norm(cross(xo, yN))
        return arrayOf(xo, yN, zN)
    }

    /**
     * Estimate camera-space wrist pose from one MediaPipe result.
     *
     * Orientation comes from the metric *world* landmarks (hand-centred, so it
     * is independent of where the hand is in the frame).
     * Depth comes from similar triangles: the real wrist->middle-MCP length
     * (world landmarks, x/y only so foreshortening is accounted for) versus
     * its length in pixels. This is an estimate: world-landmark scale is the
     * model's idea of hand size, not your user's.
     *
     * @param imgW/imgH dimensions of the UPRIGHT (already rotated) analysis image
     * @param focalPx   focal length in pixels for that same image
     */
    fun estimate(
        result: HandLandmarkerResult,
        imgW: Int,
        imgH: Int,
        focalPx: Double,
        armDeltaRad: Double = 0.0,
    ): WristPose? {
        if (result.landmarks().isEmpty() || result.worldLandmarks().isEmpty()) return null
        val lm = result.landmarks()[0]
        val wl = result.worldLandmarks()[0]

        val px0 = lm[WRIST].x() * imgW.toDouble()
        val py0 = lm[WRIST].y() * imgH.toDouble()
        val px9 = lm[MIDDLE_MCP].x() * imgW.toDouble()
        val py9 = lm[MIDDLE_MCP].y() * imgH.toDouble()
        val lenPx = hypot(px0 - px9, py0 - py9)
        // MediaPipe's world-landmark SCALE is not reliable (it read ~2x too close in testing),
        // so use it only for the foreshortening RATIO (xy length / full 3D length) and take the
        // absolute size from a typical adult palm length instead.
        val dx = (wl[WRIST].x() - wl[MIDDLE_MCP].x()).toDouble()
        val dy = (wl[WRIST].y() - wl[MIDDLE_MCP].y()).toDouble()
        val dz = (wl[WRIST].z() - wl[MIDDLE_MCP].z()).toDouble()
        val len3d = sqrt(dx * dx + dy * dy + dz * dz)
        if (lenPx < 8.0 || len3d < 0.01) return null
        val ratio = hypot(dx, dy) / len3d
        if (ratio < 0.25) return null // hand pointing almost straight at the lens: unreliable
        val lenWorldXY = TYPICAL_PALM_LENGTH_M * ratio

        val z = focalPx * lenWorldXY / lenPx
        val origin = doubleArrayOf(
            (px0 - imgW / 2.0) * z / focalPx,
            (py0 - imgH / 2.0) * z / focalPx,
            z,
        )

        // Orientation from the IMAGE landmarks (pixels, z scaled like x, +z = away from the lens).
        // These are guaranteed to be in the same frame as what's on screen. The world landmarks
        // turned out NOT to flip consistently between palm-view and back-view, so they are only
        // used above for the scale-free foreshortening ratio.
        fun p(i: Int) = doubleArrayOf(
            lm[i].x() * imgW.toDouble(),
            lm[i].y() * imgH.toDouble(),
            lm[i].z() * imgW.toDouble(),
        )
        val across = sub(p(PINKY_MCP), p(INDEX_MCP))
        // Forearm direction = from the middle of the knuckle row back to the wrist (steadier than one knuckle).
        val knuckles = arrayOf(p(INDEX_MCP), p(MIDDLE_MCP), p(RING_MCP), p(PINKY_MCP))
        val palmCentre = DoubleArray(3) { k -> knuckles.sumOf { it[k] } / 4.0 }
        val handAxis = sub(p(WRIST), palmCentre)
        // Rotate the in-image direction by the detected forearm-vs-hand angle (see ArmAxis);
        // the depth part stays the hand's. 0 rad = pure hand axis.
        val c = cos(armDeltaRad)
        val sn = sin(armDeltaRad)
        val forearm = doubleArrayOf(
            handAxis[0] * c - handAxis[1] * sn,
            handAxis[0] * sn + handAxis[1] * c,
            handAxis[2],
        )
        val (xA, yA, zA) = orthonormalize(across, forearm)
        return WristPose(origin, xA, yA, zA, focalPx, imgW, imgH)
    }
}

/** Smooths a WristPose with One Euro filters (position + two axes, then re-orthonormalised). */
class PoseFilter {
    // Tune these on-device. Position is in metres, axes are unit-vector components.
    // Higher beta = the filter opens up quickly when the hand moves (less lag), while the low
    // minCutoff still keeps a resting hand steady.
    private val pos = Array(3) { OneEuroFilter(minCutoff = 0.8, beta = 25.0) }
    private val ax = Array(3) { OneEuroFilter(minCutoff = 0.5, beta = 2.5) }
    private val ay = Array(3) { OneEuroFilter(minCutoff = 0.5, beta = 2.5) }

    fun reset() {
        (pos + ax + ay).forEach { it.reset() }
    }

    fun apply(p: WristPose, tSec: Double): WristPose {
        val o = DoubleArray(3) { pos[it].filter(p.origin[it], tSec) }
        val x = DoubleArray(3) { ax[it].filter(p.xAxis[it], tSec) }
        val y = DoubleArray(3) { ay[it].filter(p.yAxis[it], tSec) }
        val (xn, yn, zn) = PoseMath.orthonormalize(x, y)
        return WristPose(o, xn, yn, zn, p.focalPx, p.imgW, p.imgH)
    }
}