# Security Features Code Examples

## Authentication Examples

### 1. Password Reset Implementation

```dart
class PasswordResetService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final SecurityLogger _logger = SecurityLogger();

  Future<void> sendResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      await _logger.logSecurityEvent(
        event: 'password_reset_requested',
        severity: 'medium',
        details: {'email': email},
      );
    } on FirebaseAuthException catch (e) {
      await _logger.logSecurityEvent(
        event: 'password_reset_failed',
        severity: 'high',
        details: {'error': e.code, 'email': email},
      );
      rethrow;
    }
  }

  Future<void> confirmPasswordReset(String code, String newPassword) async {
    try {
      await _auth.confirmPasswordReset(
        code: code,
        newPassword: newPassword,
      );
      await _logger.logSecurityEvent(
        event: 'password_reset_completed',
        severity: 'medium',
      );
    } on FirebaseAuthException catch (e) {
      await _logger.logSecurityEvent(
        event: 'password_reset_confirmation_failed',
        severity: 'high',
        details: {'error': e.code},
      );
      rethrow;
    }
  }
}
```

### 2. Biometric Authentication Implementation

```dart
class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  final SecurityLogger _logger = SecurityLogger();

  Future<bool> isBiometricAvailable() async {
    try {
      // Check if hardware is available
      if (!await _auth.isDeviceSupported()) {
        return false;
      }

      // Check if biometrics are enrolled
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      if (!canCheckBiometrics) {
        return false;
      }

      // Get available biometrics
      final availableBiometrics = await _auth.getAvailableBiometrics();
      return availableBiometrics.isNotEmpty;
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'biometric_check_failed',
        severity: 'medium',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Please authenticate to continue',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated) {
        await _logger.logSecurityEvent(
          event: 'biometric_auth_success',
          severity: 'medium',
        );
      } else {
        await _logger.logSecurityEvent(
          event: 'biometric_auth_failed',
          severity: 'medium',
        );
      }

      return authenticated;
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'biometric_auth_error',
        severity: 'high',
        details: {'error': e.toString()},
      );
      return false;
    }
  }

  Future<void> storeBiometricCredentials(String email, String password) async {
    if (await authenticateWithBiometrics()) {
      final encryptedPassword = await _encryptData(password);
      await _storage.write(key: 'email', value: email);
      await _storage.write(key: 'password', value: encryptedPassword);
    }
  }

  Future<Map<String, String>?> getBiometricCredentials() async {
    if (await authenticateWithBiometrics()) {
      final email = await _storage.read(key: 'email');
      final encryptedPassword = await _storage.read(key: 'password');
      
      if (email != null && encryptedPassword != null) {
        final password = await _decryptData(encryptedPassword);
        return {
          'email': email,
          'password': password,
        };
      }
    }
    return null;
  }
}
```

### 3. Account Deletion Implementation

```dart
class AccountDeletionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SecurityLogger _logger = SecurityLogger();
  final BiometricService _biometric = BiometricService();

  Future<void> deleteAccount({
    required String password,
    required bool useBiometric,
  }) async {
    try {
      // Step 1: Authenticate
      if (useBiometric) {
        final isAuthenticated = await _biometric.authenticateWithBiometrics();
        if (!isAuthenticated) {
          throw 'Biometric authentication failed';
        }
      }

      final user = _auth.currentUser;
      if (user == null) throw 'No user logged in';

      // Step 2: Reauthenticate
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Step 3: Start batch deletion
      await _deleteUserData(user.uid);

      // Step 4: Delete authentication account
      await user.delete();

      await _logger.logSecurityEvent(
        event: 'account_deleted',
        severity: 'high',
        details: {'userId': user.uid},
      );
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'account_deletion_failed',
        severity: 'high',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  Future<void> _deleteUserData(String uid) async {
    // Delete user messages
    await _deleteCollection(
      'chats',
      where: 'senderId',
      isEqualTo: uid,
    );

    // Delete user profile
    await _firestore.collection('users').doc(uid).delete();

    // Delete user settings
    await _firestore.collection('settings').doc(uid).delete();

    // Delete user files
    await _deleteUserFiles(uid);
  }

  Future<void> _deleteCollection(
    String collection, {
    required String where,
    required dynamic isEqualTo,
  }) async {
    const batchSize = 500;
    var query = _firestore.collection(collection)
        .where(where, isEqualTo: isEqualTo)
        .limit(batchSize);
    
    return Future.doWhile(() async {
      final snapshot = await query.get();
      
      if (snapshot.docs.isEmpty) {
        return false;
      }

      final batch = _firestore.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.reference));
      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        return false;
      }

      query = _firestore.collection(collection)
          .where(where, isEqualTo: isEqualTo)
          .startAfterDocument(snapshot.docs.last)
          .limit(batchSize);
          
      return true;
    });
  }
}
```

## Security Service Examples

### 1. Rate Limiting Implementation

```dart
class RateLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SecurityLogger _logger = SecurityLogger();

  // Rate limits
  static const _maxLoginAttempts = 5;
  static const _maxPasswordResets = 3;
  static const _cooldownDuration = Duration(minutes: 15);

  Future<bool> checkRateLimit(
    String identifier,
    String action,
  ) async {
    final doc = await _firestore
        .collection('rate_limits')
        .doc('${action}_$identifier')
        .get();

    if (!doc.exists) {
      return true;
    }

    final data = doc.data()!;
    final attempts = data['attempts'] as int;
    final lastAttempt = (data['lastAttempt'] as Timestamp).toDate();

    // Check if cooldown period has passed
    if (DateTime.now().difference(lastAttempt) > _cooldownDuration) {
      return true;
    }

    // Check if under limit
    final maxAttempts = _getMaxAttempts(action);
    return attempts < maxAttempts;
  }

  Future<void> recordAttempt(
    String identifier,
    String action,
  ) async {
    final ref = _firestore
        .collection('rate_limits')
        .doc('${action}_$identifier');

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(ref);
      
      if (!doc.exists) {
        transaction.set(ref, {
          'attempts': 1,
          'lastAttempt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = doc.data()!;
        final lastAttempt = (data['lastAttempt'] as Timestamp).toDate();
        
        // Reset counter if cooldown period has passed
        if (DateTime.now().difference(lastAttempt) > _cooldownDuration) {
          transaction.set(ref, {
            'attempts': 1,
            'lastAttempt': FieldValue.serverTimestamp(),
          });
        } else {
          transaction.update(ref, {
            'attempts': FieldValue.increment(1),
            'lastAttempt': FieldValue.serverTimestamp(),
          });
        }
      }
    });

    await _logger.logSecurityEvent(
      event: '${action}_attempt',
      severity: 'medium',
      details: {'identifier': identifier},
    );
  }

  int _getMaxAttempts(String action) {
    switch (action) {
      case 'login':
        return _maxLoginAttempts;
      case 'password_reset':
        return _maxPasswordResets;
      default:
        return 5; // Default limit
    }
  }
}
```

### 2. Secure Storage Implementation

```dart
class SecureStorageService {
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  final SecurityLogger _logger = SecurityLogger();
  
  // Encryption key management
  static const _keyAlias = 'app_master_key';
  static const _ivSize = 16;

  Future<void> initialize() async {
    try {
      // Check if master key exists
      final hasMasterKey = await _storage.containsKey(key: _keyAlias);
      if (!hasMasterKey) {
        // Generate and store new master key
        final key = await _generateMasterKey();
        await _storage.write(
          key: _keyAlias,
          value: base64.encode(key),
        );
      }
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'storage_init_failed',
        severity: 'high',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  Future<void> secureWrite(String key, String value) async {
    try {
      // Get master key
      final masterKey = await _getMasterKey();
      
      // Generate random IV
      final iv = _generateIV();
      
      // Encrypt value
      final encrypted = await _encrypt(value, masterKey, iv);
      
      // Store encrypted data with IV
      await _storage.write(
        key: key,
        value: json.encode({
          'data': base64.encode(encrypted),
          'iv': base64.encode(iv),
        }),
      );
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'secure_write_failed',
        severity: 'high',
        details: {'key': key, 'error': e.toString()},
      );
      rethrow;
    }
  }

  Future<String?> secureRead(String key) async {
    try {
      final encrypted = await _storage.read(key: key);
      if (encrypted == null) return null;

      // Parse stored data
      final data = json.decode(encrypted);
      final encryptedBytes = base64.decode(data['data']);
      final iv = base64.decode(data['iv']);

      // Get master key
      final masterKey = await _getMasterKey();

      // Decrypt value
      return await _decrypt(encryptedBytes, masterKey, iv);
    } catch (e) {
      await _logger.logSecurityEvent(
        event: 'secure_read_failed',
        severity: 'high',
        details: {'key': key, 'error': e.toString()},
      );
      return null;
    }
  }

  Future<List<int>> _generateMasterKey() async {
    final random = Random.secure();
    return List<int>.generate(32, (i) => random.nextInt(256));
  }

  Future<List<int>> _getMasterKey() async {
    final encodedKey = await _storage.read(key: _keyAlias);
    if (encodedKey == null) {
      throw 'Master key not found';
    }
    return base64.decode(encodedKey);
  }

  List<int> _generateIV() {
    final random = Random.secure();
    return List<int>.generate(_ivSize, (i) => random.nextInt(256));
  }

  // Implement _encrypt and _decrypt methods using platform-specific encryption
  // For example, using AES-GCM on supported platforms
}
```

### 3. Security Event Logging Implementation

```dart
class SecurityLogger {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<void> logSecurityEvent({
    required String event,
    required String severity,
    Map<String, dynamic>? details,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final deviceInfo = await _getDeviceInfo();

      await _firestore.collection('security_logs').add({
        'event': event,
        'severity': severity,
        'timestamp': FieldValue.serverTimestamp(),
        'userId': user?.uid,
        'deviceInfo': deviceInfo,
        'details': details,
      });

      // For high severity events, notify security team
      if (severity == 'high') {
        await _notifySecurityTeam(event, details);
      }

      // Check for suspicious patterns
      await _checkForSuspiciousActivity(event, user?.uid);
    } catch (e) {
      // Fallback to local logging if Firebase is unavailable
      print('Security event logging failed: $e');
      _logLocally(event, severity, details);
    }
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'androidVersion': androidInfo.version.release,
          'securityPatch': androidInfo.version.securityPatch,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'platform': 'ios',
          'model': iosInfo.model,
          'systemVersion': iosInfo.systemVersion,
          'localizedModel': iosInfo.localizedModel,
        };
      }
      
      return {'platform': 'unknown'};
    } catch (e) {
      return {
        'platform': 'error',
        'error': e.toString(),
      };
    }
  }

  Future<void> _checkForSuspiciousActivity(
    String event,
    String? userId,
  ) async {
    if (userId == null) return;

    final now = DateTime.now();
    final oneHourAgo = now.subtract(Duration(hours: 1));

    // Check for multiple high-severity events
    final recentEvents = await _firestore
        .collection('security_logs')
        .where('userId', isEqualTo: userId)
        .where('severity', isEqualTo: 'high')
        .where('timestamp', isGreaterThan: oneHourAgo)
        .get();

    if (recentEvents.docs.length >= 5) {
      await _notifySecurityTeam(
        'multiple_high_severity_events',
        {'userId': userId, 'count': recentEvents.docs.length},
      );
    }
  }

  void _logLocally(
    String event,
    String severity,
    Map<String, dynamic>? details,
  ) {
    final logEntry = {
      'event': event,
      'severity': severity,
      'timestamp': DateTime.now().toIso8601String(),
      'details': details,
    };

    // Write to local file
    final file = File('security.log');
    file.writeAsStringSync(
      '${json.encode(logEntry)}\n',
      mode: FileMode.append,
    );
  }
}
``` 