import 'package:flutter/material.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_5.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:convert'; // Added for base64Decode
import 'dart:typed_data'; // Added for Uint8List
import '../../../models/message_model.dart';
import 'media_preview.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final Function(String?, [bool?]) onReply;
  final Map<String, MessageModel> allMessages;
  final String? otherUserName;
  final MessageModel? previousMessage;
  final List<MessageModel>? mediaMessages;
  final int? mediaIndex;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.allMessages,
    this.otherUserName,
    this.previousMessage,
    this.mediaMessages,
    this.mediaIndex,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  double _swipeOffset = 0;
  bool _showReplyHighlight = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSwipeReply() {
    setState(() {
      _showReplyHighlight = true;
      _swipeOffset = 32;
    });
    _controller.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 350), () {
      setState(() {
        _showReplyHighlight = false;
        _swipeOffset = 0;
      });
    });
    widget.onReply(widget.message.id);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
    final onReply = widget.onReply;
    final allMessages = widget.allMessages;
    String? replyContent;
    String? replySender;
    if (message.replyTo != null && allMessages[message.replyTo!] != null) {
      replyContent = allMessages[message.replyTo!]!.content;
      replySender = allMessages[message.replyTo!]!.senderId == message.senderId
          ? (isMe ? 'You' : 'Sender')
          : (allMessages[message.replyTo!]!.senderId == (isMe ? message.receiverId : message.senderId)
              ? 'Other'
              : '');
    }

    // System message: centered, gray, no bubble, no avatar, no tail, no timeago
    if (message.type == MessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  message.content,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Secret tap counter for recovery
    final ValueNotifier<int> tapCount = ValueNotifier<int>(0);
    final ValueNotifier<bool> showRecovered = ValueNotifier<bool>(false);

    Widget messageContentWidget() {
      if (message.isDeleted) {
        return ValueListenableBuilder<bool>(
          valueListenable: showRecovered,
          builder: (context, recovered, _) {
            if (recovered && message.originalContent != null) {
              return Text(
                message.originalContent!,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                ),
              );
            }
            return Text(
              'This message was deleted',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                fontSize: 16,
              ),
            );
          },
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.type != MessageType.text)
              MediaPreview(
                message: message,
                mediaMessages: widget.mediaMessages,
                mediaIndex: widget.mediaIndex,
              ),
            if (message.type == MessageType.text && message.content.isNotEmpty)
              Row(
                children: [
                  Flexible(
                    child: Text(
                      message.content,
                      style: TextStyle(
                        color: isMe 
                            ? Colors.white 
                            : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (message.isEdited)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        '(edited)',
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.black54,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeago.format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe 
                        ? Colors.white70 
                        : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54),
                  ),
                ),
                const SizedBox(width: 4),
                if (isMe)
                  Icon(
                    message.isRead
                        ? Icons.done_all
                        : Icons.done,
                    size: 12,
                    color: message.isRead
                        ? Colors.blue
                        : Colors.white70,
                  ),
              ],
            ),
          ],
        );
      }
    }

    Widget replyPreview() {
      if (message.replyTo != null && replyContent != null) {
        final repliedMessage = allMessages[message.replyTo!];
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
          // For video, show a play icon overlay on a dark box (no frame extraction for simplicity)
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
                  style: TextStyle(
                    fontSize: 13,
                    color: isMe
                        ? Colors.white70
                        : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  ),
                ),
              ),
            ],
          );
        } else {
          contentWidget = Text(
            replyContent!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13, 
              color: isMe 
                  ? Colors.white70 
                  : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
            ),
          );
        }
        return Container(
          // No margin, so it's inside the bubble
          padding: const EdgeInsets.only(top: 4, bottom: 4, left: 12, right: 0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
            border: Border(
              left: BorderSide(
                color: isMe ? Colors.blue : Colors.green,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                allMessages[message.replyTo!]!.senderId == message.senderId
                    ? (isMe ? 'You' : 'Sender')
                    : (allMessages[message.replyTo!]!.senderId == (isMe ? message.receiverId : message.senderId)
                        ? (widget.otherUserName ?? 'Other')
                        : 'Other'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isMe ? Colors.blue : Colors.green,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              contentWidget,
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: (isMe ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black12)).withOpacity(0.15),
                margin: const EdgeInsets.only(top: 2, bottom: 2),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: 1.0,
        // Add extra top padding if previous message was from different sender
        top: (widget.previousMessage != null && widget.previousMessage!.senderId != message.senderId) ? 8.0 : 1.0,
        left: isMe ? 48.0 : 8.0,
        right: isMe ? 8.0 : 48.0,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar removed for one-to-one chat
              //     if (!isMe) ...[
              //   const CircleAvatar(
              //     radius: 16,
              //     child: Icon(Icons.person),
              //   ),
              //   const SizedBox(width: 8),
              // ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () async {
                    final action = await showMenu<String>(
                      context: context,
                      position: RelativeRect.fromLTRB(100, 100, 100, 100),
                      items: [
                        const PopupMenuItem(
                          value: 'reply',
                          child: Text('Reply'),
                        ),
                        if (isMe && !message.isDeleted)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                        if (isMe && !message.isDeleted)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                    );
                    if (action == 'reply') {
                      onReply(message.id);
                    } else if (action == 'edit') {
                      onReply(message.id, true);
                    } else if (action == 'delete') {
                      onReply(message.id, false);
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    // WhatsApp-style swipe to reply
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity!.abs() > 250) {
                      _handleSwipeReply();
                    }
                  },
                  onTap: () {
                    if (message.isDeleted && isMe) {
                      tapCount.value++;
                      if (tapCount.value >= 15) {
                        showRecovered.value = true;
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    transform: Matrix4.translationValues(_showReplyHighlight ? _swipeOffset : 0, 0, 0),
                    curve: Curves.easeOut,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final maxWidth = constraints.maxWidth * 0.65;
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxWidth,
                          ),
                          child: Container(
                            padding: const EdgeInsets.only(
                              left: 12.0,
                              right: 12.0,
                              top: 10.0,
                              bottom: 10.0,
                            ),
                            decoration: BoxDecoration(
                              color: isMe 
                                  ? (Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.green[600] 
                                      : Theme.of(context).primaryColor)
                                  : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : Colors.grey[200]),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isMe ? 18 : 0),
                                bottomRight: Radius.circular(isMe ? 0 : 18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minHeight: 40,
                              minWidth: 40,
                            ),
                            child: Stack(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (message.replyTo != null && replyContent != null) replyPreview(),
                                    if (message.replyTo != null && replyContent != null) const SizedBox(height: 8),
                                    messageContentWidget(),
                                    const SizedBox(height: 6),
                                  ],
                                ),
                                // Bubble tail
                                Positioned(
                                  bottom: 0,
                                  left: isMe ? null : 0,
                                  right: isMe ? 0 : null,
                                  child: CustomPaint(
                                    painter: _BubbleTailPainter(
                                      color: isMe 
                                          ? (Theme.of(context).brightness == Brightness.dark 
                                              ? Colors.green[600]! 
                                              : Theme.of(context).primaryColor)
                                          : (Theme.of(context).brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[200]!),
                                      isMe: isMe,
                                    ),
                                    size: const Size(16, 10),
                                  ),
                                ),
                                if (_showReplyHighlight)
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 4,
                                      decoration: BoxDecoration(
                                        color: isMe ? Colors.blue : Colors.green,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (isMe) ...[
                // Avatar removed for one-to-one chat
                /**
                 *   const SizedBox(width: 8),
                const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person),
                ),
                 */
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMe;
  _BubbleTailPainter({required this.color, required this.isMe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isMe) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width - 10, size.height);
      path.close();
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(10, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 