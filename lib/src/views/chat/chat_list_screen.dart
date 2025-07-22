import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../views/profile/settings_screen.dart';
import 'chat_screen.dart';
import 'dart:convert';
import 'archived_chats_screen.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  String _searchQuery = '';
  bool _isSearching = false;
  Set<String> _mutedChats = {};
  Set<String> _archivedChats = {};

  void _openChatHeadsScreen(UserModel currentUser, List<UserModel> allUsers, List<String> recentChatIds) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatHeadsScreen(
          currentUser: currentUser,
          allUsers: allUsers,
          recentChatIds: recentChatIds,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser != null) {
        listenForIncomingCalls(context, currentUser);
      }
    });
    _loadMutedAndArchivedChats();
  }

  Future<void> _loadMutedAndArchivedChats() async {
    final currentUser = context.read<AuthService>().currentUser;
    if (currentUser == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
    final data = userDoc.data() ?? {};
    setState(() {
      _mutedChats = Set<String>.from(data['mutedChats'] ?? []);
      _archivedChats = Set<String>.from(data['archivedChats'] ?? []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.read<AuthService>().currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) _searchQuery = '';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          // IconButton(
          //   icon: const Icon(Icons.logout),
          //   onPressed: () {
          //     context.read<AuthService>().signOut();
          //   },
          // ),
        ],
      ),
      floatingActionButton: currentUser == null
          ? null
          : FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('users').get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();
                final allUsers = snapshot.data!.docs
                    .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
                    .where((u) => u.uid != currentUser.uid)
                    .toList();
                // Get recent chat IDs (chats with at least one message not deleted for current user)
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('chats').snapshots(),
                  builder: (context, chatSnap) {
                    List<String> recentChatIds = [];
                    if (chatSnap.hasData) {
                      for (final doc in chatSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final participants = List<String>.from(data['participants'] ?? []);
                        if (participants.contains(currentUser.uid)) {
                          recentChatIds.add(doc.id);
                        }
                      }
                    }
                    return FloatingActionButton(
                      onPressed: () => _openChatHeadsScreen(currentUser, allUsers, recentChatIds),
                      child: const Icon(Icons.chat_bubble),
                    );
                  },
                );
              },
            ),
      body: Column(
        children: [
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
              ),
            ),
          // Personal chat tile at the top
          if (currentUser != null)
            ListTile(
              leading: CachedUserAvatar(user: currentUser, key: ValueKey(currentUser.photoBase64 ?? '')),
              title: const Text('Me', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      currentUser: currentUser,
                      otherUser: currentUser,
                      isPersonalChat: true, // Add this flag to ChatScreen
                    ),
                  ),
                ).then((_) {
                  setState(() {}); // Refresh chat list after returning
                });
              },
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('uid', isNotEqualTo: currentUser?.uid)
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

                final users = snapshot.data!.docs
                    .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
                    .toList();

                final filteredUsers = _searchQuery.isEmpty
                    ? users
                    : users.where((u) => u.displayName.toLowerCase().contains(_searchQuery)).toList();

                if (filteredUsers.isEmpty) {
                  return const Center(
                    child: Text('No users found'),
                  );
                }

                // WhatsApp-like: Show a single 'Archived Chats' tile at the top if any archived chats exist
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_archivedChats.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.archive_outlined),
                          title: const Text('Archived Chats'),
                          trailing: CircleAvatar(
                            radius: 12,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Text(
                              _archivedChats.length.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ArchivedChatsScreen(
                                  currentUser: currentUser!,
                                  users: users,
                                  archivedChatIds: _archivedChats,
                                  mutedChats: _mutedChats,
                                ),
                              ),
                            ).then((_) {
                              _loadMutedAndArchivedChats();
                            });
                          },
                        ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final chatId = [currentUser!.uid, user.uid]..sort();
                          final chatDocId = chatId.join('_');
                          final isMuted = _mutedChats.contains(chatDocId);
                          final isArchived = _archivedChats.contains(chatDocId);
                          if (isArchived) return const SizedBox.shrink();
                          return StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('chats')
                                .doc(chatDocId)
                                .snapshots(),
                            builder: (context, typingSnap) {
                              bool isTyping = false;
                              if (typingSnap.hasData && typingSnap.data!.data() != null) {
                                final data = typingSnap.data!.data() as Map<String, dynamic>;
                                if (data['typingStatus'] != null) {
                                  final typingStatus = Map<String, dynamic>.from(data['typingStatus']);
                                  final typingFlag = typingStatus[user.uid] == true;
                                  final ts = typingStatus['${user.uid}_ts'];
                                  final isRecent = ts != null && ts is Timestamp && DateTime.now().difference(ts.toDate()).inSeconds < 8;
                                  isTyping = typingFlag && isRecent;
                                }
                              }
                              final isOnline = user.isOnline;
                              return FutureBuilder<QuerySnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('chats')
                                    .doc(chatDocId)
                                    .collection('messages')
                                    .orderBy('timestamp', descending: true)
                                    .limit(40)
                                    .get(),
                                builder: (context, snapshot) {
                                  // Hide chat if all messages are deleted for current user
                                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                    final messages = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
                                    final lastMsg = messages.first;
                                    final deletedFor = lastMsg['deletedFor'] as List?;
                                    if (deletedFor != null && deletedFor.contains(currentUser.uid)) {
                                      return const SizedBox.shrink();
                                    }
                                    // Unread count
                                    int unreadCount = messages.where((m) => m['receiverId'] == currentUser.uid && m['isRead'] == false).length;
                                    // Last message time formatting
                                    DateTime? lastTime;
                                    if (lastMsg['timestamp'] is Timestamp) {
                                      lastTime = (lastMsg['timestamp'] as Timestamp).toDate();
                                    } else if (lastMsg['timestamp'] is DateTime) {
                                      lastTime = lastMsg['timestamp'] as DateTime;
                                    }
                                    String timeStr = '';
                                    if (lastTime != null) {
                                      final now = DateTime.now();
                                      final diff = now.difference(lastTime);
                                      if (now.day == lastTime.day && now.month == lastTime.month && now.year == lastTime.year) {
                                        timeStr = DateFormat('HH:mm').format(lastTime);
                                      } else if (now.subtract(const Duration(days: 1)).day == lastTime.day && now.month == lastTime.month && now.year == lastTime.year) {
                                        timeStr = 'Yesterday';
                                      } else if (now.difference(lastTime).inDays < 7) {
                                        timeStr = DateFormat('EEE').format(lastTime); // Mon, Tue, etc.
                                      } else {
                                        timeStr = DateFormat('dd/MM/yy').format(lastTime);
                                      }
                                    }
                                    // Subtitle logic
                                    String subtitle = user.status ?? 'No status';
                                    if (lastMsg.isNotEmpty) {
                                      String typeStr = lastMsg['type'] ?? 'text';
                                      String content = lastMsg['content'] ?? '';
                                      switch (typeStr) {
                                        case 'image':
                                          subtitle = 'Photo';
                                          break;
                                        case 'video':
                                          subtitle = 'Video';
                                          break;
                                        case 'file':
                                          subtitle = 'File';
                                          break;
                                        default:
                                          subtitle = content;
                                      }
                                    }
                                    // Online/offline dot
                                    final now = DateTime.now();
                                    final isRecentlyOnline = user.isOnline && now.difference(user.lastSeen).inSeconds < 30;
                                    return ListTile(
                                      leading: Stack(
                                        children: [
                                          CachedUserAvatar(user: user, key: ValueKey(user.photoBase64 ?? '')),
                                          Positioned(
                                            bottom: 2,
                                            right: 2,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isRecentlyOnline ? Colors.green : Colors.grey,
                                                border: Border.all(color: Colors.white, width: 2),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      title: Text(user.displayName),
                                      subtitle: Text(isTyping ? 'Typing...' : subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          if (timeStr.isNotEmpty)
                                            Text(timeStr, style: TextStyle(fontSize: 12, color: unreadCount > 0 ? Theme.of(context).colorScheme.primary : Colors.grey)),
                                          if (unreadCount > 0)
                                            Container(
                                              margin: const EdgeInsets.only(top: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.primary,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                unreadCount.toString(),
                                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => ChatScreen(
                                              currentUser: currentUser,
                                              otherUser: user,
                                            ),
                                          ),
                                        ).then((_) {
                                          setState(() {}); // Refresh chat list after returning
                                        });
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
                                                  leading: Icon(isArchived ? Icons.unarchive : Icons.archive_outlined),
                                                  title: Text(isArchived ? 'Unarchive' : 'Archive'),
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
                                          //   // Clear chat for current user only
                                          //   final chatId = [currentUser!.uid, user.uid]..sort();
                                          //   final chatDocId = chatId.join('_');
                                          //   final messagesRef = FirebaseFirestore.instance
                                          //       .collection('chats')
                                          //       .doc(chatDocId)
                                          //       .collection('messages');
                                          //   final batch = FirebaseFirestore.instance.batch();
                                          //   final snapshot = await messagesRef.get();
                                          //   for (final doc in snapshot.docs) {
                                          //     batch.update(doc.reference, {
                                          //       'deletedFor': FieldValue.arrayUnion([currentUser.uid])
                                          //     });
                                          //   }
                                          //   await batch.commit();
                                          //   if (context.mounted) {
                                          //     setState(() {}); // <-- Add this to update the UI
                                          //     ScaffoldMessenger.of(context).showSnackBar(
                                          //       const SnackBar(content: Text('Chat cleared.')),
                                          //     );
                                          //   }
                                          // }
                                        } else if (action == 'archive') {
                                          final userRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
                                          final newArchived = Set<String>.from(_archivedChats);
                                          if (isArchived) {
                                            newArchived.remove(chatDocId);
                                          } else {
                                            newArchived.add(chatDocId);
                                          }
                                          await userRef.update({'archivedChats': newArchived.toList()});
                                          setState(() => _archivedChats = newArchived);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text(isArchived ? 'Chat archived.' : 'Chat unarchived.')),
                                          );
                                        } else if (action == 'mute') {
                                          final userRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
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
                                  } else if (snapshot.hasData && snapshot.data!.docs.isEmpty) {
                                    // No messages left, hide chat
                                    return const SizedBox.shrink();
                                  }
                                  return const SizedBox.shrink();
                                },
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatHeadsScreen extends StatefulWidget {
  final UserModel currentUser;
  final List<UserModel> allUsers;
  final List<String> recentChatIds;
  const ChatHeadsScreen({super.key, required this.currentUser, required this.allUsers, required this.recentChatIds});

  @override
  State<ChatHeadsScreen> createState() => _ChatHeadsScreenState();
}

class _ChatHeadsScreenState extends State<ChatHeadsScreen> {
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  Widget build(BuildContext context) {
    // Recent users (from recentChatIds)
    final recentUsers = widget.allUsers.where((u) => widget.recentChatIds.any((id) => id.contains(u.uid))).toList();
    // Other users
    final otherUsers = widget.allUsers.where((u) => !widget.recentChatIds.any((id) => id.contains(u.uid))).toList();
    // Filter by search
    final filteredRecent = recentUsers.where((u) => u.displayName.toLowerCase().contains(_searchQuery)).toList();
    final filteredOthers = otherUsers.where((u) => u.displayName.toLowerCase().contains(_searchQuery)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Heads'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) _searchQuery = '';
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search users...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                if (filteredRecent.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('Recent', style: Theme.of(context).textTheme.titleMedium),
                  ),
                ...filteredRecent.map((user) => ListTile(
                      leading: CachedUserAvatar(user: user, key: ValueKey(user.photoBase64 ?? '')),
                      title: Text(user.displayName),
                      onTap: () {
                        Navigator.pop(context);
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
                    )),
                if (filteredOthers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text('All Users', style: Theme.of(context).textTheme.titleMedium),
                  ),
                ...filteredOthers.map((user) => ListTile(
                      leading: CachedUserAvatar(user: user, key: ValueKey(user.photoBase64 ?? '')),
                      title: Text(user.displayName),
                      onTap: () {
                        Navigator.pop(context);
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
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CachedUserAvatar extends StatefulWidget {
  final UserModel user;
  final double radius;
  final double fontSize;
  const CachedUserAvatar({Key? key, required this.user, this.radius = 24, this.fontSize = 22}) : super(key: key);

  @override
  State<CachedUserAvatar> createState() => _CachedUserAvatarState();
}

class _CachedUserAvatarState extends State<CachedUserAvatar> {
  Uint8List? _imageBytes;
  String? _lastBase64;

  @override
  void didUpdateWidget(covariant CachedUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user.photoBase64 != _lastBase64) {
      _decodeImage();
    }
  }

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  void _decodeImage() {
    if (widget.user.photoBase64 != null && widget.user.photoBase64!.isNotEmpty) {
      _imageBytes = base64Decode(widget.user.photoBase64!);
      _lastBase64 = widget.user.photoBase64;
    } else {
      _imageBytes = null;
      _lastBase64 = null;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: _imageBytes != null
          ? CircleAvatar(
              radius: widget.radius,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              backgroundImage: MemoryImage(_imageBytes!),
            )
          : (widget.user.avatarType == 'emoji' && widget.user.avatarValue != null)
              ? CircleAvatar(
                  radius: widget.radius,
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  child: Text(widget.user.avatarValue!, style: TextStyle(fontSize: widget.fontSize)),
                )
              : CircleAvatar(
                  radius: widget.radius,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    widget.user.displayName.isNotEmpty ? widget.user.displayName[0].toUpperCase() : '',
                    style: TextStyle(color: Colors.white, fontSize: widget.fontSize),
                  ),
                ),
    );
  }
} 