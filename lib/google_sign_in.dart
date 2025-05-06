import 'package:google_sign_in/google_sign_in.dart';

final GoogleSignIn googleSignIn = GoogleSignIn(
  scopes: ['https://www.googleapis.com/auth/drive.file'],
);

Future<GoogleSignInAccount?> signInWithGoogle() async {
  final account = await googleSignIn.signIn();
  return account;
}
