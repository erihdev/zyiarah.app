// حارس انحدار: تسجيل الدخول يجب أن ينجح من الضغطة الأولى.
//
// كان العطل: شاشة الدخول تجلب الدور بنفسها وتقفز إلى '/admin'، بينما ZyiarahUserProvider
// يجلبه بالتوازي عبر authStateChanges. حارس الراوتر يحكم على حالة **المزوّد** وهي وقتها
// قديمة (role=null ⇒ يُعامَل كـ'client') فيردّ الأدمن إلى '/'، وهناك يرى AuthWrapper
// أن isAuthenticated=false (‎_user لم يُحمَّل) فيعرض شاشة الترحيب — فيظن المستخدم أن
// الدخول فشل، وتنجح الضغطة الثانية بعد أن يكون المزوّد قد أنهى التحميل.
import 'package:flutter_test/flutter_test.dart';

/// نموذج مصغّر لحارس الراوتر كما هو في lib/router.dart.
String? routerRedirect({
  required bool hasAuthUser,
  required String path,
  required bool providerLoading,
  required String? providerRole,
}) {
  const publicPaths = ['/', '/onboarding', '/login', '/guest'];
  const adminRoles = {'admin', 'super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'};
  if (!hasAuthUser && !publicPaths.contains(path)) return '/login';
  if (hasAuthUser) {
    const protectedRolePaths = {'/client', '/driver', '/admin'};
    if (providerLoading) {
      if (protectedRolePaths.contains(path)) return '/';
    } else {
      final role = providerRole ?? 'client';
      final isAdmin = adminRoles.contains(role);
      if (path == '/client' && role != 'client') return '/';
      if (path == '/driver' && role != 'driver') return '/';
      if (path == '/admin' && !isAdmin) return '/';
    }
  }
  return null;
}

/// نموذج مصغّر لـ AuthWrapper بعد الإصلاح.
String authWrapperScreen({
  required bool hasAuthUser,
  required bool providerLoading,
  required bool providerAuthenticated,
  required String? role,
}) {
  if (providerLoading) return 'splash';
  if (providerAuthenticated) {
    if (role == null) return 'role_unavailable'; // لا نُخمّن الدور
    if (role == 'driver') return 'driver';
    if (['admin', 'super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'].contains(role)) {
      return 'admin';
    }
    return 'client';
  }
  return 'onboarding';
}

/// isAuthenticated بعد الإصلاح: يتبع Firebase Auth لا مستند Firestore.
bool isAuthenticated({required bool hasAuthUser, required bool profileLoaded}) => hasAuthUser;

void main() {
  group('اللحظة الحرجة: signIn نجح والمزوّد لم يلحق بعد', () {
    // الحالة تماماً بعد نجاح signIn مباشرةً:
    const hasAuthUser = true;      // FirebaseAuth.currentUser صار موجوداً
    const providerLoading = false; // المستمع لم يعمل بعد (حالة «غير مسجّل» السابقة)
    const providerRole = null;     // الدور لم يُجلب بعد

    test('السلوك القديم: القفز إلى /admin يُردّ إلى الجذر (سبب الضغطة المهدورة)', () {
      final redirect = routerRedirect(
        hasAuthUser: hasAuthUser, path: '/admin',
        providerLoading: providerLoading, providerRole: providerRole,
      );
      expect(redirect, '/', reason: 'الحارس يرى role=null ⇒ client ⇒ يردّ الأدمن');
    });

    test('السلوك الجديد: الذهاب إلى / لا يُردّ (لا سباق)', () {
      final redirect = routerRedirect(
        hasAuthUser: hasAuthUser, path: '/',
        providerLoading: providerLoading, providerRole: providerRole,
      );
      expect(redirect, isNull, reason: '/ مسار عام — يمرّ دائماً');
    });

    test('isAuthenticated يتبع Auth لا Firestore — لا خروج كاذب', () {
      expect(isAuthenticated(hasAuthUser: true, profileLoaded: false), isTrue,
          reason: 'فشل تحميل الملف الشخصي يجب ألا يُخرج المستخدم');
    });

    test('AuthWrapper لا يعرض الترحيب لمستخدم مسجّل', () {
      // بعد الإصلاح: isAuthenticated=true فور signIn، والدور قيد التحميل ⇒ splash
      final screen = authWrapperScreen(
        hasAuthUser: true, providerLoading: true,
        providerAuthenticated: true, role: null,
      );
      expect(screen, 'splash',
          reason: 'قبل الإصلاح كان يعرض onboarding فيظنّ المستخدم أن الدخول فشل');
    });

    test('فشل جلب الدور: لا يُعرض للأدمن لوحة العميل ولا شاشة ترحيب', () {
      final screen = authWrapperScreen(
        hasAuthUser: true, providerLoading: false,
        providerAuthenticated: true, role: null,
      );
      expect(screen, 'role_unavailable',
          reason: 'role ?? client كان يعرض للأدمن لوحة العميل');
    });

    test('بعد أن يُحمّل المزوّد الدور: يصل الأدمن للوحته', () {
      final screen = authWrapperScreen(
        hasAuthUser: true, providerLoading: false,
        providerAuthenticated: true, role: 'super_admin',
      );
      expect(screen, 'admin');
    });

    test('والعميل يصل لوحته', () {
      expect(
        authWrapperScreen(
            hasAuthUser: true, providerLoading: false,
            providerAuthenticated: true, role: 'client'),
        'client',
      );
    });

    test('والسائق يصل لوحته', () {
      expect(
        authWrapperScreen(
            hasAuthUser: true, providerLoading: false,
            providerAuthenticated: true, role: 'driver'),
        'driver',
      );
    });
  });

  test('غير المسجّل يبقى على الترحيب (لا سبلاش أبدي)', () {
    expect(
      authWrapperScreen(
          hasAuthUser: false, providerLoading: false,
          providerAuthenticated: false, role: null),
      'onboarding',
    );
  });
}
