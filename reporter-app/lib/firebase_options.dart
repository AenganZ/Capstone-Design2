// Firebase 설정 파일
// missing-person-alert-94fcd 프로젝트용

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

  // missing-person-alert-94fcd 프로젝트 설정
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBh5ZrIqW8f9qJ5L4kGtYvN2CxMpDsE8Fg', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    appId: '1:123456789:web:abcdef1234567890', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    messagingSenderId: '123456789', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    projectId: 'missing-person-alert-94fcd', // 확정된 프로젝트 ID
    authDomain: 'missing-person-alert-94fcd.firebaseapp.com',
    storageBucket: 'missing-person-alert-94fcd.appspot.com',
    measurementId: 'G-XXXXXXXXXX', // Firebase Console에서 확인 필요
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBh5ZrIqW8f9qJ5L4kGtYvN2CxMpDsE8Fg', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    appId: '1:123456789:android:abcdef1234567890', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    messagingSenderId: '123456789', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    projectId: 'missing-person-alert-94fcd', // 확정된 프로젝트 ID
    storageBucket: 'missing-person-alert-94fcd.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBh5ZrIqW8f9qJ5L4kGtYvN2CxMpDsE8Fg', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    appId: '1:123456789:ios:abcdef1234567890', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    messagingSenderId: '123456789', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    projectId: 'missing-person-alert-94fcd', // 확정된 프로젝트 ID
    storageBucket: 'missing-person-alert-94fcd.appspot.com',
    iosBundleId: 'com.aenganz.reporter',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBh5ZrIqW8f9qJ5L4kGtYvN2CxMpDsE8Fg', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    appId: '1:123456789:macos:abcdef1234567890', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    messagingSenderId: '123456789', // 임시값 - Firebase Console에서 정확한 값으로 교체 필요
    projectId: 'missing-person-alert-94fcd', // 확정된 프로젝트 ID
    storageBucket: 'missing-person-alert-94fcd.appspot.com',
    iosBundleId: 'com.aenganz.reporter',
  );
}