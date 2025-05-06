import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_application_1/AccountPage.dart';
import 'package:flutter_application_1/AppDrawer copy.dart';
import 'package:flutter_application_1/CHILDPHONE.dart';
import 'package:flutter_application_1/addchild.dart';
import 'package:flutter_application_1/childactivity.dart';
import 'package:flutter_application_1/notifications.dart';

class home extends StatefulWidget {
  const home({super.key});

  @override
  State<home> createState() => _homeState();
}

class _homeState extends State<home> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String userName = "Loading...";

  @override
  void initState() {
    super.initState();
    fetchUserName();
  }

  Future<void> fetchUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('parents')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            userName = doc.data()?['name'] ?? "No Name";
          });
        } else {
          setState(() {
            userName = "Parent not found";
          });
        }
      }
    } catch (e) {
      setState(() {
        userName = "Error fetching name";
      });
      print('Error fetching user name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer1(),
      backgroundColor: Colors.blueGrey[50],
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCategoryList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
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
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: const Text(
                  "ACCOUNT",
                  style: TextStyle(letterSpacing: 1.5, color: Colors.white),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () {
                    _scaffoldKey.currentState?.openDrawer();
                  },
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 70),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26, blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: const CircleAvatar(
                radius: 45,
                backgroundColor: Colors.white,
                child: Icon(Icons.person, size: 45, color: Color(0xFF0D47A1)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              userName,
              style: const TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AccountPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Color(0xFF0D47A1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text("Account Information"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      children: [
        _buildCategoryButton(Icons.add_circle, "Add Child", Color(0xFF1976D2),
            () {
          Navigator.push(
              context, MaterialPageRoute(builder: (context) => AddChildPage()));
        }),
        _buildCategoryButton(
            Icons.child_care, "Child Activity", Color(0xFF0D47A1), () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => ChildActivityPage()));
        }),
        _buildCategoryButton(
            Icons.phone_android, "Child Phone", Color(0xFF1976D2), () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => ChildPhonePage()));
        }),
        _buildCategoryButton(
            Icons.notification_important, "Notifications", Color(0xFF0D47A1),
            () {
          Navigator.push(context,
              MaterialPageRoute(builder: (context) => NotificationsPage()));
        }),
      ],
    );
  }

  Widget _buildCategoryButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.shade300, blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.8),
              child: Icon(icon, size: 30, color: Colors.white),
            ),
            const SizedBox(width: 15),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
