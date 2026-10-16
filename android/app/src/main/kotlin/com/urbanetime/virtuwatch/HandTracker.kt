package com.urbanetime.virtuwatch

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.RectF
import android.hardware.camera2.CameraCharacteristics
import android.os.SystemClock
import android.util.Log
import android.util.Size
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.tan

/** One tracking result, ready to draw. All coordinates are in the UPRIGHT analysis image. */
class TrackingFrame(
    val imgW: Int,
    val imgH: Int,
    val mirror: Boolean,
    /** 21 normalized (x,y) pairs, or null when no hand. */
    val landmarks: FloatArray?,
    val rawPose: WristPose?,
    val pose: WristPose?,
    val hud: String,
    /** True/false once the hand's side is known (stable over a few frames); null = unknown / no hand. */
    val isLeftHand: Boolean? = null,
    /**
     * Measured arm width in analysis-image pixels (NaN = not available / hand turned away), and the
     * image-space vector from the forearm axis to the arm's centre. Used to size and centre the watch.
     */
    val fitWidthPx: Double = Double.NaN,
    val fitShiftX: Double = 0.0,
    val fitShiftY: Double = 0.0,
)

/**
 * CameraX + MediaPipe HandLandmarker. No ARCore, no Google Play Services for AR.
 * Calls [onFrame] from MediaPipe's callback thread.
 */
class HandTracker(
    private val context: Context,
    private val owner: LifecycleOwner,
    private val previewView: PreviewView,
    private val onFrame: (TrackingFrame) -> Unit,
) {
    private val tag = "TryOnTracker"
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var landmarker: HandLandmarker? = null
    private var delegateName = "?"
    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null

    /** Set by [stop]. Late callbacks (camera provider future, frames, results) must not touch anything after this. */
    @Volatile private var stopped = false
    /** Only the use cases THIS tracker bound; the camera provider is shared by the whole process. */
    private var boundUseCases: Array<UseCase> = emptyArray()

    @Volatile var smoothingEnabled = true

    /** Flip the left/right decision if MediaPipe's label turns out to be the other way round on your device. */
    @Volatile var swapHand = false
    private var stableLeft: Boolean? = null
    private var flipCount = 0
    private var rawLabel = "-"

    /** Use the image to find the real forearm direction (see ArmAxis). Toggle to compare with the hand-axis fallback. */
    @Volatile var armDetect = true
    private val armFilter = OneEuroFilter(minCutoff = 0.6, beta = 2.0)
    private var armInfo = "arm=-"

    /** Size/centre the watch to the arm's width measured in the image (see ArmAxis). */
    @Volatile var autoFit = true
    private val shiftXFilter = OneEuroFilter(minCutoff = 1.0, beta = 0.02)
    private val shiftYFilter = OneEuroFilter(minCutoff = 1.0, beta = 0.02)

    /**
     * A small ring of REUSED upright frames. Matching a (late) MediaPipe result with the picture it
     * was computed from needs the last few frames; allocating two ~1.2 MB bitmaps per frame (what the
     * first version did) caused constant garbage-collection stalls on mid-range phones.
     */
    private class Slot {
        @Volatile var ts = -1L
        var bmp: Bitmap? = null
        var canvas: Canvas? = null
    }
    private val slots = Array(6) { Slot() }
    private var slotIdx = 0
    private var rawBmp: Bitmap? = null
    private val rotMatrix = Matrix()
    private val tmpRect = RectF()

    private fun findFrame(ts: Long): Bitmap? {
        for (s in slots) if (s.ts == ts) return s.bmp
        return null
    }

    // The arm's angle/width change slowly, so measure on every 3rd result and reuse in between.
    private var cachedSkin: ArmAxis.Result? = null
    private var armTick = 0
    @Volatile private var prepMs = 0L
    private var armMs = 0L
    private val filter = PoseFilter()

    @Volatile private var uprightW = 0
    @Volatile private var uprightH = 0
    @Volatile private var focalPx = 0.0
    private var lastTs = 0L

    // HUD stats
    private var windowStart = SystemClock.elapsedRealtime()
    private var windowCount = 0
    private var resultFps = 0
    private var latencyMs = 0L

    fun start() {
        // If the hand model can't be built the camera preview still works (no tracking), instead of
        // the whole screen crashing.
        try {
            initLandmarker()
        } catch (e: Throwable) {
            Log.e(tag, "Hand tracking unavailable: ${e.message}", e)
            landmarker = null
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            // The view may have been closed while the camera provider was still starting up.
            if (stopped) return@addListener
            try {
                provider = future.get()
                bind()
            } catch (e: Throwable) {
                Log.e(tag, "Camera could not start: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /** Rebuild the hand model on the GPU or CPU (queued on the analysis thread so it can't race a frame). */
    fun setGpu(gpu: Boolean) {
        analysisExecutor.execute {
            try {
                val old = landmarker
                landmarker = null
                old?.close()
                landmarker = try {
                    build(if (gpu) Delegate.GPU else Delegate.CPU).also { delegateName = if (gpu) "GPU" else "CPU" }
                } catch (e: Throwable) {
                    Log.w(tag, "Delegate switch failed (${e.message}); using CPU")
                    build(Delegate.CPU).also { delegateName = "CPU" }
                }
                filter.reset()
            } catch (e: Throwable) {
                Log.e(tag, "setGpu failed: ${e.message}")
            }
        }
    }

    fun stop() {
        stopped = true
        try {
            unbindOwnUseCases()
        } catch (e: Throwable) {
            Log.w(tag, "unbind failed: ${e.message}")
        }
        // Close the landmarker on the analysis thread, after any frame already being processed, so
        // native MediaPipe is never closed while it is in use. Already-queued work still runs after
        // shutdown().
        try {
            analysisExecutor.execute {
                try { landmarker?.close() } catch (e: Throwable) { Log.w(tag, "close failed: ${e.message}") }
                landmarker = null
            }
        } catch (e: Throwable) {
            Log.w(tag, "could not queue landmarker close: ${e.message}")
        }
        analysisExecutor.shutdown()
    }

    private fun unbindOwnUseCases() {
        val p = provider ?: return
        if (boundUseCases.isNotEmpty()) p.unbind(*boundUseCases)
        boundUseCases = emptyArray()
    }

    // ---- MediaPipe -------------------------------------------------------

    private fun initLandmarker() {
        landmarker = try {
            build(Delegate.GPU).also { delegateName = "GPU" }
        } catch (e: Throwable) {
            Log.w(tag, "GPU delegate failed (${e.message}); falling back to CPU")
            build(Delegate.CPU).also { delegateName = "CPU" }
        }
    }

    private fun build(delegate: Delegate): HandLandmarker {
        val base = BaseOptions.builder()
            .setModelAssetPath("hand_landmarker.task")
            .setDelegate(delegate)
            .build()
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumHands(1)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setResultListener { result, _ -> onResult(result) }
            .setErrorListener { e -> Log.e(tag, "HandLandmarker error: ${e.message}") }
            .build()
        return HandLandmarker.createFromOptions(context, options)
    }

    // ---- CameraX ---------------------------------------------------------

    @SuppressLint("UnsafeOptInUsageError")
    private fun bind() {
        if (stopped) return
        val p = provider ?: return
        unbindOwnUseCases()

        // AR try-on only uses the back camera.
        val selector = CameraSelector.DEFAULT_BACK_CAMERA
        val ratio43 = AspectRatioStrategy(AspectRatio.RATIO_4_3, AspectRatioStrategy.FALLBACK_RULE_AUTO)

        val preview = Preview.Builder()
            .setResolutionSelector(ResolutionSelector.Builder().setAspectRatioStrategy(ratio43).build())
            .build()
            .also { it.surfaceProvider = previewView.surfaceProvider }

        // Small analysis frames: the hand model doesn't need more, and it keeps the Note 8 happy too.
        val analysis = ImageAnalysis.Builder()
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setAspectRatioStrategy(ratio43)
                    .setResolutionStrategy(
                        ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
                    )
                    .build()
            )
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()
            .also { it.setAnalyzer(analysisExecutor, ::analyze) }

        camera = p.bindToLifecycle(owner, selector, preview, analysis)
        boundUseCases = arrayOf(preview, analysis)
        focalPx = 0.0 // recomputed on first frame once we know the upright size
    }

    /** Where the current focal length came from (shown in the HUD). */
    @Volatile private var focalSource = "?"

    /**
     * Focal length in pixels of the upright analysis image.
     * 1) LENS_INTRINSIC_CALIBRATION (best, not on every phone)
     * 2) physical sensor size + focal length
     * 3) default 68 deg FOV
     * Anything giving a long-side FOV outside 50..95 deg is rejected as bogus.
     */
    @SuppressLint("UnsafeOptInUsageError")
    @androidx.annotation.OptIn(ExperimentalCamera2Interop::class)
    private fun computeFocalPx(w: Int, h: Int): Double {
        val long = max(w, h).toDouble()
        fun fovDeg(f: Double) = Math.toDegrees(2 * atan(long / (2 * f)))
        fun ok(f: Double) = fovDeg(f) in 50.0..95.0
        try {
            val info = Camera2CameraInfo.from(camera!!.cameraInfo)

            val calib = info.getCameraCharacteristic(CameraCharacteristics.LENS_INTRINSIC_CALIBRATION)
            val arr = info.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PRE_CORRECTION_ACTIVE_ARRAY_SIZE)
            if (calib != null && arr != null && calib.isNotEmpty()) {
                val f = calib[0].toDouble() * long / max(arr.width(), arr.height())
                if (ok(f)) { focalSource = "calib %.0f°".format(fovDeg(f)); return f }
            }

            val sensor = info.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val focals = info.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            if (sensor != null && focals != null && focals.isNotEmpty()) {
                val f = long * focals[0] / max(sensor.width, sensor.height).toDouble()
                Log.i(tag, "sensor=${sensor.width}x${sensor.height}mm focal=${focals.toList()} -> f=${"%.0f".format(f)}px fov=${"%.0f".format(fovDeg(f))}")
                if (ok(f)) { focalSource = "sensor %.0f°".format(fovDeg(f)); return f }
                focalSource = "default (rejected %.0f°)".format(fovDeg(f))
            }
        } catch (e: Throwable) {
            Log.w(tag, "Could not read camera intrinsics: ${e.message}")
        }
        if (!focalSource.startsWith("default")) focalSource = "default 68°"
        return (long / 2.0) / tan(Math.toRadians(68.0) / 2)
    }

    private fun analyze(proxy: ImageProxy) {
        try {
            if (stopped) return
            val t0 = SystemClock.elapsedRealtimeNanos()
            val rotation = proxy.imageInfo.rotationDegrees
            val rw = proxy.width
            val rh = proxy.height
            val upW = if (rotation % 180 == 0) rw else rh
            val upH = if (rotation % 180 == 0) rh else rw

            // 1) Camera frame -> a REUSED bitmap (no per-frame allocation).
            val plane = proxy.planes[0]
            val src: Bitmap
            if (plane.pixelStride == 4 && plane.rowStride == rw * 4) {
                val r: Bitmap = rawBmp?.takeIf { it.width == rw && it.height == rh }
                    ?: Bitmap.createBitmap(rw, rh, Bitmap.Config.ARGB_8888).also { rawBmp = it }
                val buf = plane.buffer
                buf.rewind()
                r.copyPixelsFromBuffer(buf)
                src = r
            } else {
                src = proxy.toBitmap() // padded rows: rare; slower but safe
            }

            // 2) Rotate to UPRIGHT ourselves into a reused ring slot, so MediaPipe's landmarks come
            // back in the same orientation the user sees. (Passing rotation via ImageProcessingOptions
            // returned landmarks in the unrotated sensor frame -> skeleton was off by 90 deg.)
            val slot = slots[slotIdx]
            slotIdx = (slotIdx + 1) % slots.size
            slot.ts = -1L // being rewritten: nobody should trust this slot until we're done
            val dst: Bitmap = slot.bmp?.takeIf { it.width == upW && it.height == upH }
                ?: Bitmap.createBitmap(upW, upH, Bitmap.Config.ARGB_8888).also {
                    slot.bmp = it
                    slot.canvas = Canvas(it)
                }
            rotMatrix.setRotate(rotation.toFloat())
            tmpRect.set(0f, 0f, rw.toFloat(), rh.toFloat())
            rotMatrix.mapRect(tmpRect)
            rotMatrix.postTranslate(-tmpRect.left, -tmpRect.top)
            slot.canvas?.drawBitmap(src, rotMatrix, null)

            uprightW = upW
            uprightH = upH
            if (focalPx == 0.0) focalPx = computeFocalPx(upW, upH)

            var ts = SystemClock.elapsedRealtime()
            if (ts <= lastTs) ts = lastTs + 1
            lastTs = ts
            slot.ts = ts
            prepMs = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000

            landmarker?.detectAsync(BitmapImageBuilder(dst).build(), ts)
        } catch (e: Throwable) {
            Log.e(tag, "analyze failed: ${e.message}")
        } finally {
            proxy.close()
        }
    }

    // ---- results ---------------------------------------------------------

    private fun onResult(result: HandLandmarkerResult) {
        if (stopped) return
        // This runs on MediaPipe's own thread: an exception escaping from here would kill the app.
        try {
            processResult(result)
        } catch (e: Throwable) {
            Log.e(tag, "onResult failed: ${e.message}", e)
        }
    }

    private fun processResult(result: HandLandmarkerResult) {
        val now = SystemClock.elapsedRealtime()
        latencyMs = now - result.timestampMs()
        windowCount++
        if (now - windowStart >= 1000) {
            resultFps = windowCount
            windowCount = 0
            windowStart = now
        }

        val w = uprightW
        val h = uprightH
        var lm: FloatArray? = null
        var raw: WristPose? = null
        var smooth: WristPose? = null
        var skin: ArmAxis.Result? = null
        var basis: DoubleArray? = null
        var palmWidthPx = 0.0

        if (w > 0 && result.landmarks().isNotEmpty()) {
            val pts = result.landmarks()[0]
            lm = FloatArray(pts.size * 2).also { arr ->
                pts.forEachIndexed { i, p -> arr[i * 2] = p.x(); arr[i * 2 + 1] = p.y() }
            }
            // Colour-free width estimate from the hand itself (index knuckle <-> pinky knuckle).
            palmWidthPx = kotlin.math.hypot(
                (pts[17].x() - pts[5].x()) * w.toDouble(),
                (pts[17].y() - pts[5].y()) * h.toDouble(),
            )

            // Where does the forearm really point, and how wide is the arm? (Needs the picture this
            // result was computed from; hand axis / palm width are only fallbacks.)
            var armDelta = 0.0
            basis = ArmAxis.handBasis(pts, w, h)
            if (armDetect || autoFit) {
                if (armTick++ % 3 == 0 || cachedSkin == null) {
                    val picture = findFrame(result.timestampMs())
                    val t0 = SystemClock.elapsedRealtimeNanos()
                    cachedSkin = if (picture != null) ArmAxis.estimate(picture, pts) else null
                    armMs = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000
                }
                skin = cachedSkin
            }
            if (armDetect) {
                val est = skin
                if (est != null && est.armOk) {
                    armDelta = armFilter.filter(est.deltaRad, now / 1000.0)
                    armInfo = "arm=%+.0f\u00B0 conf=%.2f".format(Math.toDegrees(armDelta), est.confidence)
                } else {
                    armFilter.reset()
                    armInfo = "arm=none (hand axis)"
                }
            } else {
                armFilter.reset()
                armInfo = "arm=off (hand axis)"
            }
            raw = PoseMath.estimate(result, w, h, focalPx, armDelta)
            smooth = when {
                raw == null -> null
                smoothingEnabled -> filter.apply(raw, now / 1000.0)
                else -> raw
            }
        } else {
            filter.reset() // hand lost: don't smooth from a stale pose
            stableLeft = null
            flipCount = 0
            rawLabel = "-"
            armFilter.reset()
            armInfo = "arm=-"
            cachedSkin = null
            armTick = 0
            shiftXFilter.reset()
            shiftYFilter.reset()
        }

        // Left/right: tested on-device with the back camera, MediaPipe's label already matches the
        // real hand (label "Left" for a left hand), so no inversion. "Swap L/R" flips it if some
        // other phone/camera turns out to be the other way round. Require 6 consecutive disagreeing
        // frames before the stable side changes, so it doesn't flicker.
        if (lm != null && result.handedness().isNotEmpty() && result.handedness()[0].isNotEmpty()) {
            rawLabel = result.handedness()[0][0].categoryName()
            val observedLeft = (rawLabel == "Left") != swapHand
            val cur = stableLeft
            if (cur == null) {
                stableLeft = observedLeft
                flipCount = 0
            } else if (observedLeft == cur) {
                flipCount = 0
            } else if (++flipCount >= 6) {
                stableLeft = observedLeft
                flipCount = 0
            }
        }

        // ---- fit the watch to the arm -------------------------------------------------------
        // Only when the BACK of the hand faces the camera (otherwise the visible width is the
        // wrist's thickness, not its width). Skin measurement if it passes a sanity check against
        // the palm width, else the palm-based estimate.
        var fitW = Double.NaN
        var fitSx = 0.0
        var fitSy = 0.0
        var fitInfo = "fit=off"
        if (autoFit) {
            fitInfo = "fit=-"
            val sideSign = when (stableLeft) { true -> 1.0; false -> -1.0; null -> 0.0 }
            val sm = smooth
            val facing = sm != null && sideSign != 0.0 && sm.zAxis[2] * sideSign < -0.6
            if (sm != null && !facing) {
                fitInfo = "fit=hold (hand turned)"
            } else if (sm != null) {
                val fallback = 0.85 * palmWidthPx // knuckle-to-knuckle -> wrist width, typical ratio
                val sk = skin
                val bs = basis
                val skinW = if (sk != null && bs != null && sk.widthLines >= 3 && !sk.widthRel.isNaN()) {
                    sk.widthRel * bs[0] // relative width x CURRENT palm length: valid even between re-measurements
                } else Double.NaN
                if (sk != null && bs != null && !skinW.isNaN() &&
                    skinW >= 0.7 * fallback && skinW <= 1.35 * fallback
                ) {
                    fitW = skinW * 1.02 // strap hugs the skin edge
                    // Arm axis the offset was measured against, and its perpendicular.
                    val ang = if (sk.armOk) sk.deltaRad else 0.0
                    val ax = bs[1] * kotlin.math.cos(ang) - bs[2] * kotlin.math.sin(ang)
                    val ay = bs[1] * kotlin.math.sin(ang) + bs[2] * kotlin.math.cos(ang)
                    val off = sk.offsetRel * bs[0]
                    val t = now / 1000.0
                    fitSx = shiftXFilter.filter(-ay * off, t)
                    fitSy = shiftYFilter.filter(ax * off, t)
                    fitInfo = "fit=skin %.0fpx (%d lines)".format(skinW, sk.widthLines)
                } else if (fallback > 0.0) {
                    fitW = fallback
                    shiftXFilter.reset()
                    shiftYFilter.reset()
                    fitInfo = "fit=palm %.0fpx".format(fallback)
                }
            }
        }

        val depth = smooth?.let { "%.0f cm".format(it.origin[2] * 100) } ?: "-"
        val side = when (stableLeft) { true -> "L"; false -> "R"; null -> "-" }
        val hud = "delegate=$delegateName  landmarks/s=$resultFps  latency=${latencyMs}ms  prep=${prepMs}ms arm=${armMs}ms\n" +
            "hand=$side(label $rawLabel)  depth=$depth  smoothing=${if (smoothingEnabled) "on" else "off"}  f=%.0fpx (${focalSource})".format(focalPx) + "\n$armInfo  $fitInfo"

        onFrame(TrackingFrame(w, h, false, lm, raw, smooth, hud, stableLeft, fitW, fitSx, fitSy))
    }
}