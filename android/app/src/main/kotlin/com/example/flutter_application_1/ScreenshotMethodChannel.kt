package com.example.flutter_application_1

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class ScreenshotMethodChannel(private val activity: Activity) : MethodCallHandler {
    companion object {
        private const val TAG = "ScreenshotMethodChannel"
        private const val CHANNEL_NAME = "owl_watch_screenshot_service"
        private const val REQUEST_MEDIA_PROJECTION = 1000

        // Store the result for later use
        private var pendingResult: Result? = null
        private var pendingParams: Map<String, Any>? = null
    }

    private val methodChannel: MethodChannel

    init {
        methodChannel = MethodChannel(MainActivity.flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        MainActivity.methodChannel = methodChannel
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "Method call received: ${call.method}")

        when (call.method) {
            "startScreenshotService" -> {
                val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 10
                val userId = call.argument<String>("userId")
                val childId = call.argument<String>("childId")

                if (userId.isNullOrEmpty() || childId.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENTS", "userId and childId are required", null)
                    return
                }

                // Save params for after permission request
                pendingResult = result
                pendingParams = mapOf(
                    "intervalSeconds" to intervalSeconds,
                    "userId" to userId,
                    "childId" to childId
                )

                // Request media projection permission
                requestMediaProjectionPermission()
            }
            "stopScreenshotService" -> {
                stopScreenshotService()
                result.success(true)
            }
            "getServiceStatus" -> {
                val status = getServiceStatus()
                result.success(status)
            }
            "saveServiceState" -> {
                val isServiceRunning = call.argument<Boolean>("isServiceRunning") ?: false
                val userId = call.argument<String>("userId")
                val childId = call.argument<String>("childId")
                val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 10

                saveServiceState(isServiceRunning, userId, childId, intervalSeconds)
                result.success(true)
            }
            "checkPermissions" -> {
                val permissions = checkPermissions()
                result.success(permissions)
            }
            "openAppSettings" -> {
                openAppSettings()
                result.success(true)
            }
            "requestOverlayPermission" -> {
                requestOverlayPermission()
                result.success(true)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun requestMediaProjectionPermission() {
        val projectionManager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        activity.startActivityForResult(
            projectionManager.createScreenCaptureIntent(),
            REQUEST_MEDIA_PROJECTION
        )
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // Save projection data for service use
                ScreenshotService.setMediaProjectionData(resultCode, data)

                // Start the service with pending parameters
                startScreenshotService(
                    pendingParams?.get("intervalSeconds") as Int,
                    pendingParams?.get("userId") as String,
                    pendingParams?.get("childId") as String
                )

                pendingResult?.success(true)
            } else {
                // Notify Flutter that projection permission was denied
                methodChannel.invokeMethod("onMediaProjectionDenied", null)
                pendingResult?.success(false)
            }

            // Clear pending data
            pendingResult = null
            pendingParams = null
        }
    }

    private fun startScreenshotService(intervalSeconds: Int, userId: String, childId: String) {
        val serviceIntent = Intent(activity, ScreenshotService::class.java).apply {
            putExtra("intervalSeconds", intervalSeconds)
            putExtra("userId", userId)
            putExtra("childId", childId)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(serviceIntent)
        } else {
            activity.startService(serviceIntent)
        }

        Log.d(TAG, "Screenshot service started with interval $intervalSeconds seconds")
    }

    private fun stopScreenshotService() {
        activity.stopService(Intent(activity, ScreenshotService::class.java))
        Log.d(TAG, "Screenshot service stopped")
    }

    private fun getServiceStatus(): Map<String, Any> {
        val prefs = activity.getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
        val isRunning = prefs.getBoolean("is_service_running", false)
        val childId = prefs.getString("child_id", "")
        val userId = prefs.getString("user_id", "")
        val intervalSeconds = prefs.getInt("interval_seconds", 10)

        return mapOf(
            "isRunning" to isRunning,
            "childId" to (childId ?: ""),
            "userId" to (userId ?: ""),
            "intervalSeconds" to intervalSeconds
        )
    }

    private fun saveServiceState(isRunning: Boolean, userId: String?, childId: String?, intervalSeconds: Int) {
        val prefs = activity.getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean("is_service_running", isRunning)
            putString("user_id", userId)
            putString("child_id", childId)
            putInt("interval_seconds", intervalSeconds)
            apply()
        }
    }

    private fun checkPermissions(): Map<String, Boolean> {
        val notificationsPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            PermissionUtils.hasNotificationPermission(activity)
        } else {
            true
        }

        val storagePermission = PermissionUtils.hasStoragePermission(activity)
        val overlayPermission = Settings.canDrawOverlays(activity)

        return mapOf(
            "notifications" to notificationsPermission,
            "storage" to storagePermission,
            "overlay" to overlayPermission
        )
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", activity.packageName, null)
        }
        activity.startActivity(intent)
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(activity)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")
            )
            activity.startActivity(intent)
        }
    }
}