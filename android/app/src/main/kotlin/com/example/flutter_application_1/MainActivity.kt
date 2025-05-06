package com.example.flutter_application_1

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val REQUEST_PERMISSIONS_CODE = 100
        private const val REQUEST_USAGE_STATS_CODE = 101

        // Static references accessible to other components
        lateinit var flutterEngine: FlutterEngine
            private set
        lateinit var activity: Activity
            private set
        var methodChannel: MethodChannel? = null

        // Permission request callback
        private var pendingPermissionCallback: ((Boolean) -> Unit)? = null
    }

    private lateinit var screenshotMethodChannel: ScreenshotMethodChannel
    private lateinit var googleDriveImplementation: GoogleDriveImplementation
    private lateinit var appUsageMethodChannel: AppUsageMethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Store static references
        Companion.flutterEngine = flutterEngine
        Companion.activity = this

        // Initialize the method channels
        screenshotMethodChannel = ScreenshotMethodChannel(this)
        googleDriveImplementation = GoogleDriveImplementation(this)

        // Initialize the app usage method channel
        appUsageMethodChannel = AppUsageMethodChannel(this)

        // Check and restore service state if it was running before app restart
        Handler(Looper.getMainLooper()).postDelayed({
            restoreServiceState()
        }, 2000) // Short delay to ensure Flutter is ready
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity created")

        // Initialize notifications channel for Android O+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            initNotificationChannels()
        }

        // Request necessary permissions
        checkAndRequestPermissions()
    }

    private fun initNotificationChannels() {
        // This is already handled in ScreenshotService when it starts
        // but we could initialize it here too if needed
    }

    private fun restoreServiceState() {
        try {
            val prefs = getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
            val isServiceRunning = prefs.getBoolean("is_service_running", false)

            if (isServiceRunning) {
                Log.d(TAG, "Attempting to restore screenshot service state")

                // If service was running before, notify Flutter to update UI
                val userId = prefs.getString("user_id", "")
                val childId = prefs.getString("child_id", "")
                val intervalSeconds = prefs.getInt("interval_seconds", 10)

                if (!userId.isNullOrEmpty() && !childId.isNullOrEmpty()) {
                    val serviceStatus = mapOf(
                        "isRunning" to isServiceRunning,
                        "userId" to userId,
                        "childId" to childId,
                        "intervalSeconds" to intervalSeconds
                    )

                    // Notify Flutter of restored service state
                    methodChannel?.invokeMethod("onServiceStateRestored", serviceStatus)
                }
            }

            // Check if app usage tracking was enabled and restore it
            val isUsageTrackingEnabled = prefs.getBoolean("is_usage_tracking_enabled", false)
            if (isUsageTrackingEnabled) {
                val usageIntervalSeconds = prefs.getInt("usage_interval_seconds", 60)
                appUsageMethodChannel.startUsageTracking(usageIntervalSeconds)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error restoring service state: ${e.message}")
        }
    }

    private fun checkAndRequestPermissions() {
        val permissionsToRequest = mutableListOf<String>()

        // Check notification permission for Android 13+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!PermissionUtils.hasNotificationPermission(this)) {
                permissionsToRequest.add(android.Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // Check storage permission for versions that need it
        if (!PermissionUtils.hasStoragePermission(this)) {
            permissionsToRequest.add(android.Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

        // Request necessary permissions if any
        if (permissionsToRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissionsToRequest.toTypedArray(),
                REQUEST_PERMISSIONS_CODE
            )
        }

        // Check overlay permission and request if needed
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            // We'll handle this via method channel when needed
        }

        // For usage stats permission, we'll handle it separately when needed
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == REQUEST_PERMISSIONS_CODE) {
            // Check if all permissions were granted
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }

            // Notify Flutter about permission results
            methodChannel?.invokeMethod("onPermissionsResult", mapOf("granted" to allGranted))

            // Call any pending permission callback
            pendingPermissionCallback?.invoke(allGranted)
            pendingPermissionCallback = null
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        // Handle screenshot service media projection permission result
        screenshotMethodChannel.handleActivityResult(requestCode, resultCode, data)

        // Handle usage stats permission result
        if (requestCode == REQUEST_USAGE_STATS_CODE) {
            val appUsageManager = AppUsageManager(this)
            val hasPermission = appUsageManager.hasUsageStatsPermission()

            // Notify Flutter about usage stats permission result
            methodChannel?.invokeMethod("onUsageStatsPermissionResult",
                mapOf("granted" to hasPermission))
        }
    }

    fun requestPermissionsWithCallback(permissions: Array<String>, callback: (Boolean) -> Unit) {
        pendingPermissionCallback = callback
        ActivityCompat.requestPermissions(this, permissions, REQUEST_PERMISSIONS_CODE)
    }

    // Save app usage tracking state
    fun saveUsageTrackingState(isEnabled: Boolean, intervalSeconds: Int) {
        val prefs = getSharedPreferences("screenshot_service_prefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("is_usage_tracking_enabled", isEnabled)
            .putInt("usage_interval_seconds", intervalSeconds)
            .apply()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "MainActivity destroyed")
    }
}