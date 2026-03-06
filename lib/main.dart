import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:zyiarah/firebase_options.dart';
import 'package:zyiarah/services/notification_service.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ZyiarahNotificationService().initialize();
  runApp(const ZyiarahApp());
}

class ZyiarahApp extends StatelessWidget {
  const ZyiarahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'زيارة - Zyiarah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1E3A8A),
        textTheme: GoogleFonts.tajawalTextTheme(),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A8A)),
        useMaterial3: true,
      ),
      // تعيين شاشة الترحيب كشاشة البداية
      home: const OnboardingScreen(),
    );
  }
}
