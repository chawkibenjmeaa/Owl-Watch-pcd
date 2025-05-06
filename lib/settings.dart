import 'package:flutter/material.dart';
import 'package:flutter_application_1/AppDrawer.dart';
import 'package:flutter_application_1/LoginPage.dart';
import 'package:flutter_application_1/AccountPage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool notificationsEnabled = true;
  bool restrictionsEnabled = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('parents').doc(user.uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        notificationsEnabled = data['notificationsEnabled'] ?? true;
        restrictionsEnabled = data['restrictionsEnabled'] ?? true;
      });
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('parents')
        .doc(user.uid)
        .set({key: value}, SetOptions(merge: true));
  }

  Future<void> _confirmAndToggle(
      String settingKey,
      bool newValue,
      Function(bool) setStateCallback,
      ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (newValue == false) {
      // Trying to disable — ask for password
      String password = '';
      bool confirmed = false;

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enter Password to Confirm'),
            content: TextField(
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onChanged: (value) {
                password = value;
              },
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    final credential = EmailAuthProvider.credential(
                      email: user.email!,
                      password: password,
                    );

                    await user.reauthenticateWithCredential(credential);
                    confirmed = true;
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Incorrect password"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text("Confirm"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
            ],
          );
        },
      );

      if (!confirmed) return;
    }

    // Proceed with toggle
    setState(() {
      setStateCallback(newValue);
    });

    await _updateSetting(settingKey, newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[900],
        title: const Text("Settings", style: TextStyle(letterSpacing: 1.5)),
      ),
      drawer: AppDrawer(),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text("Parental Controls",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text("Enable Restrictions"),
            subtitle: const Text("Block certain apps & limit screen time"),
            value: restrictionsEnabled,
            onChanged: (bool value) {
              _confirmAndToggle("restrictionsEnabled", value, (val) {
                restrictionsEnabled = val;
              });
            },
          ),
          const Divider(),
          const Text("General Settings",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text("Enable Notifications"),
            subtitle: const Text("Get alerts about screen time & app usage"),
            value: notificationsEnabled,
            onChanged: (bool value) {
              _confirmAndToggle("notificationsEnabled", value, (val) {
                notificationsEnabled = val;
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text("Account Settings"),
            onTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => AccountPage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Sign Out", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (context) => LoginPage()));
            },
          ),
        ],
      ),
    );
  }
}
