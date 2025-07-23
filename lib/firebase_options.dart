import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAc4ZJxyvZyqSW8w2OGfWe41yndAy-W22I',
    appId: '1:1040794750357:web:fa6e751335e4b436fb7a9c',
    messagingSenderId: '1040794750357',
    projectId: 'chatterbox-app-12345',
    authDomain: 'chatterbox-app-12345.firebaseapp.com',
    storageBucket: 'chatterbox-app-12345.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCsxP6tZ1Ho9Fbrsm2oSXtxp6b-5vuaVns',
    appId: '1:1040794750357:android:061e0f82e7536a91fb7a9c',
    messagingSenderId: '1040794750357',
    projectId: 'chatterbox-app-12345',
    storageBucket: 'chatterbox-app-12345.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD94Grwmrdgcd2B26CstfVRFClV0I_jyws',
    appId: '1:1040794750357:ios:6963378e44fc0562fb7a9c',
    messagingSenderId: '1040794750357',
    projectId: 'chatterbox-app-12345',
    storageBucket: 'chatterbox-app-12345.firebasestorage.app',
    iosBundleId: 'com.flyerchat.flyerChat',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR-MACOS-API-KEY',
    appId: 'YOUR-MACOS-APP-ID',
    messagingSenderId: 'YOUR-SENDER-ID',
    projectId: 'YOUR-PROJECT-ID',
    storageBucket: 'YOUR-STORAGE-BUCKET',
    iosClientId: 'YOUR-MACOS-CLIENT-ID',
    iosBundleId: 'YOUR-MACOS-BUNDLE-ID',
  );
}