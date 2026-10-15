package com.urbanetime.virtuwatch

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // AR try-on: native CameraX + MediaPipe + Filament view (see TryOnPlatformView.kt).
        // FlutterActivity is a LifecycleOwner, which CameraX binds to.
        flutterEngine.platformViewsController.registry
            .registerViewFactory("tryon/camera_view", TryOnViewFactory(this, messenger))

        MethodChannel(messenger, "tryon/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCamera" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        // Resolve any stale pending request so its Dart future isn't left hanging.
                        pendingPermissionResult?.success(false)
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST) {
            pendingPermissionResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            )
            pendingPermissionResult = null
        }
    }

    private companion object {
        const val CAMERA_PERMISSION_REQUEST = 1001
    }
}
