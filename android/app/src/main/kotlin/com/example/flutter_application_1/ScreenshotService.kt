package com.example.flutter_application_1

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.google.api.client.googleapis.javanet.GoogleNetHttpTransport
import com.google.api.client.http.FileContent
import com.google.api.client.json.gson.GsonFactory
import com.google.api.services.drive.Drive
import com.google.api.services.drive.DriveScopes
import com.google.api.services.drive.model.File as DriveFile
import com.google.api.services.drive.model.FileList
import com.google.auth.http.HttpCredentialsAdapter
import com.google.auth.oauth2.GoogleCredentials
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class ScreenshotService : Service() {
    companion object {
        private const val TAG = "ScreenshotService"
        private const val NOTIFICATION_CHANNEL_ID = "screenshot_service_channel"
        private const val NOTIFICATION_ID = 1001
        private const val SERVICE_PREFS = "screenshot_service_prefs"
        private const val KEY_IS_RUNNING = "is_service_running"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_CHILD_ID = "child_id"
        private const val KEY_INTERVAL = "interval_seconds"

        // Google Drive folder ID - Main root folder for the app
        private const val DRIVE_ROOT_FOLDER_ID = "1h7jYxV3fYOEy4xDhLqgCHVkR4okZOa9i"

        // Service account credentials JSON
        private const val SERVICE_ACCOUNT_JSON = """
        {
          "type": "service_account",
          "project_id": "owlwatch-458514",
          "private_key_id": "c559d1f9e585f20ab8019d4dce12dfac5ecbf8bd",
          "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCSfinJFZwYJ0kF\nPnBEsNpGPvnzpykG7kMRa/X8coW6PNK8smmqS7skz3HMO+gPhSAw249E4jjkygJE\nSGhz6k6tiuzUpvSaOHHtThZlp2LBzSxZItj0SPmx5Nno1j4ehCRPhkWE60UKPdPT\nlFPimpnB0KNwpeqHw1NiFxVne7G4YjIq1JcMbBlOpEhZqYn+30nIQDCjDwWkWQbi\nsqkPSwpdre4iR94F2yiAv8ojc0eXFppiUQMAuMOQXDJmcCf5exVS1JuzVhPacJFx\nlfODR6FlEhZNaYzjXf3PAePfjX03c63lx99kABuP8wPmqzwg0Inh+ES030cBHigN\nZMVc6PHrAgMBAAECggEAA/rafsSQB5X1pWdTXIJjg7oNR2HYuv/5IX2J4tBnsq4Z\nWZgNR9uj23WpVU+hV96Zh8pHQ6tTuV+FnT5MXC3W8l8OXR6mEZSL/9L5x8w64iIF\nXOyV8VkUM5GQnANKD8EuTVzMAbb0mrkgSqTCfKsPl1ToQ9S2IPcdClKvOa8CHoy9\n4nGjBsIg9JlEVkrD2rr2Og0rz/UDwlTUD/V0JDUsWT0rxbWUM2jAETWJZ53DDG2Z\nPxS9Iznf+e9wlO3IVSFDsYojqSJn35xiqzbluFGgrpatdkQZPAChe8g4PnJUenVI\n/h3V6Rv0/QNj2Ve9zOWAO6t7XwOu6uTJqstoi+898QKBgQDG581N9VE1vsexKTyS\nBjwr3U3eAE1uz01vAdNlzLQbvGyi5apYBTvHVlc4kufINku081eLJSYhN/uW8vhO\nh/3g10kuQN16ybHnvwimN71ypaynZ+TiuAbkeSzob1VM70ei6ckAio992173G8Xp\nc9BC1PqR4iLWHYKRZiw9rJOc2wKBgQC8iupRcc7Mc91Rl1t6c704FXK83uGMkvdD\ngp9EK+YlkQFPbHGKLHuCh0Z59nX6kfGxEmHkj3CHfFWbCeGiPpO7YFKIp3HEaaKo\nUTQYkZUcGNjz+RBGXx7PqR+HPYbGayUBOLIEKw3TRIT5D65zS0Jly4pPLy2/0CsA\nCDCAToWEMQKBgQCNE44vdAbUmusiAcB/RcLZzc5T3l0NciVWzbG1q3o3je5zn3ex\nlIywttGIQ9H31GLgBhSakY+40e81QkHR2Wy9U5UJJGKym2n+mCU3V6OcNFwAJJVY\nJPRminfKqGSU+8YQi8bQBnb96mEx3VYDXexh6pOKcx0IRsf7/r70Q3ozLwKBgDCA\nX9TBvRwVNjrV/99ZRLTXt6NkhoseB2Ojh4sG6/Z//eFLmU2dMcybNgML5r+lqZIO\nk4YzbBQ+ZNs0SInvJRvPpIuo33hSYFiCQy+Ky9vlfHIOgSRJNejfrc+hgTkruOI+\njnTKCo1tk/NqGEtqcdMz8Al8rn0odNdWQ/vNt0URAoGBAKA0zth+DK31m4O36Y7X\npxa9tK+2u+DLq0PQTi+vWg3Esh2tOPrcoTUb6ZiIkcgEYODzPA2ERZNNkfxcfXnx\nUtizksgmENkq2OBi/JXKrKARJqbxV8BNphiFJ51jfkRQqdFySUhgX6QlP7hTyF8A\nuIm1IUfNGcw7OJE6EDjBhFSl\n-----END PRIVATE KEY-----\n",
          "client_email": "owlwatch@owlwatch-458514.iam.gserviceaccount.com",
          "client_id": "108377539198260970571",
          "auth_uri": "https://accounts.google.com/o/oauth2/auth",
          "token_uri": "https://oauth2.googleapis.com/token",
          "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
          "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/owlwatch%40owlwatch-458514.iam.gserviceaccount.com",
          "universe_domain": "googleapis.com"
        }
        """

        // Media projection result code and data intent
        private var resultCode: Int = 0
        private var resultData: Intent? = null

        // Helper method to save result code and data for future use
        fun setMediaProjectionData(resultCode: Int, data: Intent?) {
            this.resultCode = resultCode
            this.resultData = data
        }

        // Method to check if service is running from shared preferences
        fun isServiceRunning(context: Context): Boolean {
            val prefs = context.getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE)
            return prefs.getBoolean(KEY_IS_RUNNING, false)
        }
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var displayWidth: Int = 0
    private var displayHeight: Int = 0
    private var displayDensity: Int = 0
    private var screenshotIntervalSeconds: Int = 10
    private var userId: String? = null
    private var childId: String? = null

    // Cache for folder IDs to avoid repeated lookups
    private var parentFolderId: String? = null
    private var childFolderId: String? = null

    private var powerManager: PowerManager? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var scheduledExecutor: ScheduledExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Google Drive service
    private var driveService: Drive? = null
    // Background thread for handling uploads
    private val uploadExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Screenshot service created")

        // Get display metrics
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            displayWidth = bounds.width()
            displayHeight = bounds.height()
            // Get the density from resources for Android 11+
            displayDensity = resources.displayMetrics.densityDpi
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getMetrics(metrics)
            displayWidth = metrics.widthPixels
            displayHeight = metrics.heightPixels
            displayDensity = metrics.densityDpi
        }

        // Ensure density is positive
        if (displayDensity <= 0) {
            displayDensity = DisplayMetrics.DENSITY_DEFAULT // Use default density (160)
        }

        Log.d(TAG, "Display metrics: width=$displayWidth, height=$displayHeight, density=$displayDensity")

        // Create a power manager and wake lock to keep the service running
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ScreenshotService::WakeLock"
        )

        // Initialize Google Drive service
        initDriveService()
    }

    private fun initDriveService() {
        try {
            // Run this in background thread since it involves network operations
            uploadExecutor.execute {
                try {
                    // Create credentials from service account JSON
                    val credentialsStream = ByteArrayInputStream(SERVICE_ACCOUNT_JSON.toByteArray())
                    val credentials = GoogleCredentials.fromStream(credentialsStream)
                        .createScoped(Collections.singleton(DriveScopes.DRIVE_FILE))

                    // Build Drive service
                    driveService = Drive.Builder(
                        GoogleNetHttpTransport.newTrustedTransport(),
                        GsonFactory.getDefaultInstance(),
                        HttpCredentialsAdapter(credentials)
                    )
                        .setApplicationName("OwlWatch Screenshot Service")
                        .build()

                    Log.d(TAG, "Google Drive service initialized successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to initialize Google Drive service: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing Drive service: ${e.message}", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service start command received")

        // Extract parameters from intent
        intent?.let {
            screenshotIntervalSeconds = it.getIntExtra("intervalSeconds", 10)
            userId = it.getStringExtra("userId")
            childId = it.getStringExtra("childId")

            Log.d(TAG, "Service parameters - Interval: $screenshotIntervalSeconds, UserId: $userId, ChildId: $childId")
        }

        // Save service state
        saveServiceState(true)

        // Start foreground service with notification
        startForeground()

        // Initialize media projection if we have valid result code and data
        if (resultCode != 0 && resultData != null) {
            initializeMediaProjection()
            // Start screenshot schedule
            startScreenshotSchedule()
            return START_STICKY
        } else {
            Log.e(TAG, "Missing media projection data, stopping service")
            stopSelf()
            return START_NOT_STICKY
        }
    }

    private fun saveServiceState(isRunning: Boolean) {
        val prefs = getSharedPreferences(SERVICE_PREFS, Context.MODE_PRIVATE)
        prefs.edit().apply {
            putBoolean(KEY_IS_RUNNING, isRunning)
            userId?.let { putString(KEY_USER_ID, it) }
            childId?.let { putString(KEY_CHILD_ID, it) }
            putInt(KEY_INTERVAL, screenshotIntervalSeconds)
            apply()
        }
    }

    private fun startForeground() {
        // Create notification channel for Android O and above
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Screenshot Service Channel",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Used for the screenshot background service"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }

        // Create intent for when notification is tapped
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        // Build the notification
        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Screenshot Service Active")
            .setContentText("Uploading screenshots to Google Drive")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        // Start as foreground service with the notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun initializeMediaProjection() {
        // Acquire wake lock to keep CPU running
        wakeLock?.acquire(10*60*1000L /*10 minutes*/)

        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            mediaProjection = projectionManager.getMediaProjection(resultCode, resultData!!)

            // Register callback
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                mediaProjection?.registerCallback(mediaProjectionCallback, mainHandler)
            }

            // Create ImageReader for screenshot capture
            imageReader = ImageReader.newInstance(
                displayWidth, displayHeight,
                PixelFormat.RGBA_8888, 2
            )

            // Create virtual display for capturing screen
            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "ScreenCapture",
                displayWidth, displayHeight, displayDensity,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader?.surface, null, null
            )

            Log.d(TAG, "Media projection initialized with display size: ${displayWidth}x${displayHeight}")
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing media projection: ${e.message}")
            stopSelf()
        }
    }

    // MediaProjection callback implementation
    private val mediaProjectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.d(TAG, "MediaProjection stopped")
            stopSelf()
        }
    }

    private fun startScreenshotSchedule() {
        Log.d(TAG, "Starting screenshot schedule every $screenshotIntervalSeconds seconds")

        scheduledExecutor = Executors.newSingleThreadScheduledExecutor()
        scheduledExecutor?.scheduleAtFixedRate({
            try {
                captureScreenshot()
            } catch (e: Exception) {
                Log.e(TAG, "Error in screenshot schedule: ${e.message}")
            }
        }, 0, screenshotIntervalSeconds.toLong(), TimeUnit.SECONDS)
    }

    private fun captureScreenshot() {
        if (imageReader == null || mediaProjection == null) {
            Log.e(TAG, "Cannot capture screenshot, resources not initialized")
            return
        }

        try {
            // Small delay to ensure display is ready
            Thread.sleep(100)

            // Get the latest image from the reader
            val image = imageReader?.acquireLatestImage()

            if (image != null) {
                try {
                    // Convert image to bitmap
                    val planes = image.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * displayWidth

                    // Calculate width with padding - ensure it's valid
                    val width = displayWidth + rowPadding / pixelStride

                    if (width <= 0 || displayHeight <= 0) {
                        Log.e(TAG, "Invalid bitmap dimensions: $width x $displayHeight")
                        image.close()
                        return
                    }

                    val bitmap = Bitmap.createBitmap(
                        width,
                        displayHeight,
                        Bitmap.Config.ARGB_8888
                    )

                    bitmap.copyPixelsFromBuffer(buffer)

                    // Save bitmap to file
                    saveScreenshotToFile(bitmap)
                } finally {
                    // Ensure image is always closed even if processing fails
                    image.close()
                }
            } else {
                Log.e(TAG, "Failed to acquire image from reader")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error capturing screenshot: ${e.message}", e)
        }
    }

    private fun saveScreenshotToFile(bitmap: Bitmap) {
        try {
            // Create file path in internal cache directory
            val timestamp = System.currentTimeMillis()
            val filename = "screenshot_${timestamp}.png"
            val outputDir = cacheDir
            val outputFile = File(outputDir, filename)

            // Save bitmap to file
            FileOutputStream(outputFile).use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }

            Log.d(TAG, "Screenshot saved to ${outputFile.absolutePath}")

            // Upload to Google Drive
            uploadFileToDrive(outputFile, filename)

            // Notify Flutter code via method channel on main thread
            mainHandler.post {
                notifyFlutterCode(outputFile.absolutePath, userId, childId)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error saving screenshot: ${e.message}")
        }
    }

    private fun uploadFileToDrive(localFile: File, filename: String) {
        // Run upload in background thread
        uploadExecutor.execute {
            try {
                if (driveService == null) {
                    Log.e(TAG, "Drive service not initialized, attempting to reinitialize")
                    initDriveService()
                    // Wait a bit for initialization
                    Thread.sleep(1000)
                    if (driveService == null) {
                        Log.e(TAG, "Drive service still not initialized, aborting upload")
                        return@execute
                    }
                }

                if (userId == null || childId == null) {
                    Log.e(TAG, "Missing userId or childId, cannot upload")
                    return@execute
                }

                // First, ensure parent folder exists (userId folder)
                val parentFolderId = ensureParentFolderExists(userId!!)

                // Then, ensure child folder exists within parent
                val childFolderId = ensureChildFolderExists(parentFolderId, childId!!)

                // Create Drive file metadata - place in child folder
                val fileMetadata = DriveFile().apply {
                    name = filename
                    parents = listOf(childFolderId)
                }

                // Set up file content
                val mediaContent = FileContent("image/png", localFile)

                // Execute upload
                val uploadedFile = driveService!!.files().create(fileMetadata, mediaContent)
                    .setFields("id, name")
                    .execute()

                Log.d(TAG, "File uploaded successfully, ID: ${uploadedFile.id}")

                // Optionally delete local file after successful upload to save space
                if (localFile.exists()) {
                    localFile.delete()
                    Log.d(TAG, "Local file deleted after successful upload")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to upload file to Google Drive: ${e.message}", e)
                // If upload failed, keep trying with exponential backoff
                // (Actual implementation would use WorkManager for reliability)
            }
        }
    }

    // Find or create parent folder (userId folder)
    private fun ensureParentFolderExists(userId: String): String {
        // Return cached ID if available
        if (parentFolderId != null) {
            return parentFolderId!!
        }

        try {
            // Check if folder already exists
            val query = "mimeType='application/vnd.google-apps.folder' and name='$userId' and '${DRIVE_ROOT_FOLDER_ID}' in parents and trashed=false"
            val result = driveService!!.files().list()
                .setQ(query)
                .setSpaces("drive")
                .setFields("files(id, name)")
                .execute()

            // If folder exists, use it
            if (result.files.isNotEmpty()) {
                parentFolderId = result.files[0].id
                Log.d(TAG, "Found existing parent folder: $parentFolderId")
                return parentFolderId!!
            }

            // Create new folder if it doesn't exist
            val folderMetadata = DriveFile().apply {
                name = userId
                mimeType = "application/vnd.google-apps.folder"
                parents = listOf(DRIVE_ROOT_FOLDER_ID)
            }

            val folder = driveService!!.files().create(folderMetadata)
                .setFields("id")
                .execute()

            parentFolderId = folder.id
            Log.d(TAG, "Created new parent folder: $parentFolderId")
            return parentFolderId!!
        } catch (e: Exception) {
            Log.e(TAG, "Error ensuring parent folder exists: ${e.message}", e)
            throw e
        }
    }

    // Find or create child folder inside parent folder
    private fun ensureChildFolderExists(parentFolderId: String, childId: String): String {
        // Return cached ID if available
        if (childFolderId != null) {
            return childFolderId!!
        }

        try {
            // Check if folder already exists
            val query = "mimeType='application/vnd.google-apps.folder' and name='$childId' and '$parentFolderId' in parents and trashed=false"
            val result = driveService!!.files().list()
                .setQ(query)
                .setSpaces("drive")
                .setFields("files(id, name)")
                .execute()

            // If folder exists, use it
            if (result.files.isNotEmpty()) {
                childFolderId = result.files[0].id
                Log.d(TAG, "Found existing child folder: $childFolderId")
                return childFolderId!!
            }

            // Create new folder if it doesn't exist
            val folderMetadata = DriveFile().apply {
                name = childId
                mimeType = "application/vnd.google-apps.folder"
                parents = listOf(parentFolderId)
            }

            val folder = driveService!!.files().create(folderMetadata)
                .setFields("id")
                .execute()

            childFolderId = folder.id
            Log.d(TAG, "Created new child folder: $childFolderId")
            return childFolderId!!
        } catch (e: Exception) {
            Log.e(TAG, "Error ensuring child folder exists: ${e.message}", e)
            throw e
        }
    }

    private fun notifyFlutterCode(filePath: String, userId: String?, childId: String?) {
        if (userId == null || childId == null) {
            Log.e(TAG, "Cannot notify Flutter, missing userId or childId")
            return
        }

        try {
            val args = mapOf(
                "filePath" to filePath,
                "userId" to userId,
                "childId" to childId,
                "uploadStatus" to "uploading_to_drive" // Add status information
            )

            // Send message to Flutter via method channel
            MainActivity.methodChannel?.invokeMethod("onScreenshotTaken", args)
            Log.d(TAG, "Notified Flutter code about new screenshot")
        } catch (e: Exception) {
            Log.e(TAG, "Error notifying Flutter code: ${e.message}")
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        Log.d(TAG, "Screenshot service being destroyed")

        // Stop the screenshot scheduler
        scheduledExecutor?.shutdownNow()

        // Shutdown upload executor
        uploadExecutor.shutdownNow()

        // Release the virtual display
        virtualDisplay?.release()

        // Close the image reader
        imageReader?.close()

        // Unregister the callback and stop media projection
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mediaProjection?.unregisterCallback(mediaProjectionCallback)
        }
        mediaProjection?.stop()

        // Release wake lock if held
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }

        // Update service state
        saveServiceState(false)

        super.onDestroy()
    }
}