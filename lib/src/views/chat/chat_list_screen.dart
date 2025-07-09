import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../views/profile/settings_screen.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = context.read<AuthService>().currentUser;
      if (currentUser != null) {
        listenForIncomingCalls(context, currentUser);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthService>().currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AuthService>().signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
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

          if (users.isEmpty) {
            return const Center(
              child: Text('No users found'),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final chatId = [currentUser!.uid, user.uid]..sort();
              final chatDocId = chatId.join('_');
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
                  // Robust online status: only show online if lastSeen is recent
                  final now = DateTime.now();
                  final isRecentlyOnline = user.isOnline && now.difference(user.lastSeen).inSeconds < 30;
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
                          isTyping = typingStatus[user.uid] == true;
                        }
                      }
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            user.displayName[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(user.displayName),
                        subtitle: Text(isTyping ? 'Typing...' : subtitle),
                        trailing: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRecentlyOnline ? Colors.green : Colors.grey,
                          ),
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
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
} 