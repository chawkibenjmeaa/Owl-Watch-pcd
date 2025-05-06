package com.example.flutter_application_1

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import java.util.*
import kotlin.collections.HashMap

class AppBlockerService : Service() {
    companion object {
        private const val TAG = "AppBlockerService"
        private const val CHECK_INTERVAL_MS = 1000L // Check every second
        private const val NOTIFICATION_CHANNEL_ID = "app_blocker_channel"
        private const val NOTIFICATION_ID = 1002

        // Intent actions
        const val ACTION_START_MONITORING = "com.example.flutter_application_1.START_MONITORING"
        const val ACTION_STOP_MONITORING = "com.example.flutter_application_1.STOP_MONITORING"
        const val ACTION_UPDATE_BLOCKED_APPS = "com.example.flutter_application_1.UPDATE_BLOCKED_APPS"

        // Intent extras
        const val EXTRA_BLOCKED_APPS = "blocked_apps"
        const val EXTRA_APP_PASSWORDS = "app_passwords"
    }

    private val handler = Handler(Looper.getMainLooper())
    private val windowManager by lazy { getSystemService(Context.WINDOW_SERVICE) as WindowManager }
    private lateinit var appUsageManager: AppUsageManager

    private var blockedApps = HashMap<String, String>() // App name to password map
    private var overlayView: View? = null
    private var currentBlockedApp: String? = null
    private var isOverlayShowing = false

    // Runnable that checks current app
    private val appCheckRunnable = object : Runnable {
        override fun run() {
            checkCurrentApp()
            handler.postDelayed(this, CHECK_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AppBlockerService created")
        appUsageManager = AppUsageManager(this)
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: ${intent?.action}")

        when (intent?.action) {
            ACTION_START_MONITORING -> {
                startForegroundAppMonitoring()
            }
            ACTION_STOP_MONITORING -> {
                stopForegroundAppMonitoring()
                stopSelf()
            }
            ACTION_UPDATE_BLOCKED_APPS -> {
                @Suppress("UNCHECKED_CAST")
                val newBlockedApps = intent.getSerializableExtra(EXTRA_BLOCKED_APPS) as? HashMap<String, String>
                if (newBlockedApps != null) {
                    blockedApps = newBlockedApps
                    Log.d(TAG, "Updated blocked apps: ${blockedApps.keys}")
                }
            }
        }

        return START_STICKY
    }

    private fun startForegroundAppMonitoring() {
        Log.d(TAG, "Starting foreground app monitoring")
        if (!hasOverlayPermission()) {
            Log.e(TAG, "Overlay permission not granted")
            return
        }

        if (!appUsageManager.hasUsageStatsPermission()) {
            Log.e(TAG, "Usage stats permission not granted")
            return
        }

        // Start checking foreground app
        handler.post(appCheckRunnable)
    }

    private fun stopForegroundAppMonitoring() {
        Log.d(TAG, "Stopping foreground app monitoring")
        handler.removeCallbacks(appCheckRunnable)
        dismissBlockingOverlay()
    }

    private fun checkCurrentApp() {
        if (!appUsageManager.hasUsageStatsPermission()) {
            Log.e(TAG, "Usage stats permission not granted")
            return
        }

        val currentApp = appUsageManager.getCurrentForegroundApp()
        Log.d(TAG, "Current app: $currentApp")

        // Check if current app is blocked
        if (currentApp != null && blockedApps.containsKey(currentApp)) {
            if (currentApp != currentBlockedApp || !isOverlayShowing) {
                currentBlockedApp = currentApp
                showBlockingOverlay(currentApp, blockedApps[currentApp] ?: "")
            }
        } else if (isOverlayShowing && (currentApp != currentBlockedApp)) {
            // App changed, remove overlay
            dismissBlockingOverlay()
        }
    }

    private fun showBlockingOverlay(appName: String, password: String) {
        if (isOverlayShowing) {
            dismissBlockingOverlay()
        }

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            getOverlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.CENTER

        // Create overlay layout - You'll need to create this layout resource
        val view = inflater.inflate(R.layout.overlay_app_blocked, null)

        val titleText = view.findViewById<TextView>(R.id.text_blocked_title)
        val passwordInput = view.findViewById<EditText>(R.id.edit_password)
        val unlockButton = view.findViewById<Button>(R.id.button_unlock)

        titleText.text = "Time's up for $appName"

        unlockButton.setOnClickListener {
            val enteredPassword = passwordInput.text.toString()
            if (enteredPassword == password) {
                // Correct password
                Toast.makeText(this, "Temporarily unlocked $appName", Toast.LENGTH_SHORT).show()
                dismissBlockingOverlay()

                // Give them a few seconds before checking again
                handler.removeCallbacks(appCheckRunnable)
                handler.postDelayed(appCheckRunnable, 15000) // 15 seconds grace period
            } else {
                // Wrong password
                Toast.makeText(this, "Incorrect password", Toast.LENGTH_SHORT).show()
            }
        }

        try {
            windowManager.addView(view, params)
            overlayView = view
            isOverlayShowing = true
            Log.d(TAG, "Showing blocking overlay for $appName")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}")
        }
    }

    private fun dismissBlockingOverlay() {
        if (overlayView != null) {
            try {
                windowManager.removeView(overlayView)
                overlayView = null
                isOverlayShowing = false
                currentBlockedApp = null
                Log.d(TAG, "Dismissed blocking overlay")
            } catch (e: Exception) {
                Log.e(TAG, "Error dismissing overlay: ${e.message}")
            }
        }
    }

    private fun hasOverlayPermission(): Boolean {
        return appUsageManager.hasOverlayPermission()
    }

    private fun getOverlayType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "App Blocker Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Monitors and blocks apps that have reached their time limit"
                enableLights(false)
                enableVibration(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("App Blocker Active")
            .setContentText("Monitoring apps for time limits")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)

        return builder.build()
    }

    override fun onDestroy() {
        dismissBlockingOverlay()
        handler.removeCallbacks(appCheckRunnable)
        super.onDestroy()
        Log.d(TAG, "AppBlockerService destroyed")
    }
}