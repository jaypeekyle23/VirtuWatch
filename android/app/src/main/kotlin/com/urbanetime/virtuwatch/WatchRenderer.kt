package com.urbanetime.virtuwatch

import android.content.Context
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import android.view.TextureView
import com.google.android.filament.Box
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Filament
import com.google.android.filament.IndexBuffer
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Material
import com.google.android.filament.RenderableManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.VertexBuffer
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.Gltfio
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.KTX1Loader
import com.google.android.filament.utils.Utils
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Draws a watch on the tracked wrist with Filament, on a transparent TextureView stacked over the
 * camera preview. The model is supplied at runtime through [loadModel]; until then nothing is drawn.
 *
 * Model frame every watch must follow (each model's strap opening is described by a [ModelFit]):
 * the strap is a closed ring.
 *   +X = out of the wrist (watch face normal)
 *   +Z = ring axis = along the forearm, toward the elbow (crown points to -Z, toward the hand)
 *   +Y = across the wrist (12 o'clock direction)
 * The ring's inner opening (where the wrist goes) is centred at (holeCx, 0, 0) with half-sizes
 * holeHalfX (x) by holeHalfY (y) model units.
 *
 * A depth-only elliptical cylinder fills that opening, so the part of the strap that passes
 * *behind* the wrist is hidden, like a real watch.
 *
 * Everything here runs on the main thread except [submit], which is called from MediaPipe's thread.
 */
class WatchRenderer(
    private val context: Context,
    private val textureView: TextureView,
) {
    private val tag = "WatchRenderer"

    // ---- tunables --------------------------------------------------------
    /** Multiplier on the default watch size (UI slider). */
    @Volatile var userScale = 1.0
    /** Distance from the wrist landmark up the forearm to the watch centre, metres (UI slider). */
    @Volatile var forearmOffsetM = 0.017

    /** Size/centre the watch to the arm measured in the image (the sliders then act as small corrections). */
    @Volatile var autoFit = true
    private val fitMin = 0.8                  // never shrink/grow the whole watch beyond this range:
    private val fitMax = 1.25                 // a 40 mm case shouldn't turn into a 50 mm one
    private val fitTauSec = 0.5               // slow, so the watch doesn't pulse in size
    @Volatile private var fitTargetRatio = 1.0
    private var fitRatio = 1.0                // main thread only

    private val wristWidthM = 0.058           // average adult wrist width
    /** Everything is drawn this much bigger than the measured fit: the plain fit looked ~10 % small on real wrists. */
    private val sizeBoost = 1.10

    // ---- inspect mode (wrist tracking off) --------------------------------------------------
    // The watch is shown whole (no wrist occluder), centred on screen, and the person turns and
    // zooms it with their fingers. All of this runs on the main thread.
    @Volatile private var inspectMode = false
    private val inspectQ = doubleArrayOf(0.0, 0.0, 0.0, 1.0)
    private var inspectScale = INSPECT_DEFAULT_SCALE
    private var inspectPanX = 0.0
    private var inspectPanY = 0.0

    /**
     * Strap-opening geometry of the watch currently loaded, in that model's own units. It is
     * replaced as ONE immutable object by [loadModel] (main thread) and read by [submit] (MediaPipe
     * thread), so a swap can never be seen half-applied. Before the first model loads nothing is
     * drawn and these values are unused.
     */
    @Volatile private var fit = ModelFit.SEIKO
    /**
     * How far ahead (seconds) to push the pose beyond the age it already has when drawn. The pose
     * is ~60-100 ms old on arrival (camera + inference + filtering), so without this the watch
     * trails a moving hand. 0 = off. (UI slider "Lead".)
     */
    @Volatile var leadSec = 0.07
    // Adaptive follow ("soft deadband"): a still hand's measurement noise (sub-mm / sub-degree) is
    // followed very slowly so the watch stays put; real movement is followed quickly.
    private val tauRestSec = 0.25
    private val tauMoveSec = 0.02

    // ---- pose handed over from the tracker thread -------------------------
    private class Target(
        val posGl: DoubleArray,
        val q: DoubleArray,
        val visible: Boolean,
        /** When this measurement arrived (System.nanoTime base, seconds). */
        val tArrSec: Double,
        /** Smoothed linear velocity, metres/s (GL camera space). */
        val vel: DoubleArray,
        /** Smoothed angular velocity, rad/s, world frame. */
        val omega: DoubleArray,
    )

    @Volatile private var target: Target? = null
    // Sensible defaults (portrait 4:3 analysis image, ~68 deg lens) so the renderer can draw before the
    // tracker has reported anything, e.g. when tracking is switched off right away (inspect mode).
    @Volatile private var imgW = 480
    @Volatile private var imgH = 640
    @Volatile private var focalPx = 0.0

    // ---- Filament objects ---------------------------------------------------
    private var engine: Engine? = null
    private var renderer: Renderer? = null
    private var scene: Scene? = null
    private var view: View? = null
    private var camera: Camera? = null
    private var swapChain: SwapChain? = null
    private var uiHelper: UiHelper? = null
    private var viewportW = 0
    private var viewportH = 0

    private var assetLoader: AssetLoader? = null
    private var resourceLoader: ResourceLoader? = null
    private var provider: UbershaderProvider? = null
    private var watchAsset: FilamentAsset? = null

    private var indirectLight: IndirectLight? = null
    private var sunEntity = 0

    private var occluderEntity = 0
    private var occluderMaterial: Material? = null
    private var occluderVb: VertexBuffer? = null
    private var occluderIb: IndexBuffer? = null

    private var choreographer: Choreographer? = null
    private var frameCallback: Choreographer.FrameCallback? = null
    private var lastFrameNs = 0L

    // smoothed state (main thread only)
    private val curPos = DoubleArray(3)
    private val curQ = doubleArrayOf(0.0, 0.0, 0.0, 1.0)
    private var shown = false

    // Render only when something changed: a steady hand then costs the GPU nothing, which leaves it
    // to hand tracking (they share the GPU). A frame is still forced once a second as a safety net.
    private var needsRender = true
    private val lastM = FloatArray(16)
    private var lastProjA = 0.0
    private var lastProjB = 0.0
    private var lastRenderNs = 0L

    // ======================================================================
    // Pose in
    // ======================================================================

    /** Called from the MediaPipe thread with each new tracking result. */
    fun submit(frame: TrackingFrame) {
        if (inspectMode) return // tracking is off: the watch stays where the person put it
        if (frame.imgW > 0 && frame.imgH > 0) {
            imgW = frame.imgW
            imgH = frame.imgH
        }
        val pose = frame.pose
        val isLeft = frame.isLeftHand
        if (pose == null || isLeft == null) {
            target = null
            return
        }
        imgW = pose.imgW
        imgH = pose.imgH
        focalPx = pose.focalPx

        // zAxis = x cross y is the BACK-of-hand normal for a left hand and the palm normal for a
        // right hand, so flip it for right hands.
        val sign = if (isLeft) 1.0 else -1.0
        val n = doubleArrayOf(pose.zAxis[0] * sign, pose.zAxis[1] * sign, pose.zAxis[2] * sign)
        val f = pose.yAxis
        // The watch model's +Z is its ring axis and its crown sits at -Z.
        //  - Left wrist: crown toward the hand  => +Z points toward the elbow (along f).
        //  - Right wrist: a watch is worn turned around, crown toward the ELBOW (so 12 o'clock still
        //    points to the pinky side and the dial reads upright) => +Z points toward the hand.
        // Without this the right-hand watch was rotated 180 deg about its face, i.e. upside down.
        val axisZ = if (isLeft) f else doubleArrayOf(-f[0], -f[1], -f[2])
        val ym = PoseMath.cross(axisZ, n)

        // Fit to the measured arm. The width is in image pixels and the watch is drawn at the same
        // depth, so any error in the depth estimate cancels: the strap spans the arm on screen.
        var shiftX = 0.0
        var shiftY = 0.0
        val fw = frame.fitWidthPx
        if (autoFit && !fw.isNaN()) {
            val zc = pose.origin[2]
            val holeWidth = fit.holeWidth // read once: a model swap may happen on the main thread
            val metresPerUnit = fw * zc / (pose.focalPx * holeWidth)
            fitTargetRatio = (metresPerUnit / (wristWidthM / holeWidth)).coerceIn(fitMin, fitMax)
            shiftX = frame.fitShiftX * zc / pose.focalPx // centre on the arm, sideways
            shiftY = frame.fitShiftY * zc / pose.focalPx
        }

        // Watch centre: wrist landmark moved up the forearm (and sideways onto the arm's centre line).
        val off = forearmOffsetM
        val wCv = doubleArrayOf(
            pose.origin[0] + f[0] * off + shiftX,
            pose.origin[1] + f[1] * off + shiftY,
            pose.origin[2] + f[2] * off,
        )

        // Camera space here is OpenCV-style (x right, y down, z forward); Filament wants
        // OpenGL-style (x right, y up, z backward): negate y and z.
        fun gl(v: DoubleArray) = doubleArrayOf(v[0], -v[1], -v[2])
        val q = quatFromColumns(gl(n), gl(ym), gl(axisZ))
        val posGl = gl(wCv)
        val nowSec = System.nanoTime() / 1e9

        // Velocity from the previous measurement (lightly smoothed), used to extrapolate forward.
        val vel = DoubleArray(3)
        val omega = DoubleArray(3)
        val prev = target
        if (prev != null && prev.visible) {
            val dtp = nowSec - prev.tArrSec
            if (dtp in 0.02..0.25) {
                for (i in 0 until 3) {
                    val vNew = (posGl[i] - prev.posGl[i]) / dtp
                    vel[i] = 0.65 * prev.vel[i] + 0.35 * vNew
                }
                // dq = q * conj(prevQ): the rotation that took the old orientation to the new one.
                val a = q
                val b = doubleArrayOf(-prev.q[0], -prev.q[1], -prev.q[2], prev.q[3])
                var dx = a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1]
                var dy = a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0]
                var dz = a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3]
                var dw = a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]
                if (dw < 0) { dx = -dx; dy = -dy; dz = -dz; dw = -dw } // shortest way round
                val vlen = sqrt(dx * dx + dy * dy + dz * dz)
                if (vlen > 1e-9) {
                    val angle = 2.0 * kotlin.math.atan2(vlen, dw)
                    for (i in 0 until 3) {
                        val axis = doubleArrayOf(dx, dy, dz)[i] / vlen
                        omega[i] = 0.65 * prev.omega[i] + 0.35 * (axis * angle / dtp)
                    }
                } else {
                    for (i in 0 until 3) omega[i] = 0.65 * prev.omega[i]
                }
            }
        }
        // Always visible. With the palm toward the camera the wrist-shaped occluder hides the case
        // (it is behind the wrist) and you see the strap's underside with the buckle, like a real watch;
        // turning the wrist in between shows the strap wrapping around the side.
        target = Target(posGl, q, true, nowSec, vel, omega)
    }

    // ======================================================================
    // Lifecycle
    // ======================================================================

    fun start() {
        Filament.init()
        Gltfio.init()
        Utils.init()

        val eng = Engine.create()
        engine = eng
        renderer = eng.createRenderer().also {
            it.clearOptions = Renderer.ClearOptions().apply {
                clear = true
                clearColor = floatArrayOf(0f, 0f, 0f, 0f)
            }
        }
        scene = eng.createScene()
        camera = eng.createCamera(EntityManager.get().create())
        view = eng.createView().also {
            it.scene = scene
            it.camera = camera
            it.blendMode = View.BlendMode.TRANSLUCENT
        }

        setupLighting(eng)
        createLoaders(eng)

        val helper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
        helper.isOpaque = false
        helper.setRenderCallback(object : UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                val e = engine ?: return
                swapChain?.let { e.destroySwapChain(it) }
                swapChain = e.createSwapChain(surface, helper.swapChainFlags)
                needsRender = true
            }

            override fun onDetachedFromSurface() {
                val e = engine ?: return
                swapChain?.let {
                    e.destroySwapChain(it)
                    e.flushAndWait()
                }
                swapChain = null
            }

            override fun onResized(width: Int, height: Int) {
                viewportW = width
                viewportH = height
                view?.viewport = Viewport(0, 0, width, height)
                needsRender = true
            }
        })
        helper.attachTo(textureView)
        uiHelper = helper

        val choreo = Choreographer.getInstance()
        choreographer = choreo
        frameCallback = object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                // An exception here would crash the whole app from the main-thread frame loop.
                try {
                    renderFrame(frameTimeNanos)
                } catch (e: Throwable) {
                    Log.e(tag, "renderFrame failed: ${e.message}", e)
                }
                choreographer?.postFrameCallback(this)
            }
        }
        choreo.postFrameCallback(frameCallback!!)
    }

    fun stop() {
        try {
            teardown()
        } catch (e: Throwable) {
            // Cleanup problems must never take the app down while leaving the screen.
            Log.e(tag, "teardown failed: ${e.message}", e)
        }
    }

    private fun teardown() {
        frameCallback?.let { choreographer?.removeFrameCallback(it) }
        frameCallback = null
        choreographer = null
        uiHelper?.detach()
        uiHelper = null

        val eng = engine ?: return
        val sc = scene
        eng.flushAndWait() // the GPU must be done with everything before it is destroyed

        watchAsset?.let {
            sc?.removeEntities(it.entities)
            assetLoader?.destroyAsset(it)
        }
        watchAsset = null
        if (occluderEntity != 0) {
            sc?.removeEntity(occluderEntity)
            eng.destroyEntity(occluderEntity)
            EntityManager.get().destroy(occluderEntity)
            occluderEntity = 0
        }
        occluderVb?.let { eng.destroyVertexBuffer(it) }
        occluderIb?.let { eng.destroyIndexBuffer(it) }
        occluderMaterial?.let { eng.destroyMaterial(it) }
        indirectLight?.let { eng.destroyIndirectLight(it) }
        if (sunEntity != 0) {
            sc?.removeEntity(sunEntity)
            eng.destroyEntity(sunEntity)
            EntityManager.get().destroy(sunEntity)
            sunEntity = 0
        }

        // Same order as Filament's own ModelViewer: loader, then the provider's materials, then the rest.
        assetLoader?.destroy()
        provider?.destroyMaterials()
        provider?.destroy()
        resourceLoader?.destroy()

        renderer?.let { eng.destroyRenderer(it) }
        view?.let { eng.destroyView(it) }
        sc?.let { eng.destroyScene(it) }
        camera?.let { eng.destroyCameraComponent(it.entity) }
        swapChain?.let { eng.destroySwapChain(it) }
        swapChain = null
        eng.destroy()

        engine = null; renderer = null; scene = null; view = null; camera = null
        assetLoader = null; resourceLoader = null; provider = null
        indirectLight = null; occluderMaterial = null; occluderVb = null; occluderIb = null
    }

    // ======================================================================
    // Setup helpers
    // ======================================================================

    private fun setupLighting(eng: Engine) {
        val sc = scene ?: return

        // Image-based light: a generated "studio" environment with soft boxes, so the steel and
        // glass actually have something to reflect. (assets/studio_ibl.ktx, built with cmgen.)
        try {
            val bytes = context.assets.open("studio_ibl.ktx").use { it.readBytes() }
            val buf = ByteBuffer.allocateDirect(bytes.size)
            buf.put(bytes)
            buf.flip()
            // In Filament 1.68 this returns a bundle (light + its cubemap texture), not the light itself.
            val ibl = KTX1Loader.createIndirectLight(eng, buf).indirectLight
            if (ibl != null) {
                ibl.intensity = 25000f
                sc.indirectLight = ibl
                indirectLight = ibl
            } else {
                Log.e(tag, "IBL could not be created, continuing without it")
            }
        } catch (e: Throwable) {
            Log.e(tag, "IBL failed, continuing without it: ${e.message}")
        }

        // One soft key light from upper-left-front (camera space == world space here).
        sunEntity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .direction(0.4f, -0.6f, -0.7f)
            .color(1.0f, 0.98f, 0.95f)
            .intensity(20000.0f)
            .build(eng, sunEntity)
        sc.addEntity(sunEntity)
    }

    private fun createLoaders(eng: Engine) {
        val prov = UbershaderProvider(eng)
        provider = prov
        assetLoader = AssetLoader(eng, prov, EntityManager.get())
        resourceLoader = ResourceLoader(eng)
    }

    /**
     * Replaces the watch with the GLB at [path], placed according to [newFit]. Main thread only.
     *
     * The new model is built BEFORE the old one is touched, so a corrupt or unreadable file returns
     * false and leaves whatever was showing intact.
     */
    fun loadModel(path: String, newFit: ModelFit): Boolean {
        val eng = engine ?: return false
        val loader = assetLoader ?: return false
        val resLoader = resourceLoader ?: return false
        val startedAt = System.nanoTime()

        val newAsset: FilamentAsset = try {
            // The strap is made a little bigger than the case (see StrapScaler); the file on disk is untouched.
            val bytes = StrapScaler.apply(File(path).readBytes(), newFit, STRAP_SCALE)
            val buf = ByteBuffer.allocateDirect(bytes.size)
            buf.put(bytes)
            buf.flip()
            val asset = loader.createAsset(buf) ?: run {
                Log.e(tag, "Filament could not parse $path")
                return false
            }
            try {
                resLoader.loadResources(asset)
            } catch (t: Throwable) {
                loader.destroyAsset(asset)
                throw t
            }
            asset.releaseSourceData()
            // The reshaped strap can reach past the bounding box stored in the file; never cull the watch.
            val rm = eng.renderableManager
            for (e in asset.renderableEntities) {
                val inst = rm.getInstance(e)
                if (inst != 0) rm.setCulling(inst, false)
            }
            asset
        } catch (e: Throwable) {
            Log.e(tag, "Could not load model $path: ${e.message}")
            return false
        }

        val parsedAt = System.nanoTime()

        // Swap. Hide first (takes the old watch and occluder out of the scene), wait for the GPU to
        // finish with them, then destroy.
        setShown(false)
        eng.flushAndWait()
        watchAsset?.let { loader.destroyAsset(it) }
        watchAsset = newAsset
        fit = newFit
        rebuildOccluder(eng, newFit)

        // The new asset has no transform yet, and applyTransform() skips matrices equal to the last
        // one it sent, so invalidate that cache. updateWatch() re-shows the watch on the next frame.
        lastM.fill(Float.MAX_VALUE)
        needsRender = true
        // Timing, so a slow load can be told apart from a slow download in logcat.
        Log.i(
            tag,
            "loadModel ${File(path).name}: parsed in ${(parsedAt - startedAt) / 1_000_000} ms, " +
                "swapped in ${(System.nanoTime() - parsedAt) / 1_000_000} ms"
        )
        return true
    }

    /**
     * (Re)builds the depth-only elliptical cylinder that fills the strap ring's opening (model units),
     * so the far side of the strap is hidden behind the "wrist". Priority 0 => drawn before the watch.
     * Its size comes from [f], so it is rebuilt for every model; the material is created once.
     */
    private fun rebuildOccluder(eng: Engine, f: ModelFit) {
        // Drop the previous one. Callers hide the watch first, so it is no longer in the scene.
        if (occluderEntity != 0) {
            eng.destroyEntity(occluderEntity)
            EntityManager.get().destroy(occluderEntity)
            occluderEntity = 0
        }
        occluderVb?.let { eng.destroyVertexBuffer(it) }
        occluderIb?.let { eng.destroyIndexBuffer(it) }
        occluderVb = null
        occluderIb = null

        try {
            var material = occluderMaterial
            if (material == null) {
                val matBytes = context.assets.open("occluder.filamat").use { it.readBytes() }
                val matBuf = ByteBuffer.allocateDirect(matBytes.size)
                matBuf.put(matBytes)
                matBuf.flip()
                material = Material.Builder().payload(matBuf, matBuf.remaining()).build(eng)
                occluderMaterial = material
            }

            val segs = 48
            val halfLen = 0.42f                          // along the forearm axis (watch is +-0.3 wide)
            val rx = (f.holeHalfX * STRAP_SCALE * 0.985).toFloat() // a hair inside the (enlarged) strap to avoid z-fighting
            val ry = (f.holeHalfY * STRAP_SCALE * 0.985).toFloat()
            val cx = f.holeCx.toFloat()

            val verts = FloatArray(segs * 2 * 3)
            for (i in 0 until segs) {
                val a = (2.0 * Math.PI * i / segs)
                val x = cx + rx * cos(a).toFloat()
                val y = ry * sin(a).toFloat()
                verts[(i * 2) * 3 + 0] = x
                verts[(i * 2) * 3 + 1] = y
                verts[(i * 2) * 3 + 2] = -halfLen
                verts[(i * 2 + 1) * 3 + 0] = x
                verts[(i * 2 + 1) * 3 + 1] = y
                verts[(i * 2 + 1) * 3 + 2] = halfLen
            }
            val idx = ShortArray(segs * 6)
            for (i in 0 until segs) {
                val a0 = i * 2
                val a1 = i * 2 + 1
                val b0 = ((i + 1) % segs) * 2
                val b1 = b0 + 1
                idx[i * 6 + 0] = a0.toShort(); idx[i * 6 + 1] = b0.toShort(); idx[i * 6 + 2] = a1.toShort()
                idx[i * 6 + 3] = b0.toShort(); idx[i * 6 + 4] = b1.toShort(); idx[i * 6 + 5] = a1.toShort()
            }

            val vbData = ByteBuffer.allocateDirect(verts.size * 4).order(ByteOrder.nativeOrder())
            vbData.asFloatBuffer().put(verts)
            val ibData = ByteBuffer.allocateDirect(idx.size * 2).order(ByteOrder.nativeOrder())
            ibData.asShortBuffer().put(idx)

            val vb = VertexBuffer.Builder()
                .bufferCount(1)
                .vertexCount(segs * 2)
                .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
                .build(eng)
            vb.setBufferAt(eng, 0, vbData)
            val ib = IndexBuffer.Builder()
                .indexCount(idx.size)
                .bufferType(IndexBuffer.Builder.IndexType.USHORT)
                .build(eng)
            ib.setBuffer(eng, ibData)
            occluderVb = vb
            occluderIb = ib

            val e = EntityManager.get().create()
            RenderableManager.Builder(1)
                .boundingBox(Box(cx, 0f, 0f, rx, ry, halfLen))
                .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vb, ib)
                .material(0, material.defaultInstance)
                .culling(false)
                .castShadows(false)
                .receiveShadows(false)
                .priority(0)
                .build(eng, e)
            occluderEntity = e
        } catch (e: Throwable) {
            Log.e(tag, "Could not create occluder: ${e.message}")
        }
    }

    // ======================================================================
    // Per-frame
    // ======================================================================

    private fun renderFrame(frameTimeNanos: Long) {
        val rend = renderer ?: return
        val v = view ?: return
        val sc = swapChain ?: return
        val cam = camera ?: return
        val fpx = effectiveFocalPx()
        if (viewportW == 0 || viewportH == 0 || imgW == 0 || fpx <= 0.0) return

        val dt = if (lastFrameNs == 0L) 0.016 else ((frameTimeNanos - lastFrameNs) / 1e9).coerceIn(0.001, 0.1)
        lastFrameNs = frameTimeNanos

        // Projection matching the preview's FILL_CENTER crop of the analysis image.
        val s = max(viewportW.toDouble() / imgW, viewportH.toDouble() / imgH)
        val a = 2.0 * s * fpx / viewportW
        val b = 2.0 * s * fpx / viewportH
        val near = 0.02
        val far = 3.0
        val p = DoubleArray(16)
        p[0] = a
        p[5] = b
        p[10] = -(far + near) / (far - near)
        p[11] = -1.0
        p[14] = -2.0 * far * near / (far - near)
        if (a != lastProjA || b != lastProjB) {
            cam.setCustomProjection(p, near, far)
            lastProjA = a
            lastProjB = b
            needsRender = true
        }

        // Ease the fit ratio toward its target (1.0 when auto-fit is off).
        val ratioTarget = if (autoFit) fitTargetRatio else 1.0
        fitRatio += (ratioTarget - fitRatio) * (1.0 - exp(-dt / fitTauSec))

        if (inspectMode) updateInspect() else updateWatch(target, dt, frameTimeNanos / 1e9)

        val force = frameTimeNanos - lastRenderNs > 1_000_000_000L
        if (!needsRender && !force) return
        if (rend.beginFrame(sc, frameTimeNanos)) {
            rend.render(v)
            rend.endFrame()
            needsRender = false
            lastRenderNs = frameTimeNanos
        }
    }

    private fun updateWatch(t: Target?, dt: Double, nowSec: Double) {
        if (t == null || !t.visible) {
            setShown(false)
            return
        }

        // Predict where the wrist is NOW: the measurement's age plus the lead. Extrapolation fades in
        // only above a small speed, otherwise measurement jitter would be amplified while the hand is still.
        val horizon = ((nowSec - t.tArrSec) + leadSec).coerceIn(0.0, 0.25)
        val speed = sqrt(t.vel[0] * t.vel[0] + t.vel[1] * t.vel[1] + t.vel[2] * t.vel[2])
        val fv = smoothstep(0.06, 0.20, speed) // m/s
        val predPos = DoubleArray(3) { t.posGl[it] + t.vel[it] * horizon * fv }

        val wn = sqrt(t.omega[0] * t.omega[0] + t.omega[1] * t.omega[1] + t.omega[2] * t.omega[2])
        val fw = smoothstep(0.60, 1.60, wn) // rad/s
        val predQ = rotateQuat(t.q, t.omega, wn, horizon * fw)

        if (!shown) {
            System.arraycopy(predPos, 0, curPos, 0, 3)
            System.arraycopy(predQ, 0, curQ, 0, 4)
            setShown(true)
        } else {
            // Position: the further the displayed pose is from the target, the faster it follows.
            val ex = predPos[0] - curPos[0]
            val ey = predPos[1] - curPos[1]
            val ez = predPos[2] - curPos[2]
            val dPos = sqrt(ex * ex + ey * ey + ez * ez)
            val tauP = tauRestSec + (tauMoveSec - tauRestSec) * smoothstep(0.0005, 0.004, dPos) // 0.5 .. 4 mm
            val kP = 1.0 - exp(-dt / tauP)
            for (i in 0 until 3) curPos[i] += (predPos[i] - curPos[i]) * kP

            // Rotation: same idea on the angle between the two orientations.
            val dot = kotlin.math.abs(
                curQ[0] * predQ[0] + curQ[1] * predQ[1] + curQ[2] * predQ[2] + curQ[3] * predQ[3]
            ).coerceAtMost(1.0)
            val dAng = 2.0 * kotlin.math.acos(dot)
            val tauR = tauRestSec + (tauMoveSec - tauRestSec) * smoothstep(0.005, 0.045, dAng) // 0.3 .. 2.6 deg
            nlerpInto(curQ, predQ, 1.0 - exp(-dt / tauR))
        }
        applyTransform()
    }

    private fun smoothstep(e0: Double, e1: Double, x: Double): Double {
        val t = ((x - e0) / (e1 - e0)).coerceIn(0.0, 1.0)
        return t * t * (3 - 2 * t)
    }

    /** q advanced by angular velocity omega (magnitude wn, rad/s) for h seconds (world frame). */
    private fun rotateQuat(q: DoubleArray, omega: DoubleArray, wn: Double, h: Double): DoubleArray {
        val angle = (wn * h).coerceAtMost(0.4) // never swing more than ~23 deg ahead
        if (angle < 1e-6 || wn < 1e-9) return q
        val sh = sin(angle / 2) / wn
        val dx = omega[0] * sh
        val dy = omega[1] * sh
        val dz = omega[2] * sh
        val dw = cos(angle / 2)
        // result = dq * q
        val rx = dw * q[0] + dx * q[3] + dy * q[2] - dz * q[1]
        val ry = dw * q[1] - dx * q[2] + dy * q[3] + dz * q[0]
        val rz = dw * q[2] + dx * q[1] - dy * q[0] + dz * q[3]
        val rw = dw * q[3] - dx * q[0] - dy * q[1] - dz * q[2]
        val len = sqrt(rx * rx + ry * ry + rz * rz + rw * rw)
        return doubleArrayOf(rx / len, ry / len, rz / len, rw / len)
    }

    private fun setShown(show: Boolean) {
        if (show == shown) return
        shown = show
        needsRender = true
        val sc = scene ?: return
        watchAsset?.let { if (show) sc.addEntities(it.entities) else sc.removeEntities(it.entities) }
        if (occluderEntity != 0) {
            if (show && !inspectMode) sc.addEntity(occluderEntity) else sc.removeEntity(occluderEntity)
        }
    }

    private fun applyTransform() {
        val eng = engine ?: return
        val f = fit
        // Inspect mode: size comes from pinch-zoom, and the model turns about its own middle, not the strap opening's.
        val scale = if (inspectMode) {
            (wristWidthM / f.holeWidth) * f.scale * sizeBoost * inspectScale
        } else {
            (wristWidthM / f.holeWidth) * userScale * fitRatio * f.scale * sizeBoost
        }
        val pivotX = if (inspectMode) 0.0 else f.holeCx

        // Rotation from quaternion (x, y, z, w).
        val x = curQ[0]; val y = curQ[1]; val z = curQ[2]; val w = curQ[3]
        val r00 = 1 - 2 * (y * y + z * z); val r01 = 2 * (x * y - z * w); val r02 = 2 * (x * z + y * w)
        val r10 = 2 * (x * y + z * w); val r11 = 1 - 2 * (x * x + z * z); val r12 = 2 * (y * z - x * w)
        val r20 = 2 * (x * z - y * w); val r21 = 2 * (y * z + x * w); val r22 = 1 - 2 * (x * x + y * y)

        // M = T(position) * R * S(scale) * T(-holeCentre); the hole centre is (holeCx, 0, 0).
        val tx = curPos[0] - r00 * scale * pivotX
        val ty = curPos[1] - r10 * scale * pivotX
        val tz = curPos[2] - r20 * scale * pivotX

        val m = floatArrayOf(
            (r00 * scale).toFloat(), (r10 * scale).toFloat(), (r20 * scale).toFloat(), 0f,
            (r01 * scale).toFloat(), (r11 * scale).toFloat(), (r21 * scale).toFloat(), 0f,
            (r02 * scale).toFloat(), (r12 * scale).toFloat(), (r22 * scale).toFloat(), 0f,
            tx.toFloat(), ty.toFloat(), tz.toFloat(), 1f,
        )

        var changed = false
        for (i in 0 until 16) {
            if (kotlin.math.abs(m[i] - lastM[i]) > 2e-5f) { changed = true; break }
        }
        if (!changed) return // identical to what is on screen: nothing for Filament to do
        System.arraycopy(m, 0, lastM, 0, 16)
        needsRender = true

        val tm = eng.transformManager
        watchAsset?.let {
            val inst = tm.getInstance(it.root)
            if (inst != 0) tm.setTransform(inst, m)
        }
        if (occluderEntity != 0) {
            // The occluder's entity needs a transform component the first time.
            if (tm.getInstance(occluderEntity) == 0) tm.create(occluderEntity)
            val inst = tm.getInstance(occluderEntity)
            if (inst != 0) tm.setTransform(inst, m)
        }
    }

    // ======================================================================
    // Inspect mode (wrist tracking off). Main thread only.
    // ======================================================================

    private fun effectiveFocalPx(): Double {
        val f = focalPx
        if (f > 0.0) return f
        val long = max(imgW, imgH).toDouble()
        return (long / 2.0) / kotlin.math.tan(Math.toRadians(68.0) / 2) // same default the tracker falls back to
    }

    /** Turns inspect mode on (tracking off) or off (back to following the wrist). */
    fun setInspectMode(on: Boolean) {
        if (inspectMode == on) return
        inspectMode = on
        if (on) {
            resetInspectView()
            // The wrist-shaped occluder would hide the far side of the strap; inspecting shows the whole watch.
            val sc = scene
            if (shown && sc != null && occluderEntity != 0) sc.removeEntity(occluderEntity)
        } else {
            // Back to live tracking: hidden until the hand is seen again, then it snaps onto the wrist.
            target = null
            setShown(false)
        }
        lastM.fill(Float.MAX_VALUE)
        needsRender = true
    }

    /** Centres the watch, faces it to the camera with a slight tilt, and resets the zoom. */
    fun resetInspectView() {
        // Face toward the camera, 12 o'clock up, crown to the right.
        val base = quatFromColumns(
            doubleArrayOf(0.0, 0.0, 1.0),
            doubleArrayOf(0.0, 1.0, 0.0),
            doubleArrayOf(-1.0, 0.0, 0.0),
        )
        val tilt = qMul(qAxisAngle(0.0, 1.0, 0.0, 0.45), qAxisAngle(1.0, 0.0, 0.0, -0.25))
        val q = qMul(tilt, base)
        System.arraycopy(q, 0, inspectQ, 0, 4)
        inspectScale = INSPECT_DEFAULT_SCALE
        inspectPanX = 0.0
        inspectPanY = 0.0
        lastM.fill(Float.MAX_VALUE)
        needsRender = true
    }

    /** One-finger drag: turn the watch like a trackball. */
    fun inspectRotateBy(dxPx: Float, dyPx: Float) {
        if (!inspectMode) return
        val k = 0.01
        val dq = qMul(qAxisAngle(0.0, 1.0, 0.0, dxPx * k), qAxisAngle(1.0, 0.0, 0.0, dyPx * k))
        val q = qMul(dq, inspectQ)
        val len = sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
        if (len < 1e-9) return
        for (i in 0 until 4) inspectQ[i] = q[i] / len
        needsRender = true
    }

    /** Pinch: multiply the zoom by [factor]. */
    fun inspectZoomBy(factor: Double) {
        if (!inspectMode || !factor.isFinite() || factor <= 0.0) return
        inspectScale = (inspectScale * factor).coerceIn(INSPECT_MIN_SCALE, INSPECT_MAX_SCALE)
        needsRender = true
    }

    /** Two-finger drag: slide the watch across the screen (so a zoomed-in detail can be brought to the middle). */
    fun inspectPanBy(dxPx: Float, dyPx: Float) {
        if (!inspectMode || viewportW == 0 || viewportH == 0) return
        val s = max(viewportW.toDouble() / imgW, viewportH.toDouble() / imgH)
        val metresPerPx = INSPECT_DEPTH_M / (s * effectiveFocalPx())
        inspectPanX = (inspectPanX + dxPx * metresPerPx).coerceIn(-0.3, 0.3)
        inspectPanY = (inspectPanY - dyPx * metresPerPx).coerceIn(-0.3, 0.3) // screen y grows downward, GL y upward
        needsRender = true
    }

    private fun updateInspect() {
        if (watchAsset == null) return
        if (!shown) setShown(true)
        curPos[0] = inspectPanX
        curPos[1] = inspectPanY
        curPos[2] = -INSPECT_DEPTH_M
        System.arraycopy(inspectQ, 0, curQ, 0, 4)
        applyTransform()
    }

    // ======================================================================
    // Quaternion helpers
    // ======================================================================

    /** a * b for quaternions (x, y, z, w). */
    private fun qMul(a: DoubleArray, b: DoubleArray): DoubleArray = doubleArrayOf(
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
    )

    private fun qAxisAngle(ax: Double, ay: Double, az: Double, angle: Double): DoubleArray {
        val s = sin(angle / 2)
        return doubleArrayOf(ax * s, ay * s, az * s, cos(angle / 2))
    }

    /** Quaternion (x,y,z,w) of the rotation whose columns are c0, c1, c2. */
    private fun quatFromColumns(c0: DoubleArray, c1: DoubleArray, c2: DoubleArray): DoubleArray {
        val r00 = c0[0]; val r10 = c0[1]; val r20 = c0[2]
        val r01 = c1[0]; val r11 = c1[1]; val r21 = c1[2]
        val r02 = c2[0]; val r12 = c2[1]; val r22 = c2[2]
        val tr = r00 + r11 + r22
        val qx: Double; val qy: Double; val qz: Double; val qw: Double
        if (tr > 0) {
            val s = sqrt(tr + 1.0) * 2
            qw = 0.25 * s; qx = (r21 - r12) / s; qy = (r02 - r20) / s; qz = (r10 - r01) / s
        } else if (r00 > r11 && r00 > r22) {
            val s = sqrt(1.0 + r00 - r11 - r22) * 2
            qw = (r21 - r12) / s; qx = 0.25 * s; qy = (r01 + r10) / s; qz = (r02 + r20) / s
        } else if (r11 > r22) {
            val s = sqrt(1.0 + r11 - r00 - r22) * 2
            qw = (r02 - r20) / s; qx = (r01 + r10) / s; qy = 0.25 * s; qz = (r12 + r21) / s
        } else {
            val s = sqrt(1.0 + r22 - r00 - r11) * 2
            qw = (r10 - r01) / s; qx = (r02 + r20) / s; qy = (r12 + r21) / s; qz = 0.25 * s
        }
        val len = sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
        return doubleArrayOf(qx / len, qy / len, qz / len, qw / len)
    }

    /** cur = normalize(lerp(cur, target, k)) taking the shortest path. */
    private fun nlerpInto(cur: DoubleArray, tgt: DoubleArray, k: Double) {
        val dot = cur[0] * tgt[0] + cur[1] * tgt[1] + cur[2] * tgt[2] + cur[3] * tgt[3]
        val sgn = if (dot < 0) -1.0 else 1.0
        var len = 0.0
        for (i in 0 until 4) {
            cur[i] = cur[i] * (1 - k) + tgt[i] * sgn * k
            len += cur[i] * cur[i]
        }
        len = sqrt(len)
        if (len > 1e-9) for (i in 0 until 4) cur[i] /= len
    }
}

/** The strap is drawn this much bigger than the case (on top of the overall size boost): 1.10 x 1.09 ~ 1.20. */
internal const val STRAP_SCALE = 1.09

// Inspect mode: how far from the camera the watch floats, and the pinch-zoom range (x default size).
private const val INSPECT_DEPTH_M = 0.5
private const val INSPECT_DEFAULT_SCALE = 2.2
private const val INSPECT_MIN_SCALE = 0.5
private const val INSPECT_MAX_SCALE = 8.0

/**
 * Where one watch model's strap opening is, in that model's own units: the centre along X, and the
 * half-sizes in X (thickness) and Y (width). Immutable, so it can be handed between threads safely.
 * [scale] is an optional per-watch size multiplier on top of the fit to the wearer's wrist.
 */
class ModelFit(
    val holeCx: Double,
    val holeHalfX: Double,
    val holeHalfY: Double,
    val scale: Double = 1.0,
) {
    val holeWidth: Double get() = 2 * holeHalfY

    companion object {
        /** The original Seiko measurements. Only a placeholder until a model is loaded. */
        val SEIKO = ModelFit(-0.057, 0.25, 0.435)

        /** Parses the map sent from Dart; null if anything is missing, non-finite or non-positive. */
        fun fromMap(m: Map<*, *>?): ModelFit? {
            if (m == null) return null
            fun num(key: String) = (m[key] as? Number)?.toDouble()?.takeIf { it.isFinite() }
            val cx = num("holeCx") ?: return null
            val hx = num("holeHalfX") ?: return null
            val hy = num("holeHalfY") ?: return null
            val sc = num("scale") ?: 1.0
            if (hx <= 0.0 || hy <= 0.0 || sc <= 0.0) return null
            return ModelFit(cx, hx, hy, sc)
        }
    }
}
