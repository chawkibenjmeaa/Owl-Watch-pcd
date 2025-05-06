import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

class GoogleDriveService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  );

  static drive.DriveApi? _driveApi;
  static bool _initialized = false;

  /// Initialize the Google Drive service
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Sign in silently (without UI)
      await _googleSignIn.signInSilently();

      // Get http client
      final client = await _googleSignIn.authenticatedClient();

      if (client != null) {
        _driveApi = drive.DriveApi(client);
        _initialized = true;
        debugPrint('Google Drive API initialized successfully');
      } else {
        debugPrint('Failed to initialize Google Drive API - client is null');
      }
    } catch (e) {
      debugPrint('Error initializing Google Drive service: $e');
    }
  }

  /// Sign in to Google if not already signed in
  static Future<bool> _ensureSignedIn() async {
    if (_driveApi != null) return true;

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        debugPrint('Google Sign-In failed or was canceled');
        return false;
      }

      // Get http client
      final client = await _googleSignIn.authenticatedClient();

      if (client != null) {
        _driveApi = drive.DriveApi(client);
        _initialized = true;
        debugPrint('Google Drive API initialized after sign-in');
        return true;
      } else {
        debugPrint('Failed to get authenticated client');
        return false;
      }
    } catch (e) {
      debugPrint('Error signing in to Google: $e');
      return false;
    }
  }

  /// Get or create a folder in Google Drive
  static Future<String?> _getOrCreateFolder(String folderName, {String? parentId}) async {
    if (!await _ensureSignedIn()) return null;

    try {
      // Search for existing folder
      String query = "name='$folderName' and mimeType='application/vnd.google-apps.folder'";
      if (parentId != null) {
        query += " and '$parentId' in parents";
      }
      query += " and trashed=false";

      final result = await _driveApi!.files.list(
        q: query,
        $fields: 'files(id, name)',
      );

      // Return existing folder if found
      if (result.files != null && result.files!.isNotEmpty) {
        debugPrint('Found existing folder: ${result.files!.first.name}');
        return result.files!.first.id;
      }

      // Create new folder
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      if (parentId != null) {
        folder.parents = [parentId];
      }

      final createdFolder = await _driveApi!.files.create(folder);
      debugPrint('Created new folder: $folderName with ID: ${createdFolder.id}');
      return createdFolder.id;
    } catch (e) {
      debugPrint('Error getting or creating folder: $e');
      return null;
    }
  }

  /// Upload a screenshot to Google Drive
  static Future<bool> uploadScreenshot({
    required Uint8List bytes,
    required String firebaseUserId,
    required String childId,
    required String timestamp,
  }) async {
    if (!await _ensureSignedIn()) return false;

    try {
      // Create folder structure (Base folder/UserID/ChildID)
      final baseFolder = await _getOrCreateFolder('OwlWatch Screenshots');
      if (baseFolder == null) return false;

      final userFolder = await _getOrCreateFolder(firebaseUserId, parentId: baseFolder);
      if (userFolder == null) return false;

      final childFolder = await _getOrCreateFolder(childId, parentId: userFolder);
      if (childFolder == null) return false;

      // Create file metadata
      final fileMetadata = drive.File()
        ..name = 'screenshot_$timestamp.jpg'
        ..mimeType = 'image/jpeg'
        ..parents = [childFolder];

      // Create media stream for upload
      final media = drive.Media(
        http.ByteStream.fromBytes(bytes),
        bytes.length,
        contentType: 'image/jpeg',
      );

      // Upload file
      final uploadedFile = await _driveApi!.files.create(
        fileMetadata,
        uploadMedia: media,
      );

      debugPrint('Uploaded screenshot to Google Drive with ID: ${uploadedFile.id}');
      return true;
    } catch (e) {
      debugPrint('Error uploading screenshot to Google Drive: $e');
      return false;
    }
  }

  /// Get a list of screenshots for a specific child
  static Future<List<Map<String, String>>> getScreenshotsList(
      String firebaseUserId,
      String childId,
      ) async {
    if (!await _ensureSignedIn()) return [];

    try {
      // Get folder structure
      final baseFolder = await _getOrCreateFolder('OwlWatch Screenshots');
      if (baseFolder == null) return [];

      final userFolder = await _getOrCreateFolder(firebaseUserId, parentId: baseFolder);
      if (userFolder == null) return [];

      final childFolder = await _getOrCreateFolder(childId, parentId: userFolder);
      if (childFolder == null) return [];

      // List files in the child folder
      final result = await _driveApi!.files.list(
        q: "'$childFolder' in parents and trashed=false",
        $fields: 'files(id, name, createdTime, webViewLink)',
        orderBy: 'createdTime desc',
      );

      if (result.files == null || result.files!.isEmpty) {
        debugPrint('No screenshots found for child: $childId');
        return [];
      }

      // Map files to a list of maps with relevant information
      final screenshots = result.files!.map((file) {
        return {
          'id': file.id ?? '',
          'name': file.name ?? '',
          'timestamp': file.createdTime?.toIso8601String() ?? '',
          'viewUrl': file.webViewLink ?? '',
        };
      }).toList();

      debugPrint('Found ${screenshots.length} screenshots for child: $childId');
      return screenshots;
    } catch (e) {
      debugPrint('Error getting screenshots list: $e');
      return [];
    }
  }

  /// Download a screenshot from Google Drive
  static Future<Uint8List?> downloadScreenshot(String fileId) async {
    if (!await _ensureSignedIn()) return null;

    try {
      // Get media content
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      // Collect all bytes
      final List<int> dataStore = [];
      await media.stream.forEach((data) {
        dataStore.addAll(data);
      });

      return Uint8List.fromList(dataStore);
    } catch (e) {
      debugPrint('Error downloading screenshot: $e');
      return null;
    }
  }

  /// Delete a screenshot from Google Drive
  static Future<bool> deleteScreenshot(String fileId) async {
    if (!await _ensureSignedIn()) return false;

    try {
      await _driveApi!.files.delete(fileId);
      debugPrint('Deleted screenshot with ID: $fileId');
      return true;
    } catch (e) {
      debugPrint('Error deleting screenshot: $e');
      return false;
    }
  }

  /// Delete all screenshots for a specific child
  static Future<bool> deleteAllScreenshots(
      String firebaseUserId,
      String childId,
      ) async {
    if (!await _ensureSignedIn()) return false;

    try {
      // Get folder structure
      final baseFolder = await _getOrCreateFolder('OwlWatch Screenshots');
      if (baseFolder == null) return false;

      final userFolder = await _getOrCreateFolder(firebaseUserId, parentId: baseFolder);
      if (userFolder == null) return false;

      final childFolder = await _getOrCreateFolder(childId, parentId: userFolder);
      if (childFolder == null) return false;

      // Get all files in the child folder
      final result = await _driveApi!.files.list(
        q: "'$childFolder' in parents and trashed=false",
        $fields: 'files(id)',
      );

      if (result.files == null || result.files!.isEmpty) {
        debugPrint('No screenshots found to delete for child: $childId');
        return true;
      }

      // Delete each file
      for (final file in result.files!) {
        if (file.id != null) {
          await _driveApi!.files.delete(file.id!);
        }
      }

      debugPrint('Deleted ${result.files!.length} screenshots for child: $childId');

      // Optionally, delete the child folder itself
      // await _driveApi!.files.delete(childFolder);

      return true;
    } catch (e) {
      debugPrint('Error deleting all screenshots: $e');
      return false;
    }
  }

  /// Sign out from Google
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _driveApi = null;
      _initialized = false;
      debugPrint('Signed out from Google');
    } catch (e) {
      debugPrint('Error signing out from Google: $e');
    }
  }

  /// Check if user is signed in
  static Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      debugPrint('Error checking sign-in status: $e');
      return false;
    }
  }

  /// Get current user email
  static Future<String?> getCurrentUserEmail() async {
    try {
      final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      return account?.email;
    } catch (e) {
      debugPrint('Error getting current user email: $e');
      return null;
    }
  }

  /// Share a folder with another user
  static Future<bool> shareFolder({
    required String folderId,
    required String email,
    required String role, // 'reader', 'writer', or 'owner'
  }) async {
    if (!await _ensureSignedIn()) return false;

    try {
      final permission = drive.Permission()
        ..type = 'user'
        ..role = role
        ..emailAddress = email;

      await _driveApi!.permissions.create(
        permission,
        folderId,
        sendNotificationEmail: true,
      );

      debugPrint('Shared folder $folderId with $email as $role');
      return true;
    } catch (e) {
      debugPrint('Error sharing folder: $e');
      return false;
    }
  }
}
