import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../services/media_service.dart';
import 'widgets/media_preview.dart';
import 'widgets/message_input.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'widgets/message_bubble.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
//app certificate secondary
// e212492ef48b47ae9dc5508d28d6c806
class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel otherUser;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _mediaService = MediaService();
  bool _isLoading = false;
  bool _showEmoji = false;
  MessageModel? _replyTo;
  bool _showScrollToBottom = false;
  String _messageSearchQuery = '';
  bool _isSearchingMessages = false;
  bool _isMuted = false;
  bool _isArchived = false;

  // Typing indicator state
  Timer? _typingTimer;
  bool _isOtherTyping = false;
  StreamSubscription<DocumentSnapshot>? _typingSubscription;
  bool _isOtherUserOnline = false;

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    listenForIncomingCalls(context, widget.currentUser);
    _messageController.addListener(_onTyping);
    _listenToOtherTyping();
    _scrollController.addListener(_onScroll);
    // Scroll to bottom after messages are loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollToBottom();
      });
    });
    _loadMutedAndArchived();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTyping);
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final shouldShow = maxScroll - currentScroll > 200;
      if (shouldShow != _showScrollToBottom) {
        setState(() {
          _showScrollToBottom = shouldShow;
        });
      }
    }
  }

  String _getChatId() {
    final List<String> ids = [widget.currentUser.uid, widget.otherUser.uid];
    ids.sort();
    return ids.join('_');
  }

  Future<void> _markMessagesAsRead() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_getChatId())
          .collection('messages')
          .where('receiverId', isEqualTo: widget.currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();

      for (final doc in querySnapshot.docs) {
        await doc.reference.update({'isRead': true});
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  Future<void> _sendMessage({
    String? content,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
  }) async {
    if ((content == null || content.trim().isEmpty) && type == MessageType.text) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final message = MessageModel(
        id: const Uuid().v4(),
        senderId: widget.currentUser.uid,
        receiverId: widget.otherUser.uid,
        content: content ?? '',
        type: type,
        timestamp: DateTime.now(),
        replyTo: _replyTo?.id,
        metadata: metadata,
      );

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_getChatId())
          .collection('messages')
          .doc(message.id)
          .set(message.toMap());

      _messageController.clear();
      _replyTo = null;
      _scrollToBottom();
      // Immediately set typing status to false when message is sent
      _setTypingStatus(false);
      _typingTimer?.cancel();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleImageSelection() async {
    setState(() => _isLoading = true);
    final result = await _mediaService.pickAndEncodeImage(isMessage: true);
    setState(() => _isLoading = false);
    if (result == null) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
      return;
    }
    await _sendMessage(
      content: result['base64'],
      type: MessageType.image,
      metadata: {
        'name': result['name'],
        'type': result['type'],
        'size': result['size'],
      },
    );
  }

  Future<void> _handleVideoSelection() async {
    setState(() => _isLoading = true);
    final result = await _mediaService.pickAndEncodeVideo();
    setState(() => _isLoading = false);
    if (result == null) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
      return;
    }
    await _sendMessage(
      content: result['base64'],
      type: MessageType.video,
      metadata: {
        'name': result['name'],
        'type': result['type'],
        'size': result['size'],
      },
    );
  }

  Future<void> _handleFileSelection() async {
    setState(() => _isLoading = true);
    final result = await _mediaService.pickAndEncodeFile();
    setState(() => _isLoading = false);
    if (result == null) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
      return;
    }
    await _sendMessage(
      content: '',
      type: MessageType.file,
      metadata: {
        'base64': result['base64'],
        'name': result['name'],
        'type': result['type'],
        'size': result['size'],
      },
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmoji = !_showEmoji);
  }

  void _onEmojiSelected(Emoji emoji) {
    _messageController.text += emoji.emoji;
  }

  void _onTyping() {
    _setTypingStatus(true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _setTypingStatus(false);
    });
  }

  void _setTypingStatus(bool isTyping) async {
    final chatId = _getChatId();
    final typingField = 'typingStatus.${widget.currentUser.uid}';
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'typingStatus': {widget.currentUser.uid: isTyping}
    }, SetOptions(merge: true));
  }

  void _listenToOtherTyping() {
    final chatId = _getChatId();
    _typingSubscription = FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots().listen((doc) {
      final data = doc.data();
      if (data != null && data['typingStatus'] != null) {
        final typingStatus = Map<String, dynamic>.from(data['typingStatus']);
        final otherUid = widget.otherUser.uid;
        if (mounted) {
          setState(() {
            _isOtherTyping = typingStatus[otherUid] == true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isOtherTyping = false;
          });
        }
      }
    });
  }

  Future<void> _clearChatForCurrentUser() async {
    final chatId = _getChatId();
    final userId = widget.currentUser.uid;
    final messagesRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages');
    final batch = FirebaseFirestore.instance.batch();
    final snapshot = await messagesRef.get();
    for (final doc in snapshot.docs) {
      // Mark as deleted for this user only (add a deletedFor field)
      batch.update(doc.reference, {
        'deletedFor': FieldValue.arrayUnion([userId])
      });
    }
    await batch.commit();
    setState(() {});
  }

  Future<void> _loadMutedAndArchived() async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUser.uid).get();
    final data = userDoc.data() ?? {};
    final chatId = _getChatId();
    setState(() {
      _isMuted = (data['mutedChats'] ?? []).contains(chatId);
      _isArchived = (data['archivedChats'] ?? []).contains(chatId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_showEmoji) {
          setState(() => _showEmoji = false);
        }
      },
      child: Scaffold(
        floatingActionButton: _showScrollToBottom
            ? Padding(
                padding: const EdgeInsets.only(bottom: 80.0, left: 16.0),
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                  onPressed: _scrollToBottom,
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        appBar: AppBar(
          title: !_isSearchingMessages
              ? GestureDetector(
                  onTap: () async {
                    final action = await showModalBottomSheet<String>(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: _buildUserAvatar(widget.otherUser, context, radius: 24, fontSize: 22),
                              title: Text(widget.otherUser.displayName, style: const TextStyle(fontSize: 18)),
                              subtitle: StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(widget.otherUser.uid)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  bool isOnline = false;
                                  if (snapshot.hasData && snapshot.data!.data() != null) {
                                    final data = snapshot.data!.data() as Map<String, dynamic>;
                                    final lastSeen = data['lastSeen'] as Timestamp?;
                                    final isOnlineStatus = data['isOnline'] as bool? ?? false;
                                    if (lastSeen != null) {
                                      final now = DateTime.now();
                                      isOnline = isOnlineStatus && now.difference(lastSeen.toDate()).inSeconds < 30;
                                    }
                                  }
                                  return Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOnline ? Colors.green : Colors.grey,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.delete_outline, color: Colors.red),
                              title: const Text('Clear Chat', style: TextStyle(color: Colors.red)),
                              onTap: () async {
                                Navigator.pop(context, 'clear');
                              },
                            ),
                            // Archive
                            ListTile(
                              leading: Icon(_isArchived ? Icons.unarchive : Icons.archive_outlined),
                              title: Text(_isArchived ? 'Unarchive' : 'Archive'),
                              onTap: () async {
                                Navigator.pop(context, 'archive');
                              },
                            ),
                            // Mute
                            ListTile(
                              leading: Icon(_isMuted ? Icons.notifications_active : Icons.notifications_off_outlined),
                              title: Text(_isMuted ? 'Unmute' : 'Mute'),
                              onTap: () async {
                                Navigator.pop(context, 'mute');
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                    if (action == 'clear') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear Chat?'),
                          content: const Text('Are you sure you want to clear your side of this chat? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _clearChatForCurrentUser();
                      }
                    } else if (action == 'archive') {
                      final userRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUser.uid);
                      final userDoc = await userRef.get();
                      final data = userDoc.data() ?? {};
                      final chatId = _getChatId();
                      final archived = Set<String>.from(data['archivedChats'] ?? []);
                      if (_isArchived) {
                        archived.remove(chatId);
                      } else {
                        archived.add(chatId);
                      }
                      await userRef.update({'archivedChats': archived.toList()});
                      setState(() => _isArchived = !_isArchived);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_isArchived ? 'Chat archived.' : 'Chat unarchived.')),
                      );
                    } else if (action == 'mute') {
                      final userRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUser.uid);
                      final userDoc = await userRef.get();
                      final data = userDoc.data() ?? {};
                      final chatId = _getChatId();
                      final muted = Set<String>.from(data['mutedChats'] ?? []);
                      if (_isMuted) {
                        muted.remove(chatId);
                      } else {
                        muted.add(chatId);
                      }
                      await userRef.update({'mutedChats': muted.toList()});
                      setState(() => _isMuted = !_isMuted);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_isMuted ? 'Chat muted.' : 'Chat unmuted.')),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      _buildUserAvatar(widget.otherUser, context, radius: 18, fontSize: 18),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.otherUser.displayName, style: const TextStyle(fontSize: 18)),
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.otherUser.uid)
                                .snapshots(),
                            builder: (context, snapshot) {
                              bool isOnline = false;
                              if (snapshot.hasData && snapshot.data!.data() != null) {
                                final data = snapshot.data!.data() as Map<String, dynamic>;
                                final lastSeen = data['lastSeen'] as Timestamp?;
                                final isOnlineStatus = data['isOnline'] as bool? ?? false;
                                if (lastSeen != null) {
                                  final now = DateTime.now();
                                  isOnline = isOnlineStatus && now.difference(lastSeen.toDate()).inSeconds < 30;
                                }
                              }
                              return Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isOnline ? Colors.green : Colors.grey,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search messages...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).appBarTheme.backgroundColor ?? (Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white),
                  ),
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    fontSize: 18,
                  ),
                  cursorColor: Theme.of(context).colorScheme.primary,
                  onChanged: (value) {
                    setState(() {
                      _messageSearchQuery = value.trim().toLowerCase();
                    });
                  },
                ),
          actions: [
            if (!_isSearchingMessages)
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() {
                    _isSearchingMessages = true;
                  });
                },
              ),
            if (_isSearchingMessages)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSearchingMessages = false;
                    _messageSearchQuery = '';
                  });
                },
              ),
            IconButton(
              icon: const Icon(Icons.call),
              onPressed: () {
                startCall(context, widget.currentUser, widget.otherUser, false);
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: () {
                startCall(context, widget.currentUser, widget.otherUser, true);
              },
            ),
          ],
        ),
        body: Column(
          children: [
            if (_replyTo != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[800] 
                    : Colors.grey[200],
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to: ${_replyTo!.content}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark 
                              ? Colors.white 
                              : Colors.black,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white 
                          : Colors.black,
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_getChatId())
                    .collection('messages')
                    .orderBy('timestamp', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Error:  ${snapshot.error}'),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final messages = snapshot.data!.docs
                      .map((doc) =>
                          MessageModel.fromMap(doc.data() as Map<String, dynamic>))
                      .toList();
                  // Build a map for reply-to lookup
                  final allMessages = {for (var m in messages) m.id: m};

                  final filteredMessages = _messageSearchQuery.isEmpty
                      ? messages
                      : messages.where((m) => m.content.toLowerCase().contains(_messageSearchQuery)).toList();
                  final visibleMessages = filteredMessages.where((m) {
                    final meta = m.metadata;
                    final deletedFor = meta != null ? meta['deletedFor'] as List? : null;
                    return deletedFor == null || !deletedFor.contains(widget.currentUser.uid);
                  }).toList();

                  // Mark messages as read when messages are loaded
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markMessagesAsRead();
                  });

                  if (visibleMessages.isEmpty) {
                    return const Center(
                      child: Text('No messages found'),
                    );
                  }

                  // Scroll to bottom when messages are first loaded
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients && !_showScrollToBottom) {
                      _scrollToBottom();
                    }
                  });

                  // Scroll to bottom when a new message arrives, but only if user is near the bottom
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      final maxScroll = _scrollController.position.maxScrollExtent;
                      final currentScroll = _scrollController.position.pixels;
                      if (maxScroll - currentScroll < 200) {
                        _scrollToBottom();
                      }
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: visibleMessages.length,
                    itemBuilder: (context, index) {
                      final message = visibleMessages[index];
                      final isMe = message.senderId == widget.currentUser.uid;
                      final originalIndex = messages.indexWhere((m) => m.id == message.id);
                      final previousMessage = originalIndex > 0 ? messages[originalIndex - 1] : null;

                      return MessageBubble(
                        message: message,
                        isMe: isMe,
                        // onReply is now also used for edit/delete
                        onReply: (String? messageId, [bool? isEdit]) async {
                          if (messageId != null && isEdit != null) {
                            if (isEdit) {
                              // Edit message logic
                              final msg = messages.firstWhere((m) => m.id == messageId);
                              final now = DateTime.now();
                              if (now.difference(msg.timestamp).inMinutes < 15 && !msg.isDeleted) {
                                final controller = TextEditingController(text: msg.content);
                                final result = await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Edit Message'),
                                    content: TextField(
                                      controller: controller,
                                      maxLines: null,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, controller.text.trim()),
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                if (result != null && result.isNotEmpty && result != msg.content) {
                                  await FirebaseFirestore.instance
                                    .collection('chats')
                                    .doc(_getChatId())
                                    .collection('messages')
                                    .doc(msg.id)
                                    .update({
                                      'content': result,
                                      'isEdited': true,
                                      'editedAt': Timestamp.fromDate(DateTime.now()),
                                    });
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('You can only edit messages within 15 minutes of sending.')),
                                );
                              }
                            } else {
                              // Delete message logic
                              final msg = messages.firstWhere((m) => m.id == messageId);
                              if (!msg.isDeleted) {
                                await FirebaseFirestore.instance
                                  .collection('chats')
                                  .doc(_getChatId())
                                  .collection('messages')
                                  .doc(msg.id)
                                  .update({
                                    'isDeleted': true,
                                    'originalContent': msg.content,
                                    'content': '',
                                  });
                              }
                            }
                          } else if (messageId != null && isEdit == null) {
                            // Reply logic - messageId is provided but isEdit is null
                            final msg = messages.firstWhere((m) => m.id == messageId);
                            setState(() => _replyTo = msg);
                          } else if (messageId == null) {
                            setState(() => _replyTo = message);
                          }
                        },
                        allMessages: allMessages,
                        otherUserName: widget.otherUser.displayName,
                        previousMessage: previousMessage,
                      );
                    },
                  );
                },
              ),
            ),
            if (_isOtherTyping)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Row(
                  children: [
                    TypingBubble(),
                    const SizedBox(width: 8),
                    Text('${widget.otherUser.displayName} is typing...'),
                  ],
                ),
              ),
            MessageInput(
              controller: _messageController,
              isLoading: _isLoading,
              onSendMessage: () => _sendMessage(
                content: _messageController.text.trim(),
              ),
              onAttachmentPressed: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.image),
                        title: const Text('Image'),
                        onTap: () {
                          Navigator.pop(context);
                          _handleImageSelection();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.videocam),
                        title: const Text('Video'),
                        onTap: () {
                          Navigator.pop(context);
                          _handleVideoSelection();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.attach_file),
                        title: const Text('File'),
                        onTap: () {
                          Navigator.pop(context);
                          _handleFileSelection();
                        },
                      ),
                    ],
                  ),
                );
              },
              onEmojiPressed: _toggleEmojiPicker,
              onChanged: (_) => _onTyping(),
            ),
            if (_showEmoji)
              SizedBox(
                height: 250,
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const String appId = '42da22b9df1649c386f7c40b5a5025dc'; // Replace with your App ID
const String? token = '007eJxTYFBOaP+pmeG/fdqXu7prPpnZFxzQEk6/Y/h05Rqnovs7WQQUGEyMUhKNjJIsU9IMzUwsk40tzNLMk00MkkwTTQ2MTFOSf2/Oy2gIZGQ49OAQIyMDBIL4nAwlqbkFIfnZqXkMDAAv/SMJ'; // For dev, null is fine if token is not enabled
//tempToken
class CallScreen extends StatefulWidget {
  final bool isVideo;
  final String channelName;
  final bool isCaller;
  final UserModel currentUser;
  final UserModel otherUser;

  const CallScreen({
    Key? key,
    required this.channelName,
    this.isVideo = true,
    this.isCaller = false,
    required this.currentUser,
    required this.otherUser,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int? _remoteUid;
  late RtcEngine _engine;
  StreamSubscription<DocumentSnapshot>? _callStatusSub;
  AudioPlayer? _ringPlayer;
  bool _callEnded = false;
  String _callState = 'Connecting';
  bool _muted = false;
  bool _speakerOn = false;
  bool _localVideoSmall = true;
  Timer? _callTimer;
  int _callDuration = 0;
  bool _reconnecting = false;
  bool _showSwitchType = false;
  bool _wasInCall = false; // Track if call was ever 'In Call'

  @override
  void initState() {
    super.initState();
    _initAgora();
    if (widget.isCaller) {
      _callState = 'Ringing';
      _playRingback();
      _callStatusSub = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.channelName)
          .snapshots()
          .listen((doc) {
        final data = doc.data();
        if (data == null) {
          if (mounted) Navigator.pop(context);
          return;
        }
        if (data['status'] == 'accepted') {
          _stopRingback();
          setState(() {
            _callState = 'Connecting'; // Wait for both users to join
            _reconnecting = false;
          });
        } else if (data['status'] == 'declined' || data['status'] == 'ended') {
          _stopRingback();
          _endCallAndCleanup();
          if (mounted) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['status'] == 'declined' ? 'Call declined' : 'Call ended')),
          );
        }
      });
    } else {
      _callState = 'Connecting';
      _callStatusSub = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.channelName)
          .snapshots()
          .listen((doc) {
        final data = doc.data();
        if (data == null || data['status'] == 'ended') {
          if (mounted) Navigator.pop(context);
        } else if (data['status'] == 'accepted') {
          setState(() {
            _callState = 'Connecting'; // Wait for both users to join
            _reconnecting = false;
          });
        } else if (data['status'] == 'declined') {
          if (mounted) Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call declined')),
          );
        }
      });
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callDuration = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _callDuration++;
      });
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _getAgoraUid(String uid) {
    // Use a hash of the Firebase UID, mod 2^31-1 (Agora UID must be int)
    return md5.convert(utf8.encode(uid)).bytes.fold(0, (a, b) => a * 256 + b) % 2147483647;
  }

  Future<void> _initAgora() async {
    await [Permission.microphone, if (widget.isVideo) Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: appId));

    final localAgoraUid = _getAgoraUid(widget.currentUser.uid);
    print('[DEBUG] App ID: $appId');
    print('[DEBUG] Channel: ${widget.channelName}');
    print('[DEBUG] UID: $localAgoraUid');
    print('[DEBUG] Token:  [31m${(token ?? '').substring(0, 10)}...');
    print('[DEBUG] Is Video: ${widget.isVideo}');

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print('[DEBUG] Local user joined Agora channel: channel=${connection.channelId}, uid=${connection.localUid}, elapsed=$elapsed');
          setState(() {
            _callState = _remoteUid != null ? 'In Call' : 'Connecting';
            _reconnecting = false;
          });
          if (_remoteUid != null) {
            _wasInCall = true;
            _startCallTimer();
            _stopRingback();
          }
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          print('[DEBUG] Remote user joined Agora channel: remoteUid=$remoteUid, channel=${connection.channelId}, elapsed=$elapsed');
          setState(() {
            _remoteUid = remoteUid;
            _callState = 'In Call';
            _reconnecting = false;
          });
          _wasInCall = true;
          _startCallTimer();
          _stopRingback();
        },
        onUserOffline: (connection, remoteUid, reason) {
          print('[DEBUG] Remote user left Agora channel: remoteUid=$remoteUid, reason=$reason');
          setState(() {
            _remoteUid = null;
            if (_wasInCall) {
              _callState = 'Reconnecting';
              _reconnecting = true;
            } else {
              _callState = 'Connecting';
              _reconnecting = false;
            }
          });
        },
        onConnectionLost: (connection) {
          print('[DEBUG] Agora connection lost: channel=${connection.channelId}');
          setState(() {
            if (_wasInCall) {
              _callState = 'Reconnecting';
              _reconnecting = true;
            } else {
              _callState = 'Connecting';
              _reconnecting = false;
            }
          });
        },
        onConnectionStateChanged: (connection, state, reason) {
          print('[DEBUG] Agora connection state changed: $state, reason=$reason, channel=${connection.channelId}');
          if (state == ConnectionStateType.connectionStateFailed) {
            setState(() {
              if (_wasInCall) {
                _callState = 'Reconnecting';
                _reconnecting = true;
              } else {
                _callState = 'Connecting';
                _reconnecting = false;
              }
            });
            _stopRingback();
          } else if (state == ConnectionStateType.connectionStateConnected) {
            setState(() {
              _callState = _remoteUid != null ? 'In Call' : 'Connecting';
              _reconnecting = false;
            });
            if (_remoteUid != null) {
              _wasInCall = true;
              _startCallTimer();
              _stopRingback();
            }
          }
        },
        onError: (err, msg) {
          print('[DEBUG][ERROR] Agora error: $err, message: $msg');
          _stopRingback();
        },
      ),
    );

    await _engine.enableAudio();
    if (widget.isVideo) {
      await _engine.enableVideo();
      setState(() => _showSwitchType = true);
    } else {
      setState(() => _showSwitchType = true);
    }

    await _engine.joinChannel(
      token: token ?? '',
      channelId: widget.channelName,
      uid: localAgoraUid,
      options: const ChannelMediaOptions(),
    );
  }

  Future<void> _switchCallType() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Switching call type is not implemented.')),
    );
  }

  Future<void> _playRingback() async {
    _ringPlayer = AudioPlayer();
    await _ringPlayer!.play(AssetSource('ring.mp3'), volume: 1.0,);
  }

  void _stopRingback() {
    _ringPlayer?.stop();
    _ringPlayer?.dispose();
    _ringPlayer = null;
  }

  Future<void> _endCallAndCleanup() async {
    if (_callEnded) return;
    _callEnded = true;
    _callTimer?.cancel();
    final callDoc = FirebaseFirestore.instance.collection('calls').doc(widget.channelName);
    try {
      final docSnap = await callDoc.get();
      if (docSnap.exists) {
        await callDoc.update({'status': 'ended'});
        // Delete after short delay to allow both clients to process
        Future.delayed(const Duration(seconds: 5), () async {
          try {
            final docSnap2 = await callDoc.get();
            if (docSnap2.exists) {
              await callDoc.delete();
            }
          } catch (e) {
            // Ignore not-found
          }
        });
      }
    } catch (e) {
      // Ignore not-found
    }
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _stopRingback();
    _engine.leaveChannel();
    _engine.release();
    _endCallAndCleanup();
    _callTimer?.cancel();
    super.dispose();
  }

  void _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine.muteLocalAudioStream(_muted);
  }

  void _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _engine.setEnableSpeakerphone(_speakerOn);
  }

  void _switchCamera() async {
    await _engine.switchCamera();
    setState(() => _localVideoSmall = !_localVideoSmall);
  }

  Widget _buildAvatar() {
    final user = widget.currentUser.uid == widget.otherUser.uid ? widget.currentUser : widget.otherUser;
    final photo = user.photoURL;
    return CircleAvatar(
      radius: 48,
      backgroundColor: Colors.grey[300],
      backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
      child: (photo == null || photo.isEmpty)
          ? Text(user.displayName[0].toUpperCase(), style: const TextStyle(fontSize: 40, color: Colors.white))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherUser = widget.currentUser.uid == widget.otherUser.uid ? widget.currentUser : widget.otherUser;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isVideo ? 'Video Call' : 'Audio Call')),
      body: Stack(
        children: [
          if (widget.isVideo && _remoteUid != null)
            Positioned.fill(
              child: AgoraVideoView(
                controller: VideoViewController.remote(
                  rtcEngine: _engine,
                  canvas: const VideoCanvas(uid: 1),
                  connection: RtcConnection(channelId: widget.channelName),
                ),
              ),
            ),
          if (widget.isVideo)
            Positioned(
              top: 40,
              right: 16,
              child: SizedBox(
                width: 100,
                height: 150,
                child: AgoraVideoView(
                  controller: VideoViewController(
                    rtcEngine: _engine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
              ),
            ),
          if (!widget.isVideo || _remoteUid == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatar(),
                  const SizedBox(height: 16),
                  Text(otherUser.displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_callState, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                  if (_callState == 'In Call')
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(_formatDuration(_callDuration), style: const TextStyle(fontSize: 16, color: Colors.green)),
                    ),
                ],
              ),
            ),
          // Call controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 32),
                  onPressed: _toggleMute,
                  color: Colors.black54,
                ),
                const SizedBox(width: 32),
                if (widget.isVideo)
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 32),
                    onPressed: _switchCamera,
                    color: Colors.black54,
                  ),
                if (widget.isVideo) const SizedBox(width: 32),
                IconButton(
                  icon: Icon(_speakerOn ? Icons.volume_up : Icons.volume_off, color: Colors.white, size: 32),
                  onPressed: _toggleSpeaker,
                  color: Colors.black54,
                ),
                const SizedBox(width: 32),
                if (_showSwitchType)
                  IconButton(
                    icon: Icon(widget.isVideo ? Icons.call : Icons.videocam, color: Colors.white, size: 32),
                    onPressed: _switchCallType,
                    color: Colors.black54,
                  ),
                if (_showSwitchType) const SizedBox(width: 32),
                FloatingActionButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.call_end),
                  backgroundColor: Colors.red,
                ),
              ],
            ),
          ),
          if (_reconnecting && _wasInCall)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Reconnecting...', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
        ],
      ),
      backgroundColor: Colors.black,
    );
  }
}

String getChannelName(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort();
  return ids.join('_');
}

Future<void> startCall(BuildContext context, UserModel caller, UserModel callee, bool isVideo) async {
  final channelName = getChannelName(caller.uid, callee.uid);
  final callDoc = FirebaseFirestore.instance.collection('calls').doc(channelName);
  await callDoc.set({
    'callerId': caller.uid,
    'callerName': caller.displayName,
    'callerPhoto': caller.photoURL,
    'calleeId': callee.uid,
    'calleeName': callee.displayName,
    'calleePhoto': callee.photoURL,
    'isVideo': isVideo,
    'status': 'ringing',
    'timestamp': FieldValue.serverTimestamp(),
  });
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => CallScreen(
        isVideo: isVideo,
        channelName: channelName,
        isCaller: true,
        currentUser: caller,
        otherUser: callee,
      ),
    ),
  );
}

void listenForIncomingCalls(BuildContext context, UserModel currentUser) {
  AudioPlayer? _calleeRingPlayer;
  void _playCalleeRing() async {
    _calleeRingPlayer = AudioPlayer();
    await _calleeRingPlayer!.play(AssetSource('ring.mp3'), volume: 1.0);
  }
  void _stopCalleeRing() {
    _calleeRingPlayer?.stop();
    _calleeRingPlayer?.dispose();
    _calleeRingPlayer = null;
  }

  FirebaseFirestore.instance
      .collection('calls')
      .where('calleeId', isEqualTo: currentUser.uid)
      .where('status', isEqualTo: 'ringing')
      .snapshots()
      .listen((snapshot) {
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final channelName = doc.id;
      final isVideo = data['isVideo'] ?? true;
      print('[DEBUG] Incoming call doc: $channelName, status=${data['status']}');
      // If call is ended or declined, pop dialog if open and stop ringtone
      if (data['status'] == 'ended' || data['status'] == 'declined') {
        _stopCalleeRing();
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        continue;
      }
      // Show dialog and play ringtone if not already playing
      _playCalleeRing();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Incoming ${isVideo ? 'Video' : 'Audio'} Call'),
          content: Text('From: ${data['callerName']}'),
          actions: [
            TextButton(
              onPressed: () async {
                await doc.reference.update({'status': 'declined'});
                Future.delayed(const Duration(seconds: 5), () async {
                  try {
                    final docSnap = await doc.reference.get();
                    if (docSnap.exists) {
                      await doc.reference.delete();
                    }
                  } catch (e) {
                    // Ignore not-found
                  }
                });
                _stopCalleeRing();
                Navigator.pop(context);
              },
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () async {
                await doc.reference.update({'status': 'accepted'});
                _stopCalleeRing();
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CallScreen(
                      isVideo: isVideo,
                      channelName: channelName,
                      isCaller: false,
                      currentUser: currentUser,
                      otherUser: UserModel(
                        uid: data['callerId']!,
                        displayName: data['callerName']!,
                        photoURL: data['callerPhoto'] ?? '',
                        isOnline: true,
                        email: '',
                        lastSeen: DateTime.now(),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      ).then((_) {
        _stopCalleeRing();
      });
    }
  });
} 

class TypingBubble extends StatefulWidget {
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1Anim;
  late Animation<double> _dot2Anim;
  late Animation<double> _dot3Anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _dot1Anim = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.4, curve: Curves.easeInOut)),
    );
    _dot2Anim = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.6, curve: Curves.easeInOut)),
    );
    _dot3Anim = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _dot1Anim.value),
              child: child,
            ),
            child: _buildDot(context),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _dot2Anim.value),
              child: child,
            ),
            child: _buildDot(context),
          ),
          const SizedBox(width: 4),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _dot3Anim.value),
              child: child,
            ),
            child: _buildDot(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Colors.grey[600],
        shape: BoxShape.circle,
      ),
    );
  }
} 

Widget _buildUserAvatar(UserModel user, BuildContext context, {double radius = 24, double fontSize = 22}) {
  if (user.photoBase64 != null && user.photoBase64!.isNotEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      backgroundImage: MemoryImage(base64Decode(user.photoBase64!)),
    );
  } else if (user.avatarType == 'emoji' && user.avatarValue != null) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.orange.withOpacity(0.2),
      child: Text(user.avatarValue!, style: TextStyle(fontSize: fontSize)),
    );
  } else {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      child: Text(
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '',
        style: TextStyle(color: Colors.white, fontSize: fontSize),
      ),
    );
  }
} 