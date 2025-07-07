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

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.replyTo != null)
            Container(
              margin: EdgeInsets.only(
                left: isMe ? 0 : 48,
                right: isMe ? 48 : 0,
                bottom: 4,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Reply to: ${message.replyTo}',
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
                  child: ChatBubble(
                    clipper: ChatBubbleClipper5(
                      type: isMe
                          ? BubbleType.sendBubble
                          : BubbleType.receiverBubble,
                    ),
                    alignment:
                        isMe ? Alignment.centerRight : Alignment.centerLeft,
                    margin: EdgeInsets.zero,
                    backGroundColor:
                        isMe ? Theme.of(context).primaryColor : Colors.grey[200],
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
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