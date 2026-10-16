package com.urbanetime.virtuwatch

import android.content.Context
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
        watch.submit(it)
        overlay.update(it)
    }
    private val channel = MethodChannel(messenger, "tryon/camera_view_$viewId")

    init {
        root.addView(previewView, FrameLayout.LayoutParams(-1, -1))
        root.addView(watchView, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "switchCamera" -> { tracker.switchCamera(); result.success(null) }
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
                        result.success(watch.loadModel(path, fit))
                    }
                }
                "swapHand" -> {
                    tracker.swapHand = !tracker.swapHand
                    result.success(tracker.swapHand)
                }
                else -> result.notImplemented()
            }
        }
        watch.start()
        tracker.start()
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        tracker.stop()
        watch.stop()
    }
}

class TryOnViewFactory(
    private val owner: LifecycleOwner,
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        TryOnPlatformView(context, owner, messenger, viewId)
}