package com.example.flutter_application_1

import android.content.Context
import android.util.Log
import com.google.api.client.googleapis.javanet.GoogleNetHttpTransport
import com.google.api.client.http.FileContent
import com.google.api.client.http.HttpRequestInitializer
import com.google.api.client.json.gson.GsonFactory
import com.google.api.services.drive.Drive
import com.google.api.services.drive.DriveScopes
import com.google.api.services.drive.model.File
import com.google.api.services.drive.model.Permission
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.util.Collections
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class GoogleDriveImplementation(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "GoogleDriveImpl"
        private const val CHANNEL_NAME = "com.example.flutter_application_1/drive"
        private const val PCD_FOLDER_NAME = "PCD Screenshots"

        // Add constant for the target folder ID
        private const val TARGET_FOLDER_ID = "1h7jYxV3fYOEy4xDhLqgCHVkR4okZOa9i"

        // Track initialization state like in Dart code
        private var isInitialized = false
        private var isInitializing = false
    }

    private val methodChannel: MethodChannel
    private var driveService: Drive? = null
    private var serviceAccountEmail: String? = null
    private val executor = Executors.newSingleThreadExecutor()

    init {
        methodChannel = MethodChannel(MainActivity.flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initializeDriveService" -> {
                executeAsync({
                    initializeDriveService(call.argument<String>("credentialsPath"))
                }, result)
            }
            "verifyDriveAccess" -> {
                // Always try to verify the target folder ID
                val folderId = call.argument<String>("folderId") ?: TARGET_FOLDER_ID
                executeAsync({
                    verifyDriveAccess(folderId)
                }, result)
            }
            "listFiles" -> {
                val maxResults = call.argument<Int>("maxResults") ?: 10
                executeAsync({
                    listFiles(maxResults)
                }, result)
            }
            "getServiceAccountInfo" -> {
                executeAsync({
                    getServiceAccountInfo()
                }, result)
            }
            "createFolder" -> {
                val folderName = call.argument<String>("folderName") ?: PCD_FOLDER_NAME
                if (folderName.isEmpty()) {
                    result.error("INVALID_ARGUMENTS", "Folder name is required", null)
                    return
                }
                executeAsync({
                    findOrCreateFolder(folderName)
                }, result)
            }
            "uploadFile" -> {
                val filePath = call.argument<String>("filePath")
                val userId = call.argument<String>("userId")
                val childId = call.argument<String>("childId")
                // Always use the target folder ID if not specified
                val folderId = call.argument<String>("folderId") ?: TARGET_FOLDER_ID

                if (filePath.isNullOrEmpty() || userId.isNullOrEmpty() || childId.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENTS", "Missing required parameters", null)
                    return
                }

                executeAsync({
                    uploadFileToDrive(filePath, userId, childId, folderId)
                }, result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun executeAsync(callable: Callable<Any?>, result: MethodChannel.Result) {
        executor.execute {
            try {
                val response = callable.call()
                MainActivity.activity.runOnUiThread {
                    result.success(response)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error executing Drive operation: ${e.message}", e)
                MainActivity.activity.runOnUiThread {
                    result.error("DRIVE_ERROR", e.message, null)
                }
            }
        }
    }

    private fun initializeDriveService(credentialsPath: String?): Boolean {
        try {
            // If already initialized, return true
            if (isInitialized && driveService != null) {
                Log.d(TAG, "Drive service already initialized")
                return true
            }

            // If currently initializing, wait to avoid concurrent initialization
            if (isInitializing) {
                Log.d(TAG, "Drive service initialization in progress")
                return false
            }

            isInitializing = true
            Log.d(TAG, "Initializing Drive service")

            try {
                // Get the credentials file path - try multiple locations
                val providedPath = credentialsPath
                val defaultPath = "${context.filesDir.absolutePath}/credentials.json"

                // Determine which path to use
                val finalPath = providedPath ?: defaultPath
                Log.d(TAG, "Attempting to use credentials at: $finalPath")

                val credentialsFile = java.io.File(finalPath)

                if (!credentialsFile.exists()) {
                    Log.e(TAG, "Credentials file not found at $finalPath")

                    // Try alternative paths
                    val alternativePath = "${context.getExternalFilesDir(null)?.absolutePath}/credentials.json"
                    val alternativeFile = java.io.File(alternativePath)

                    if (alternativeFile.exists()) {
                        Log.d(TAG, "Found credentials at alternative path: $alternativePath")
                        // Copy to the expected location
                        alternativeFile.copyTo(credentialsFile, true)
                        Log.d(TAG, "Copied credentials to expected location: $finalPath")
                    } else {
                        // Look for the file in app's cache directory
                        val cacheFile = java.io.File("${context.cacheDir.absolutePath}/credentials.json")
                        if (cacheFile.exists()) {
                            Log.d(TAG, "Found credentials in cache: ${cacheFile.absolutePath}")
                            cacheFile.copyTo(credentialsFile, true)
                            Log.d(TAG, "Copied credentials from cache to: $finalPath")
                        } else {
                            // Search in app documents directory
                            val appDocumentsDir = context.getDir("app_flutter", Context.MODE_PRIVATE)
                            val appDocFile = java.io.File("${appDocumentsDir.absolutePath}/credentials.json")

                            if (appDocFile.exists()) {
                                Log.d(TAG, "Found credentials in app_flutter dir: ${appDocFile.absolutePath}")
                                appDocFile.copyTo(credentialsFile, true)
                                Log.d(TAG, "Copied credentials to: $finalPath")
                            } else {
                                Log.e(TAG, "Credentials file not found in any known location")
                                isInitializing = false
                                return false
                            }
                        }
                    }
                }

                // Log file details
                Log.d(TAG, "Credentials file size: ${credentialsFile.length()} bytes")

                // Read the file content to verify it's valid
                val fileContent = credentialsFile.readText()
                if (!fileContent.contains("service_account")) {
                    Log.e(TAG, "Invalid credentials file content - missing service_account")
                    isInitializing = false
                    return false
                }

                // Load Google service account credentials
                val credentials = com.google.auth.oauth2.GoogleCredentials.fromStream(FileInputStream(credentialsFile))
                    .createScoped(Collections.singleton(DriveScopes.DRIVE))  // Using full DRIVE scope instead of DRIVE_FILE

                // Store service account email for diagnostics
                if (credentials is com.google.auth.oauth2.ServiceAccountCredentials) {
                    serviceAccountEmail = credentials.account
                    Log.d(TAG, "Service account email: $serviceAccountEmail")
                }

                // Build the Drive service
                val httpTransport = GoogleNetHttpTransport.newTrustedTransport()
                val jsonFactory = GsonFactory.getDefaultInstance()

                driveService = Drive.Builder(
                    httpTransport,
                    jsonFactory,
                    com.google.auth.http.HttpCredentialsAdapter(credentials) as HttpRequestInitializer
                )
                    .setApplicationName("Owl Watch")
                    .build()

                // Test the connection by trying to list files
                try {
                    val files = driveService?.files()?.list()
                        ?.setPageSize(1)
                        ?.execute()

                    Log.d(TAG, "Test connection successful - can list files")
                    isInitialized = true

                    // Verify access to the target folder
                    val hasAccess = verifyDriveAccess(TARGET_FOLDER_ID)
                    if (hasAccess) {
                        Log.d(TAG, "Successfully verified access to target folder ID: $TARGET_FOLDER_ID")
                    } else {
                        Log.w(TAG, "Access to target folder could not be verified, but proceeding with initialization")
                    }

                } catch (e: Exception) {
                    Log.e(TAG, "Drive service initialized but test connection failed: ${e.message}", e)
                    isInitialized = true // Still mark as initialized since we got this far
                }

                isInitializing = false
                Log.d(TAG, "Drive service initialized successfully")
                return true
            } catch (e: Exception) {
                isInitialized = false
                isInitializing = false
                Log.e(TAG, "Error initializing Drive service: ${e.message}", e)
                throw e
            }
        } catch (e: Exception) {
            isInitialized = false
            isInitializing = false
            Log.e(TAG, "Error initializing Drive service: ${e.message}", e)
            throw e
        }
    }

    // Find or create PCD Screenshots folder with proper permissions
    private fun findOrCreatePCDScreenshotsFolder(): String? {
        // Try to use the target folder first
        if (verifyDriveAccess(TARGET_FOLDER_ID)) {
            Log.d(TAG, "Using specified target folder ID: $TARGET_FOLDER_ID")
            return TARGET_FOLDER_ID
        }

        // Fall back to finding or creating the folder
        return findOrCreateFolder(PCD_FOLDER_NAME)
    }

    // Find an existing folder or create it if it doesn't exist
    private fun findOrCreateFolder(folderName: String): String? {
        try {
            if (!isInitialized || driveService == null) {
                if (!initializeDriveService(null)) {
                    Log.e(TAG, "Drive service not initialized")
                    return null
                }
            }

            // First check if we can access the target folder
            if (verifyDriveAccess(TARGET_FOLDER_ID)) {
                Log.d(TAG, "Using target folder ID instead of creating a new one")
                return TARGET_FOLDER_ID
            }

            Log.d(TAG, "Searching for folder: $folderName")

            // Try to find the folder
            val query = "mimeType='application/vnd.google-apps.folder' and name='$folderName' and trashed=false"
            val result = driveService?.files()?.list()
                ?.setQ(query)
                ?.setSpaces("drive")
                ?.setFields("files(id, name, capabilities)")
                ?.execute()

            if (result != null && result.files.isNotEmpty()) {
                val folder = result.files.first()
                Log.d(TAG, "Found existing folder: ${folder.name} with ID: ${folder.id}")

                // Check if we have edit permissions
                val canEdit = folder.capabilities?.canEdit ?: false
                Log.d(TAG, "Can edit folder: $canEdit")

                if (!canEdit) {
                    Log.d(TAG, "Attempting to add editor permission to folder")
                    try {
                        makeEditor(folder.id)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to add editor permission: ${e.message}")
                        // Continue using the folder even without editor permission
                    }
                }

                return folder.id
            }

            // If folder wasn't found, create it
            Log.d(TAG, "Creating new folder: $folderName")
            val folderId = createFolder(folderName)

            if (folderId != null) {
                Log.d(TAG, "Created new folder with ID: $folderId")
                // Make the folder accessible with editor permissions
                makeEditor(folderId)
            } else {
                Log.e(TAG, "Failed to create new folder")
            }

            return folderId
        } catch (e: Exception) {
            Log.e(TAG, "Error finding or creating folder: ${e.message}", e)
            return null
        }
    }

    private fun verifyDriveAccess(folderId: String?): Boolean {
        try {
            if (!isInitialized || driveService == null) {
                if (!initializeDriveService(null)) {
                    Log.e(TAG, "Drive service not initialized")
                    return false
                }
            }

            // Log the attempt with folder ID
            Log.d(TAG, "Verifying access to folder ID: $folderId")

            // Try to get folder metadata to verify access
            if (folderId != null) {
                try {
                    val folder = driveService?.files()?.get(folderId)
                        ?.setFields("id, name, capabilities")
                        ?.execute()

                    val canEdit = folder?.capabilities?.canEdit ?: false
                    Log.d(TAG, "Successfully verified folder access: ${folder?.name}, canEdit: $canEdit")

                    // Add the folder name to service account info for debugging
                    folder?.name?.let { folderName ->
                        val serviceAccountInfo = getServiceAccountInfo() as? MutableMap<String, String>
                        serviceAccountInfo?.put("currentFolderName", folderName)
                    }

                    return folder != null
                } catch (e: Exception) {
                    Log.e(TAG, "Error verifying Drive access: ${e.message}", e)

                    // Try to list files to see if we have any access
                    try {
                        val files = driveService?.files()?.list()
                            ?.setPageSize(1)
                            ?.execute()

                        Log.d(TAG, "Can list files but not access specified folder")
                        if (files != null && files.files.isNotEmpty()) {
                            Log.d(TAG, "Sample file found: ${files.files[0].name}")
                        }

                        return false
                    } catch (e2: Exception) {
                        Log.e(TAG, "Cannot list files either: ${e2.message}", e2)
                        return false
                    }
                }
            }

            return false
        } catch (e: Exception) {
            Log.e(TAG, "Error verifying Drive access: ${e.message}", e)
            return false
        }
    }

    private fun listFiles(maxResults: Int): List<Map<String, String>> {
        try {
            if (!isInitialized || driveService == null) {
                if (!initializeDriveService(null)) {
                    Log.e(TAG, "Drive service not initialized")
                    return emptyList()
                }
            }

            val result = mutableListOf<Map<String, String>>()
            val files = driveService?.files()?.list()
                ?.setPageSize(maxResults)
                ?.setFields("files(id, name, mimeType, modifiedTime, webViewLink)")
                ?.execute()

            if (files != null && files.files.isNotEmpty()) {
                Log.d(TAG, "Successfully listed ${files.files.size} files")

                files.files.forEach { file ->
                    val fileMap = mutableMapOf<String, String>()
                    fileMap["id"] = file.id ?: ""
                    fileMap["name"] = file.name ?: ""
                    fileMap["mimeType"] = file.mimeType ?: ""
                    fileMap["modifiedTime"] = file.modifiedTime?.toString() ?: ""
                    fileMap["webViewLink"] = file.webViewLink ?: ""

                    // Add file to result list
                    result.add(fileMap)

                    Log.d(TAG, "File: ${file.name}, ID: ${file.id}, Type: ${file.mimeType}")
                }
                return result
            } else {
                Log.d(TAG, "No files found in Drive")
                return emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error listing files: ${e.message}", e)
            throw e
        }
    }

    // Create a new folder in the root of Drive or in a parent folder
    private fun createFolder(folderName: String, parentFolderId: String? = null): String? {
        try {
            if (!isInitialized || driveService == null) {
                if (!initializeDriveService(null)) {
                    throw Exception("Drive service not initialized")
                }
            }

            val fileMetadata = File().apply {
                name = folderName
                mimeType = "application/vnd.google-apps.folder"
                if (parentFolderId != null) {
                    parents = listOf(parentFolderId)
                }
            }

            val folder = driveService?.files()?.create(fileMetadata)
                ?.setFields("id, name, webViewLink")
                ?.execute()

            val folderId = folder?.id
            if (folderId != null) {
                Log.d(TAG, "Created new folder '$folderName' with ID: $folderId")
            } else {
                Log.e(TAG, "Failed to create folder, returned ID is null")
            }

            return folderId
        } catch (e: Exception) {
            Log.e(TAG, "Error creating folder: ${e.message}", e)
            throw e
        }
    }

    // Make a file or folder accessible to anyone with editor permissions
    private fun makeEditor(fileId: String) {
        try {
            Log.d(TAG, "Setting editor permission on file/folder: $fileId")

            // Create permission for anyone with the link to edit
            val editorPermission = Permission().apply {
                type = "anyone"  // Makes it available to anyone with the link
                role = "writer"  // "writer" provides edit access
            }

            // Apply the permission
            val result = driveService?.permissions()?.create(fileId, editorPermission)
                ?.setFields("id, type, role")
                ?.execute()

            Log.d(TAG, "Added editor permission: ${result?.id}, type: ${result?.type}, role: ${result?.role}")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting editor permission: ${e.message}", e)
            throw e
        }
    }

    private fun getServiceAccountInfo(): Map<String, String> {
        val info = mutableMapOf<String, String>()
        info["serviceAccountEmail"] = serviceAccountEmail ?: "Unknown"
        info["isInitialized"] = isInitialized.toString()
        info["email"] = serviceAccountEmail ?: "Unknown" // Add for consistency with Dart code
        info["targetFolderId"] = TARGET_FOLDER_ID // Add the target folder ID to the info

        // Try to get root folder info
        try {
            val rootFolder = driveService?.files()?.get("root")?.execute()
            info["rootFolderId"] = rootFolder?.id ?: "Unknown"
        } catch (e: Exception) {
            info["rootFolderError"] = e.message ?: "Unknown error"
        }

        // Try to get target folder info
        try {
            val targetFolder = driveService?.files()?.get(TARGET_FOLDER_ID)?.execute()
            info["targetFolderName"] = targetFolder?.name ?: "Unknown"
            info["targetFolderAccessible"] = "true"
        } catch (e: Exception) {
            info["targetFolderAccessible"] = "false"
            info["targetFolderError"] = e.message ?: "Unknown error"
        }

        return info
    }

    private fun uploadFileToDrive(
        filePath: String,
        userId: String,
        childId: String,
        folderId: String
    ): String? {
        try {
            if (!isInitialized || driveService == null) {
                if (!initializeDriveService(null)) {
                    throw Exception("Drive service not initialized")
                }
            }

            val sourceFile = java.io.File(filePath)
            if (!sourceFile.exists()) {
                throw Exception("Source file not found: $filePath")
            }

            Log.d(TAG, "Found source file: $filePath, size: ${sourceFile.length()} bytes")

            // Use the provided folder ID, defaulting to TARGET_FOLDER_ID if not specified
            var targetFolderId = folderId
            if (targetFolderId.isEmpty()) {
                targetFolderId = TARGET_FOLDER_ID
                Log.d(TAG, "Using default target folder ID: $targetFolderId")
            }

            // Verify folder exists and is accessible
            try {
                val folder = driveService?.files()?.get(targetFolderId)
                    ?.setFields("id, name, capabilities")
                    ?.execute()

                Log.d(TAG, "Target folder exists: ${folder?.name}, canEdit: ${folder?.capabilities?.canEdit}")

                // If we can't edit the folder, try to add permission
                if (folder?.capabilities?.canEdit == false) {
                    try {
                        makeEditor(targetFolderId)
                        Log.d(TAG, "Added editor permission to folder")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to add editor permission: ${e.message}")
                        // Continue anyway
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Cannot access target folder: ${e.message}")

                // Try to use the TARGET_FOLDER_ID if different from the provided ID
                if (targetFolderId != TARGET_FOLDER_ID) {
                    Log.d(TAG, "Trying to use TARGET_FOLDER_ID instead")
                    try {
                        val folder = driveService?.files()?.get(TARGET_FOLDER_ID)
                            ?.setFields("id, name")
                            ?.execute()
                        if (folder != null) {
                            Log.d(TAG, "Successfully switched to TARGET_FOLDER_ID: ${folder.name}")
                            targetFolderId = TARGET_FOLDER_ID
                        }
                    } catch (e2: Exception) {
                        Log.e(TAG, "Cannot access TARGET_FOLDER_ID either: ${e2.message}")

                        // Last resort - create a new folder
                        Log.d(TAG, "Creating fallback folder")
                        targetFolderId = findOrCreatePCDScreenshotsFolder() ?:
                                throw Exception("Cannot create or access any folder for screenshots")
                    }
                } else {
                    // Try to create a new folder as last resort
                    Log.d(TAG, "Looking for PCD Screenshots folder")
                    targetFolderId = findOrCreatePCDScreenshotsFolder() ?:
                            throw Exception("Cannot create folder for screenshots")
                }
                Log.d(TAG, "Using folder ID: $targetFolderId")
            }

            // Create file metadata
            val timestamp = System.currentTimeMillis()
            val fileName = "screenshot_${childId}_${timestamp}.png"

            val fileMetadata = File().apply {
                name = fileName
                parents = listOf(targetFolderId)
                // Add custom properties for organization
                appProperties = mapOf(
                    "userId" to userId,
                    "childId" to childId,
                    "timestamp" to timestamp.toString()
                )
            }

            // Create file content
            val mediaContent = FileContent("image/png", sourceFile)

            // Upload file to Drive
            Log.d(TAG, "Uploading file $fileName to folder $targetFolderId")
            val uploadedFile = driveService?.files()?.create(fileMetadata, mediaContent)
                ?.setFields("id, name, webViewLink")
                ?.execute()

            val fileId = uploadedFile?.id
            Log.d(TAG, "File uploaded successfully with ID: $fileId, webViewLink: ${uploadedFile?.webViewLink}")

            return fileId
        } catch (e: Exception) {
            Log.e(TAG, "Error uploading file to Drive: ${e.message}", e)
            throw e
        }
    }
}