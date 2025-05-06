import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Securely manages Google Drive API credentials
class SecureCredentials {
  static const String _credentialsKey = 'google_drive_credentials';
  static final _secureStorage = FlutterSecureStorage();

  /// Load credentials securely - call this during app initialization
  static Future<Map<String, dynamic>> loadCredentials() async {
    try {
      // Option 1: Load from secure storage if previously stored
      final storedCredentials = await _secureStorage.read(key: _credentialsKey);
      if (storedCredentials != null) {
        return jsonDecode(storedCredentials);
      }

      // Option 2: Load from assets and store securely
      // Place your JSON file in the assets folder and reference it in pubspec.yaml
      final jsonString = await rootBundle.loadString('assets/owlwatch_credentials.json');
      final credentials = jsonDecode(jsonString);

      // Store for future use
      await _secureStorage.write(
        key: _credentialsKey,
        value: jsonString,
      );

      return credentials;
    } catch (e) {
      // Option 3: Load from environment variables as fallback
      // This is for CI/CD or deployment scenarios
      return {
        "type": "service_account",
        "project_id": Platform.environment['owlwatch'] ?? '',
        "private_key_id": Platform.environment['b945b7e5fe412a858e5195715394cbccc5b53a67'] ?? '',
        "private_key": Platform.environment['OWLWATCH_PRIVATE_KEY']?.replaceAll('\\n', '\n') ?? '',
        "client_email": Platform.environment['owl-watch@owlwatch.iam.gserviceaccount.com'] ?? '',
        "client_id": Platform.environment['101029969889075115111'] ?? '',
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": Platform.environment['https://www.googleapis.com/robot/v1/metadata/x509/owl-watch%40owlwatch.iam.gserviceaccount.com'] ?? '',
        "universe_domain": "googleapis.com"
      };
    }
  }
}