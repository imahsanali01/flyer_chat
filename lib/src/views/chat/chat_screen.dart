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
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
//app certificate secondary
// e212492ef48b47ae9dc5508d28d6c806
class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel otherUser;
  final bool isPersonalChat;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
    this.isPersonalChat = false,
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

  // Multi-select state
  Set<String> _selectedMessageIds = {};
  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;

  // Typing indicator state
  Timer? _typingTimer;
  bool _isOtherTyping = false;
  StreamSubscription<DocumentSnapshot>? _typingSubscription;
  bool _isOtherUserOnline = false;

  // Track last message count for auto-scroll
  int _lastMessageCount = 0;

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
    _setTypingStatus(false); // Ensure typing status is reset on exit
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
      final messageId = const Uuid().v4();
      final messageMap = MessageModel(
        id: messageId,
        senderId: widget.currentUser.uid,
        receiverId: widget.otherUser.uid,
        content: content ?? '',
        type: type,
        timestamp: DateTime.now(), // Placeholder, will be replaced by serverTimestamp
        replyTo: _replyTo?.id,
        metadata: metadata,
      ).toMap();
      // Overwrite the timestamp with serverTimestamp
      messageMap['timestamp'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_getChatId())
          .collection('messages')
          .doc(messageId)
          .set(messageMap);

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
    final isActuallyTyping = _messageController.text.trim().isNotEmpty;
    _setTypingStatus(isActuallyTyping);
    _typingTimer?.cancel();
    if (isActuallyTyping) {
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _setTypingStatus(false);
      });
    }
  }

  void _setTypingStatus(bool isTyping) async {
    final chatId = _getChatId();
    final typingField = 'typingStatus.${widget.currentUser.uid}';
    await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'typingStatus': {
        widget.currentUser.uid: isTyping,
        '${widget.currentUser.uid}_ts': isTyping ? FieldValue.serverTimestamp() : null,
      }
    }, SetOptions(merge: true));
  }

  void _listenToOtherTyping() {
    final chatId = _getChatId();
    _typingSubscription = FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots().listen((doc) {
      final data = doc.data();
      if (data != null && data['typingStatus'] != null) {
        final typingStatus = Map<String, dynamic>.from(data['typingStatus']);
        final otherUid = widget.otherUser.uid;
        final isTyping = typingStatus[otherUid] == true;
        final ts = typingStatus['${otherUid}_ts'];
        final isRecent = ts != null && ts is Timestamp && DateTime.now().difference(ts.toDate()).inSeconds < 8;
        final showTyping = isTyping && isRecent;
        if (mounted) {
          setState(() {
            _isOtherTyping = showTyping;
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
    final otherUserId = widget.otherUser.uid;
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

    // Check if all messages are deleted for both users
    final updatedSnapshot = await messagesRef.get();
    bool allCleared = updatedSnapshot.docs.isNotEmpty && updatedSnapshot.docs.every((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final deletedFor = data['deletedFor'] as List?;
      return deletedFor != null && deletedFor.contains(userId) && deletedFor.contains(otherUserId);
    });
    if (allCleared) {
      // Delete all messages and the chat document
      final deleteBatch = FirebaseFirestore.instance.batch();
      for (final doc in updatedSnapshot.docs) {
        deleteBatch.delete(doc.reference);
      }
      deleteBatch.delete(FirebaseFirestore.instance.collection('chats').doc(chatId));
      await deleteBatch.commit();
    }
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

  Widget _buildReplyPreview(Map<String, MessageModel> allMessages) {
    if (_replyTo == null) return const SizedBox.shrink();
    final repliedMessage = allMessages[_replyTo!.id];
    Widget contentWidget;
    if (repliedMessage != null && repliedMessage.type == MessageType.image) {
      Uint8List? imageBytes;
      if (repliedMessage.content.isNotEmpty) {
        imageBytes = base64Decode(repliedMessage.content);
      } else if (repliedMessage.metadata != null && repliedMessage.metadata?['base64'] != null) {
        imageBytes = base64Decode(repliedMessage.metadata?['base64']);
      }
      contentWidget = imageBytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                imageBytes,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.broken_image, size: 32);
    } else if (repliedMessage != null && repliedMessage.type == MessageType.video) {
      contentWidget = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white, size: 32),
        ),
      );
    } else if (repliedMessage != null && repliedMessage.type == MessageType.file) {
      final fileName = repliedMessage.metadata?['name'] ?? 'File';
      contentWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 24),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      );
    } else {
      contentWidget = Text(
        repliedMessage?.content ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 4,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repliedMessage?.senderId == widget.currentUser.uid ? 'You' : widget.otherUser.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                contentWidget,
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = _getChatId();
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots(),
      builder: (context, chatSnapshot) {
        Map<String, dynamic>? chatData = chatSnapshot.data?.data() as Map<String, dynamic>?;
        final background = chatData != null && chatData['background'] != null ? chatData['background'] as Map<String, dynamic> : null;
        Color? bgColor;
        DecorationImage? bgImage;
        if (background != null) {
          if (background['type'] == 'color' && background['value'] != null) {
            bgColor = Color(int.parse(background['value'].toString().replaceFirst('#', '0xff')));
          } else if (background['type'] == 'image' && background['value'] != null) {
            bgImage = DecorationImage(
              image: MemoryImage(base64Decode(background['value'])),
              fit: BoxFit.cover,
            );
          }
        }
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .orderBy('timestamp', descending: false)
              .orderBy('id', descending: false)
              .snapshots(),
          builder: (context, snapshot) {
            // Error/loading handling
            if (snapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('Chat')),
                body: Center(child: Text('Error:  ${snapshot.error}')),
              );
            }
            if (!snapshot.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Chat')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            // Prepare message lists
            final messages = snapshot.data!.docs
                .map((doc) => MessageModel.fromMap(doc.data() as Map<String, dynamic>))
                .where((m) => m.timestamp != null)
                .toList();
            messages.sort((a, b) {
              final cmp = a.timestamp.compareTo(b.timestamp);
              if (cmp != 0) return cmp;
              return a.id.compareTo(b.id);
            });
            final allMessages = {for (var m in messages) m.id: m};
            final filteredMessages = _messageSearchQuery.isEmpty
                ? messages
                : messages.where((m) => m.content.toLowerCase().contains(_messageSearchQuery)).toList();
            final visibleMessages = filteredMessages.where((m) {
              final meta = m.metadata;
              final deletedFor = meta != null ? meta['deletedFor'] as List? : null;
              return deletedFor == null || !deletedFor.contains(widget.currentUser.uid);
            }).toList();

            // After visibleMessages is built, add post-frame callback for auto-scroll and read receipts
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                final maxScroll = _scrollController.position.maxScrollExtent;
                final currentScroll = _scrollController.position.pixels;
                // Auto-scroll if new message and user is near bottom
                if (visibleMessages.length > _lastMessageCount && maxScroll - currentScroll < 200) {
                  _scrollToBottom();
                }
                _lastMessageCount = visibleMessages.length;
              }
              // Mark as read only if there are unread messages
              final unread = visibleMessages.any((m) => m.receiverId == widget.currentUser.uid && !m.isRead);
              if (unread) {
                _markMessagesAsRead();
              }
            });

            // Now return the Scaffold with AppBar and body, using visibleMessages/allMessages as needed
            return Scaffold(
              appBar: _isSelectionMode
                  ? AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() => _selectedMessageIds.clear());
                        },
                      ),
                      title: Text('${_selectedMessageIds.length} selected'),
                      actions: [
                        if (_selectedMessageIds.length == 1)
                          IconButton(
                            icon: const Icon(Icons.reply),
                            onPressed: () {
                              final msgId = _selectedMessageIds.first;
                              setState(() {
                                _replyTo = allMessages[msgId];
                                _selectedMessageIds.clear();
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            final selectedMsgs = visibleMessages.where((m) => _selectedMessageIds.contains(m.id)).toList();
                            final text = selectedMsgs.map((m) => m.content).join('\n');
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                            setState(() => _selectedMessageIds.clear());
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forward not implemented')));
                            setState(() => _selectedMessageIds.clear());
                          },
                        ),
                        if (_selectedMessageIds.length == 1)
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () {
                              final msg = visibleMessages.firstWhere((m) => m.id == _selectedMessageIds.first);
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Message Info'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Sender: ${msg.senderId == widget.currentUser.uid ? 'You' : widget.otherUser.displayName}'),
                                      Text('Time: ${msg.timestamp}'),
                                      Text('Type: ${msg.type.toString().split('.').last}'),
                                      Text('Read: ${msg.isRead ? 'Yes' : 'No'}'),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                              setState(() => _selectedMessageIds.clear());
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final chatId = _getChatId();
                            for (final msgId in _selectedMessageIds) {
                              await FirebaseFirestore.instance
                                  .collection('chats')
                                  .doc(chatId)
                                  .collection('messages')
                                  .doc(msgId)
                                  .update({
                                'isDeleted': true,
                                'originalContent': '',
                                'content': '',
                              });
                            }
                            setState(() => _selectedMessageIds.clear());
                          },
                        ),
                      ],
                    )
                  : AppBar(
                      title: !_isSearchingMessages
                          ? GestureDetector(
                              onTap: () async {
                                if (widget.isPersonalChat) return; // No menu for personal chat
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
                                                isOnline = data['isOnline'] as bool? ?? false;
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
                                        if (!widget.isPersonalChat) ...[
                                          ListTile(
                                            leading: Icon(_isArchived ? Icons.unarchive : Icons.archive_outlined),
                                            title: Text(_isArchived ? 'Unarchive' : 'Archive'),
                                            onTap: () async {
                                              Navigator.pop(context, 'archive');
                                            },
                                          ),
                                          ListTile(
                                            leading: Icon(_isMuted ? Icons.notifications_active : Icons.notifications_off_outlined),
                                            title: Text(_isMuted ? 'Unmute' : 'Mute'),
                                            onTap: () async {
                                              Navigator.pop(context, 'mute');
                                            },
                                          ),
                                        ],
                                        if (!widget.isPersonalChat)
                                          ListTile(
                                            leading: const Icon(Icons.format_paint),
                                            title: const Text('Change Background'),
                                            onTap: () async {
                                              Navigator.pop(context);
                                              showDialog(
                                                context: context,
                                                builder: (context) => _BackgroundPickerDialog(
                                                  chatId: _getChatId(),
                                                  currentUser: widget.currentUser,
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                                if (action == 'clear') {
                                  // final confirm = await showDialog<bool>(
                                  //   context: context,
                                  //   builder: (context) => AlertDialog(
                                  //     title: const Text('Clear Chat?'),
                                  //     content: const Text('Are you sure you want to clear your side of this chat? This cannot be undone.'),
                                  //     actions: [
                                  //       TextButton(
                                  //         onPressed: () => Navigator.pop(context, false),
                                  //         child: const Text('Cancel'),
                                  //       ),
                                  //       TextButton(
                                  //         onPressed: () => Navigator.pop(context, true),
                                  //         child: const Text('Clear'),
                                  //       ),
                                  //     ],
                                  //   ),
                                  // );
                                  // if (confirm == true) {
                                  //   await _clearChatForCurrentUser();
                                  // }
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
                                      if (!widget.isPersonalChat)
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(widget.otherUser.uid)
                                              .snapshots(),
                                          builder: (context, snapshot) {
                                            bool isOnline = false;
                                            if (snapshot.hasData && snapshot.data!.data() != null) {
                                              final data = snapshot.data!.data() as Map<String, dynamic>;
                                              isOnline = data['isOnline'] as bool? ?? false;
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
                    if (!widget.isPersonalChat) ...[
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
                  ],
                ),
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
              body: Container(
                decoration: BoxDecoration(
                  color: bgColor ?? Theme.of(context).scaffoldBackgroundColor,
                  image: bgImage,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: visibleMessages.length,
                        itemBuilder: (context, index) {
                          final message = visibleMessages[index];
                          final isMe = message.senderId == widget.currentUser.uid;
                          final previousMessage = index > 0 ? visibleMessages[index - 1] : null;
                          final mediaMessages = visibleMessages
                              .where((m) => m.type == MessageType.image || m.type == MessageType.video)
                              .toList();
                          final mediaIndex = (message.type == MessageType.image || message.type == MessageType.video)
                              ? mediaMessages.indexWhere((m) => m.id == message.id)
                              : null;
                          return MessageBubble(
                            message: message,
                            isMe: isMe,
                            onReply: (String? messageId, [bool? isEdit]) async {
                              if (_isSelectionMode) return;
                              if (messageId != null && isEdit != null) {
                                if (isEdit) {
                                  final msg = messages.firstWhere((m) => m.id == messageId);
                                  final now = DateTime.now();
                                  if (now.difference(msg.timestamp!).inMinutes < 15 && !msg.isDeleted) {
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
                                final msg = messages.firstWhere((m) => m.id == messageId);
                                setState(() => _replyTo = msg);
                              } else if (messageId == null) {
                                setState(() => _replyTo = message);
                              }
                            },
                            allMessages: allMessages,
                            otherUserName: widget.otherUser.displayName,
                            previousMessage: previousMessage,
                            mediaMessages: mediaMessages.isNotEmpty ? mediaMessages : null,
                            mediaIndex: mediaIndex,
                            isSelected: _selectedMessageIds.contains(message.id),
                            isSelectionMode: _isSelectionMode,
                            onSelect: () {
                              setState(() {
                                if (_selectedMessageIds.contains(message.id)) {
                                  _selectedMessageIds.remove(message.id);
                                } else {
                                  _selectedMessageIds.add(message.id);
                                }
                              });
                            },
                            onStartSelection: () {
                              setState(() {
                                _selectedMessageIds.add(message.id);
                              });
                            },
                          );
                        },
                      ),
                    ),
                    // Only show typing indicator if not a personal chat
                    if (_isOtherTyping && !widget.isPersonalChat)
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
                    if (_replyTo != null) _buildReplyPreview(allMessages),
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
          },
        );
      },
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

class _BackgroundPickerDialog extends StatefulWidget {
  final String chatId;
  final UserModel currentUser;
  const _BackgroundPickerDialog({required this.chatId, required this.currentUser});
  @override
  State<_BackgroundPickerDialog> createState() => _BackgroundPickerDialogState();
}

class _BackgroundPickerDialogState extends State<_BackgroundPickerDialog> {
  Color? _selectedColor;
  Uint8List? _selectedImage;
  bool _isLoading = false;

  Future<void> _pickColor() async {
    Color pickerColor = Colors.blue;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
            enableAlpha: false,
            showLabel: false,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: const Text('Select'),
            onPressed: () {
              setState(() {
                _selectedColor = pickerColor;
                _selectedImage = null;
              });
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImage = bytes;
        _selectedColor = null;
      });
    }
  }

  Future<void> _setDefault() async {
    setState(() {
      _selectedColor = null;
      _selectedImage = null;
    });
  }

  Future<void> _saveBackground() async {
    if (mounted) setState(() => _isLoading = true);
    Map<String, dynamic>? bg;
    if (_selectedImage != null) {
      bg = {
        'type': 'image',
        'value': base64Encode(_selectedImage!),
      };
    } else if (_selectedColor != null) {
      bg = {
        'type': 'color',
        'value': '#${_selectedColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      };
    } // else: default, so remove background
    if (bg != null) {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
        'background': bg,
      }, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set({
        'background': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    // Send system message
    final userName = widget.currentUser.displayName;
    final systemMsg = 'Wallpaper updated by $userName';
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').doc(msgId).set({
      'id': msgId,
      'senderId': 'system',
      'receiverId': '',
      'content': systemMsg,
      'type': 'system',
      'timestamp': Timestamp.now(),
      'isRead': true,
    });
    if (mounted) setState(() => _isLoading = false);
    Navigator.of(context).pop();
  }

  Future<void> _setDefaultWithConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Default?'),
        content: const Text('Are you sure you want to reset the chat background to the default?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ElevatedButton(
            child: const Text('Reset'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (mounted) {
        setState(() {
          _selectedColor = null;
          _selectedImage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultColor = Theme.of(context).scaffoldBackgroundColor;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Change Chat Background', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.color_lens),
                      label: const Text('Pick Color'),
                      style: ElevatedButton.styleFrom(shape: StadiumBorder()),
                      onPressed: _pickColor,
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Image'),
                      style: ElevatedButton.styleFrom(shape: StadiumBorder()),
                      onPressed: _pickImage,
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Default'),
                      style: ElevatedButton.styleFrom(shape: StadiumBorder()),
                      onPressed: _setDefaultWithConfirmation,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Default preview
                    GestureDetector(
                      onTap: _setDefaultWithConfirmation,
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: defaultColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: const Center(child: Icon(Icons.format_paint, size: 28)),
                          ),
                          const SizedBox(height: 6),
                          const Text('Default', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    if (_selectedColor != null) ...[
                      const SizedBox(width: 24),
                      Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _selectedColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text('Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                    if (_selectedImage != null) ...[
                      const SizedBox(width: 24),
                      Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(_selectedImage!, width: 56, height: 56, fit: BoxFit.cover),
                          ),
                          const SizedBox(height: 6),
                          const Text('Image', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isLoading ? null : _saveBackground,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 