package com.urbanetime.virtuwatch

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingStorageResult: MethodChannel.Result? = null
    private val photoExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // AR try-on: native CameraX + MediaPipe + Filament view (see TryOnPlatformView.kt).
        // FlutterActivity is a LifecycleOwner, which CameraX binds to.
        flutterEngine.platformViewsController.registry
            .registerViewFactory("tryon/camera_view", TryOnViewFactory(this, messenger))

        // Deleting a try-on photo lives here rather than on the camera view's channel, so it still
        // works after the user has left the AR screen and the native view is gone.
        MethodChannel(messenger, "tryon/photos").setMethodCallHandler { call, result ->
            when (call.method) {
                "deletePhoto" -> {
                    val uri = call.argument<String>("uri")
                    val path = call.argument<String>("path")
                    photoExecutor.execute {
                        val ok = PhotoFiles.delete(this, uri, path)
                        runOnUiThread { result.success(ok) }
                    }
                }
                else -> result.notImplemented()
            }
        }

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
                // Saving a photo to the gallery needs no permission on Android 10+ (MediaStore);
                // Android 7-9 still needs WRITE_EXTERNAL_STORAGE.
                "requestStorage" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                        == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pendingStorageResult?.success(false)
                        pendingStorageResult = result
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_PERMISSION_REQUEST
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
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            pendingStorageResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            )
            pendingStorageResult = null
        }
    }

    override fun onDestroy() {
        photoExecutor.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val CAMERA_PERMISSION_REQUEST = 1001
        const val STORAGE_PERMISSION_REQUEST = 1002
    }
}
