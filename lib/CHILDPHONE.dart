import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'AppUsageService.dart';

bool notificationsEnabled = true;
bool restrictionsEnabled = true;

class ChildPhonePage extends StatefulWidget {
  const ChildPhonePage({super.key});

  @override
  State<ChildPhonePage> createState() => _ChildPhonePageState();
}

class _ChildPhonePageState extends State<ChildPhonePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Use the AppUsageService singleton
  final AppUsageService _appUsageService = AppUsageService();

  StreamSubscription? _appUsageSubscription;
  String? _currentChildId;
  String? _currentApp;
  Map<String, int> _appUsageStats = {};
  List<String> _installedApps = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  bool _isLoadingApps = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _initNotifications();
    await _appUsageService.initialize();
    _hasPermission = await _appUsageService.hasUsagePermission();

    if (!_hasPermission) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    await _loadParentSettings();
    _setupAppUsageListener();
    await _loadInstalledApps();

    // Set up a refresh timer to update app stats periodically
    _refreshTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      await _refreshData();
    });

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _refreshData() async {
    try {
      // Refresh app usage stats
      final stats = await _appUsageService.getAppUsageStats();
      final currentApp = await _appUsageService.getCurrentForegroundApp();

      setState(() {
        _appUsageStats = stats;
        _currentApp = currentApp;
      });

      // Check app time and notify if needed
      _checkAppTimeAndNotify();
    } catch (e) {
      print('Error refreshing data: $e');
    }
  }

  Future<void> _loadInstalledApps() async {
    setState(() {
      _isLoadingApps = true;
    });

    try {
      // Using getTargetedApps() instead of getAllApps() since it is available in AppUsageService
      final apps = await _appUsageService.getTargetedApps();
      setState(() {
        _installedApps = apps;
        _isLoadingApps = false;
      });
    } catch (e) {
      print('Error loading installed apps: $e');
      setState(() {
        _isLoadingApps = false;
      });
    }
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings androidInitSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
    InitializationSettings(android: androidInitSettings);

    await notificationsPlugin.initialize(initSettings);
  }

  void _setupAppUsageListener() {
    // Subscribe to app usage updates from the service
    _appUsageSubscription = _appUsageService.appUsageStream.listen((data) {
      final currentApp = data['currentApp'] as String?;

      // Handle potential null or invalid usageStats
      final usageStatsData = data['usageStats'];
      Map<String, int> usageStats = {};

      if (usageStatsData != null && usageStatsData is Map<Object?, Object?>) {
        usageStats = Map<String, int>.from(
            usageStatsData.map(
                    (key, value) => MapEntry(key.toString(), (value as num).toInt())
            )
        );
      }

      if (mounted) {
        setState(() {
          _currentApp = currentApp;
          _appUsageStats = usageStats;
        });

        // Check if we need to send notifications based on remaining time
        _checkAppTimeAndNotify();
      }
    });
  }

  Future<void> _loadParentSettings() async {
    final parent = _auth.currentUser;
    if (parent == null) return;

    try {
      final doc = await _firestore.collection('parents').doc(parent.uid).get();
      final data = doc.data() ?? {};

      setState(() {
        notificationsEnabled = data['notificationsEnabled'] ?? true;
        restrictionsEnabled = data['restrictionsEnabled'] ?? true;
      });

      if (restrictionsEnabled) {
        // Get child ID of the first child (could be improved to handle multiple children)
        final childrenSnapshot = await _firestore
            .collection('parents')
            .doc(parent.uid)
            .collection('children')
            .limit(1)
            .get();

        if (childrenSnapshot.docs.isNotEmpty) {
          _currentChildId = childrenSnapshot.docs.first.id;

          // Start tracking usage with the AppUsageService
          if (_hasPermission) {
            await _appUsageService.startUsageTracking(
              intervalSeconds: 60,
              childId: _currentChildId,
            );
          }
        }
      }
    } catch (e) {
      print('Error loading parent settings: $e');
    }
  }

  void _checkAppTimeAndNotify() async {
    if (_currentChildId == null || _currentApp == null || !notificationsEnabled) return;

    final parent = _auth.currentUser;
    if (parent == null) return;

    try {
      // Get the current child's data
      final childDoc = await _firestore
          .collection('parents')
          .doc(parent.uid)
          .collection('children')
          .doc(_currentChildId)
          .get();

      if (!childDoc.exists) return;

      final childData = childDoc.data() as Map<String, dynamic>;
      final allowedApps = Map<String, dynamic>.from(childData['allowedApps'] ?? {});

      // Check if current app has a time limit
      if (_currentApp != null && allowedApps.containsKey(_currentApp)) {
        final timeLeft = allowedApps[_currentApp] as int;

        // Send notification when 5 minutes are left
        if (timeLeft == 5) {
          _sendNotification(
              "${childData['name']} has 5 min left on $_currentApp!"
          );
        }

        // Send notification when time is up
        if (timeLeft <= 0) {
          _sendNotification(
              "${childData['name']}'s time is up for $_currentApp. The app should be closed."
          );
        }
      }
    } catch (e) {
      print('Error checking app time: $e');
    }
  }

  void _sendNotification(String message) async {
    if (!notificationsEnabled) return;

    try {
      const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
          'app_timer',
          'App Usage Timer',
          importance: Importance.max,
          priority: Priority.high
      );

      const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

      await notificationsPlugin.show(
          0,
          'Usage Alert',
          message,
          platformDetails
      );
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  void _showEditTimeDialog(String childId, String app, int currentTime) {
    final controller = TextEditingController(text: currentTime.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit time for $app'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Time (minutes)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final newTime = int.tryParse(controller.text) ?? currentTime;
                await _updateAppTime(childId, app, newTime);
                Navigator.pop(context);
              } catch (e) {
                print('Error updating app time: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update time limit')),
                );
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddAppDialog(String childId) async {
    // Ensure we have the latest list of installed apps
    if (_installedApps.isEmpty) {
      await _loadInstalledApps();
    }

    String? selectedApp;
    final timeController = TextEditingController();
    final searchController = TextEditingController();
    List<String> filteredApps = List.from(_installedApps);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text('Add App Limit'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Apps',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setStateDialog(() {
                        filteredApps = _installedApps
                            .where((app) => app.toLowerCase().contains(value.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  SizedBox(height: 10),
                  _isLoadingApps
                      ? Center(child: CircularProgressIndicator())
                      : Flexible(
                    child: Container(
                      height: 200,
                      child: filteredApps.isEmpty
                          ? Center(child: Text('No apps found'))
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = filteredApps[index];
                          return ListTile(
                            title: Text(app),
                            leading: Icon(Icons.app_shortcut),
                            selected: selectedApp == app,
                            onTap: () {
                              setStateDialog(() {
                                selectedApp = app;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: timeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Time Limit (minutes)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final time = int.tryParse(timeController.text.trim()) ?? 0;
                    if (selectedApp != null && time > 0) {
                      await _updateAppTime(childId, selectedApp!, time);
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please select an app and enter a valid time limit'),
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error adding app: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to add app limit')),
                    );
                  }
                },
                child: Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateAppTime(String childId, String app, int newTime) async {
    try {
      // Update app time limit using AppUsageService's existing method
      // We'll use setAppTimeLimit instead of addOrUpdateApp
      await _appUsageService.setAppTimeLimit(app, newTime);

      // Update directly in Firestore as well
      await _updateAppTimeInFirestore(childId, app, newTime);

      // Immediately update the UI by refreshing data
      final stats = await _appUsageService.getAppUsageStats();
      final currentApp = await _appUsageService.getCurrentForegroundApp();

      if (mounted) {
        setState(() {
          _appUsageStats = stats;
          _currentApp = currentApp;
        });
      }
    } catch (e) {
      print('Error updating app time: $e');
      throw e; // Rethrow to handle in the calling function
    }
  }

  // New method to update app time in Firestore directly
  Future<void> _updateAppTimeInFirestore(String childId, String appName, int timeLimit) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final childRef = _firestore
          .collection('parents')
          .doc(user.uid)
          .collection('children')
          .doc(childId);

      final childDoc = await childRef.get();
      if (!childDoc.exists) return;

      final childData = childDoc.data() as Map<String, dynamic>;

      // Get current allowed apps
      final allowedApps = Map<String, dynamic>.from(childData['allowedApps'] ?? {});

      // Update app time limit
      allowedApps[appName] = timeLimit;

      await childRef.update({
        'allowedApps': allowedApps,
      });
    } catch (e) {
      print('Error updating app time in Firestore: $e');
      throw e;
    }
  }

  void _showPasswordDialog(
      String password,
      String app, {
        required VoidCallback onSuccess,
      }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter password to edit $app'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text == password) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Access granted to edit $app')),
                );
                onSuccess();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Incorrect password')),
                );
              }
            },
            child: Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.privacy_tip, size: 64, color: Colors.amber),
          SizedBox(height: 16),
          Text(
            'Usage statistics permission required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text(
            'This app needs permission to access usage statistics to monitor app usage.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: () async {
              await _appUsageService.requestUsagePermission();
              // Check if permission was granted
              final hasPermission = await _appUsageService.hasUsagePermission();

              if (mounted) {
                setState(() {
                  _hasPermission = hasPermission;
                });
              }

              if (hasPermission) {
                _loadParentSettings();
                _setupAppUsageListener();
                _loadInstalledApps();
              }
            },
            child: Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  Widget buildChildCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final apps = Map<String, dynamic>.from(data['allowedApps'] ?? {});
    final filteredApps =
    apps.entries.where((entry) => entry.value > 0).toList();
    final totalPhoneTime =
    filteredApps.fold(0, (sum, val) => sum + (val.value as int));
    final password = data['password'] ?? '';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    data['name'] ?? 'Child',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                if (_currentApp != null)
                  Chip(
                    label: Text('Currently using: $_currentApp'),
                    backgroundColor: Colors.blue[100],
                  ),
              ],
            ),
            SizedBox(height: 8),
            Text("Remaining phone time: $totalPhoneTime min"),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add App Limit'),
              onPressed: () => _showAddAppDialog(doc.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'App Time Limits',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            if (filteredApps.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('No app limits set', style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            ...filteredApps.map((entry) {
              final app = entry.key;
              final timeLeft = entry.value;

              // Check if this is the current app
              final bool isCurrentApp = app == _currentApp;

              return Card(
                color: isCurrentApp ? Colors.blue[50] : null,
                margin: EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(
                    Icons.app_shortcut,
                    color: isCurrentApp ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    app,
                    style: TextStyle(
                        fontWeight: isCurrentApp ? FontWeight.bold : FontWeight.normal
                    ),
                  ),
                  subtitle: Text("Time left: $timeLeft min"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit),
                        onPressed: () => _showPasswordDialog(
                          password,
                          app,
                          onSuccess: () => _showEditTimeDialog(doc.id, app, timeLeft),
                        ),
                      ),
                      // Add a delete button
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showPasswordDialog(
                          password,
                          app,
                          onSuccess: () async {
                            try {
                              // Set time to 0 to effectively remove the app
                              await _updateAppTime(doc.id, app, 0);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('App limit removed')),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to remove app limit')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // Show app usage stats
            if (_appUsageStats.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                'Today\'s App Usage',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Container(
                height: 200,
                child: ListView(
                  children: _appUsageStats.entries
                      .where((entry) => entry.value > 0)
                      .map((entry) {
                    final totalUsage = _appUsageStats.values.fold(0, (a, b) => a + b);
                    final progressValue = totalUsage > 0
                        ? entry.value / (totalUsage * 1.5)
                        : 0.0;

                    return ListTile(
                      dense: true,
                      title: Text(entry.key),
                      trailing: Text('${entry.value} min'),
                      subtitle: LinearProgressIndicator(
                        value: progressValue.clamp(0.0, 1.0),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parent = _auth.currentUser;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Child Phone Control"),
          backgroundColor: Colors.blue[900],
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (parent == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Child Phone Control"),
          backgroundColor: Colors.blue[900],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Not logged in"),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Navigate to login page or trigger login
                  // This depends on your app's navigation structure
                },
                child: Text("Login"),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Child Phone Control"),
          backgroundColor: Colors.blue[900],
        ),
        body: _buildPermissionRequest(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Child Phone Control"),
        backgroundColor: Colors.blue[900],
        actions: [
          // Toggle for notifications
          Row(
            children: [
              Text("Notifications"),
              Switch(
                value: notificationsEnabled,
                onChanged: (value) async {
                  setState(() {
                    notificationsEnabled = value;
                  });

                  try {
                    // Save to Firestore
                    await _firestore
                        .collection('parents')
                        .doc(parent.uid)
                        .update({'notificationsEnabled': value});
                  } catch (e) {
                    print('Error updating notification setting: $e');
                  }
                },
                activeColor: Colors.white,
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              setState(() {
                _isLoading = true;
              });

              try {
                // Refresh installed apps list
                await _loadInstalledApps();

                // Refresh app usage stats
                await _refreshData();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Data refreshed')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to refresh data')),
                );
              } finally {
                setState(() {
                  _isLoading = false;
                });
              }
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: _firestore
            .collection('parents')
            .doc(parent.uid)
            .collection('children')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error loading data: ${snapshot.error}"));
          }

          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("No children found"),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to add child page
                      // This depends on your app's navigation structure
                    },
                    child: Text("Add Child"),
                  ),
                ],
              ),
            );
          }

          return ListView(
            children: docs.map((doc) => buildChildCard(doc)).toList(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    // Clean up resources
    _appUsageSubscription?.cancel();
    _appUsageService.stopUsageTracking();
    _refreshTimer?.cancel();
    super.dispose();
  }
}