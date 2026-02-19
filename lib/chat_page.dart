import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatPage extends StatefulWidget {
  final String receiverUserName;
  final String receiverUserID;

  const ChatPage({
    super.key,
    required this.receiverUserName,
    required this.receiverUserID,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late StreamSubscription<QuerySnapshot> _messagesSubscription;

  @override
  void initState() {
    super.initState();
    markAsRead(); // Mark messages as read when entering the chat
    _setupMessageStatusListener();
  }

  void _setupMessageStatusListener() {
     _messagesSubscription = _firestore
        .collection('chat_rooms')
        .doc(getChatRoomId())
        .collection('messages')
        .where('receiverId', isEqualTo: _auth.currentUser!.uid)
        .where('status', isEqualTo: 'sent')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.update({'status': 'read'});
      }
    });
  }


  @override
  void dispose() {
    _messagesSubscription.cancel();
    super.dispose();
  }

  String getChatRoomId() {
    List<String> ids = [_auth.currentUser!.uid, widget.receiverUserID];
    ids.sort();
    return ids.join("_");
  }

  void sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      final chatRoomId = getChatRoomId();
      final timestamp = Timestamp.now();
      final myId = _auth.currentUser!.uid;
      final messageText = _messageController.text;

      // Clear the controller BEFORE the async operation
      _messageController.clear();

      // Create a reference to the chat room document
      final chatRoomRef = _firestore.collection('chat_rooms').doc(chatRoomId);

      // Create the new message
      final newMessageRef = chatRoomRef.collection('messages').doc();

      // Use a batch write to perform multiple operations atomically
      WriteBatch batch = _firestore.batch();

      // 1. Set the new message data
      batch.set(newMessageRef, {
        'senderId': myId,
        'receiverId': widget.receiverUserID,
        'message': messageText,
        'timestamp': timestamp,
        'status': 'sent',
      });

      // 2. Update the chat room metadata
      batch.set(
          chatRoomRef,
          {
            'lastMessage': messageText,
            'lastMessageTimestamp': timestamp,
            'participants': [myId, widget.receiverUserID],
            // Atomically increment the unread count for the receiver
            'unreadCount_${widget.receiverUserID}': FieldValue.increment(1),
          },
          SetOptions(merge: true));

      // Commit the batch
      await batch.commit();
    }
  }

  void markAsRead() async {
    final chatRoomId = getChatRoomId();
    final myId = _auth.currentUser!.uid;

    // Reset my unread count in the chat room document
    _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'unreadCount_$myId': 0,
    });

    // Mark individual messages as read
    var snapshot = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('receiverId', isEqualTo: myId)
        .where('status', isNotEqualTo: 'read')
        .get();
        
    WriteBatch batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'status': 'read'});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
          backgroundColor: const Color(0xFFECE5DD),
          appBar: AppBar(
            backgroundColor: const Color(0xFF075E54),
            foregroundColor: Colors.white,
            title: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('Users').doc(widget.receiverUserID).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.data != null) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final isOnline = data['isOnline'] ?? false;
                  final lastSeen = data['lastSeen'] as Timestamp?;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.receiverUserName, style: const TextStyle(fontSize: 18)),
                      Text(
                        isOnline
                            ? 'Online'
                            : (lastSeen != null ? 'Last seen ${DateFormat.jm().format(lastSeen.toDate())}' : 'Offline'),
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  );
                }
                return Text(widget.receiverUserName); // Fallback
              },
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder(
                  stream: _firestore
                      .collection('chat_rooms')
                      .doc(getChatRoomId())
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    // Mark messages as read whenever the stream rebuild
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(10),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        return _buildMessageItem(snapshot.data!.docs[index]);
                      },
                    );
                  },
                ),
              ),
              _buildMessageInput(),
            ],
          )),
    );
  }

  Widget _buildMessageItem(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    bool isMe = data['senderId'] == _auth.currentUser!.uid;
    var time = DateFormat('hh:mm a').format((data['timestamp'] as Timestamp).toDate());
    return Container(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 1, spreadRadius: 1)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data['message'],
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 5),
                    if (isMe)
                      Icon(
                        data['status'] == 'read'
                            ? Icons.done_all
                            : (data['status'] == 'delivered' ? Icons.done_all : Icons.done),
                        size: 16,
                        color: data['status'] == 'read' ? Colors.blue : Colors.grey,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: "Your text...",
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            backgroundColor: const Color(0xFF075E54),
            radius: 25,
            child: IconButton(
              onPressed: sendMessage,
              icon: const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
