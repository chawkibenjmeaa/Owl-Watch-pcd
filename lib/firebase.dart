import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> registerParent({
    required String email,
    required String password,
    required String name,
    String phone = '',
  }) async {
    try {
      // Create user in Firebase Auth
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Get UID
      String uid = userCredential.user!.uid;

      // Save extra user info in Firestore
      await _firestore.collection('parents').doc(uid).set({
        'email': email,
        'name': name,
        'password': password,
        'phone': phone,
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseAuthException catch (e) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        message: e.message,
        code: e.code,
      );
    } catch (e) {
      rethrow;
    }
  }

  // This method is for saving a Google user
  Future<void> saveGoogleUser(
      {required String email, required String name}) async {
    try {
      // Get the current user
      User? user = _auth.currentUser;

      if (user != null) {
        // Save the user information in Firestore (or any other database you're using)
        await _firestore.collection('users').doc(user.uid).set({
          'email': email,
          'name': name,
          'lastSignIn': DateTime.now(),
          // You can add more user details here if needed
        });
      }
    } catch (e) {
      print('Error saving Google user: $e');
      throw FirebaseException(message: 'Error saving user details', plugin: '');
    }
  }
}
