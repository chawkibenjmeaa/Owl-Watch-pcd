import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/AppDrawer.dart'; // Make sure this path is correct

class AddChildPage extends StatefulWidget {
  const AddChildPage({super.key});

  @override
  _AddChildPageState createState() => _AddChildPageState();
}

class _AddChildPageState extends State<AddChildPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String? selectedDay;
  String? selectedMonth;
  String? selectedYear;

  final List<String> days =
      List.generate(31, (index) => (index + 1).toString());
  final List<String> months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ];
  final List<String> years =
      List.generate(50, (index) => (2025 - index).toString());

  void _addChild() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: User not authenticated")),
      );
      return;
    }

    final String name = nameController.text.trim();
    final String password = passwordController.text.trim();

    if (name.isEmpty ||
        selectedDay == null ||
        selectedMonth == null ||
        selectedYear == null ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    final birthDate = "$selectedDay $selectedMonth $selectedYear";

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('parents')
          .doc(user.uid)
          .collection('children')
          .add({
        'name': name,
        'birthDate': birthDate,
        'password': password,
        'createdAt': Timestamp.now(),
      });

      print("Child added to: parents/${user.uid}/children/${docRef.id}");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Child added successfully")),
      );

      nameController.clear();
      passwordController.clear();
      setState(() {
        selectedDay = null;
        selectedMonth = null;
        selectedYear = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving child: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text("Add a Child", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[900],
      ),
      drawer: AppDrawer(), // ✅ using your reusable drawer
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 10,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel("Your Child's Name"),
                  _buildInputField(nameController, "Enter Name", Icons.person),
                  SizedBox(height: 20),
                  _buildLabel("Birth Date"),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: _buildDropdown("Day", selectedDay, days,
                              (val) => setState(() => selectedDay = val))),
                      SizedBox(width: 10),
                      Expanded(
                          child: _buildDropdown("Month", selectedMonth, months,
                              (val) => setState(() => selectedMonth = val))),
                      SizedBox(width: 10),
                      Expanded(
                          child: _buildDropdown("Year", selectedYear, years,
                              (val) => setState(() => selectedYear = val))),
                    ],
                  ),
                  SizedBox(height: 20),
                  _buildLabel("Password"),
                  _buildInputField(
                      passwordController, "Enter Password", Icons.lock,
                      isPassword: true),
                  SizedBox(height: 30),
                  Center(
                    child: ElevatedButton(
                      onPressed: _addChild,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[900],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                      ),
                      child: Text("ADD",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildInputField(
      TextEditingController controller, String hint, IconData icon,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blue[900]),
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      ),
    );
  }

  Widget _buildDropdown(String hint, String? value, List<String> items,
      void Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      value: value,
      hint: Text(hint),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
