import 'package:flutter/material.dart';
import 'package:flutter_application_1/AppDrawer.dart';

class ChildActivityPage extends StatefulWidget {
  const ChildActivityPage({super.key});

  @override
  _ChildActivityPageState createState() => _ChildActivityPageState();
}

class _ChildActivityPageState extends State<ChildActivityPage> {
  List<Map<String, dynamic>> activityHistory = [
    {
      'child': 'Alex',
      'type': 'Website',
      'content': 'www.example.com',
      'time': '10:30 AM',
      'concern': false,
    },
    {
      'child': 'Emma',
      'type': 'Video',
      'content': 'Scary Movie Clip',
      'time': '08:45 PM',
      'concern': true,
    },
    {
      'child': 'Alex',
      'type': 'Website',
      'content': 'www.education.com',
      'time': '02:15 PM',
      'concern': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Child Activity"),
        backgroundColor: Colors.blue[900],
      ),
      drawer: AppDrawer(), // ✅ Add App Drawer
      body: ListView.builder(
        padding: EdgeInsets.all(10),
        itemCount: activityHistory.length,
        itemBuilder: (context, index) {
          var activity = activityHistory[index];
          return Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: ListTile(
              contentPadding: EdgeInsets.all(15),
              leading: Icon(
                activity['type'] == 'Website'
                    ? Icons.public
                    : Icons.video_library,
                color: activity['concern'] ? Colors.red : Colors.blue[900],
              ),
              title: Text(
                "${activity['child']} - ${activity['type']}",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Content: ${activity['content']}",
                      style: TextStyle(fontSize: 16)),
                  Text("Time: ${activity['time']}",
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  if (activity['concern'])
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 5),
                        Text("Potential Concern!",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                ],
              ),
              trailing: Icon(Icons.arrow_forward_ios, color: Colors.grey),
            ),
          );
        },
      ),
    );
  }
}
