import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_application_1/AppDrawer.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'drive_service.dart';

// Integrated PermissionsHandler class
class PermissionsHandler {
  static const MethodChannel _channel = MethodChannel('owl_watch_screenshot_service');

  // Check all required permissions
  static Future<Map<String, bool>> checkPermissions() async {
    try {
      final Map<dynamic, dynamic> result = await _channel.invokeMethod('checkPermissions');
      return Map<String, bool>.from(result);
    } on PlatformException catch (e) {
      debugPrint('Error checking permissions: ${e.message}');
      return {
        'notifications': false,
        'storage': false,
        'overlay': false,
      };
    }
  }

  // Open app settings
  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      debugPrint('Error opening app settings: ${e.message}');
    }
  }

  // Request overlay permission
  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      debugPrint('Error requesting overlay permission: ${e.message}');
    }
  }

  // Set up permission status listener
  static void setupPermissionStatusListener(Function(Map<String, dynamic>) callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPermissionStatus') {
        final Map<dynamic, dynamic> arguments = call.arguments;
        callback(Map<String, dynamic>.from(arguments));
      }
    });
  }
}

// Permission Dialog Widget
class PermissionDialog extends StatelessWidget {
  final Map<String, bool> permissions;

  const PermissionDialog({Key? key, required this.permissions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Additional Permissions Required'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Some permissions were denied. Please enable them in Settings to use screenshot functionality.'),
          const SizedBox(height: 16),
          if (permissions['notifications'] == false)
            _buildPermissionItem('Notifications', 'Required for service operation'),
          if (permissions['storage'] == false)
            _buildPermissionItem('Storage', 'Required to save screenshots'),
          if (permissions['overlay'] == false)
            _buildPermissionItem('Display over other apps', 'Required for screenshot capture'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            if (permissions['overlay'] == false) {
              PermissionsHandler.requestOverlayPermission();
            } else {
              PermissionsHandler.openAppSettings();
            }
          },
          child: const Text('Open Settings'),
        ),
      ],
    );
  }

  Widget _buildPermissionItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(description, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  _NotificationsPageState createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool appLocked = false;
  bool isCapturing = false;
  List<Map<String, dynamic>> children = [];

  // Platform channel for native Android code
  static const platform = MethodChannel(
    'owl_watch_screenshot_service',
  );
  String? lockedChildId;

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Initialize Google Drive Service
    GoogleDriveService.initialize();

    initializeNotifications();
    fetchChildren();

    // Set up the method channel listener for screenshots from native code
    platform.setMethodCallHandler(_handleMethod);

    // Check for service restoration on app start
    if (Platform.isAndroid) {
      checkServiceStatus();
    }

    // Set up permission status listener using PermissionsHandler
    PermissionsHandler.setupPermissionStatusListener((status) {
      if (status['permissionsDenied'] == true ||
          status['overlayPermissionDenied'] == true ||
          status['mediaProjectionDenied'] == true) {
        _showPermissionDialog();
      }
    });

    // Check permissions on screen load
    _checkPermissions();
  }

  // Check permissions using the PermissionsHandler
  Future<void> _checkPermissions() async {
    final permissions = await PermissionsHandler.checkPermissions();
    if (permissions.values.contains(false)) {
      _showPermissionDialog();
    }
  }

  // Show permission dialog using the PermissionDialog widget
  void _showPermissionDialog() async {
    final permissions = await PermissionsHandler.checkPermissions();
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => PermissionDialog(permissions: permissions),
      );
    }
  }

  // Check if screenshot service is already running
  Future<void> checkServiceStatus() async {
    try {
      final Map<String, dynamic>? status = await platform.invokeMapMethod('getServiceStatus');
      if (status != null && status['isRunning'] == true) {
        setState(() {
          appLocked = true;
          isCapturing = true;
          lockedChildId = status['childId'];
        });
      }
    } catch (e) {
      debugPrint("Error checking service status: $e");
    }
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotTaken':
        final Map<String, dynamic> args = Map<String, dynamic>.from(
          call.arguments,
        );
        final String filePath = args['filePath'];
        final String userId = args['userId'];
        final String childId = args['childId'];

        // Upload the file exclusively to Google Drive
        await _uploadScreenshotToGoogleDrive(filePath, userId, childId);
        break;
      case 'onPermissionError':
      // Handle permission errors from native code
        setState(() {
          isCapturing = false;
          appLocked = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permission denied. Please grant permissions in settings.")),
          );

          // Show permission dialog using PermissionDialog instead
          _showPermissionDialog();
        }
        break;
      case 'onMediaProjectionDenied':
      // When screen capture permission is denied
        setState(() {
          isCapturing = false;
          appLocked = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Screen capture permission denied")),
          );
        }
        break;
      default:
        debugPrint('Unknown method ${call.method}');
    }
  }

  // Updated method that only uses Google Drive
  // Updated method with better error handling and retry logic
  Future<void> _uploadScreenshotToGoogleDrive(
      String filePath,
      String userId,
      String childId,
      ) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint("Screenshot file not found: $filePath");
        return;
      }

      final bytes = await file.readAsBytes();

      // Find child name for notification
      final child = children.firstWhere(
            (c) => c['id'] == childId,
        orElse: () => {'name': 'Unknown'},
      );

      // Try to upload to Google Drive with built-in retry
      final fileId = await GoogleDriveService.uploadScreenshot(
        bytes: bytes,
        firebaseUserId: userId,
        childId: childId,
        timestamp: DateTime.now().millisecondsSinceEpoch.toString(),
        retryCount: 3, // Set retry count
      );

      if (fileId != null) {
        // Show notification for successful upload
        await showNotification(child['name']);
        debugPrint("Screenshot successfully uploaded to Google Drive with ID: $fileId");
      } else {
        // Show a notification about the failed upload
        await showErrorNotification(child['name']);
        debugPrint("Failed to upload screenshot to Google Drive");
      }

      // Delete the temporary file regardless of upload success
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint("Error deleting temporary file: $e");
        }
      }
    } catch (e) {
      debugPrint("Error in upload process: $e");

      // Try to find child name even in error case
      String childName = 'Unknown';
      try {
        final child = children.firstWhere(
              (c) => c['id'] == childId,
          orElse: () => {'name': 'Unknown'},
        );
        childName = child['name'];
      } catch (_) {}

      await showErrorNotification(childName);
    }
  }

  // Add error notification method
  Future<void> showErrorNotification(String childName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'screenshot_error_channel',
      'Screenshot Error Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      1, // Different ID from success notification
      'Upload Failed',
      'Failed to upload screenshot for $childName. Will retry next capture.',
      platformChannelSpecifics,
    );
  }

  // New method to verify Drive access on start
  Future<void> verifyDriveAccessOnStart() async {
    try {
      final hasAccess = await GoogleDriveService.verifyDriveAccess();
      if (!hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Google Drive access issue detected. Please check your internet connection."),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error verifying Drive access: $e");
    }
  }

  Future<void> saveServiceState(String childId, bool isRunning) async {
    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('saveServiceState', {
          'isServiceRunning': isRunning,
          'userId': FirebaseAuth.instance.currentUser?.uid,
          'childId': childId,
          'intervalSeconds': 10, // Using 10 seconds as requested
        });
      } catch (e) {
        debugPrint("Error saving service state: $e");
      }
    }
  }

  Future<void> initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showNotification(String childName) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'screenshot_channel',
      'Screenshot Notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      'Screenshot Uploaded',
      'A new screenshot for $childName was uploaded to Google Drive',
      platformChannelSpecifics,
    );
  }

  Future<void> fetchChildren() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final parentId = user.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('parents')
        .doc(parentId)
        .collection('children')
        .get();

    setState(() {
      children = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, 'name': data['name'] ?? 'Unknown'};
      }).toList();
    });
  }

  // Simplified permission checker that uses PermissionsHandler
  Future<bool> requestRequiredPermissions() async {
    if (!Platform.isAndroid) return true;

    // Show explanation dialog before requesting permissions
    bool shouldProceed = await showExplanationDialog(
      "Permission Required",
      "This app needs access to capture screenshots and upload to Google Drive. "
          "You will be prompted for several permissions. Please grant all of them for the app to work properly.",
    );

    if (!shouldProceed) return false;

    // Check permissions using PermissionsHandler
    final permissions = await PermissionsHandler.checkPermissions();

    if (permissions.values.contains(false)) {
      // Show permission dialog using PermissionDialog
      _showPermissionDialog();
      return false;
    }

    return true;
  }

  // Show explanation dialog before requesting permissions
  Future<bool> showExplanationDialog(String title, String message) async {
    if (!mounted) return false;

    bool proceed = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              proceed = false;
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              proceed = true;
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return proceed;
  }

  // Show media projection dialog
  Future<void> showMediaProjectionDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Screen Capture Permission'),
        content: const Text(
            'The next prompt will ask for permission to capture your screen. '
                'This is required for the screenshot functionality to work. '
                'Screenshots will be uploaded to Google Drive.'
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> startBackgroundScreenshots(String childId) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Background screenshots not supported on web")),
      );
      return;
    }

    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Background screenshots only supported on Android")),
      );
      return;
    }

    // Request all necessary permissions with the simplified helper method
    bool permissionsGranted = await requestRequiredPermissions();

    if (!permissionsGranted) {
      // Don't proceed if permissions weren't granted
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    stopAutoScreenshot(); // Stop any existing screenshot service

    // Show media projection info dialog
    await showMediaProjectionDialog();

    try {
      // Start the native Android screenshot service
      final success = await platform.invokeMethod('startScreenshotService', {
        'intervalSeconds': 10,
        'userId': user.uid,
        'childId': childId,
      });

      if (success) {
        setState(() {
          appLocked = true;
          isCapturing = true;
          lockedChildId = childId;
        });

        // Save service state
        await saveServiceState(childId, true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Screenshot service started - uploading to Google Drive")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to start screenshot service")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void stopAutoScreenshot() async {
    if (isCapturing && Platform.isAndroid) {
      try {
        await platform.invokeMethod('stopScreenshotService');

        // Clear service state when stopping
        if (lockedChildId != null) {
          await saveServiceState(lockedChildId!, false);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Screenshot service stopped")),
        );
      } catch (e) {
        debugPrint("Error stopping screenshot service: $e");
      }
    }

    setState(() {
      isCapturing = false;
      appLocked = false;
      lockedChildId = null;
    });
  }

  Future<void> unlockWithPassword(String childId) async {
    final passwordController = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('parents')
        .doc(user.uid)
        .collection('children')
        .doc(childId)
        .get();

    final storedPassword = snapshot.data()?['password'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter Password to Unlock"),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (passwordController.text == storedPassword) {
                stopAutoScreenshot();
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Incorrect password!")),
                );
              }
            },
            child: const Text("Unlock"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Widget buildChildPhoneActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          const Text(
            "Auto Screenshot Control",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0D47A1),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "All screenshots will be uploaded to Google Drive",
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Color(0xFF455A64),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: children.length,
              itemBuilder: (context, index) {
                final child = children[index];
                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.child_care,
                      color: Color(0xFF1976D2),
                    ),
                    title: Text(child['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("ID: ${child['id']}"),
                        const Text("Interval: Every 10 seconds"),
                        const Text("Upload: Google Drive"),
                        Text(
                          "Mode: ${Platform.isAndroid ? 'Background capture' : 'App-only capture'}",
                        ),
                      ],
                    ),
                    trailing: isCapturing && lockedChildId == child['id']
                        ? TextButton(
                      onPressed: () => unlockWithPassword(child['id']),
                      child: const Text("Unlock"),
                    )
                        : ElevatedButton(
                      onPressed: isCapturing
                          ? null
                          : () => startBackgroundScreenshots(child['id']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1976D2),
                      ),
                      child: const Text("Start"),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "App Locked During Screenshotting",
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 5),
              const Text(
                "Screenshots are being uploaded to Google Drive",
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: lockedChildId != null
                    ? () => unlockWithPassword(lockedChildId!)
                    : null,
                child: const Text("Unlock"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Container(
      height: 220,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
                const Expanded(
                  child: Text(
                    "NOTIFICATIONS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(
                  child: Text(
                    "Alerts",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Tab(
                  child: Text(
                    "Child phone actions",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    stopAutoScreenshot();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(),
      backgroundColor: Colors.blueGrey[50],
      body: Column(
        children: [
          buildHeader(),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    const Center(child: Text("Alerts Section")),
                    buildChildPhoneActions(),
                  ],
                ),
                if (appLocked) buildOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}