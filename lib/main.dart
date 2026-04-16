import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Required for flutter_foreground_task v8 — must be before runApp
  FlutterForegroundTask.initCommunicationPort();

  // Initialize Firebase with explicit options from google-services.json
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase not configured yet — app still works, group rides disabled
  }

  // Allow both portrait and landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF080808),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const MotoPulseApp());
}

class MotoPulseApp extends StatelessWidget {
  const MotoPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MotoPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE8003D),
          secondary: Color(0xFFFF6B00),
          surface: Color(0xFF111111),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF080808),
        fontFamily: 'Roboto',
        useMaterial3: true,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w200,
              letterSpacing: -1),
          displayMedium: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w200,
              letterSpacing: -0.5),
          headlineLarge: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w300),
          titleLarge: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3),
          bodyMedium: TextStyle(color: Colors.white54),
          labelSmall: TextStyle(
              color: Colors.white38,
              letterSpacing: 2,
              fontWeight: FontWeight.w500),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF111111),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1A1A1A),
          contentTextStyle: TextStyle(color: Colors.white70),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      // WithForegroundTask ensures proper lifecycle handling for background GPS
      home: WithForegroundTask(child: const SplashScreen()),
    );
  }
}
