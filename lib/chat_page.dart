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

  StreamSubscription<QuerySnapshot>? _deliveredListener;

  @override
  void initState() {
    super.initState();
    _listenForDeliveredMessages();
    markAsRead();
  }

  @override
  void dispose() {
    _deliveredListener?.cancel();
    super.dispose();
  }

  String getChatRoomId() {
    List<String> ids = [_auth.currentUser!.uid, widget.receiverUserID];
    ids.sort();
    return ids.join("_");
  }

  /// LISTEN: sent → delivered
  void _listenForDeliveredMessages() {
    _deliveredListener = _firestore
        .collection('chat_rooms')
        .doc(getChatRoomId())
        .collection('messages')
        .where('receiverId', isEqualTo: _auth.currentUser!.uid)
        .where('status', isEqualTo: 'sent')
        .snapshots()
        .listen((snapshot) async {
      WriteBatch batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'delivered'});
      }
      await batch.commit();
    });
  }

  /// SEND MESSAGE
  Future<void> sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String text = _messageController.text.trim();
    _messageController.clear();

    final chatRoomId = getChatRoomId();
    final myId = _auth.currentUser!.uid;
    final timestamp = Timestamp.now();

    final chatRoomRef = _firestore.collection('chat_rooms').doc(chatRoomId);
    final messageRef = chatRoomRef.collection('messages').doc();

    WriteBatch batch = _firestore.batch();

    batch.set(messageRef, {
      'senderId': myId,
      'receiverId': widget.receiverUserID,
      'message': text,
      'timestamp': timestamp,
      'status': 'sent',
    });

    batch.set(
      chatRoomRef,
      {
        'participants': [myId, widget.receiverUserID],
        'lastMessage': text,
        'lastMessageTimestamp': timestamp,
        'unreadCount_${widget.receiverUserID}': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// DELIVERED → READ
  Future<void> markAsRead() async {
    final chatRoomId = getChatRoomId();
    final myId = _auth.currentUser!.uid;

    _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'unreadCount_$myId': 0,
    });

    var snapshot = await _firestore
        .collection('chat_rooms')
        .doc(chatRoomId)
        .collection('messages')
        .where('receiverId', isEqualTo: myId)
        .where('status', isEqualTo: 'delivered')
        .get();

    WriteBatch batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'status': 'read'});
    }

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        title: Text(widget.receiverUserName),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('chat_rooms')
                  .doc(getChatRoomId())
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    return _buildMessage(snapshot.data!.docs[index]);
                  },
                );
              },
            ),
          ),
          _buildInputField(),
        ],
      ),
    );
  }

  Widget _buildMessage(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    bool isMe = data['senderId'] == _auth.currentUser!.uid;

    String time =
        DateFormat('hh:mm a').format((data['timestamp'] as Timestamp).toDate());

    return Container(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              data['message'],
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(width: 4),
                if (isMe) _buildStatusIcon(data['status']),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    if (status == 'sent') {
      return const Icon(Icons.done, size: 16, color: Colors.grey);
    } else if (status == 'delivered') {
      return const Icon(Icons.done_all, size: 16, color: Colors.grey);
    } else {
      return const Icon(Icons.done_all, size: 16, color: Colors.blue);
    }
  }

  Widget _buildInputField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: "Your text...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 5),
          CircleAvatar(
            backgroundColor: const Color(0xFF075E54),
            child: IconButton(
              onPressed: sendMessage,
              icon: const Icon(Icons.send, color: Colors.white),
            ),
          )
        ],
      ),
    );
  }
}
