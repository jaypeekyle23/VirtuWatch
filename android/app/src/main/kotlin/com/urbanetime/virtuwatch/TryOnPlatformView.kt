package com.urbanetime.virtuwatch

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class TryOnPlatformView(
    context: Context,
    owner: LifecycleOwner,
    messenger: BinaryMessenger,
    viewId: Int,
) : PlatformView {
    private val root = FrameLayout(context)
    private val previewView = PreviewView(context).apply {
        // COMPATIBLE = TextureView: plays nicely inside Flutter platform views.
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    // Transparent layer the watch is drawn on, between the camera preview and the debug overlay.
    private val watchView = TextureView(context)
    private val watch = WatchRenderer(context, watchView)
    private val overlay = TryOnOverlayView(context)
    private val tracker = HandTracker(context, owner, previewView) {
        // Called on MediaPipe's thread; an exception escaping here would crash the app.
        try {
            watch.submit(it)
            overlay.update(it)
        } catch (e: Throwable) {
            Log.e("TryOnPlatformView", "frame handling failed: ${e.message}", e)
        }
    }
    private val channel = MethodChannel(messenger, "tryon/camera_view_$viewId")
    private val ctx = context
    private val ioExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        root.addView(previewView, FrameLayout.LayoutParams(-1, -1))
        root.addView(watchView, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "capturePhoto" -> {
                    try {
                        capturePhoto(result)
                    } catch (e: Throwable) {
                        Log.e("TryOnPlatformView", "capturePhoto failed: ${e.message}", e)
                        result.error("capture_failed", e.message, null)
                    }
                }
                "setSmoothing" -> {
                    tracker.smoothingEnabled = call.arguments as? Boolean ?: true
                    result.success(null)
                }
                "setWatchScale" -> {
                    watch.userScale = (call.arguments as? Number)?.toDouble() ?: 1.0
                    result.success(null)
                }
                "setForearmOffset" -> {
                    watch.forearmOffsetM = (call.arguments as? Number)?.toDouble() ?: 0.03
                    result.success(null)
                }
                "setDebug" -> {
                    overlay.debugVisible = call.arguments as? Boolean ?: true
                    result.success(null)
                }
                "setGpu" -> {
                    tracker.setGpu(call.arguments as? Boolean ?: true)
                    result.success(null)
                }
                "setLead" -> {
                    watch.leadSec = ((call.arguments as? Number)?.toDouble() ?: 70.0) / 1000.0
                    result.success(null)
                }
                "setAutoFit" -> {
                    val on = call.arguments as? Boolean ?: true
                    tracker.autoFit = on
                    watch.autoFit = on
                    result.success(null)
                }
                "setArmDetect" -> {
                    tracker.armDetect = call.arguments as? Boolean ?: true
                    result.success(null)
                }
                "loadModel" -> {
                    val path = call.argument<String>("path")
                    val fit = ModelFit.fromMap(call.argument<Map<*, *>>("fit"))
                    if (path == null || fit == null) {
                        result.error("bad_args", "loadModel needs a path and a valid fit", null)
                    } else {
                        try {
                            result.success(watch.loadModel(path, fit))
                        } catch (e: Throwable) {
                            Log.e("TryOnPlatformView", "loadModel failed: ${e.message}", e)
                            result.error("load_failed", e.message, null)
                        }
                    }
                }
                "swapHand" -> {
                    tracker.swapHand = !tracker.swapHand
                    result.success(tracker.swapHand)
                }
                else -> result.notImplemented()
            }
        }
        // Started separately so a failure in one (renderer or camera) can't stop the view from
        // being created at all, which would crash the screen.
        try { watch.start() } catch (e: Throwable) { Log.e("TryOnPlatformView", "renderer failed to start: ${e.message}", e) }
        try { tracker.start() } catch (e: Throwable) { Log.e("TryOnPlatformView", "tracker failed to start: ${e.message}", e) }
    }

    override fun getView(): View = root

    /**
     * Saves what the user sees (camera picture + the watch drawn on top, without the debug overlay)
     * to the gallery. The two views are grabbed here on the main thread; stacking them, encoding and
     * writing the file happen on a background thread. [result] is answered on the main thread.
     */
    private fun capturePhoto(result: MethodChannel.Result) {
        val camera = previewView.bitmap
        if (camera == null) {
            result.error("capture_failed", "The camera isn't ready yet.", null)
            return
        }
        val watchLayer = try { watchView.bitmap } catch (e: Throwable) { null }
        val w = camera.width
        val h = camera.height
        ioExecutor.execute {
            try {
                val photo = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(photo)
                canvas.drawBitmap(camera, 0f, 0f, null)
                if (watchLayer != null) canvas.drawBitmap(watchLayer, null, Rect(0, 0, w, h), null)
                camera.recycle()
                watchLayer?.recycle()
                saveToGallery(photo)
                photo.recycle()
                mainHandler.post { result.success(true) }
            } catch (e: Throwable) {
                Log.e("TryOnPlatformView", "save failed: ${e.message}", e)
                mainHandler.post { result.error("capture_failed", e.message, null) }
            }
        }
    }

    /** Writes [bmp] as a JPEG into Pictures/VirtuWatch, visible in the gallery app. */
    @Suppress("DEPRECATION")
    private fun saveToGallery(bmp: Bitmap) {
        val name = "VirtuWatch_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".jpg"
        val resolver = ctx.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/VirtuWatch")
            values.put(MediaStore.Images.Media.IS_PENDING, 1)
        } else {
            // Android 7-9: no scoped storage; needs WRITE_EXTERNAL_STORAGE (requested from Dart first).
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "VirtuWatch")
            if (!dir.exists() && !dir.mkdirs()) throw IllegalStateException("Couldn't create the Pictures/VirtuWatch folder")
            values.put(MediaStore.Images.Media.DATA, File(dir, name).absolutePath)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Couldn't create the image file")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IllegalStateException("Couldn't open the image file")
            out.use {
                if (!bmp.compress(Bitmap.CompressFormat.JPEG, 95, it)) {
                    throw IllegalStateException("Couldn't encode the photo")
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val done = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                resolver.update(uri, done, null, null)
            }
        } catch (e: Throwable) {
            try { resolver.delete(uri, null, null) } catch (ignored: Throwable) {}
            throw e
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        try { tracker.stop() } catch (e: Throwable) { Log.e("TryOnPlatformView", "tracker stop failed: ${e.message}", e) }
        try { watch.stop() } catch (e: Throwable) { Log.e("TryOnPlatformView", "renderer stop failed: ${e.message}", e) }
        ioExecutor.shutdown() // a photo already being saved still finishes
    }
}

class TryOnViewFactory(
    private val owner: LifecycleOwner,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        TryOnPlatformView(context, owner, messenger, viewId)
}