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

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
    listenForIncomingCalls(context, widget.currentUser);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleImageSelection() async {
    final url = await _mediaService.uploadImage(
      userId: widget.currentUser.uid,
      source: ImageSource.gallery,
      isMessage: true,
    );

    if (url != null) {
      await _sendMessage(
        content: url,
        type: MessageType.image,
      );
    }
  }

  Future<void> _handleVideoSelection() async {
    final url = await _mediaService.uploadVideo(
      userId: widget.currentUser.uid,
      source: ImageSource.gallery,
    );

    if (url != null) {
      await _sendMessage(
        content: url,
        type: MessageType.video,
      );
    }
  }

  Future<void> _handleFileSelection() async {
    final fileData = await _mediaService.uploadFile(
      userId: widget.currentUser.uid,
    );

    if (fileData != null) {
      await _sendMessage(
        content: fileData['url']!,
        type: MessageType.file,
        metadata: fileData,
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_showEmoji) {
          setState(() => _showEmoji = false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.otherUser.displayName),
              Text(
                widget.otherUser.isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.otherUser.isOnline ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
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
                color: Colors.grey[200],
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to: ${_replyTo!.content}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
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
                      child: Text('Error: ${snapshot.error}'),
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

                  if (messages.isEmpty) {
                    return const Center(
                      child: Text('No messages yet'),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final isMe = message.senderId == widget.currentUser.uid;

                      return MessageBubble(
                        message: message,
                        isMe: isMe,
                        onReply: () => setState(() => _replyTo = message),
                      );
                    },
                  );
                },
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
const String? token = null; // For dev, null is fine if token is not enabled

class CallScreen extends StatefulWidget {
  final bool isVideo;
  final String channelName;
  final bool isCaller;

  const CallScreen({Key? key, required this.channelName, this.isVideo = true, this.isCaller = false}) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  int? _remoteUid;
  late RtcEngine _engine;
  StreamSubscription<DocumentSnapshot>? _callStatusSub;
  AudioPlayer? _ringPlayer;
  bool _callEnded = false;

  @override
  void initState() {
    super.initState();
    _initAgora();
    if (widget.isCaller) {
      _playRingback();
      _callStatusSub = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.channelName)
          .snapshots()
          .listen((doc) {
        final data = doc.data();
        if (data == null) return;
        if (data['status'] == 'accepted') {
          _stopRingback();
        } else if (data['status'] == 'declined') {
          _stopRingback();
          _endCallAndCleanup();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call declined')),
          );
        }
      });
    }
  }

  Future<void> _initAgora() async {
    await [Permission.microphone, if (widget.isVideo) Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: appId));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          print('Local user joined');
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          setState(() {
            _remoteUid = remoteUid;
          });
        },
        onUserOffline: (connection, remoteUid, reason) {
          setState(() {
            _remoteUid = null;
          });
        },
      ),
    );

    await _engine.enableAudio();
    if (widget.isVideo) {
      await _engine.enableVideo();
    }

    await _engine.joinChannel(
      token: token ?? '',
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(),
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
    final callDoc = FirebaseFirestore.instance.collection('calls').doc(widget.channelName);
    await callDoc.update({'status': 'ended'});
    // Delete after short delay to allow both clients to process
    Future.delayed(const Duration(seconds: 5), () async {
      await callDoc.delete();
    });
  }

  @override
  void dispose() {
    _callStatusSub?.cancel();
    _stopRingback();
    _engine.leaveChannel();
    _engine.release();
    _endCallAndCleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isVideo ? 'Video Call' : 'Audio Call')),
      body: Center(
        child: _remoteUid == null
            ? const Text('Waiting for user to join...')
            : widget.isVideo
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: _engine,
                      canvas: const VideoCanvas(uid: 1),
                      connection: RtcConnection(channelId: widget.channelName),
                    ),
                  )
                : const Text('Connected (audio only)'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.call_end),
        backgroundColor: Colors.red,
      ),
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
    'calleeId': callee.uid,
    'calleeName': callee.displayName,
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
      ),
    ),
  );
}

void listenForIncomingCalls(BuildContext context, UserModel currentUser) {
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
                  await doc.reference.delete();
                });
                Navigator.pop(context);
              },
              child: const Text('Decline'),
            ),
            TextButton(
              onPressed: () async {
                await doc.reference.update({'status': 'accepted'});
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CallScreen(
                      isVideo: isVideo,
                      channelName: channelName,
                      isCaller: false,
                    ),
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      );
    }
  });
} 