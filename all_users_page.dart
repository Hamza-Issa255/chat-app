import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:chatapp/chat_page.dart'; // Ensure this path is correct

class AllUsersPage extends StatelessWidget {
  const AllUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Contacts"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('Users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("An error occurred"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // Exclude the current user from the list
            return data['email'] != currentUser?.email;
          }).toList();

          if (users.isEmpty) {
            return const Center(child: Text("No other users found."));
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data() as Map<String, dynamic>;
              final userName = data['name'] ?? data['email'] ?? 'Unknown User';
              final userID = data['uid'];

              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(userName),
                onTap: () {
                  // Navigate to chat page and pop this page off the stack
                  Navigator.pop(context); // Go back to home page
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatPage(
                        receiverUserName: userName,
                        receiverUserID: userID,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
