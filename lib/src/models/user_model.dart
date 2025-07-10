import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel {
  @HiveField(0)
  final String uid;

  @HiveField(1)
  final String email;

  @HiveField(2)
  final String displayName;

  @HiveField(3)
  final String? photoURL;

  @HiveField(4)
  final String? status;

  @HiveField(5)
  final DateTime lastSeen;

  @HiveField(6)
  final bool isOnline;

  @HiveField(7)
  final String? photoBase64;
  @HiveField(8)
  final String? avatarType;
  @HiveField(9)
  final String? avatarValue;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.status,
    required this.lastSeen,
    this.isOnline = false,
    this.photoBase64,
    this.avatarType,
    this.avatarValue,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'status': status,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'isOnline': isOnline,
      'photoBase64': photoBase64,
      'avatarType': avatarType,
      'avatarValue': avatarValue,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    // Handle lastSeen field
    DateTime lastSeen;
    final lastSeenData = map['lastSeen'];
    if (lastSeenData is Timestamp) {
      lastSeen = lastSeenData.toDate();
    } else if (lastSeenData is DateTime) {
      lastSeen = lastSeenData;
    } else {
      lastSeen = DateTime.now();
    }

    // Handle required fields with default values if null
    String uid = '';
    if (map['uid'] != null) {
      uid = map['uid'].toString();
    } else if (map['id'] != null) { // Sometimes Firebase uses 'id' instead of 'uid'
      uid = map['id'].toString();
    }

    String email = '';
    if (map['email'] != null) {
      email = map['email'].toString();
    }

    String displayName = '';
    if (map['displayName'] != null) {
      displayName = map['displayName'].toString();
    } else if (map['name'] != null) { // Sometimes 'name' is used instead of 'displayName'
      displayName = map['name'].toString();
    } else if (email.isNotEmpty) {
      displayName = email.split('@')[0]; // Use email username as fallback
    }

    // Handle optional fields
    String? photoURL;
    if (map['photoURL'] != null) {
      photoURL = map['photoURL'].toString();
    } else if (map['photoUrl'] != null) { // Handle alternative casing
      photoURL = map['photoUrl'].toString();
    }

    String? status;
    if (map['status'] != null) {
      status = map['status'].toString();
    }

    bool isOnline = false;
    if (map['isOnline'] != null) {
      isOnline = map['isOnline'] is bool 
          ? map['isOnline'] 
          : map['isOnline'].toString().toLowerCase() == 'true';
    }

    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoURL: photoURL,
      status: status,
      lastSeen: lastSeen,
      isOnline: isOnline,
      photoBase64: map['photoBase64'] as String?,
      avatarType: map['avatarType'] as String?,
      avatarValue: map['avatarValue'] as String?,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoURL,
    String? status,
    DateTime? lastSeen,
    bool? isOnline,
    String? photoBase64,
    String? avatarType,
    String? avatarValue,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL ?? '',
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      photoBase64: photoBase64 ?? this.photoBase64,
      avatarType: avatarType ?? this.avatarType,
      avatarValue: avatarValue ?? this.avatarValue,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, email: $email, displayName: $displayName, photoURL: $photoURL, status: $status, lastSeen: $lastSeen, isOnline: $isOnline)';
  }
}
