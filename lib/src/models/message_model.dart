import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'message_model.g.dart';

@HiveType(typeId: 1)
enum MessageType {
  @HiveField(0)
  text,
  @HiveField(1)
  image,
  @HiveField(2)
  audio,
  @HiveField(3)
  video,
  @HiveField(4)
  file,
  @HiveField(5)
  location,
  @HiveField(6)
  sticker
}

@HiveType(typeId: 2)
class MessageModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String senderId;

  @HiveField(2)
  final String receiverId;

  @HiveField(3)
  final String content;

  @HiveField(4)
  final MessageType type;

  @HiveField(5)
  final DateTime timestamp;

  @HiveField(6)
  final bool isRead;

  @HiveField(7)
  final Map<String, dynamic>? metadata;

  @HiveField(8)
  final String? replyTo;

  @HiveField(9)
  final List<String>? mentions;

  @HiveField(10)
  final bool isEdited;

  @HiveField(11)
  final DateTime? editedAt;

  @HiveField(12)
  final bool isDeleted;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.metadata,
    this.replyTo,
    this.mentions,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      content: map['content'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.toString() == 'MessageType.${map['type']}',
      ),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isRead: map['isRead'] as bool? ?? false,
      metadata: map['metadata'] as Map<String, dynamic>?,
      replyTo: map['replyTo'] as String?,
      mentions: (map['mentions'] as List<dynamic>?)?.cast<String>(),
      isEdited: map['isEdited'] as bool? ?? false,
      editedAt: map['editedAt'] != null
          ? (map['editedAt'] as Timestamp).toDate()
          : null,
      isDeleted: map['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'type': type.toString().split('.').last,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
      'metadata': metadata,
      'replyTo': replyTo,
      'mentions': mentions,
      'isEdited': isEdited,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'isDeleted': isDeleted,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    bool? isRead,
    Map<String, dynamic>? metadata,
    String? replyTo,
    List<String>? mentions,
    bool? isEdited,
    DateTime? editedAt,
    bool? isDeleted,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      metadata: metadata ?? this.metadata,
      replyTo: replyTo ?? this.replyTo,
      mentions: mentions ?? this.mentions,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
