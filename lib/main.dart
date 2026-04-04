import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:zyiarah/firebase_options.dart';
import 'package:zyiarah/services/notification_service.dart';
import 'dart:ui';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:zyiarah/screens/driver_dashboard.dart';
import 'package:zyiarah/screens/admin/admin_dashboard_screen.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/deep_link_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // System-wide crash reporting setup
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  ZyiarahNotificationService().initialize();
  ZyiarahDeepLinkService().initialize(navigatorKey);
  runApp(const ZyiarahApp());
}

class ZyiarahApp extends StatelessWidget {
  const ZyiarahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'زيارة - Zyiarah',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        textTheme: GoogleFonts.tajawalTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: const Color(0xFF0F172A), displayColor: const Color(0xFF0F172A)),
        ),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB), surface: const Color(0xFFF8FAFC)),
        useMaterial3: true,
      ),
      // AuthWrapper للتحقق من حالة تسجيل الدخول تلقائياً
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // حالة التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // إذا كان المستخدم مسجلاً دخوله
        if (snapshot.hasData && snapshot.data != null) {
          return FutureBuilder<String>(
            future: ZyiarahFirebaseService().getUserRole(snapshot.data!.uid),
            builder: (context, roleSnapshot) {
              if (roleSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (roleSnapshot.data == 'driver') {
                return const DriverDashboard();
              } else if (roleSnapshot.data == 'admin') {
                return const AdminDashboardScreen();
              } else {
                return const ClientDashboard();
              }
            },
          );
        }

        // إذا لم يكن مسجلاً دخوله، نعرض شاشة الترحيب
        return const OnboardingScreen();
      },
    );
  }
}
