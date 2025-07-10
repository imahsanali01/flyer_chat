import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import 'chat_screen.dart';
import 'dart:convert';

class ArchivedChatsScreen extends StatefulWidget {
  final UserModel currentUser;
  final List<UserModel> users;
  final Set<String> archivedChatIds;
  final Set<String> mutedChats;

  const ArchivedChatsScreen({
    super.key,
    required this.currentUser,
    required this.users,
    required this.archivedChatIds,
    required this.mutedChats,
  });

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  late Set<String> _archivedChats;
  late Set<String> _mutedChats;

  @override
  void initState() {
    super.initState();
    _archivedChats = Set<String>.from(widget.archivedChatIds);
    _mutedChats = Set<String>.from(widget.mutedChats);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived Chats')),
      body: Builder(
        builder: (context) {
          final validChatEntries = _archivedChats
              .map((chatDocId) {
                final ids = chatDocId.split('_');
                final otherUserId = ids.firstWhere((id) => id != widget.currentUser.uid, orElse: () => '');
                final user = widget.users.firstWhere((u) => u.uid == otherUserId, orElse: () => UserModel.empty());
                return {'chatDocId': chatDocId, 'user': user};
              })
              .where((entry) => (entry['user'] as UserModel).uid.isNotEmpty)
              .toList();

          return ListView(
            children: validChatEntries.map((entry) {
              final chatDocId = entry['chatDocId'] as String;
              final user = entry['user'] as UserModel;
              final isMuted = _mutedChats.contains(chatDocId);
              return FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatDocId)
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .limit(1)
                    .get(),
                builder: (context, snapshot) {
                  String subtitle = user.status ?? 'No status';
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    final lastMsg = snapshot.data!.docs.first.data() as Map<String, dynamic>;
                    subtitle = lastMsg['content'] ?? '';
                  }
                  final now = DateTime.now();
                  final isRecentlyOnline = user.isOnline && now.difference(user.lastSeen).inSeconds < 30;
                  return ListTile(
                    leading: _buildUserAvatar(user, context),
                    title: Text(user.displayName),
                    subtitle: Text(subtitle),
                    trailing: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isMuted ? Colors.grey : (isRecentlyOnline ? Colors.green : Colors.grey),
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            currentUser: widget.currentUser,
                            otherUser: user,
                          ),
                        ),
                      );
                    },
                    onLongPress: () async {
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
                                leading: const Icon(Icons.delete_outline, color: Colors.red),
                                title: const Text('Clear Chat', style: TextStyle(color: Colors.red)),
                                onTap: () => Navigator.pop(context, 'clear'),
                              ),
                              ListTile(
                                leading: Icon(_archivedChats.contains(chatDocId) ? Icons.unarchive : Icons.archive_outlined),
                                title: Text(_archivedChats.contains(chatDocId) ? 'Unarchive' : 'Archive'),
                                onTap: () => Navigator.pop(context, 'archive'),
                              ),
                              ListTile(
                                leading: Icon(isMuted ? Icons.notifications_active : Icons.notifications_off_outlined),
                                title: Text(isMuted ? 'Unmute' : 'Mute'),
                                onTap: () => Navigator.pop(context, 'mute'),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (action == 'clear') {
                        final messagesRef = FirebaseFirestore.instance
                            .collection('chats')
                            .doc(chatDocId)
                            .collection('messages');
                        final batch = FirebaseFirestore.instance.batch();
                        final snapshot = await messagesRef.get();
                        for (final doc in snapshot.docs) {
                          batch.update(doc.reference, {
                            'deletedFor': FieldValue.arrayUnion([widget.currentUser.uid])
                          });
                        }
                        await batch.commit();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Chat cleared.')),
                          );
                        }
                      } else if (action == 'archive') {
                        final userRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUser.uid);
                        final newArchived = Set<String>.from(_archivedChats);
                        if (_archivedChats.contains(chatDocId)) {
                          newArchived.remove(chatDocId);
                        } else {
                          newArchived.add(chatDocId);
                        }
                        await userRef.update({'archivedChats': newArchived.toList()});
                        setState(() => _archivedChats = newArchived);
                        if (newArchived.isEmpty && context.mounted) {
                          Navigator.pop(context);
                        }
                      } else if (action == 'mute') {
                        final userRef = FirebaseFirestore.instance.collection('users').doc(widget.currentUser.uid);
                        final newMuted = Set<String>.from(_mutedChats);
                        if (isMuted) {
                          newMuted.remove(chatDocId);
                        } else {
                          newMuted.add(chatDocId);
                        }
                        await userRef.update({'mutedChats': newMuted.toList()});
                        setState(() => _mutedChats = newMuted);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isMuted ? 'Chat unmuted.' : 'Chat muted.')),
                        );
                      }
                    },
                  );
                },
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

Widget _buildUserAvatar(UserModel user, BuildContext context) {
  if (user.photoBase64 != null && user.photoBase64!.isNotEmpty) {
    return CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      backgroundImage: MemoryImage(base64Decode(user.photoBase64!)),
    );
  } else if (user.avatarType == 'emoji' && user.avatarValue != null) {
    return CircleAvatar(
      backgroundColor: Colors.orange.withOpacity(0.2),
      child: Text(user.avatarValue!, style: const TextStyle(fontSize: 22)),
    );
  } else {
    return CircleAvatar(
      backgroundColor: Theme.of(context).primaryColor,
      child: Text(
        user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
} 