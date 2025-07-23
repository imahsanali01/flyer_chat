# Security Flow Diagrams

## Authentication Flows

### 1. Password Reset Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant AS as AuthService
    participant F as Firebase
    participant E as Email

    U->>A: Click "Forgot Password"
    A->>AS: sendPasswordResetEmail(email)
    AS->>F: Send Reset Request
    F->>E: Send Reset Email
    E->>U: Reset Link
    U->>A: Click Reset Link
    A->>AS: verifyPasswordResetCode(code)
    AS->>F: Verify Code
    F-->>AS: Code Valid
    U->>A: Enter New Password
    A->>AS: confirmPasswordReset(code, newPassword)
    AS->>F: Update Password
    F-->>AS: Success
    AS-->>A: Update UI
    A-->>U: Show Success
```

### 2. Biometric Authentication Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant AS as AuthService
    participant LA as LocalAuth
    participant SS as SecureStorage
    participant F as Firebase

    U->>A: Enable Biometric
    A->>LA: Check Availability
    LA-->>A: Available
    A->>LA: Request Authentication
    LA->>U: Show Biometric Prompt
    U->>LA: Provide Biometric
    LA-->>A: Authentication Success
    A->>SS: Store Credentials
    A->>F: Update User Settings
    F-->>A: Success
    A-->>U: Show Success

    Note over U,F: Later Login...

    U->>A: Login with Biometric
    A->>LA: Request Authentication
    LA->>U: Show Biometric Prompt
    U->>LA: Provide Biometric
    LA-->>A: Authentication Success
    A->>SS: Get Stored Credentials
    A->>F: Login with Credentials
    F-->>A: Success
    A-->>U: Show Home Screen
```

### 3. Account Deletion Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant AS as AuthService
    participant F as Firebase
    participant SS as SecureStorage

    U->>A: Request Account Deletion
    A->>U: Show Warning Dialog
    U->>A: Confirm & Enter Password
    A->>AS: deleteAccount(password)
    AS->>F: Reauthenticate
    F-->>AS: Auth Success
    AS->>F: Start Batch Operation
    AS->>F: Delete Messages
    AS->>F: Update Chat Rooms
    AS->>F: Delete User Document
    F-->>AS: Batch Success
    AS->>F: Delete Auth Account
    F-->>AS: Account Deleted
    AS->>SS: Clear Local Data
    AS-->>A: Navigate to Login
    A-->>U: Show Success
```

## Error Handling Flows

### 1. Rate Limiting Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant AS as AuthService
    participant F as Firebase

    U->>A: Multiple Login Attempts
    A->>AS: checkRateLimit()
    AS->>AS: Check Last Attempt
    alt Under Limit
        AS-->>A: Allow Attempt
        A->>F: Try Login
    else Over Limit
        AS-->>A: Block Attempt
        A-->>U: Show Cooldown
    end
```

### 2. Session Recovery Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant AS as AuthService
    participant F as Firebase
    participant SS as SecureStorage

    U->>A: Open App
    A->>AS: Check Session
    AS->>F: Verify Token
    alt Token Valid
        F-->>AS: Success
        AS-->>A: Resume Session
    else Token Expired
        F-->>AS: Error
        AS->>SS: Get Refresh Token
        AS->>F: Refresh Session
        F-->>AS: New Token
        AS-->>A: Update Session
    end
    A-->>U: Show Content
```

## Data Protection Flows

### 1. Secure Storage Flow
```mermaid
sequenceDiagram
    participant A as App
    participant SS as SecureStorage
    participant KS as KeyStore/Keychain
    participant ES as EncryptedStorage

    A->>SS: Store Sensitive Data
    SS->>KS: Get Encryption Key
    KS-->>SS: Key
    SS->>SS: Encrypt Data
    SS->>ES: Store Encrypted Data
    ES-->>SS: Success
    SS-->>A: Complete

    Note over A,ES: Later Retrieval...

    A->>SS: Get Sensitive Data
    SS->>ES: Get Encrypted Data
    ES-->>SS: Data
    SS->>KS: Get Decryption Key
    KS-->>SS: Key
    SS->>SS: Decrypt Data
    SS-->>A: Return Data
``` 