import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:zyiarah/screens/splash_screen.dart';
import 'package:zyiarah/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:zyiarah/firebase_options.dart';
import 'package:zyiarah/services/notification_service.dart';
import 'dart:ui';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:zyiarah/screens/driver_dashboard.dart';
import 'package:zyiarah/screens/admin/admin_dashboard_screen.dart';
import 'package:zyiarah/services/deep_link_service.dart';
import 'package:zyiarah/router.dart';
import 'package:zyiarah/utils/global_error_handler.dart';

import 'package:provider/provider.dart';
import 'package:zyiarah/providers/user_provider.dart';
import 'package:zyiarah/providers/config_provider.dart';
import 'package:zyiarah/providers/order_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // Enable Firestore Persistence for Enterprise Resilience
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // System-wide crash reporting setup
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    GlobalErrorHandler.handleError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    GlobalErrorHandler.handleError(error, stack);
    return true;
  };

  ZyiarahNotificationService().initialize();
  ZyiarahDeepLinkService().initialize(navigatorKey);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ZyiarahUserProvider()),
        ChangeNotifierProvider(create: (_) => ZyiarahConfigProvider()),
        ChangeNotifierProvider(create: (_) => ZyiarahOrderProvider()),
      ],
      child: const ZyiarahApp(),
    ),
  );
}

class ZyiarahApp extends StatelessWidget {
  const ZyiarahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'زيارة - Zyiarah',
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: ZyiarahTheme.light,
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<ZyiarahUserProvider>(context);

    // حالة التحميل - تظهر فقط عند التغيير الحقيقي للحالة
    if (userProvider.isLoading) {
      return const ZyiarahSplashScreen();
    }

    // إذا كان المستخدم مسجلاً دخوله
    if (userProvider.isAuthenticated) {
      final String role = userProvider.role ?? 'client';
      
      if (role == 'driver') {
        return const DriverDashboard();
      } else if (['admin', 'super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'].contains(role)) {
        return const AdminDashboardScreen();
      } else {
        return const ClientDashboard();
      }
    }

    // إذا لم يكن مسجلاً دخوله، نعرض شاشة الترحيب
    return const OnboardingScreen();
  }
}
