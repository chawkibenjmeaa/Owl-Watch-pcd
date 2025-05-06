package com.example.flutter_application_1

import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*
import kotlin.concurrent.fixedRateTimer

class AppUsageMethodChannel(private val context: Context) {
    companion object {
        private const val TAG = "AppUsageMethodChannel"
        private const val CHANNEL_NAME = "com.example.flutter_application_1/app_usage"
    }

    private val appUsageManager = AppUsageManager(context)
    private var usageTrackingTimer: Timer? = null
    private var methodChannel: MethodChannel? = null

    init {
        setupMethodChannel()
    }

    private fun setupMethodChannel() {
        try {
            methodChannel = MethodChannel(
                MainActivity.flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL_NAME
            )

            methodChannel?.setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }

            Log.d(TAG, "AppUsageMethodChannel initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up method channel: ${e.message}")
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasUsagePermission" -> {
                result.success(appUsageManager.hasUsageStatsPermission())
            }
            "hasOverlayPermission" -> {
                result.success(appUsageManager.hasOverlayPermission())
            }
            "requestUsagePermission" -> {
                appUsageManager.requestUsageStatsPermission()
                result.success(true)
            }
            "requestOverlayPermission" -> {
                appUsageManager.requestOverlayPermission()
                result.success(true)
            }
            "getAppUsageStats" -> {
                val stats = appUsageManager.getAppUsageStats()
                result.success(stats)
            }
            "getCurrentForegroundApp" -> {
                val app = appUsageManager.getCurrentForegroundApp()
                result.success(app)
            }
            // Add these functions to the handleMethodCall method block in AppUsageMethodChannel.kt

            "getTargetedApps" -> {
                try {
                    // Get social media and game apps
                    val apps = appUsageManager.getTargetedApps()
                    if (apps.isEmpty()) {
                        // For debug purposes, get detailed app info
                        val appsByCategory = appUsageManager.getAppsByCategory()
                        Log.d(TAG, "Social Media Apps: ${appsByCategory["socialMedia"]?.size ?: 0}")
                        Log.d(TAG, "Game Apps: ${appsByCategory["games"]?.size ?: 0}")
                        Log.d(TAG, "Other Apps: ${appsByCategory["other"]?.size ?: 0}")
                    }
                    result.success(apps)
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting targeted apps: ${e.message}")
                    e.printStackTrace()
                    result.error("GET_APPS_ERROR", "Failed to get targeted apps", e.message)
                }
            }
            "getSocialMediaApps" -> {
                try {
                    val apps = appUsageManager.getSocialMediaApps()
                    if (apps.isEmpty()) {
                        Log.d(TAG, "No social media apps found, check detection logic")
                    }
                    result.success(apps)
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting social media apps: ${e.message}")
                    e.printStackTrace()
                    result.error("GET_SOCIAL_ERROR", "Failed to get social media apps", e.message)
                }
            }
            "getGameApps" -> {
                try {
                    val apps = appUsageManager.getGameApps()
                    if (apps.isEmpty()) {
                        Log.d(TAG, "No game apps found, check detection logic")
                    }
                    result.success(apps)
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting game apps: ${e.message}")
                    e.printStackTrace()
                    result.error("GET_GAMES_ERROR", "Failed to get game apps", e.message)
                }
            }
            "startUsageTracking" -> {
                val intervalSeconds = call.argument<Int>("intervalSeconds") ?: 60
                val showNotifications = call.argument<Boolean>("showNotifications") ?: true
                startUsageTracking(intervalSeconds, showNotifications)
                result.success(true)
            }
            "stopUsageTracking" -> {
                stopUsageTracking()
                result.success(true)
            }
            "setAppTimeLimits" -> {
                @Suppress("UNCHECKED_CAST")
                val limits = call.argument<Map<String, Int>>("limits") as? Map<String, Int> ?: emptyMap()
                @Suppress("UNCHECKED_CAST")
                val passwords = call.argument<Map<String, String>>("passwords") as? Map<String, String> ?: emptyMap()

                appUsageManager.updateAppTimeLimits(limits, passwords)
                result.success(true)
            }
            "startAppBlocker" -> {
                startAppBlockerService()
                result.success(true)
            }
            "stopAppBlocker" -> {
                stopAppBlockerService()
                result.success(true)
            }
            "debugInstalledApps" -> {
                try {
                    val debugInfo = appUsageManager.debugInstalledApps()
                    result.success(debugInfo)
                } catch (e: Exception) {
                    Log.e(TAG, "Error debugging installed apps: ${e.message}")
                    result.error("DEBUG_ERROR", "Failed to debug installed apps", e.message)
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    fun startUsageTracking(intervalSeconds: Int, showNotifications: Boolean = true) {
        stopUsageTracking() // Stop any existing timer

        // Start internal tracking in the AppUsageManager
        appUsageManager.startForegroundTracking(showNotifications)

        // Set up callback to send updates to Flutter
        appUsageManager.setForegroundAppCallback { appName, timeSpentMinutes ->
            MainActivity.activity.runOnUiThread {
                methodChannel?.invokeMethod("onAppUsageUpdate", mapOf(
                    "appName" to appName,
                    "timeSpentMinutes" to timeSpentMinutes
                ))
            }
        }

        // Set up additional timer for periodic updates to Flutter
        usageTrackingTimer = fixedRateTimer(
            name = "AppUsageTracker",
            daemon = true,
            initialDelay = 0L,
            period = intervalSeconds * 1000L
        ) {
            try {
                val currentApp = appUsageManager.getCurrentForegroundApp()
                val usageStats = appUsageManager.getAppUsageStats()

                // Send the usage stats to Flutter
                MainActivity.activity.runOnUiThread {
                    methodChannel?.invokeMethod("onUsageStatsUpdate", mapOf(
                        "currentApp" to currentApp,
                        "usageStats" to usageStats
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in usage tracking timer: ${e.message}")
            }
        }

        Log.d(TAG, "Usage tracking started with interval: $intervalSeconds seconds")
    }

    fun stopUsageTracking() {
        usageTrackingTimer?.cancel()
        usageTrackingTimer = null
        appUsageManager.stopForegroundTracking()
        Log.d(TAG, "Usage tracking stopped")
    }

    fun startAppBlockerService() {
        val intent = Intent(context, AppBlockerService::class.java).apply {
            action = AppBlockerService.ACTION_START_MONITORING
        }

        context.startService(intent)
        Log.d(TAG, "App blocker service started")
    }

    fun stopAppBlockerService() {
        val intent = Intent(context, AppBlockerService::class.java).apply {
            action = AppBlockerService.ACTION_STOP_MONITORING
        }

        context.startService(intent)
        Log.d(TAG, "App blocker service stopped")
    }
}