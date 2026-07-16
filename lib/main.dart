import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:zyiarah/screens/splash_screen.dart';
import 'package:zyiarah/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:zyiarah/services/geofence_service.dart';
import 'package:zyiarah/services/tabby_service.dart';
import 'package:zyiarah/router.dart';

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

  // (A1) تفعيل جمع تقارير الانهيار صراحةً — بدونه لا تصل انهيارات TestFlight/الإنتاج إلى Firebase.
  // Crashlytics بلا تنفيذ على الويب: استدعاؤه هناك يرمي Assertion قبل رسم الواجهة فتظهر
  // شاشة بيضاء. نحصره في المنصّات التي تدعمه (iOS/Android) — سلوك الإنتاج بلا تغيير.
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    // System-wide crash reporting (silent — no user-facing snackbar)
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // (A2) انتظار اكتمال التهيئة قبل تشغيل الواجهة لمنع سباق نسخة الإصدار (Release race)
  // كل تهيئة محميّة داخلياً بـ try/catch فلن تُسقط الإقلاع.
  await ZyiarahNotificationService().initialize();
  ZyiarahDeepLinkService().initialize(navigatorKey);
  await GeofenceService.initialize(); // تحميل مناطق التغطية من Firestore
  await TabbyService.initialize(); // تهيئة Tabby BNPL

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
      // تعريب كامل: منتقيات التاريخ/الوقت والحوارات تظهر بالعربية RTL بدل الإنجليزية.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<ZyiarahUserProvider>(context);

    // isAuthenticated صار يتبع Firebase Auth مباشرةً، فلحظة ما بعد signIn (قبل أن
    // يُحمّل المزوّد الملف الشخصي) تُغطَّى بـ isLoading — لا تُعرض شاشة الترحيب خطأً.
    if (userProvider.isLoading) {
      return const ZyiarahSplashScreen();
    }

    if (userProvider.isAuthenticated) {
      final String? role = userProvider.role;

      // الجلسة قائمة لكن الدور لم يُحمَّل (تعثّر شبكي). **لا نُخمّن الدور**: كان
      // `role ?? 'client'` يعرض للأدمن/السائق لوحة العميل عند أي فشل جلب. نعرض
      // إعادة محاولة صريحة بدل وجهة خاطئة أو شاشة ترحيب كاذبة.
      if (role == null) {
        return _RoleUnavailableScreen(provider: userProvider);
      }

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

/// الجلسة قائمة لكن تعذّر تحميل الدور (تعثّر شبكي/صلاحيات).
///
/// تحلّ محلّ سلوكين خاطئين كانا قائمين: عرض شاشة الترحيب (فيظنّ المستخدم أنه خرج)،
/// أو افتراض 'client' فيرى الأدمن لوحة العميل. هنا: رسالة صريحة + إعادة محاولة،
/// والجلسة لا تُمسّ.
class _RoleUnavailableScreen extends StatelessWidget {
  final ZyiarahUserProvider provider;
  const _RoleUnavailableScreen({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 56, color: Color(0xFF94A3B8)),
                const SizedBox(height: 18),
                const Text(
                  'تعذّر تحميل بياناتك',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'تحقّق من اتصالك بالإنترنت وأعد المحاولة.\nلم يتم تسجيل خروجك — حسابك كما هو.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.6),
                ),
                const SizedBox(height: 26),
                ElevatedButton.icon(
                  onPressed: () {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) provider.refreshUser(uid);
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D1B5E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                TextButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('تسجيل الخروج', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
