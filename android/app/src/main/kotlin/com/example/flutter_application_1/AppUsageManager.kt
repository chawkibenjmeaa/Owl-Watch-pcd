package com.example.flutter_application_1

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.*
import kotlin.collections.HashMap

class AppUsageManager(private val context: Context) {
    companion object {
        private const val TAG = "AppUsageManager"
        private const val NOTIFICATION_CHANNEL_ID = "app_usage_channel"
        private const val NOTIFICATION_ID = 1001
        private const val FOREGROUND_UPDATE_INTERVAL_MS = 5000L // Check every 5 seconds
    }

    private val usageStatsManager by lazy {
        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    }

    private val notificationManager by lazy {
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentApp: String? = null
    private var appStartTimes = HashMap<String, Long>()
    private var appUsageTracking = false
    private var notificationEnabled = true

    // Map to store app time limits and passwords
    private var appTimeLimits = HashMap<String, Int>() // App name to minutes
    private var appPasswords = HashMap<String, String>() // App name to password

    // Use this to pass foreground updates to Flutter
    private var onForegroundAppChanged: ((String, Long) -> Unit)? = null

    // List of known social media app package prefixes
    private val socialMediaPackages = listOf(
        "com.facebook", "com.instagram", "com.whatsapp",
        "com.snapchat", "com.twitter", "com.tiktok",
        "com.zhiliaoapp.musically", "com.pinterest", "com.discord",
        "com.reddit", "com.tumblr", "org.telegram",
        "com.linkedin", "com.viber", "jp.naver.line",
        "kik.android", "com.google.android.youtube",
        "com.skype", "com.slack", "com.clubhouse"
    )

    // List of known gaming app package prefixes
    private val gamePackages = listOf(
        "com.supercell", "com.king", "com.rovio",
        "com.ea", "com.gameloft", "com.nintendo",
        "com.activision", "com.tencent", "com.ubisoft",
        "com.zynga", "com.playrix", "com.mojang",
        "com.epicgames", "com.rockstargames", "io.voodoo",
        "com.innersloth.among", "com.roblox", "com.miniclip",
        "com.dts.freefireth", "com.pubg", "com.miHoYo"
    )

    // Keywords in app names that likely indicate games
    private val gameKeywords = listOf(
        "game", "games", "play", "clash", "battle", "war", "candy", "saga",
        "puzzle", "racing", "run", "jump", "craft", "craft", "royal", "shooter",
        "ball", "legends", "hero", "heroes", "rpg", "adventure", "quest", "fight",
        "race", "simulator", "sim", "defense", "kingdom", "empire", "casino"
    )

    // Foreground app checking runnable
    private val foregroundCheckRunnable = object : Runnable {
        override fun run() {
            checkCurrentForegroundApp()
            if (appUsageTracking) {
                handler.postDelayed(this, FOREGROUND_UPDATE_INTERVAL_MS)
            }
        }
    }

    // Check if the app has usage stats permission
    fun hasUsageStatsPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // Check if we have overlay permission
    fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }
    fun debugInstalledApps(): Map<String, Any> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

            var totalApps = 0
            var socialMediaCount = 0
            var gamesCount = 0
            var detectedSocialMediaApps = mutableListOf<String>()
            var detectedGameApps = mutableListOf<String>()

            // Sample a few apps for debugging
            val sampleApps = mutableListOf<Map<String, Any>>()

            for (appInfo in installedApps) {
                totalApps++

                try {
                    val packageName = appInfo.packageName
                    val appName = packageManager.getApplicationLabel(appInfo).toString()

                    val isSocialMedia = isSocialMediaApp(packageName, appName)
                    val isGame = isGameApp(packageName, appName)

                    if (isSocialMedia) {
                        socialMediaCount++
                        if (detectedSocialMediaApps.size < 10) {
                            detectedSocialMediaApps.add("$appName ($packageName)")
                        }
                    }

                    if (isGame) {
                        gamesCount++
                        if (detectedGameApps.size < 10) {
                            detectedGameApps.add("$appName ($packageName)")
                        }
                    }

                    // Add some samples for detailed inspection
                    if (sampleApps.size < 20) {
                        sampleApps.add(mapOf(
                            "name" to appName,
                            "package" to packageName,
                            "isSocialMedia" to isSocialMedia,
                            "isGame" to isGame
                        ))
                    }
                } catch (e: Exception) {
                    // Skip this app if we can't get its info
                    continue
                }
            }

            return mapOf(
                "totalApps" to totalApps,
                "socialMediaCount" to socialMediaCount,
                "gamesCount" to gamesCount,
                "socialMediaSamples" to detectedSocialMediaApps,
                "gameSamples" to detectedGameApps,
                "appSamples" to sampleApps
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error debugging installed apps: ${e.message}")
            return mapOf("error" to (e.message ?: "Unknown error"))
        }
    }

    // Open usage access settings
    fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
    }

    // Open overlay permission settings
    fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context.startActivity(intent)
        }
    }

    // Get app usage stats for social media and games only
    fun getAppUsageStats(): Map<String, Long> {
        if (!hasUsageStatsPermission()) {
            Log.e(TAG, "No usage stats permission")
            return emptyMap()
        }

        val packageManager = context.packageManager
        val appUsageMap = HashMap<String, Long>()

        // Get stats from beginning of day until now
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        try {
            // Get usage events
            val usageEvents = usageStatsManager.queryEvents(startTime, endTime)
            val event = UsageEvents.Event()

            // Track app usage durations
            val eventMap = HashMap<String, Long>()
            val packageNameToAppName = HashMap<String, String>()

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                val packageName = event.packageName

                // Skip our own app
                if (packageName == context.packageName) continue

                // Track foreground time
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    eventMap[packageName] = event.timeStamp
                } else if (event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                    val startTime = eventMap[packageName]
                    if (startTime != null) {
                        val usageTime = event.timeStamp - startTime
                        appUsageMap[packageName] = (appUsageMap[packageName] ?: 0) + usageTime
                        eventMap.remove(packageName)
                    }
                }
            }

            // Handle apps that are still in foreground
            val currentTime = System.currentTimeMillis()
            for ((packageName, startTime) in eventMap) {
                val usageTime = currentTime - startTime
                appUsageMap[packageName] = (appUsageMap[packageName] ?: 0) + usageTime
            }

            // Convert milliseconds to minutes and include only social media and games
            val finalUsageMap = HashMap<String, Long>()
            for ((packageName, timeInMillis) in appUsageMap) {
                try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    val appName = packageManager.getApplicationLabel(appInfo).toString()

                    // Check if this is a social media or game app
                    if (isSocialMediaApp(packageName, appName) || isGameApp(packageName, appName)) {
                        val timeInMinutes = timeInMillis / (1000 * 60)
                        if (timeInMinutes > 0) {
                            finalUsageMap[appName] = timeInMinutes
                        }
                    }
                } catch (e: PackageManager.NameNotFoundException) {
                    // Skip apps that can't be resolved
                    continue
                }
            }

            return finalUsageMap
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app usage stats: ${e.message}")
            return emptyMap()
        }
    }

    // Check if the app is a social media app based on package name or app name
    // Improved version of isSocialMediaApp and isGameApp functions

    // Check if the app is a social media app based on package name or app name
    private fun isSocialMediaApp(packageName: String, appName: String): Boolean {
        // Check against known social media package prefixes
        for (prefix in socialMediaPackages) {
            if (packageName.startsWith(prefix)) {
                return true
            }
        }

        // Additional check for system package name patterns
        if (packageName.contains("google.android") &&
            (packageName.contains("messaging") || packageName.contains("hangouts"))) {
            return true
        }

        // Check common social media app names
        val lowercaseName = appName.lowercase(Locale.getDefault())
        val socialMediaKeywords = listOf(
            "facebook", "instagram", "whatsapp", "snapchat", "twitter", "tiktok",
            "pinterest", "discord", "reddit", "tumblr", "telegram", "messenger",
            "linkedin", "wechat", "line", "viber", "skype", "slack", "youtube",
            "zoom", "teams", "clubhouse", "signal", "quora", "weibo", "chat",
            "social", "message", "talk", "meet", "mail", "gmail", "email", "vk",
            "dating", "tinder", "bumble", "hinge", "grindr", "badoo"
        )

        for (keyword in socialMediaKeywords) {
            if (lowercaseName.contains(keyword)) {
                return true
            }
        }

        return false
    }

    // Check if the app is a game app based on package name or app name
    private fun isGameApp(packageName: String, appName: String): Boolean {
        // Check against known game package prefixes
        for (prefix in gamePackages) {
            if (packageName.startsWith(prefix)) {
                return true
            }
        }

        // First try to check app category - most reliable way
        try {
            val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (appInfo.category == ApplicationInfo.CATEGORY_GAME) {
                    return true
                }
            }
        } catch (e: Exception) {
            // Ignore errors checking category
        }

        // Check game-related package name patterns
        if (packageName.contains(".game") || packageName.contains(".games") ||
            packageName.contains(".gaming")) {
            return true
        }

        // Check if app name contains game-related keywords
        val lowercaseName = appName.lowercase(Locale.getDefault())
        for (keyword in gameKeywords) {
            if (lowercaseName.contains(keyword)) {
                return true
            }
        }

        // Additional game-related keywords
        val moreGameKeywords = listOf(
            "farm", "ville", "crush", "solitaire", "poker", "casino", "slots",
            "bingo", "chess", "checkers", "mahjong", "sudoku", "crossword",
            "puzzle", "tetris", "match", "bubble", "birds", "angry", "zombie",
            "clans", "royale", "war", "race", "run", "jump", "fly", "gun", "hunt",
            "fishing", "football", "soccer", "basketball", "tennis", "golf",
            "card", "board", "table", "dice", "strategy"
        )

        for (keyword in moreGameKeywords) {
            if (lowercaseName.contains(keyword)) {
                return true
            }
        }

        return false
    }

    // Get a map of app names to package names for better debugging
    fun getAppsByCategory(): Map<String, List<String>> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

            val socialMediaApps = mutableListOf<String>()
            val gameApps = mutableListOf<String>()
            val otherApps = mutableListOf<String>()

            for (appInfo in installedApps) {
                val packageName = appInfo.packageName
                try {
                    val appName = packageManager.getApplicationLabel(appInfo).toString().trim()

                    if (appName.isNotBlank()) {
                        if (isSocialMediaApp(packageName, appName)) {
                            socialMediaApps.add("$appName ($packageName)")
                        } else if (isGameApp(packageName, appName)) {
                            gameApps.add("$appName ($packageName)")
                        } else {
                            otherApps.add("$appName ($packageName)")
                        }
                    }
                } catch (e: Exception) {
                    // Skip this app if we can't get its name
                    continue
                }
            }

            return mapOf(
                "socialMedia" to socialMediaApps.sorted(),
                "games" to gameApps.sorted(),
                "other" to otherApps.sorted()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error categorizing apps: ${e.message}")
            return emptyMap()
        }
    }

    // Get current foreground app (only return if it's social media or game)
    fun getCurrentForegroundApp(): String? {
        if (!hasUsageStatsPermission()) {
            return null
        }

        val time = System.currentTimeMillis()
        val usageEvents = usageStatsManager.queryEvents(time - 1000 * 60, time)
        val event = UsageEvents.Event()
        var currentApp: String? = null
        var currentPackage: String? = null

        while (usageEvents.hasNextEvent()) {
            usageEvents.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                currentPackage = event.packageName
            }
        }

        if (currentPackage != null && currentPackage != context.packageName) {
            try {
                val appInfo = context.packageManager.getApplicationInfo(currentPackage, 0)
                val appName = context.packageManager.getApplicationLabel(appInfo).toString()

                // Only return the app if it's social media or game
                if (isSocialMediaApp(currentPackage, appName) || isGameApp(currentPackage, appName)) {
                    return appName
                }
            } catch (e: Exception) {
                return null
            }
        }

        return null
    }

    // Get a list of installed social media and game apps
    fun getTargetedApps(): List<String> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            val appNamesList = mutableListOf<String>()

            for (appInfo in installedApps) {
                val packageName = appInfo.packageName
                val appName = packageManager.getApplicationLabel(appInfo).toString()

                // Keep only social media and game apps
                if (isSocialMediaApp(packageName, appName) || isGameApp(packageName, appName)) {
                    appNamesList.add(appName)
                }
            }

            return appNamesList.distinct().sorted()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting targeted apps: ${e.message}")
            return emptyList()
        }
    }

    // Get social media apps only
    fun getSocialMediaApps(): List<String> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            val appNamesList = mutableListOf<String>()

            for (appInfo in installedApps) {
                val packageName = appInfo.packageName
                val appName = packageManager.getApplicationLabel(appInfo).toString()

                if (isSocialMediaApp(packageName, appName)) {
                    appNamesList.add(appName)
                }
            }

            return appNamesList.distinct().sorted()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting social media apps: ${e.message}")
            return emptyList()
        }
    }

    // Get game apps only
    fun getGameApps(): List<String> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            val appNamesList = mutableListOf<String>()

            for (appInfo in installedApps) {
                val packageName = appInfo.packageName
                val appName = packageManager.getApplicationLabel(appInfo).toString()

                if (isGameApp(packageName, appName)) {
                    appNamesList.add(appName)
                }
            }

            return appNamesList.distinct().sorted()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting game apps: ${e.message}")
            return emptyList()
        }
    }

    // Get target apps with their package names (for better identification)
    fun getTargetedAppsWithPackageNames(): Map<String, String> {
        try {
            val packageManager = context.packageManager
            val installedApps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            val appMap = mutableMapOf<String, String>()

            for (appInfo in installedApps) {
                val packageName = appInfo.packageName
                val appName = packageManager.getApplicationLabel(appInfo).toString().trim()

                if (appName.isNotBlank() &&
                    (isSocialMediaApp(packageName, appName) || isGameApp(packageName, appName))) {
                    appMap[appName] = packageName
                }
            }

            return appMap
        } catch (e: Exception) {
            Log.e(TAG, "Error getting targeted apps with package names: ${e.message}")
            return emptyMap()
        }
    }

    // Set callback for foreground app changes
    fun setForegroundAppCallback(callback: (String, Long) -> Unit) {
        onForegroundAppChanged = callback
    }

    // Start foreground app tracking
    fun startForegroundTracking(notificationsEnabled: Boolean = true) {
        if (!hasUsageStatsPermission()) {
            Log.e(TAG, "Cannot start tracking - no usage permission")
            return
        }

        this.notificationEnabled = notificationsEnabled

        if (!appUsageTracking) {
            appUsageTracking = true

            // Create notification channel for Android O+
            createNotificationChannel()

            // Start checking foreground app
            handler.post(foregroundCheckRunnable)

            Log.d(TAG, "Started foreground app tracking")
        }
    }

    // Stop foreground app tracking
    fun stopForegroundTracking() {
        appUsageTracking = false
        handler.removeCallbacks(foregroundCheckRunnable)
        appStartTimes.clear()
        currentApp = null
        Log.d(TAG, "Stopped foreground app tracking")
    }

    // Check which app is in foreground and update tracking
    private fun checkCurrentForegroundApp() {
        if (!hasUsageStatsPermission()) return

        val foregroundApp = getCurrentForegroundApp() ?: return

        // Only proceed if this is a social media or game app
        val currentTime = System.currentTimeMillis()

        // App changed
        if (foregroundApp != currentApp) {
            val oldApp = currentApp

            // Update start time for new app
            if (!appStartTimes.containsKey(foregroundApp)) {
                appStartTimes[foregroundApp] = currentTime
            }

            // Calculate time spent on previous app
            if (oldApp != null && appStartTimes.containsKey(oldApp)) {
                val startTime = appStartTimes[oldApp] ?: currentTime
                val timeSpentMs = currentTime - startTime
                val timeSpentMinutes = timeSpentMs / (1000 * 60)

                Log.d(TAG, "App changed from $oldApp to $foregroundApp. Time spent: $timeSpentMinutes minutes")

                // Notify Flutter of the app change and time spent
                onForegroundAppChanged?.invoke(oldApp, timeSpentMinutes)
            }

            // Update current app
            currentApp = foregroundApp

            // Show notification about current app
            if (notificationEnabled) {
                showCurrentAppNotification(foregroundApp)
            }

            // Check if this app has a time limit and start the blocker service if needed
            checkAndUpdateAppBlocker()
        }
    }

    // Update time limits for apps
    fun updateAppTimeLimits(limits: Map<String, Int>, passwords: Map<String, String>) {
        for ((app, limit) in limits) {
            appTimeLimits[app] = limit
        }

        for ((app, password) in passwords) {
            appPasswords[app] = password
        }

        // Update the blocker service with new limits
        checkAndUpdateAppBlocker()
    }

    // Update the app blocker service with blocked apps
    private fun checkAndUpdateAppBlocker() {
        // Create map of apps that have reached their time limit (using usage stats)
        val blockedApps = HashMap<String, String>()
        val appUsage = getAppUsageStats()

        for ((app, timeLimit) in appTimeLimits) {
            val currentUsage = appUsage[app] ?: 0
            if (timeLimit > 0 && currentUsage >= timeLimit) {
                val password = appPasswords[app] ?: "1234" // Default password if none set
                blockedApps[app] = password
                Log.d(TAG, "App $app has reached limit: $currentUsage min / $timeLimit min")
            }
        }

        // Also add apps that explicitly have 0 time limit (completely blocked)
        for ((app, timeLimit) in appTimeLimits) {
            if (timeLimit <= 0 && !blockedApps.containsKey(app)) {
                val password = appPasswords[app] ?: "1234"
                blockedApps[app] = password
                Log.d(TAG, "App $app is completely blocked (time limit: $timeLimit)")
            }
        }

        if (blockedApps.isNotEmpty()) {
            // Start or update the blocker service
            val intent = Intent(context, AppBlockerService::class.java).apply {
                action = AppBlockerService.ACTION_UPDATE_BLOCKED_APPS
                putExtra(AppBlockerService.EXTRA_BLOCKED_APPS, blockedApps)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }

            // Also start monitoring if not already started
            val monitorIntent = Intent(context, AppBlockerService::class.java).apply {
                action = AppBlockerService.ACTION_START_MONITORING
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(monitorIntent)
            } else {
                context.startService(monitorIntent)
            }
        }
    }

    // Create notification channel for Android O+
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelName = "App Usage Monitoring"
            val channelDescription = "Shows which social media or game app is currently in use"
            val importance = NotificationManager.IMPORTANCE_LOW

            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, channelName, importance).apply {
                description = channelDescription
                enableLights(false)
                enableVibration(false)
            }

            notificationManager.createNotificationChannel(channel)
        }
    }

    // Show notification with current foreground app
    private fun showCurrentAppNotification(appName: String) {
        if (!notificationEnabled) return

        try {
            // Get time spent on this app today
            val appStats = getAppUsageStats()
            val timeSpent = appStats[appName] ?: 0

            // Calculate time limit if set
            val timeLimit = appTimeLimits[appName] ?: 0
            val contentText = if (timeLimit > 0) {
                "You've used $appName for $timeSpent min. Limit: $timeLimit min."
            } else {
                "You've used $appName for $timeSpent min today."
            }

            // Create intent to open main activity when notification is tapped
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or getPendingIntentFlag()
            )

            // Determine app type for notification
            val appType = if (isSocialMediaApp("", appName)) "Social Media" else "Game"

            // Build notification
            val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("Currently using $appType: $appName")
                .setContentText(contentText)
                .setSmallIcon(android.R.drawable.ic_menu_recent_history)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()

            // Show notification
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing notification: ${e.message}")
        }
    }

    // Helper function for PendingIntent flags compatibility
    private fun getPendingIntentFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }
}