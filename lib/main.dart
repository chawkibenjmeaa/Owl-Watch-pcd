// main.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_application_1/AccountPage.dart';
import 'package:flutter_application_1/loadingpage.dart';
import 'package:flutter_application_1/drive_service.dart';
import 'package:path_provider/path_provider.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase only if not already initialized
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase initialized successfully');
    } else {
      debugPrint('Firebase already initialized, skipping initialization');
    }
  } catch (e) {
    debugPrint('Error initializing Firebase: $e');
  }

  // Setup Google Drive service
  await setupGoogleDriveService();

  runApp(const MyApp());
}

// Set up Google Drive service with service account JSON
Future<void> setupGoogleDriveService() async {
  try {
    // First create the credentials file
    await createCredentialsFile();

    // Then initialize the Google Drive service
    bool initialized = await GoogleDriveService.initialize();

    if (initialized) {
      debugPrint('Google Drive service setup completed successfully');

      // Verify access to confirm everything is working
      bool hasAccess = await GoogleDriveService.verifyDriveAccess();
      debugPrint('Drive access verification: ${hasAccess ? 'SUCCESS' : 'FAILED'}');
    } else {
      debugPrint('Failed to initialize Google Drive service');
    }
  } catch (e) {
    debugPrint('Error setting up Google Drive service: $e');
  }
}

// Create credentials file from service account JSON
// Create credentials file from service account JSON
Future<void> createCredentialsFile() async {
  try {
    // The path we're using in Flutter
    final appDocDir = await getApplicationDocumentsDirectory();
    final credentialsPath = '${appDocDir.path}/credentials.json';
    final credentialsFile = File(credentialsPath);

    // The path Android code is expecting (internal files directory)
    final appFilesDir = await getApplicationSupportDirectory();
    final internalPath = '${appFilesDir.path}/credentials.json';
    final internalFile = File(internalPath);

    // Create the credentials file if it doesn't exist in either location
    if (!await credentialsFile.exists() && !await internalFile.exists()) {
      // Service account credentials JSON
      const credentialsJson = '''
      {
        "type": "service_account",
        "project_id": "owlwatch-458514",
        "private_key_id": "c559d1f9e585f20ab8019d4dce12dfac5ecbf8bd",
        "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCSfinJFZwYJ0kF\\nPnBEsNpGPvnzpykG7kMRa/X8coW6PNK8smmqS7skz3HMO+gPhSAw249E4jjkygJE\\nSGhz6k6tiuzUpvSaOHHtThZlp2LBzSxZItj0SPmx5Nno1j4ehCRPhkWE60UKPdPT\\nlFPimpnB0KNwpeqHw1NiFxVne7G4YjIq1JcMbBlOpEhZqYn+30nIQDCjDwWkWQbi\\nsqkPSwpdre4iR94F2yiAv8ojc0eXFppiUQMAuMOQXDJmcCf5exVS1JuzVhPacJFx\\nlfODR6FlEhZNaYzjXf3PAePfjX03c63lx99kABuP8wPmqzwg0Inh+ES030cBHigN\\nZMVc6PHrAgMBAAECggEAA/rafsSQB5X1pWdTXIJjg7oNR2HYuv/5IX2J4tBnsq4Z\\nWZgNR9uj23WpVU+hV96Zh8pHQ6tTuV+FnT5MXC3W8l8OXR6mEZSL/9L5x8w64iIF\\nXOyV8VkUM5GQnANKD8EuTVzMAbb0mrkgSqTCfKsPl1ToQ9S2IPcdClKvOa8CHoy9\\n4nGjBsIg9JlEVkrD2rr2Og0rz/UDwlTUD/V0JDUsWT0rxbWUM2jAETWJZ53DDG2Z\\nPxS9Iznf+e9wlO3IVSFDsYojqSJn35xiqzbluFGgrpatdkQZPAChe8g4PnJUenVI\\n/h3V6Rv0/QNj2Ve9zOWAO6t7XwOu6uTJqstoi+898QKBgQDG581N9VE1vsexKTyS\\nBjwr3U3eAE1uz01vAdNlzLQbvGyi5apYBTvHVlc4kufINku081eLJSYhN/uW8vhO\\nh/3g10kuQN16ybHnvwimN71ypaynZ+TiuAbkeSzob1VM70ei6ckAio992173G8Xp\\nc9BC1PqR4iLWHYKRZiw9rJOc2wKBgQC8iupRcc7Mc91Rl1t6c704FXK83uGMkvdD\\ngp9EK+YlkQFPbHGKLHuCh0Z59nX6kfGxEmHkj3CHfFWbCeGiPpO7YFKIp3HEaaKo\\nUTQYkZUcGNjz+RBGXx7PqR+HPYbGayUBOLIEKw3TRIT5D65zS0Jly4pPLy2/0CsA\\nCDCAToWEMQKBgQCNE44vdAbUmusiAcB/RcLZzc5T3l0NciVWzbG1q3o3je5zn3ex\\nlIywttGIQ9H31GLgBhSakY+40e81QkHR2Wy9U5UJJGKym2n+mCU3V6OcNFwAJJVY\\nJPRminfKqGSU+8YQi8bQBnb96mEx3VYDXexh6pOKcx0IRsf7/r70Q3ozLwKBgDCA\\nX9TBvRwVNjrV/99ZRLTXt6NkhoseB2Ojh4sG6/Z//eFLmU2dMcybNgML5r+lqZIO\\nk4YzbBQ+ZNs0SInvJRvPpIuo33hSYFiCQy+Ky9vlfHIOgSRJNejfrc+hgTkruOI+\\njnTKCo1tk/NqGEtqcdMz8Al8rn0odNdWQ/vNt0URAoGBAKA0zth+DK31m4O36Y7X\\npxa9tK+2u+DLq0PQTi+vWg3Esh2tOPrcoTUb6ZiIkcgEYODzPA2ERZNNkfxcfXnx\\nUtizksgmENkq2OBi/JXKrKARJqbxV8BNphiFJ51jfkRQqdFySUhgX6QlP7hTyF8A\\nuIm1IUfNGcw7OJE6EDjBhFSl\\n-----END PRIVATE KEY-----\\n",
        "client_email": "owlwatch@owlwatch-458514.iam.gserviceaccount.com",
        "client_id": "108377539198260970571",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/owlwatch%40owlwatch-458514.iam.gserviceaccount.com",
        "universe_domain": "googleapis.com"
      }
      ''';

      // Write credentials to BOTH locations
      await credentialsFile.writeAsString(credentialsJson);
      await internalFile.writeAsString(credentialsJson);

      debugPrint('Credentials file created successfully at app documents: $credentialsPath');
      debugPrint('Credentials file created successfully at internal files: $internalPath');

      // Verify the files were created with content
      if (await credentialsFile.exists() && await internalFile.exists()) {
        int docFileSize = await credentialsFile.length();
        int internalFileSize = await internalFile.length();
        debugPrint('Verified app documents file exists with size: $docFileSize bytes');
        debugPrint('Verified internal file exists with size: $internalFileSize bytes');
      }
    } else if (!await internalFile.exists() && await credentialsFile.exists()) {
      // If only the app documents file exists, copy it to the internal files dir
      String content = await credentialsFile.readAsString();
      await internalFile.writeAsString(content);
      debugPrint('Copied credentials from app documents to internal files: $internalPath');
    } else if (await internalFile.exists() && !await credentialsFile.exists()) {
      // If only the internal file exists, copy it to the app documents dir
      String content = await internalFile.readAsString();
      await credentialsFile.writeAsString(content);
      debugPrint('Copied credentials from internal files to app documents: $credentialsPath');
    } else {
      debugPrint('Credentials files already exist at both locations');
    }
  } catch (e) {
    debugPrint('Error creating credentials file: $e');
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Owl Watch',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoadingScreen(),
      routes: {
        '/AccountPage': (context) => const AccountPage(),
      },
    );
  }
}