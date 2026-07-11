import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:zyiarah/providers/user_provider.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:zyiarah/screens/login_screen.dart';
import 'package:zyiarah/screens/guest_explore_screen.dart';
import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:zyiarah/screens/driver_dashboard.dart';
import 'package:zyiarah/screens/admin/admin_dashboard_screen.dart';
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/main.dart';

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
    const publicPaths = ['/', '/onboarding', '/login', '/guest'];

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
        if (path == '/driver' && role != 'driver') return '/';
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
    GoRoute(
      path: '/track/:orderId',
      builder: (context, state) {
        final orderId = state.pathParameters['orderId']!;
        return OrderTrackingScreen(orderId: orderId);
      },
    ),
  ],
);
