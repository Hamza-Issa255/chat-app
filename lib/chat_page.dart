import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class ChatPage extends StatefulWidget {
  final String receiverUserName;
  final String receiverUserID;
  final String? receiverProfileImage; // Optional profile image

  const ChatPage({
    super.key,
    required this.receiverUserName,
    required this.receiverUserID,
    this.receiverProfileImage,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  
  bool _isTyping = false;
  Timer? _typingTimer;
  bool _receiverIsTyping = false;

  @override
  void initState() {
    super.initState();
    _setupTypingListener();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  String getChatRoomId() {
    List<String> ids = [_auth.currentUser!.uid, widget.receiverUserID];
    ids.sort();
    return ids.join("_");
  }

  void _setupTypingListener() {
    _firestore
        .collection('chat_rooms')
        .doc(getChatRoomId())
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _receiverIsTyping = snapshot.data()?['typing_${widget.receiverUserID}'] ?? false;
        });
      }
    });
  }

  void _updateTypingStatus(bool isTyping) {
    if (_auth.currentUser == null) return;
    
    String chatRoomId = getChatRoomId();
    _firestore.collection('chat_rooms').doc(chatRoomId).update({
      'typing_${_auth.currentUser!.uid}': isTyping,
      'last_activity': FieldValue.serverTimestamp(),
    });
  }

  void _onTextChanged(String text) {
    if (!_isTyping && text.isNotEmpty) {
      setState(() => _isTyping = true);
      _updateTypingStatus(true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_isTyping) {
        setState(() => _isTyping = false);
        _updateTypingStatus(false);
      }
    });
  }

  void sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String message = _messageController.text.trim();
    _messageController.clear();
    _updateTypingStatus(false);
    
    try {
      String chatRoomId = getChatRoomId();
      
      // Create or update chat room
      await _firestore.collection('chat_rooms').doc(chatRoomId).set({
        'participants': [_auth.currentUser!.uid, widget.receiverUserID],
        'last_message': message,
        'last_message_time': FieldValue.serverTimestamp(),
        'last_message_sender': _auth.currentUser!.uid,
        'typing_${_auth.currentUser!.uid}': false,
      }, SetOptions(merge: true));

      // Add message
      await _firestore
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': _auth.currentUser!.uid,
        'receiverId': widget.receiverUserID,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'text',
      });

      // Scroll to bottom
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void markAsRead() async {
    try {
      String chatRoomId = getChatRoomId();
      var snapshot = await _firestore
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages')
          .where('receiverId', isEqualTo: _auth.currentUser!.uid)
          .where('isRead', isEqualTo: false)
          .get();

      WriteBatch batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    
    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();
    
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (date.day == now.day - 1) {
      return 'Yesterday';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF0F2), // Telegram light gray background
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTypingIndicator(),
          Expanded(
            child: _buildMessagesList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0.5,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Profile avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            backgroundImage: widget.receiverProfileImage != null
                ? NetworkImage(widget.receiverProfileImage!)
                : null,
            child: widget.receiverProfileImage == null
                ? Text(
                    widget.receiverUserName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2A6B9C), // Telegram blue
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          // Username centered
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.receiverUserName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  "online",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF2A6B9C), // Telegram blue
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _receiverIsTyping ? 30 : 0,
      child: _receiverIsTyping
          ? Container(
              color: const Color(0xFFEFF0F2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    widget.receiverUserName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A6B9C),
                    ),
                  ),
                  const Text(
                    " is typing",
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(width: 8),
                  const _TypingDots(),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder(
      stream: _firestore
          .collection('chat_rooms')
          .doc(getChatRoomId())
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Error loading messages',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF2A6B9C),
            ),
          );
        }

        var messages = snapshot.data!.docs;
        
        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 50,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Say hello to ${widget.receiverUserName}!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        markAsRead();
        _scrollToBottom();

        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final previousMessage = index < messages.length - 1 ? messages[index + 1] : null;
            
            return _buildMessageItem(
              message,
              showHeader: _shouldShowHeader(message, previousMessage),
            );
          },
        );
      },
    );
  }

  bool _shouldShowHeader(DocumentSnapshot current, DocumentSnapshot? previous) {
    if (previous == null) return true;
    
    Map<String, dynamic> currentData = current.data() as Map<String, dynamic>;
    Map<String, dynamic> previousData = previous.data() as Map<String, dynamic>;
    
    // Show header if sender changed or time difference > 5 minutes
    if (currentData['senderId'] != previousData['senderId']) return true;
    
    Timestamp? currentTime = currentData['timestamp'];
    Timestamp? previousTime = previousData['timestamp'];
    
    if (currentTime == null || previousTime == null) return true;
    
    Duration difference = currentTime.toDate().difference(previousTime.toDate());
    return difference.inMinutes > 5;
  }

  Widget _buildMessageItem(DocumentSnapshot doc, {bool showHeader = false}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    bool isMe = data['senderId'] == _auth.currentUser!.uid;
    Timestamp? timestamp = data['timestamp'];
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          if (showHeader && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 45, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.receiverUserName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A6B9C),
                  ),
                ),
              ),
            ),
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: widget.receiverProfileImage != null
                        ? NetworkImage(widget.receiverProfileImage!)
                        : null,
                    child: widget.receiverProfileImage == null
                        ? Text(
                            widget.receiverUserName[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2A6B9C),
                            ),
                          )
                        : null,
                  ),
                ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: EdgeInsets.only(
                    left: isMe ? 45 : 8,
                    right: isMe ? 8 : 45,
                    top: 2,
                    bottom: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        data['message'],
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTimestamp(timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (isMe)
                            Icon(
                              data['isRead'] == true
                                  ? Icons.done_all
                                  : Icons.done,
                              size: 13,
                              color: data['isRead'] == true
                                  ? Colors.blue[700]
                                  : Colors.grey[500],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
        top: 10,
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button (optional, can be removed if not needed)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A6B9C).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.attach_file, color: Color(0xFF2A6B9C), size: 22),
                onPressed: () {
                  // Implement attachment if needed
                },
              ),
            ),
            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  onChanged: _onTextChanged,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: "Write a message...",
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            // Send button
            if (_messageController.text.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2A6B9C),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: sendMessage,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            double value = (_controller.value - index * 0.15).clamp(0, 1);
            double scale = 1 + 0.5 * (1 - (value * 4 - 2).abs());
            
            return Transform.scale(
              scale: scale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A6B9C),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}