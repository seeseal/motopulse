import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not supported.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDOqKLFQxLlVmYlGjHMT2XY7Y5o0vkg1x4',
    appId: '1:670238222872:android:9fcc39e59131e8ee9ff16d',
    messagingSenderId: '670238222872',
    projectId: 'motopulse-47efe',
    storageBucket: 'motopulse-47efe.firebasestorage.app',
  );
}
