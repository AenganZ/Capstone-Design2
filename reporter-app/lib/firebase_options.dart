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
    apiKey: 'AIzaSyAfWT0ETs0gwl1sqkWLX3Y4OvreVkkJblY',
    appId: '1:527805312261:web:a02b1eec78485eda0d9b6c',
    messagingSenderId: '527805312261',
    projectId: 'missing-person-alert-94fcd',
    authDomain: 'missing-person-alert-94fcd.firebaseapp.com',
    storageBucket: 'missing-person-alert-94fcd.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAfWT0ETs0gwl1sqkWLX3Y4OvreVkkJblY',
    appId: '1:527805312261:android:a02b1eec78485eda0d9b6c',
    messagingSenderId: '527805312261',
    projectId: 'missing-person-alert-94fcd',
    storageBucket: 'missing-person-alert-94fcd.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAfWT0ETs0gwl1sqkWLX3Y4OvreVkkJblY',
    appId: '1:527805312261:ios:a02b1eec78485eda0d9b6c',
    messagingSenderId: '527805312261',
    projectId: 'missing-person-alert-94fcd',
    storageBucket: 'missing-person-alert-94fcd.firebasestorage.app',
    iosBundleId: 'com.aenganz.reporter',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAfWT0ETs0gwl1sqkWLX3Y4OvreVkkJblY',
    appId: '1:527805312261:macos:a02b1eec78485eda0d9b6c',
    messagingSenderId: '527805312261',
    projectId: 'missing-person-alert-94fcd',
    storageBucket: 'missing-person-alert-94fcd.firebasestorage.app',
    iosBundleId: 'com.aenganz.reporter',
  );
}