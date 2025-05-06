import 'dart:async';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppUsageService {
  static final AppUsageService _instance = AppUsageService._internal();
  factory AppUsageService() => _instance;
  AppUsageService._internal();

  final MethodChannel _channel = const MethodChannel('com.example.flutter_application_1/app_usage');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream controllers for app usage updates
  final _appUsageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get appUsageStream => _appUsageController.stream;

  final _usageStatsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get usageStatsStream => _usageStatsController.stream;

  // Track if service is running
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // Cache for app lists
  List<String> _cachedSocialMediaApps = [];
  List<String> _cachedGameApps = [];
  List<String> _cachedTargetedApps = [];
  List<String> _cachedAllApps = []; // New cache for all installed apps
  DateTime _lastAppListRefresh = DateTime(2000); // Initial date in the past

  // Current child ID being tracked
  String? _currentChildId;

  // Cache for app time limits
  Map<String, int> _appTimeLimits = {};
  Map<String, String> _appPasswords = {};

  // Initialize the service
  Future<void> initialize() async {
    try {
      _channel.setMethodCallHandler(_handleMethodCall);

      // Check if we have permissions
      final hasUsagePermission = await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
      final hasOverlayPermission = await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;

      if (!hasUsagePermission) {
        print('No usage stats permission');
      }

      if (!hasOverlayPermission) {
        print('No overlay permission');
      }

      // Pre-fetch and cache app lists on initialization
      await _prefetchAppLists();
    } catch (e) {
      print('Error initializing AppUsageService: $e');
    }
  }

  // New method to prefetch all app lists at once
  Future<void> _prefetchAppLists() async {
    try {
      print('Prefetching app lists...');

      // Get all installed apps first (fallback if categorization fails)
      final allApps = await _getAllInstalledApps();
      if (allApps.isNotEmpty) {
        _cachedAllApps = allApps;
        print('Cached ${_cachedAllApps.length} installed apps');
      }

      // Try to get categorized apps
      await _getSocialMediaAppsFromNative();
      await _getGameAppsFromNative();
      await _getTargetedAppsFromNative();

      _lastAppListRefresh = DateTime.now();
    } catch (e) {
      print('Error prefetching app lists: $e');
    }
  }

  // Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAppUsageUpdate':
        final Map<String, dynamic> data = Map<String, dynamic>.from(call.arguments);
        _appUsageController.add(data);

        // Update Firestore with the latest app usage data
        await _updateFirestore(data);
        break;
      case 'onUsageStatsUpdate':
        final Map<String, dynamic> data = Map<String, dynamic>.from(call.arguments);
        _usageStatsController.add(data);

        // Update Firestore with usage stats
        await _updateFirestoreWithUsageStats(data);
        break;
      default:
        print('Unknown method ${call.method}');
    }
    return null;
  }

  // Check if app has usage stats permission
  Future<bool> hasUsagePermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } catch (e) {
      print('Error checking usage permission: $e');
      return false;
    }
  }

  // Check if app has overlay permission
  Future<bool> hasOverlayPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
    } catch (e) {
      print('Error checking overlay permission: $e');
      return false;
    }
  }

  // Request usage stats permission
  Future<void> requestUsagePermission() async {
    try {
      await _channel.invokeMethod<bool>('requestUsagePermission');
    } catch (e) {
      print('Error requesting usage permission: $e');
    }
  }

  // Request overlay permission
  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<bool>('requestOverlayPermission');
    } catch (e) {
      print('Error requesting overlay permission: $e');
    }
  }

  // Get all installed apps from native side
  Future<List<String>> _getAllInstalledApps() async {
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>('getAllInstalledApps');
      if (result == null || result.isEmpty) {
        print('Warning: Native side returned null or empty installed apps list');
        return [];
      }

      final apps = result.map((app) => app.toString()).toList();
      print('Retrieved ${apps.length} installed apps from native side');
      return apps;
    } catch (e) {
      print('Error getting all installed apps: $e');
      return [];
    }
  }

  // Get current app usage stats (one-time query)
  Future<Map<String, int>> getAppUsageStats() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getAppUsageStats');
      if (result == null) return {};

      // Convert to Map<String, int>
      return Map<String, int>.fromEntries(
          result.entries.map((entry) => MapEntry(entry.key.toString(), (entry.value as num).toInt()))
      );
    } catch (e) {
      print('Error getting app usage stats: $e');
      return {};
    }
  }

  // Get current foreground app
  Future<String?> getCurrentForegroundApp() async {
    try {
      return await _channel.invokeMethod<String?>('getCurrentForegroundApp');
    } catch (e) {
      print('Error getting current foreground app: $e');
      return null;
    }
  }

  // Internal method to get social media apps from native side
  Future<List<String>> _getSocialMediaAppsFromNative() async {
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>('getSocialMediaApps');
      if (result == null || result.isEmpty) {
        print('Warning: Native side returned null or empty social media apps list');
        return [];
      }

      final apps = result.map((app) => app.toString()).toList();
      _cachedSocialMediaApps = apps;
      print('Retrieved ${apps.length} social media apps from native side');
      return apps;
    } catch (e) {
      print('Error getting social media apps from native: $e');
      return [];
    }
  }

  // Get social media apps with cache and fallback
  Future<List<String>> getSocialMediaApps() async {
    try {
      // Check if we have a recent cache
      final now = DateTime.now();
      if (_cachedSocialMediaApps.isNotEmpty &&
          now.difference(_lastAppListRefresh).inMinutes < 30) {
        return _cachedSocialMediaApps;
      }

      // Try to get from native side
      final apps = await _getSocialMediaAppsFromNative();

      // If we got apps, update cache
      if (apps.isNotEmpty) {
        _cachedSocialMediaApps = apps;
        _lastAppListRefresh = now;
        return _cachedSocialMediaApps;
      }
      // If native method failed but we have a previous cache, use that
      else if (_cachedSocialMediaApps.isNotEmpty) {
        print('Using cached social media apps: ${_cachedSocialMediaApps.length} apps');
        return _cachedSocialMediaApps;
      }
      // If all else failed and we have all apps cached, provide some default social media apps
      else if (_cachedAllApps.isNotEmpty) {
        print('Falling back to filtering all apps for potential social media apps');
        final socialKeywords = ['facebook', 'instagram', 'twitter', 'snapchat', 'tiktok',
          'whatsapp', 'telegram', 'messenger', 'discord', 'reddit', 'linkedin'];

        final filteredApps = _cachedAllApps.where((app) =>
            socialKeywords.any((keyword) => app.toLowerCase().contains(keyword))).toList();

        if (filteredApps.isNotEmpty) {
          _cachedSocialMediaApps = filteredApps;
          return filteredApps;
        }
      }

      return [];
    } catch (e) {
      print('Error getting social media apps: $e');
      // Return cached apps if available despite the error
      return _cachedSocialMediaApps.isNotEmpty ? _cachedSocialMediaApps : [];
    }
  }

  // Internal method to get game apps from native side
  Future<List<String>> _getGameAppsFromNative() async {
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>('getGameApps');
      if (result == null || result.isEmpty) {
        print('Warning: Native side returned null or empty game apps list');
        return [];
      }

      final apps = result.map((app) => app.toString()).toList();
      _cachedGameApps = apps;
      print('Retrieved ${apps.length} game apps from native side');
      return apps;
    } catch (e) {
      print('Error getting game apps from native: $e');
      return [];
    }
  }

  // Get game apps with cache and fallback
  Future<List<String>> getGameApps() async {
    try {
      // Check if we have a recent cache
      final now = DateTime.now();
      if (_cachedGameApps.isNotEmpty &&
          now.difference(_lastAppListRefresh).inMinutes < 30) {
        return _cachedGameApps;
      }

      // Try to get from native side
      final apps = await _getGameAppsFromNative();

      // If we got apps, update cache
      if (apps.isNotEmpty) {
        _cachedGameApps = apps;
        _lastAppListRefresh = now;
        return _cachedGameApps;
      }
      // If native method failed but we have a previous cache, use that
      else if (_cachedGameApps.isNotEmpty) {
        print('Using cached game apps: ${_cachedGameApps.length} apps');
        return _cachedGameApps;
      }
      // If all else failed and we have all apps cached, provide some default game apps
      else if (_cachedAllApps.isNotEmpty) {
        print('Falling back to filtering all apps for potential game apps');
        final gameKeywords = ['game', 'play', 'craft', 'battle', 'royale', 'clash', 'legends',
          'puzzle', 'racing', 'adventure', 'quest', 'sport'];

        final filteredApps = _cachedAllApps.where((app) =>
            gameKeywords.any((keyword) => app.toLowerCase().contains(keyword))).toList();

        if (filteredApps.isNotEmpty) {
          _cachedGameApps = filteredApps;
          return filteredApps;
        }
      }

      return [];
    } catch (e) {
      print('Error getting game apps: $e');
      // Return cached apps if available despite the error
      return _cachedGameApps.isNotEmpty ? _cachedGameApps : [];
    }
  }

  // Internal method to get targeted apps from native side
  Future<List<String>> _getTargetedAppsFromNative() async {
    try {
      final List<Object?>? result = await _channel.invokeMethod<List<Object?>>('getTargetedApps');
      if (result == null || result.isEmpty) {
        print('Warning: Native side returned null or empty targeted apps list');
        return [];
      }

      final apps = result.map((app) => app.toString()).toList();
      _cachedTargetedApps = apps;
      print('Retrieved ${apps.length} targeted apps from native side');
      return apps;
    } catch (e) {
      print('Error getting targeted apps from native: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> debugAppLists() async {
    Map<String, dynamic> result = {};

    try {
      print('Debugging app lists...');

      // Force refresh app lists
      await forceRefreshAppLists();

      // Try to get each list
      final socialApps = await getSocialMediaApps();
      final gameApps = await getGameApps();
      final allApps = await getTargetedApps();
      final installedApps = await _getAllInstalledApps();

      print('Social media apps found: ${socialApps.length}');
      print('Game apps found: ${gameApps.length}');
      print('Total targeted apps found: ${allApps.length}');
      print('Total installed apps found: ${installedApps.length}');

      result = {
        'socialMedia': socialApps,
        'games': gameApps,
        'targeted': allApps,
        'installed': installedApps.take(50).toList(), // First 50 for brevity
      };

      // Debug output
      if (socialApps.isEmpty) {
        print('No social media apps found. Check native detection logic.');
      } else {
        print('First 5 social media apps: ${socialApps.take(5).join(", ")}');
      }

      if (gameApps.isEmpty) {
        print('No game apps found. Check native detection logic.');
      } else {
        print('First 5 game apps: ${gameApps.take(5).join(", ")}');
      }

    } catch (e) {
      print('Error debugging app lists: $e');
      result['error'] = e.toString();
    }

    return result;
  }

  // Get all targeted apps (social media + games) with improved reliability
  Future<List<String>> getTargetedApps() async {
    try {
      // Check if we have a recent cache
      final now = DateTime.now();
      if (_cachedTargetedApps.isNotEmpty &&
          now.difference(_lastAppListRefresh).inMinutes < 30) {
        return _cachedTargetedApps;
      }

      // Try to get from native side
      final apps = await _getTargetedAppsFromNative();

      // If we got apps, update cache
      if (apps.isNotEmpty) {
        _cachedTargetedApps = apps;
        _lastAppListRefresh = now;
        return _cachedTargetedApps;
      }
      // If native method failed but we have both social and game apps, combine them
      else if (_cachedSocialMediaApps.isNotEmpty || _cachedGameApps.isNotEmpty) {
        print('Native targeted apps failed, combining social and game apps');
        final socialApps = await getSocialMediaApps();
        final gameApps = await getGameApps();

        // Combine and deduplicate
        final Set<String> combinedSet = Set<String>.from(socialApps)..addAll(gameApps);
        _cachedTargetedApps = combinedSet.toList();
        return _cachedTargetedApps;
      }
      // Last resort: return all installed apps
      else if (_cachedAllApps.isNotEmpty) {
        print('Falling back to all installed apps');
        _cachedTargetedApps = _cachedAllApps;
        return _cachedAllApps;
      }

      // Try one last direct call to get all apps
      final allApps = await _getAllInstalledApps();
      if (allApps.isNotEmpty) {
        _cachedAllApps = allApps;
        _cachedTargetedApps = allApps;
        return allApps;
      }

      return [];
    } catch (e) {
      print('Error getting targeted apps: $e');

      // Try to return whatever cache we have
      if (_cachedTargetedApps.isNotEmpty) {
        return _cachedTargetedApps;
      }
      if (_cachedAllApps.isNotEmpty) {
        return _cachedAllApps;
      }
      if (_cachedSocialMediaApps.isNotEmpty || _cachedGameApps.isNotEmpty) {
        final Set<String> combinedSet = Set<String>.from(_cachedSocialMediaApps)..addAll(_cachedGameApps);
        return combinedSet.toList();
      }

      return [];
    }
  }

  Future<Map<String, dynamic>> debugInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('debugInstalledApps');
      if (result == null) {
        return {'error': 'No result returned from native side'};
      }

      // Convert to Dart types
      final Map<String, dynamic> dartResult = {};
      result.forEach((key, value) {
        final String keyStr = key.toString();
        if (value is List) {
          dartResult[keyStr] = (value as List<dynamic>).map((item) => item.toString()).toList();
        } else if (value is Map) {
          dartResult[keyStr] = Map<String, dynamic>.from(
              (value as Map).map((k, v) => MapEntry(k.toString(), v))
          );
        } else {
          dartResult[keyStr] = value;
        }
      });

      // Print some debug info
      print('Total apps detected: ${dartResult['totalApps']}');
      print('Social media apps: ${dartResult['socialMediaCount']}');
      print('Game apps: ${dartResult['gamesCount']}');

      if (dartResult.containsKey('socialMediaSamples')) {
        print('Social media samples: ${(dartResult['socialMediaSamples'] as List).join(", ")}');
      }

      if (dartResult.containsKey('gameSamples')) {
        print('Game samples: ${(dartResult['gameSamples'] as List).join(", ")}');
      }

      return dartResult;
    } catch (e) {
      print('Error debugging installed apps: $e');
      return {'error': e.toString()};
    }
  }

  // Start usage tracking service
  Future<void> startUsageTracking({
    int intervalSeconds = 60,
    bool showNotifications = true,
    String? childId
  }) async {
    if (_isRunning) return;

    final user = _auth.currentUser;
    if (user == null) return;

    // Check permissions
    final hasUsagePermission = await this.hasUsagePermission();
    if (!hasUsagePermission) {
      requestUsagePermission();
      return;
    }

    // Start tracking
    await _channel.invokeMethod<bool>('startUsageTracking', {
      'intervalSeconds': intervalSeconds,
      'showNotifications': showNotifications,
    });

    _isRunning = true;
    _currentChildId = childId;

    // Load existing app time limits from Firestore and apply them
    if (childId != null) {
      await _loadAndApplyTimeLimits(childId);
    }
  }

  // Stop usage tracking service
  Future<void> stopUsageTracking() async {
    if (!_isRunning) return;

    await _channel.invokeMethod<bool>('stopUsageTracking');
    _isRunning = false;
    _currentChildId = null;
  }

  // Start app blocker service
  Future<void> startAppBlocker() async {
    // Check overlay permission
    final hasOverlayPermission = await this.hasOverlayPermission();
    if (!hasOverlayPermission) {
      requestOverlayPermission();
      return;
    }

    await _channel.invokeMethod<bool>('startAppBlocker');
  }

  // Stop app blocker service
  Future<void> stopAppBlocker() async {
    await _channel.invokeMethod<bool>('stopAppBlocker');
  }

  // Force refresh app lists
  Future<void> forceRefreshAppLists() async {
    try {
      print('Force refreshing app lists...');

      // Clear caches
      _cachedSocialMediaApps = [];
      _cachedGameApps = [];
      _cachedTargetedApps = [];
      _lastAppListRefresh = DateTime(2000);

      // Get all installed apps first (as fallback)
      _cachedAllApps = await _getAllInstalledApps();

      // Try to get categorized apps
      final socialApps = await _getSocialMediaAppsFromNative();
      if (socialApps.isNotEmpty) {
        _cachedSocialMediaApps = socialApps;
      }

      final gameApps = await _getGameAppsFromNative();
      if (gameApps.isNotEmpty) {
        _cachedGameApps = gameApps;
      }

      final targetedApps = await _getTargetedAppsFromNative();
      if (targetedApps.isNotEmpty) {
        _cachedTargetedApps = targetedApps;
      } else {
        // If targeted apps failed, combine social and game
        final Set<String> combinedSet = Set<String>.from(_cachedSocialMediaApps)..addAll(_cachedGameApps);
        _cachedTargetedApps = combinedSet.toList();
      }

      _lastAppListRefresh = DateTime.now();

      print('App lists refreshed: ${_cachedSocialMediaApps.length} social, ${_cachedGameApps.length} games, ${_cachedTargetedApps.length} targeted');
    } catch (e) {
      print('Error refreshing app lists: $e');
    }
  }

  // Set time limit for an app
  Future<void> setAppTimeLimit(String appName, int timeLimit, {String password = "1234"}) async {
    try {
      // Update local cache
      _appTimeLimits[appName] = timeLimit;
      _appPasswords[appName] = password;

      // Update limits in the native side
      await _channel.invokeMethod<bool>('setAppTimeLimits', {
        'limits': _appTimeLimits,
        'passwords': _appPasswords,
      });

      // Update Firestore if a child is being tracked
      if (_currentChildId != null) {
        await updateAppTimeLimit(_currentChildId!, appName, timeLimit, password);
      }
    } catch (e) {
      print('Error setting app time limit: $e');
    }
  }

  // Update app time limit in Firestore
  Future<void> updateAppTimeLimit(String childId, String appName, int timeLimit, String password) async {
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

      // Get current app restrictions
      final appRestrictions = Map<String, dynamic>.from(childData['appRestrictions'] ?? {});

      // Update app time limit
      appRestrictions[appName] = {
        'timeLimit': timeLimit,
        'password': password,
      };

      await childRef.update({
        'appRestrictions': appRestrictions,
      });
    } catch (e) {
      print('Error updating app time limit in Firestore: $e');
    }
  }

  // Load app time limits from Firestore and apply them
  Future<void> _loadAndApplyTimeLimits(String childId) async {
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

      // Get app restrictions
      final appRestrictions = Map<String, dynamic>.from(childData['appRestrictions'] ?? {});

      // Clear current limits
      _appTimeLimits.clear();
      _appPasswords.clear();

      // Update local cache
      for (var entry in appRestrictions.entries) {
        final appName = entry.key;
        final restrictions = entry.value as Map<String, dynamic>;

        _appTimeLimits[appName] = restrictions['timeLimit'] as int;
        _appPasswords[appName] = restrictions['password'] as String;
      }

      // Apply limits to native side
      if (_appTimeLimits.isNotEmpty) {
        await _channel.invokeMethod<bool>('setAppTimeLimits', {
          'limits': _appTimeLimits,
          'passwords': _appPasswords,
        });
      }
    } catch (e) {
      print('Error loading app time limits: $e');
    }
  }

  // Update Firestore with app usage data
  Future<void> _updateFirestore(Map<String, dynamic> data) async {
    try {
      final user = _auth.currentUser;
      final childId = _currentChildId;

      if (user == null || childId == null) return;

      // Extract data
      final appName = data['appName'] as String;
      final timeSpentMinutes = data['timeSpentMinutes'] as int;

      // Reference to the child document
      final childRef = _firestore
          .collection('parents')
          .doc(user.uid)
          .collection('children')
          .doc(childId);

      // Get current timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Update app usage history
      final usageHistoryRef = childRef.collection('appUsageHistory');
      await usageHistoryRef.add({
        'appName': appName,
        'timeSpent': timeSpentMinutes,
        'timestamp': timestamp,
      });

      // Update child document with the last used app
      await childRef.update({
        'lastUsedApp': appName,
        'lastUsedTimestamp': timestamp,
      });

    } catch (e) {
      print('Error updating Firestore: $e');
    }
  }

  // Update Firestore with usage stats
  Future<void> _updateFirestoreWithUsageStats(Map<String, dynamic> data) async {
    try {
      final user = _auth.currentUser;
      final childId = _currentChildId;

      if (user == null || childId == null) return;

      // Extract data
      final currentApp = data['currentApp'] as String?;
      final usageStats = Map<String, int>.from(
          (data['usageStats'] as Map<Object?, Object?>).map(
                  (key, value) => MapEntry(key.toString(), (value as num).toInt())
          )
      );

      // Reference to the child document
      final childRef = _firestore
          .collection('parents')
          .doc(user.uid)
          .collection('children')
          .doc(childId);

      // Get current timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Update child document with the full usage stats
      await childRef.update({
        'appUsageStats': usageStats,
        'currentApp': currentApp,
        'lastUpdateTimestamp': timestamp,
      });
    } catch (e) {
      print('Error updating Firestore with usage stats: $e');
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    _appUsageController.close();
    _usageStatsController.close();
    stopUsageTracking();
  }
}