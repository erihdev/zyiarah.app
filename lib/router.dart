import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:zyiarah/providers/user_provider.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:zyiarah/screens/login_screen.dart';
import 'package:zyiarah/screens/signup_screen.dart';
import 'package:zyiarah/screens/guest_explore_screen.dart';
import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:zyiarah/screens/driver_dashboard.dart';
import 'package:zyiarah/screens/admin/admin_dashboard_screen.dart';
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/screens/orders_list_screen.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/profile_screen.dart';
import 'package:zyiarah/main.dart';

/// انتقال شرائح التبويب السفلي — كان معرَّفاً كـ PageRouteBuilder داخل client_dashboard
/// حين كانت الشاشات تُدفع عبر Navigator. نُبقيه حرفياً كما هو بعد نقلها إلى الراوتر.
CustomTransitionPage<T> _slideFadePage<T>(Widget child, GoRouterState state) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// يُعيد تقييم redirect عند كل تغيير في حالة Auth (دخول / خروج)
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _adminRoles = {'admin', 'super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'};

final GoRouter appRouter = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/',
  refreshListenable: _GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final path = state.uri.path;
    const publicPaths = ['/', '/onboarding', '/login', '/signup', '/guest'];

    // مستخدم غير مسجّل يحاول الوصول لصفحة محمية
    if (user == null && !publicPaths.contains(path)) {
      return '/login';
    }

    // مستخدم مسجّل: تحقق من الدور قبل السماح بالوصول المباشر للمسارات الحساسة
    if (user != null) {
      ZyiarahUserProvider? userProvider;
      try {
        userProvider = Provider.of<ZyiarahUserProvider>(context, listen: false);
      } catch (_) {}
      const protectedRolePaths = {'/client', '/driver', '/admin'};
      if (userProvider == null || userProvider.isLoading) {
        // أثناء تحميل الدور: لا تسمح بالوصول المباشر لمسار دور حسّاس (كان يفشل
        // مفتوحاً فيَعرض شاشة الدور الخطأ لرابط عميق أثناء الإقلاع). نحوّل إلى '/'
        // حيث يعرض AuthWrapper سبلاش ثم يوجّه تلقائياً للوجهة الصحيحة بعد معرفة الدور.
        if (protectedRolePaths.contains(path)) return '/';
      } else {
        final role = userProvider.role ?? 'client';
        final isAdmin = _adminRoles.contains(role);
        if (path == '/client' && role != 'client') return '/';
        if (path == '/driver' && role != 'driver' && role != 'worker') return '/';
        if (path == '/admin' && !isAdmin) return '/';
      }
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AuthWrapper(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const ZyiarahLoginScreen(),
    ),
    // شاشة التسجيل تستدعي context.go('/') عند النجاح، فلا يجوز دفعها عبر Navigator:
    // كان الراوتر يتغيّر تحتها وهي تبقى فوقه، فيظنّ المستخدم أن التسجيل فشل ويعيد
    // المحاولة على حسابه الذي أُنشئ للتوّ فيُقابَل بـ«البريد مستخدم بالفعل».
    GoRoute(
      path: '/signup',
      builder: (context, state) => const ZyiarahSignupScreen(),
    ),
    GoRoute(
      path: '/guest',
      builder: (context, state) => const GuestExploreScreen(),
    ),
    GoRoute(
      path: '/client',
      builder: (context, state) => const ClientDashboard(),
    ),
    GoRoute(
      path: '/driver',
      builder: (context, state) => const DriverDashboard(),
    ),
    GoRoute(
      path: '/admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    // شاشات التبويب السفلي للعميل. كانت تُدفع عبر Navigator من client_dashboard بينما
    // تستدعي هي نفسها context.go(...) بداخلها — فاضطُرّ كلٌّ منها لحيلة محلّية تلتفّ على
    // ذلك (popUntil في الملف الشخصي، وفحص canPop في قائمة الطلبات). تسجيلها مسارات
    // حقيقية يزيل سبب الحيلتين بدل ترقيعهما، ويجعل مصدر التنقّل واحداً.
    GoRoute(
      path: '/orders',
      pageBuilder: (context, state) => _slideFadePage(const OrdersListScreen(), state),
    ),
    GoRoute(
      path: '/store',
      pageBuilder: (context, state) => _slideFadePage(const ZyiarahStoreScreen(), state),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => _slideFadePage(const ZyiarahProfileScreen(), state),
    ),
    GoRoute(
      path: '/track/:orderId',
      builder: (context, state) {
        final orderId = state.pathParameters['orderId']!;
        return OrderTrackingScreen(orderId: orderId);
      },
    ),
  ],
);
