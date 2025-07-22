import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import './secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class AuthService extends ChangeNotifier with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  UserModel? _user;
  DateTime? _lastLoginAttempt;
  int _loginAttempts = 0;
  bool _biometricEnabled = false;
  Timer? _heartbeatTimer;
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  UserModel? get currentUser => _user;
  bool get biometricEnabled => _biometricEnabled;

  AuthService() {
    _isLoading = true;
    _initializeAuth();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _initializeAuth() async {
    try {
      // Only set persistence on web platform
      if (kIsWeb) {
        await _auth.setPersistence(Persistence.LOCAL);
      }
      bool firstEvent = true;
      _auth.authStateChanges().listen((User? user) async {
        if (user != null) {
          await _loadUserData(user.uid);
          _startHeartbeat();
        } else {
          _user = null;
          _stopHeartbeat();
          notifyListeners();
        }
        if (firstEvent) {
          _isLoading = false;
          firstEvent = false;
          notifyListeners();
        }
      });
    } catch (e) {
      print('Error initializing auth: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Ensure lastSeen is properly handled
        if (data['lastSeen'] == null) {
          data['lastSeen'] = Timestamp.now();
        }
        _user = UserModel.fromMap({
          ...data,
          'uid': uid, // Ensure uid is always set
        });
        notifyListeners();
      } else {
        debugPrint('User document does not exist for uid: $uid');
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> reloadUserData(String uid) async {
    await _loadUserData(uid);
  }

  Future<UserModel?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      // First, try to get the user credential
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Wait for a short duration to allow Firebase Auth to complete its internal processes
      await Future.delayed(const Duration(milliseconds: 500));

      // Get the current user
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw FirebaseAuthException(
          code: 'null-user',
          message: 'Failed to sign in: No user returned',
        );
      }

      // Check if user document exists
      final doc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        // Create user document if it doesn't exist
        final newUser = UserModel(
          uid: currentUser.uid,
          email: email,
          displayName: currentUser.displayName ?? email.split('@')[0],
          lastSeen: DateTime.now(),
          status: 'Hey there! I am using Flyer Chat',
        );
        
        final userData = newUser.toMap();
        await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .set(userData);
            
        _user = newUser;
        notifyListeners();
      } else {
        // Load existing user data
        await _loadUserData(currentUser.uid);
      }

      return _user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('Error signing in: $e');
      rethrow;
    }
  }

  Future<UserModel?> registerWithEmailAndPassword(
    String email,
    String password,
    String displayName,
  ) async {
    try {
      // Create the user with Firebase Auth
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Wait for a short duration to allow Firebase Auth to complete its internal processes
      await Future.delayed(const Duration(milliseconds: 500));

      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw FirebaseAuthException(
          code: 'null-user',
          message: 'Failed to register: No user returned',
        );
      }

      // Update the user's display name
      await currentUser.updateDisplayName(displayName);

      // Create the user document in Firestore
      final user = UserModel(
        uid: currentUser.uid,
        email: email,
        displayName: displayName,
        lastSeen: DateTime.now(),
        status: 'Hey there! I am using Flyer Chat',
      );

      final userData = user.toMap();
      await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .set(userData);

      _user = user;
      notifyListeners();
      return user;
    } catch (e) {
      debugPrint('Error registering user: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      if (_user != null) {
        await updateUserStatus(isOnline: false);
      }
      await _auth.signOut();
      _user = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  Future<void> updateUserStatus({required bool isOnline}) async {
    try {
      if (_user != null) {
        final updates = {
          'isOnline': isOnline,
          'lastSeen': Timestamp.now(),
        };

        await _firestore
            .collection('users')
            .doc(_user!.uid)
            .update(updates);

        _user = _user!.copyWith(
          isOnline: isOnline,
          lastSeen: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating user status: $e');
    }
  }

  Future<void> reauthenticate(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw 'No user is currently signed in';
      }

      // Create credentials
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );

      // Reauthenticate
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'Failed to reauthenticate: $e';
    }
  }

  Future<void> changePassword(String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw 'No user is currently signed in';
      }

      if (!_isStrongPassword(newPassword)) {
        throw 'Password must be at least 8 characters long and contain uppercase letters and numbers';
      }

      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'Failed to change password: $e';
    }
  }

  Future<void> deleteAccount(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        throw 'No user is currently signed in';
      }

      // First, reauthenticate the user
      await reauthenticate(password);

      // Get user data for cleanup
      final uid = user.uid;

      // Start cleanup
      final batch = _firestore.batch();

      // Delete user's messages from all chats
      final chats = await _firestore
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();

      for (final chat in chats.docs) {
        // Delete messages in batches of 500 (Firestore limit)
        final messages = await chat.reference
            .collection('messages')
            .where('senderId', isEqualTo: uid)
            .get();

        for (final message in messages.docs) {
          batch.delete(message.reference);
        }

        // Update chat metadata or delete if no other participants
        final participants = List<String>.from(chat.data()['participants'] ?? []);
        participants.remove(uid);
        if (participants.isEmpty) {
          batch.delete(chat.reference);
        } else {
          batch.update(chat.reference, {
            'participants': participants,
            'lastUpdated': Timestamp.now(),
          });
        }
      }

      // Delete user document
      batch.delete(_firestore.collection('users').doc(uid));

      // Commit all Firestore changes
      await batch.commit();

      // Delete user authentication
      await user.delete();

      // Clear local storage
      final storage = SecureStorageService();
      await storage.deleteAllData();

      // Clear local state
      _user = null;
      notifyListeners();
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'Failed to delete account: $e';
    }
  }

  bool _isStrongPassword(String password) {
    return password.length >= 8 && 
           RegExp(r'[A-Z]').hasMatch(password) && 
           RegExp(r'[0-9]').hasMatch(password);
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+').hasMatch(email);
  }

  Future<bool> _canAttemptLogin() async {
    final now = DateTime.now();
    if (_lastLoginAttempt != null && 
        _loginAttempts >= 5 && 
        now.difference(_lastLoginAttempt!) < const Duration(minutes: 5)) {
      return false;
    }
    _lastLoginAttempt = now;
    _loginAttempts++;
    return true;
  }

  void _setupTokenRefresh() {
    _auth.idTokenChanges().listen((User? user) async {
      if (user != null) {
        // Handle token refresh
        final token = await user.getIdToken();
        // Update token in your app's state/storage
      }
    });
  }

  String _getReadableError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled';
      case 'requires-recent-login':
        return 'Please log in again before deleting your account';
      case 'expired-action-code':
        return 'The password reset code has expired';
      case 'invalid-action-code':
        return 'The password reset code is invalid';
      case 'user-disabled':
        return 'This account has been disabled';
      default:
        return e.message ?? 'An error occurred';
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      if (!_isValidEmail(email)) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'The email address is invalid.',
        );
      }

      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'An error occurred while sending password reset email';
    }
  }

  Future<void> verifyPasswordResetCode(String code) async {
    try {
      await _auth.verifyPasswordResetCode(code);
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'An error occurred while verifying reset code';
    }
  }

  Future<void> confirmPasswordReset(String code, String newPassword) async {
    try {
      if (!_isStrongPassword(newPassword)) {
        throw 'Password must be at least 8 characters long and contain uppercase letters and numbers';
      }

      await _auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (e) {
      throw _getReadableError(e);
    } catch (e) {
      throw 'An error occurred while resetting password';
    }
  }

  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      throw 'An error occurred while sending verification email';
    }
  }

  bool isEmailVerified() {
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<bool> isBiometricAvailable() async {
    try {
      // Skip biometric check on emulators
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        if (!androidInfo.isPhysicalDevice) {
          debugPrint('Running on emulator - biometrics disabled');
          return false;
        }
      }

      // Check device support first as it's more reliable
      if (!await _localAuth.isDeviceSupported()) {
        return false;
      }

      // Only check canCheckBiometrics if device is supported
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      debugPrint('Error checking biometric availability: $e');
      return false;
    }
  }

  Future<void> enableBiometric() async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        throw 'Biometric authentication is not available on this device';
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to enable biometric login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate) {
        _biometricEnabled = true;
        // Store user preference in Firestore
        if (_user != null) {
          await _firestore
              .collection('users')
              .doc(_user!.uid)
              .update({'biometricEnabled': true});
        }
        notifyListeners();
      }
    } catch (e) {
      throw 'Failed to enable biometric authentication';
    }
  }

  Future<void> disableBiometric() async {
    try {
      _biometricEnabled = false;
      if (_user != null) {
        await _firestore
            .collection('users')
            .doc(_user!.uid)
            .update({'biometricEnabled': false});
      }
      notifyListeners();
    } catch (e) {
      throw 'Failed to disable biometric authentication';
    }
  }

  Future<UserModel?> signInWithBiometric() async {
    try {
      if (!_biometricEnabled) {
        throw 'Biometric authentication is not enabled';
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to login',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuthenticate && _user != null) {
        // Re-authenticate with Firebase using stored credentials
        // Note: You would need to securely store credentials for this
        return _user;
      } else {
        throw 'Biometric authentication failed';
      }
    } catch (e) {
      throw 'Failed to authenticate with biometrics';
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Update presence immediately and every 20 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      updateUserStatus(isOnline: true);
    });
    updateUserStatus(isOnline: true);
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    updateUserStatus(isOnline: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_user == null) return;
    if (state == AppLifecycleState.resumed) {
      // App comes to foreground: set online and start heartbeat
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      // App goes to background or is closed: set offline and stop heartbeat
      _stopHeartbeat();
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _user = null;
    super.dispose();
  }
} 