import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'dart:io';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  UserModel? _user;
  DateTime? _lastLoginAttempt;
  int _loginAttempts = 0;

  UserModel? get currentUser => _user;

  AuthService() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      // Only set persistence on web platform
      if (kIsWeb) {
        await _auth.setPersistence(Persistence.LOCAL);
      }
      
      _auth.authStateChanges().listen((User? user) async {
        if (user != null) {
          await _loadUserData(user.uid);
        } else {
          _user = null;
          notifyListeners();
        }
      });
    } catch (e) {
      print('Error initializing auth: $e');
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

  @override
  void dispose() {
    _user = null;
    super.dispose();
  }
} 