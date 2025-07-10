import 'package:flutter/material.dart';
import 'package:flyer_chat/src/views/auth/login_screen.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/secure_storage_service.dart';
import '../../views/auth/change_password_screen.dart';
import '../../views/auth/password_reset_screen.dart';
import 'delete_account_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBiometricAvailable = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final authService = context.read<AuthService>();
    final isAvailable = await authService.isBiometricAvailable();
    setState(() => _isBiometricAvailable = isAvailable);
  }

  Future<void> _toggleBiometric(bool enabled) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      if (enabled) {
        await authService.enableBiometric();
      } else {
        await authService.disableBiometric();
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendVerificationEmail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      await authService.sendEmailVerification();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification email sent! Please check your inbox.'),
        ),
      );
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final isEmailVerified = authService.isEmailVerified();
    final isBiometricEnabled = authService.biometricEnabled;
    final user = authService.currentUser;

    Future<void> _pickAndUploadImage() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked != null && user != null) {
        final ref = FirebaseStorage.instance.ref().child('profile_pics/${user.uid}.jpg');
        await ref.putData(await picked.readAsBytes());
        final url = await ref.getDownloadURL();
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'photoURL': url});
        await authService.reloadUserData(user.uid); // Refresh user data
        setState(() {});
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (user != null) ...[
            Center(
              child: Stack(
                children: [
                  _buildProfileAvatar(user),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _pickAndUploadImageBase64,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Theme.of(context).primaryColor,
                            child: const Icon(Icons.edit, color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showAvatarPicker,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.orange,
                            child: const Icon(Icons.emoji_emotions, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          const Text(
            'Security',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    isEmailVerified ? Icons.verified : Icons.mark_email_unread,
                    color: isEmailVerified ? Colors.green : Colors.orange,
                  ),
                  title: const Text('Email Verification'),
                  subtitle: Text(
                    isEmailVerified
                        ? 'Your email is verified'
                        : 'Your email is not verified',
                  ),
                  trailing: !isEmailVerified
                      ? TextButton(
                          onPressed: _isLoading ? null : _sendVerificationEmail,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Verify'),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green),
                ),
                if (_isBiometricAvailable) ...[
                  const Divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Biometric Login'),
                    subtitle: const Text(
                      'Use fingerprint or face recognition to sign in',
                    ),
                    value: isBiometricEnabled,
                    onChanged: _isLoading ? null : _toggleBiometric,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Change Password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign Out'),
                  onTap: () async {
                    try {
                      await authService.signOut();
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete Account',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Account?'),
                        content: const Text(
                          'Are you sure you want to delete your account? '
                          'This action cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const DeleteAccountScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Continue'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar(user) {
    if (user.photoBase64 != null && user.photoBase64!.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        backgroundImage: MemoryImage(base64Decode(user.photoBase64!)),
      );
    } else if (user.avatarType == 'emoji' && user.avatarValue != null) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Colors.orange.withOpacity(0.2),
        child: Text(user.avatarValue!, style: const TextStyle(fontSize: 32)),
      );
    } else {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        child: Text(user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '', style: const TextStyle(fontSize: 32, color: Colors.white)),
      );
    }
  }

  Future<void> _pickAndUploadImageBase64() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 128, maxHeight: 128);
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    if (picked != null && user != null) {
      final bytes = await picked.readAsBytes();
      final base64Str = base64Encode(bytes);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'photoBase64': base64Str,
        'photoURL': '',
        'avatarType': '',
        'avatarValue': '',
      });
      await authService.reloadUserData(user.uid);
      setState(() {});
    }
  }

  void _showAvatarPicker() async {
    final emojis = ['😀','😎','🦄','🐱','🐶','👽','👾','🐸','🐵','🐼','🦊','🐻','🐯','🦁','🐮','🐷','🐨','🐔','🐧','🐦','🐤','🐣','🦉','🦋','🐌','🐞','🐢','🐍','🐙','🦑','🦀','🐠','🐬','🐳','🐋','🦈','🐊','🐅','🐆','🦓','🦍','🐘','🦏','🦛','🐪','🐫','🦒','🦘','🦥','🦦','🦨','🦡','🐁','🐀','🐇','🐿️','🦔'];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Pick an avatar'),
        children: emojis.map((e) => SimpleDialogOption(
          child: Text(e, style: const TextStyle(fontSize: 28)),
          onPressed: () => Navigator.pop(context, e),
        )).toList(),
      ),
    );
    if (selected != null) {
      final authService = context.read<AuthService>();
      final user = authService.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'avatarType': 'emoji',
          'avatarValue': selected,
          'photoBase64': '',
          'photoURL': '',
        });
        await authService.reloadUserData(user.uid);
        setState(() {});
      }
    }
  }
} 