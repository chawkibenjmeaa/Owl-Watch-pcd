import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScreenshotService {
  static const MethodChannel _channel = MethodChannel('com.example.flutter_application_1/screenshot');

  // Stream controllers for handling events
  static final _screenshotTakenController = StreamController<Map<String, dynamic>>.broadcast();
  static final _screenshotErrorController = StreamController<Map<String, dynamic>>.broadcast();
  static final _serviceStateController = StreamController<Map<String, dynamic>>.broadcast();

  // Streams that can be listened to from Flutter
  static Stream<Map<String, dynamic>> get onScreenshotTaken => _screenshotTakenController.stream;
  static Stream<Map<String, dynamic>> get onScreenshotError => _screenshotErrorController.stream;
  static Stream<Map<String, dynamic>> get onServiceStateChanged => _serviceStateController.stream;

  static Future<void> initialize() async {
    // Set up method call handler for incoming events from native side
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotTaken':
        _screenshotTakenController.add(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onScreenshotError':
        _screenshotErrorController.add(Map<String, dynamic>.from(call.arguments));
        break;
      case 'onServiceStarted':
      case 'onServiceStopped':
      case 'onServicePaused':
        _serviceStateController.add(Map<String, dynamic>.from(call.arguments));
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  // Service control methods
  static Future<bool> startScreenshotService({
    required String userId,
    required String childId,
    int intervalSeconds = 10,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'startScreenshotService',
        {
          'userId': userId,
          'childId': childId,
          'intervalSeconds': intervalSeconds,
        },
      );
      return result ?? false;
    } catch (e) {
      print('Error starting screenshot service: $e');
      return false;
    }
  }

  static Future<bool> stopScreenshotService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopScreenshotService');
      return result ?? false;
    } catch (e) {
      print('Error stopping screenshot service: $e');
      return false;
    }
  }

  static Future<bool> updateInterval(int intervalSeconds) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'updateInterval',
        {'intervalSeconds': intervalSeconds},
      );
      return result ?? false;
    } catch (e) {
      print('Error updating interval: $e');
      return false;
    }
  }

  static Future<bool> pauseScreenshots() async {
    try {
      final result = await _channel.invokeMethod<bool>('pauseScreenshots');
      return result ?? false;
    } catch (e) {
      print('Error pausing screenshots: $e');
      return false;
    }
  }

  static Future<bool> resumeScreenshots({int intervalSeconds = 10}) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'resumeScreenshots',
        {'intervalSeconds': intervalSeconds},
      );
      return result ?? false;
    } catch (e) {
      print('Error resuming screenshots: $e');
      return false;
    }
  }

  static Future<bool> isServiceRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      return result ?? false;
    } catch (e) {
      print('Error checking service status: $e');
      return false;
    }
  }

  // Important: Call this method when your app is disposed
  static void dispose() {
    _screenshotTakenController.close();
    _screenshotErrorController.close();
    _serviceStateController.close();
  }
}