import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
      apiKey: "AIzaSyB-7AkH4kIeTRnS147Ytx65VpYp_ki0ABs",
      authDomain: "projet-pcd-5c35a.firebaseapp.com",
      projectId: "projet-pcd-5c35a",
      storageBucket: "projet-pcd-5c35a.firebasestorage.app",
      messagingSenderId: "198066338521",
      appId: "1:198066338521:web:27d0bf2faa5fc48a73dcc8"
  );

  static const FirebaseOptions android = FirebaseOptions(
      apiKey: "AIzaSyB-7AkH4kIeTRnS147Ytx65VpYp_ki0ABs",
      appId: "1:198066338521:android:8232ae60ae52300b73dcc8", // You need the correct Android app ID
      messagingSenderId: "198066338521",
      projectId: "projet-pcd-5c35a",
      storageBucket: "projet-pcd-5c35a.firebasestorage.app"
  );

  static const FirebaseOptions ios = FirebaseOptions(
      apiKey: "IOS_API_KEY_HERE", // Replace with iOS API key if you need iOS support
      appId: "IOS_APP_ID_HERE", // Replace with iOS app ID if you need iOS support
      messagingSenderId: "198066338521",
      projectId: "projet-pcd-5c35a",
      storageBucket: "projet-pcd-5c35a.firebasestorage.app"
  );
}