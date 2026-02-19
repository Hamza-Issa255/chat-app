import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'chat_page.dart';
import 'all_users_page.dart';
import 'theme_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  void signOut() {
    _updateUserStatus(false).then((_) {
      _auth.signOut();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateUserStatus(true);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isResumed = state == AppLifecycleState.resumed;
    _updateUserStatus(isResumed);
  }

  Future<void> _updateUserStatus(bool isOnline) async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('Users').doc(uid).update({
        'isOnline': isOnline,
        'lastSeen': Timestamp.now(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _auth.currentUser!.uid;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text("Chats"),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.blue,
        actions: [],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
             DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF075E54),
              ),
              child: Text(
                _auth.currentUser?.displayName ?? "Settings",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Change Password feature coming soon!')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_6),
              title: const Text('Dark Mode'),
              trailing: Switch(
                value: themeProvider.themeMode == ThemeMode.dark,
                onChanged: (value) {
                  themeProvider.toggleTheme();
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () {
                Navigator.pop(context); // Close the drawer
                signOut();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search chats...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Theme.of(context).colorScheme.secondaryContainer,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chat_rooms')
                  .where('participants', arrayContains: myId)
                  .orderBy('lastMessageTimestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No chats yet. Start a new conversation!"));
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final chatRoom = snapshot.data!.docs[index];
                    final data = chatRoom.data() as Map<String, dynamic>;

                    final List<dynamic> participants = data['participants'];
                    final otherUserID = participants.firstWhere((id) => id != myId, orElse: () => null);

                    if (otherUserID == null) return const SizedBox.shrink();

                    final unreadCount = data['unreadCount_$myId'] ?? 0;
                    final lastMessage = data['lastMessage'] as String? ?? 'No messages yet.';
                    final timestamp = data['lastMessageTimestamp'] as Timestamp?;

                    return FutureBuilder<DocumentSnapshot>(
                      future: _firestore.collection('Users').doc(otherUserID).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                           return const SizedBox.shrink();
                        }
                        
                        final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                        final userName = userData['name'] ?? 'Unknown User';

                        if (_searchQuery.isNotEmpty && !userName.toLowerCase().contains(_searchQuery.toLowerCase())) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          children: [
                            ListTile(
                              leading: const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 30)),
                              title: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if(timestamp != null) Text(DateFormat.jm().format(timestamp.toDate()), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if (unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF25D366),
                                        borderRadius: BorderRadius.circular(12.0),
                                      ),
                                      child: Text(
                                        unreadCount.toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatPage(
                                      receiverUserName: userName,
                                      receiverUserID: otherUserID,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 80, right: 10),
                              child: Divider(height: 1, thickness: 0.5),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AllUsersPage()),
          );
        },
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.add_comment_rounded, color: Colors.white),
      ),
    );
  }
}
