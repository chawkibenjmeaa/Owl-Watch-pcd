import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveService {
  static const MethodChannel _channel = MethodChannel('com.example.flutter_application_1/drive');
  static const String FOLDER_ID_PREF_KEY = 'drive_target_folder_id';

  // Target folder ID will now be loaded from SharedPreferences with a fallback value
  static String _targetFolderId = '1h7jYxV3fYOEy4xDhLqgCHVkR4okZOa9i';
  static String get targetFolderId => _targetFolderId;

  static bool _isInitialized = false;
  static bool _isInitializing = false;
  static final List<Function> _initCallbacks = [];
  static final String CREDENTIALS_FILENAME = 'credentials.json';

  // Load the stored folder ID from SharedPreferences
  static Future<void> _loadTargetFolderId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString(FOLDER_ID_PREF_KEY);
      if (storedId != null && storedId.isNotEmpty) {
        _targetFolderId = storedId;
        debugPrint('📂 Loaded target folder ID from preferences: $_targetFolderId');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading target folder ID: $e');
    }
  }

  // Initialize the Drive API client with better error handling and callback support
  static Future<bool> initialize() async {
    // Load any previously saved folder ID
    await _loadTargetFolderId();

    if (_isInitialized) return true;
    if (_isInitializing) {
      // Return a promise that will be resolved when initialization completes
      Completer<bool> completer = Completer<bool>();
      _initCallbacks.add((bool success) => completer.complete(success));
      return completer.future;
    }

    _isInitializing = true;
    try {
      // Get the path to the credentials file - use both paths to ensure compatibility
      final appDocDir = await getApplicationDocumentsDirectory();
      final appDocPath = '${appDocDir.path}/$CREDENTIALS_FILENAME';

      // Get the application files directory path (matches Android's context.filesDir)
      final appFilesDir = await getApplicationSupportDirectory();
      final appFilesPath = '${appFilesDir.path}/$CREDENTIALS_FILENAME';

      // Log both paths for debugging
      debugPrint('App documents credentials path: $appDocPath');
      debugPrint('App files credentials path: $appFilesPath');

      // Ensure the credentials file exists in both locations
      File docCredentialsFile = File(appDocPath);
      if (await docCredentialsFile.exists()) {
        // Verify file size and content
        int fileSize = await docCredentialsFile.length();
        debugPrint('Credentials file size: $fileSize bytes');

        if (fileSize < 100) {
          debugPrint('Warning: Credentials file seems too small: $fileSize bytes');
        }

        // Copy from app documents to app files directory
        File filesCredentialsFile = File(appFilesPath);
        if (!await filesCredentialsFile.exists()) {
          await filesCredentialsFile.writeAsBytes(await docCredentialsFile.readAsBytes());
          debugPrint('Copied credentials to files directory: $appFilesPath');
        }
      } else {
        debugPrint('❌ Credentials file not found at: $appDocPath');

        // Look in alternative locations
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/$CREDENTIALS_FILENAME';
        File tempCredentialsFile = File(tempPath);

        if (await tempCredentialsFile.exists()) {
          debugPrint('Found credentials in temp directory, copying to app files');
          File filesCredentialsFile = File(appFilesPath);
          await filesCredentialsFile.writeAsBytes(await tempCredentialsFile.readAsBytes());
        } else {
          debugPrint('❌ Could not find credentials file in any location');
          _isInitialized = false;
          _isInitializing = false;
          return false;
        }
      }

      // Verify the file contents
      File fileToCheck = File(appFilesPath);
      if (await fileToCheck.exists()) {
        String fileContents = await fileToCheck.readAsString();
        if (fileContents.isEmpty || !fileContents.contains('service_account')) {
          debugPrint('❌ Credentials file exists but appears invalid');
          _isInitialized = false;
          _isInitializing = false;
          return false;
        }

        // Log the service account email from credentials for verification
        if (fileContents.contains('client_email')) {
          final emailStartIndex = fileContents.indexOf('client_email');
          if (emailStartIndex > 0) {
            final emailSubstring = fileContents.substring(emailStartIndex, fileContents.indexOf(',', emailStartIndex));
            debugPrint('📧 Service account email from credentials: $emailSubstring');
          }
        }
      } else {
        debugPrint('❌ Credentials file does not exist at expected path: $appFilesPath');
        _isInitialized = false;
        _isInitializing = false;
        return false;
      }

      // Initialize the native Drive service with explicit error logging
      Map<String, dynamic> args = {
        'credentialsPath': appFilesPath  // Pass the path that Android code expects
      };

      try {
        final result = await _channel.invokeMethod<bool>('initializeDriveService', args) ?? false;
        _isInitialized = result;
        debugPrint('Google Drive service initialized successfully: $_isInitialized');

        // Verify service account after initialization
        if (_isInitialized) {
          final accountInfo = await getServiceAccountInfo();
          if (accountInfo != null) {
            debugPrint('📧 Active service account: ${accountInfo['email']}');
          }
        }
      } catch (e) {
        debugPrint('❌ Method channel error: ${e.toString()}');
        _isInitialized = false;
      }

      // Notify all pending callbacks
      for (var callback in _initCallbacks) {
        callback(_isInitialized);
      }
      _initCallbacks.clear();

      return _isInitialized;
    } catch (e) {
      debugPrint('❌ Error initializing Google Drive service: $e');
      _isInitialized = false;
      _isInitializing = false;

      // Notify all pending callbacks of failure
      for (var callback in _initCallbacks) {
        callback(false);
      }
      _initCallbacks.clear();

      return false;
    }
  }

  // Upload screenshot to Google Drive with retry mechanism
  static Future<String?> uploadScreenshot({
    required Uint8List bytes,
    required String firebaseUserId,
    required String childId,
    required String timestamp,
    int retryCount = 3,
  }) async {
    if (!_isInitialized) {
      debugPrint('Drive API not initialized, initializing now...');
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('❌ Failed to initialize Google Drive service');
        return null;
      }
    }

    String? fileId;
    File? tempFile;

    try {
      // Create a temporary file to upload
      final tempDir = await getTemporaryDirectory();
      final fileName = 'screenshot_${childId}_$timestamp.png';
      tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      debugPrint('Created temporary file: ${tempFile.path}');
      debugPrint('File size: ${await tempFile.length()} bytes');

      // Try to upload with retries
      for (int attempt = 0; attempt < retryCount; attempt++) {
        try {
          // Use the native method channel to upload the file
          fileId = await _channel.invokeMethod<String>('uploadFile', {
            'filePath': tempFile.path,
            'userId': firebaseUserId,
            'childId': childId,
            'folderId': _targetFolderId,
          });

          if (fileId != null) {
            debugPrint('✅ Screenshot uploaded to Drive with ID: $fileId');
            break;
          } else {
            debugPrint('❌ Upload attempt ${attempt+1} failed, fileId is null');
            if (attempt < retryCount - 1) {
              await Future.delayed(Duration(seconds: 2 * (attempt + 1))); // Exponential backoff
            }
          }
        } catch (e) {
          debugPrint('❌ Upload attempt ${attempt+1} failed with error: $e');

          if (attempt < retryCount - 1) {
            await Future.delayed(Duration(seconds: 2 * (attempt + 1))); // Exponential backoff
          } else {
            rethrow; // Re-throw on last attempt
          }
        }
      }

      return fileId;
    } catch (e) {
      debugPrint('❌ Error uploading screenshot to Drive after $retryCount attempts: $e');
      return null;
    } finally {
      // Clean up temp file even if upload fails
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (e) {
          debugPrint('Warning: Error deleting temporary file: $e');
        }
      }
    }
  }

  // Verify access to a specific folder
  static Future<bool> verifyFolderAccess(String folderId) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      debugPrint('Verifying access to folder ID: $folderId');
      final result = await _channel.invokeMethod<bool>('verifyDriveAccess', {
        'folderId': folderId
      }) ?? false;

      if (result) {
        debugPrint('✅ Successfully verified access to Drive folder: $folderId');
      } else {
        debugPrint('❌ Cannot access Drive folder: $folderId');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error verifying folder access: $e');
      return false;
    }
  }

  // Check if the Drive API is properly configured with improved diagnostics
  static Future<bool> verifyDriveAccess() async {
    if (!_isInitialized) {
      debugPrint('Drive service not initialized, initializing now...');
      final initialized = await initialize();
      if (!initialized) {
        debugPrint('❌ Failed to initialize Drive service');
        return false;
      }
    }

    try {
      // First try to validate the targetFolderId
      if (_targetFolderId.isEmpty) {
        debugPrint('❌ Target folder ID is empty');
        return false;
      }

      debugPrint('Verifying access to folder ID: $_targetFolderId');

      final result = await _channel.invokeMethod<bool>('verifyDriveAccess', {
        'folderId': _targetFolderId
      }) ?? false;

      if (result) {
        debugPrint('✅ Successfully verified access to Drive folder');
      } else {
        debugPrint('❌ Failed to verify Drive folder access');

        // Try to list files instead to see if we have any access
        try {
          final hasAnyAccess = await _channel.invokeMethod<bool>('listFiles', {
            'maxResults': 1
          }) ?? false;

          if (hasAnyAccess) {
            debugPrint('✅ Drive service has access to Drive API, but not to the specified folder');
            debugPrint('⚠️ Please check that the folder ID is correct and shared with the service account');
          } else {
            debugPrint('❌ Drive service cannot access Drive API at all');
            debugPrint('⚠️ Please check service account credentials and scopes');
          }
        } catch (e) {
          debugPrint('❌ Error checking general Drive access: $e');
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error verifying Drive access: $e');
      return false;
    }
  }

  // Get information about the service account to help with troubleshooting
  static Future<Map<String, dynamic>?> getServiceAccountInfo() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return null;
    }

    try {
      // Fix for type casting issue - explicitly cast each value in the map
      final result = await _channel.invokeMethod('getServiceAccountInfo');

      if (result == null) {
        return null;
      }

      // Create a new map with the correct types
      final Map<String, dynamic> typedResult = {};
      (result as Map).forEach((key, value) {
        if (key is String) {
          typedResult[key] = value;
        }
      });

      return typedResult;
    } catch (e) {
      debugPrint('❌ Error getting service account info: $e');
      return null;
    }
  }
}