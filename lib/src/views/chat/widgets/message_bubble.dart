import 'package:flutter/material.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_5.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../models/message_model.dart';
import 'media_preview.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final VoidCallback onReply;
  final Map<String, MessageModel> allMessages;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.allMessages,
  });

  @override
  Widget build(BuildContext context) {
    String? replyContent;
    if (message.replyTo != null && allMessages[message.replyTo!] != null) {
      replyContent = allMessages[message.replyTo!]!.content;
    }
    return Padding(
      padding: EdgeInsets.only(
        top: 4.0,
        bottom: 4.0,
        left: isMe ? 48.0 : 8.0,
        right: isMe ? 8.0 : 48.0,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.replyTo != null && replyContent != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Reply to: $replyContent',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (message.replyTo != null && replyContent == null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Reply to: (message not found)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: onReply,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isMe ? Theme.of(context).primaryColor : Colors.grey[200],
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
                    child: Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: 14.0,
                            right: 14.0,
                            top: 10.0,
                            bottom: 18.0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.type != MessageType.text)
                                MediaPreview(message: message),
                              if (message.content.isNotEmpty)
                                Text(
                                  message.content,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black,
                                    fontSize: 16,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    timeago.format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe ? Colors.white70 : Colors.black54,
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
                          ),
                        ),
                        // Bubble tail
                        Positioned(
                          bottom: 0,
                          left: isMe ? null : 0,
                          right: isMe ? 0 : null,
                          child: CustomPaint(
                            painter: _BubbleTailPainter(
                              color: isMe ? Theme.of(context).primaryColor : Colors.grey[200]!,
                              isMe: isMe,
                            ),
                            size: const Size(16, 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                const CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person),
                ),
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