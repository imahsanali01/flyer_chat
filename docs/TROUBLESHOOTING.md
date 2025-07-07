# Security Features Troubleshooting Guide

## Common Issues and Solutions

### Authentication Issues

#### 1. Password Reset Problems

**Issue**: Reset email not received
```
Problem: User requests password reset but doesn't receive email
Solutions:
1. Check spam folder
2. Verify email address is correct
3. Check rate limiting status
4. Ensure Firebase email service is configured
```

**Issue**: Reset link expired
```
Problem: "Link expired" error when trying to reset password
Solutions:
1. Request new reset link
2. Check time between request and usage (valid for 1 hour)
3. Ensure not using old reset link from previous requests
```

**Code Example - Handling Reset Link Expiration**:
```dart
try {
  await authService.verifyPasswordResetCode(code);
} on FirebaseAuthException catch (e) {
  if (e.code == 'expired-action-code') {
    // Show user-friendly message
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Link Expired'),
        content: Text('Please request a new password reset link.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => PasswordResetScreen(),
              ),
            ),
            child: Text('Request New Link'),
          ),
        ],
      ),
    );
  }
}
```

#### 2. Biometric Authentication Issues

**Issue**: Biometric setup fails
```
Problem: Unable to enable biometric authentication
Solutions:
1. Check device compatibility
2. Verify biometric sensor is working
3. Ensure device has registered biometrics
4. Check app permissions
```

**Code Example - Biometric Availability Check**:
```dart
Future<void> troubleshootBiometric() async {
  final LocalAuthentication auth = LocalAuthentication();
  
  // Check if hardware is available
  if (!await auth.isDeviceSupported()) {
    print('Device does not support biometric authentication');
    return;
  }

  // Check if biometrics are enrolled
  if (!await auth.canCheckBiometrics) {
    print('No biometrics enrolled on this device');
    return;
  }

  // Get available biometrics
  final List<BiometricType> availableBiometrics =
      await auth.getAvailableBiometrics();
      
  if (availableBiometrics.isEmpty) {
    print('No biometrics available');
    return;
  }

  // Check specific types
  if (availableBiometrics.contains(BiometricType.fingerprint)) {
    print('Fingerprint authentication available');
  }
  if (availableBiometrics.contains(BiometricType.face)) {
    print('Face authentication available');
  }
}
```

#### 3. Account Deletion Issues

**Issue**: Deletion process hangs
```
Problem: Account deletion process seems stuck
Solutions:
1. Check network connection
2. Verify user reauthentication
3. Monitor batch operation progress
4. Check for large data volumes
```

**Code Example - Robust Account Deletion**:
```dart
Future<void> robustAccountDeletion(String password) async {
  try {
    // Step 1: Check network
    final hasNetwork = await checkConnectivity();
    if (!hasNetwork) {
      throw 'No network connection';
    }

    // Step 2: Reauthenticate with timeout
    await Future.timeout(
      authService.reauthenticate(password),
      Duration(seconds: 30),
    );

    // Step 3: Start deletion with progress
    final progress = ValueNotifier<double>(0.0);
    
    // Delete messages
    final totalMessages = await countUserMessages();
    var deletedMessages = 0;
    await for (final batch in deleteMessagesInBatches()) {
      deletedMessages += batch.size;
      progress.value = deletedMessages / totalMessages;
    }

    // Delete account
    await authService.deleteAccount(password);
  } on TimeoutException {
    throw 'Operation timed out. Please try again.';
  } catch (e) {
    throw 'Deletion failed: $e';
  }
}
```

### Session Management Issues

#### 1. Token Refresh Problems

**Issue**: Session unexpectedly ends
```
Problem: User gets logged out randomly
Solutions:
1. Check token refresh mechanism
2. Verify network connectivity
3. Check for clock sync issues
4. Monitor token expiration
```

**Code Example - Token Refresh Handling**:
```dart
class TokenManager {
  Timer? _refreshTimer;
  
  void startTokenRefresh() {
    // Check token every 30 minutes
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      Duration(minutes: 30),
      (_) => _checkAndRefreshToken(),
    );
  }

  Future<void> _checkAndRefreshToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final decodedToken = parseJwt(token);
      
      // Refresh if token expires in less than 5 minutes
      final expirationTime = DateTime.fromMillisecondsSinceEpoch(
        decodedToken['exp'] * 1000,
      );
      
      if (DateTime.now().isAfter(
        expirationTime.subtract(Duration(minutes: 5)),
      )) {
        await user.getIdToken(true); // Force refresh
      }
    } catch (e) {
      print('Token refresh failed: $e');
    }
  }
}
```

### Data Protection Issues

#### 1. Secure Storage Problems

**Issue**: Credentials not persisting
```
Problem: Biometric login stops working after app restart
Solutions:
1. Check keychain/keystore access
2. Verify encryption key persistence
3. Check for storage permission issues
4. Monitor for storage corruption
```

**Code Example - Robust Secure Storage**:
```dart
class RobustSecureStorage {
  final _storage = FlutterSecureStorage();
  final _backupStorage = SharedPreferences.getInstance();

  Future<void> secureWrite(String key, String value) async {
    try {
      // Primary write
      await _storage.write(key: key, value: value);
      
      // Backup write (encrypted)
      final encrypted = await _encryptValue(value);
      await (await _backupStorage).setString(key, encrypted);
    } catch (e) {
      print('Storage write failed: $e');
      throw 'Failed to store secure data';
    }
  }

  Future<String?> secureRead(String key) async {
    try {
      // Try primary storage
      final value = await _storage.read(key: key);
      if (value != null) return value;

      // Try backup
      final encrypted = (await _backupStorage).getString(key);
      if (encrypted != null) {
        return await _decryptValue(encrypted);
      }
      
      return null;
    } catch (e) {
      print('Storage read failed: $e');
      return null;
    }
  }
}
```

## Performance Optimization

### 1. Batch Operations

**Code Example - Optimized Batch Deletion**:
```dart
Future<void> optimizedBatchDeletion(String uid) async {
  const batchSize = 500; // Firestore limit
  final batches = <WriteBatch>[];
  var currentBatch = FirebaseFirestore.instance.batch();
  var operationCount = 0;

  // Get all user data references
  final userDataRefs = await getUserDataReferences(uid);

  for (final ref in userDataRefs) {
    currentBatch.delete(ref);
    operationCount++;

    if (operationCount >= batchSize) {
      batches.add(currentBatch);
      currentBatch = FirebaseFirestore.instance.batch();
      operationCount = 0;
    }
  }

  if (operationCount > 0) {
    batches.add(currentBatch);
  }

  // Execute batches in parallel with error handling
  await Future.wait(
    batches.map((batch) => batch.commit().catchError((e) {
      print('Batch operation failed: $e');
      throw e;
    })),
  );
}
```

## Security Audit Checklist

### 1. Regular Checks
```
Daily:
- Monitor failed login attempts
- Check for unusual activity patterns
- Verify token refresh system

Weekly:
- Review security logs
- Check rate limiting effectiveness
- Monitor biometric usage statistics

Monthly:
- Full security audit
- Update security dependencies
- Review and update security documentation
```

### 2. Error Monitoring

**Code Example - Security Event Logging**:
```dart
class SecurityLogger {
  static Future<void> logSecurityEvent({
    required String event,
    required String severity,
    Map<String, dynamic>? details,
  }) async {
    final timestamp = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance
        .collection('security_logs')
        .add({
          'event': event,
          'severity': severity,
          'timestamp': timestamp,
          'userId': user?.uid,
          'deviceInfo': await _getDeviceInfo(),
          'details': details,
        });

    if (severity == 'high') {
      // Send immediate notification to security team
      await _notifySecurityTeam(event, details);
    }
  }
}
```

## Contact Support

For urgent security issues:
- Email: security@flyerchat.com
- Emergency hotline: +1-XXX-XXX-XXXX
- In-app support ticket (Security category) 