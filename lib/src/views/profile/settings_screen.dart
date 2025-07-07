import 'package:flutter/material.dart';
import 'package:flyer_chat/src/views/auth/login_screen.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/secure_storage_service.dart';
import '../../views/auth/change_password_screen.dart';
import '../../views/auth/password_reset_screen.dart';
import 'delete_account_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
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
                        // Navigator.of(context) .pushNamedAndRemoveUntil('/login', (route) => false);
                         //   Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                  Navigator.of(context).pop();
                   Navigator.of(context).pop();
                    await  context.read<AuthService>().signOut();
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
} 