import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_more_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_hub_screen.dart';
import 'package:zyiarah/screens/admin/admin_insights_screen.dart';
import 'package:zyiarah/screens/admin/admin_search_screen.dart';
import 'package:zyiarah/screens/splash_screen.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';
import 'package:zyiarah/services/firebase_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _role = 'none'; 
  bool _isLoadingRole = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchAdminRole();
  }

  Future<void> _fetchAdminRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Use the centralized service to fetch the role (UID-based)
        final ZyiarahFirebaseService firebaseService = ZyiarahFirebaseService();
        // getUserRole يرجع null عند خطأ قراءةٍ صلب — نُبقي سلوك هذه الشاشة كما كان.
        String role = await firebaseService.getUserRole(user.uid) ?? 'client';
        
        if (mounted) {
          setState(() {
            // Check if the returned role is one of the admin roles
            if (['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin', 'admin'].contains(role)) {
              _role = role == 'admin' ? 'super_admin' : role; // Normalize generic admin to super
            } else {
              _role = 'none';
            }
            _isLoadingRole = false;
          });
        }
      } else if (mounted) {
        setState(() => _isLoadingRole = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  /// التبويباتُ **بانياتٌ لا ودجاتٌ مبنيّة**: كلُّ تبويبٍ يُبنى أوّلَ مرّةٍ
  /// يُزارُ فيها لا عند فتحِ اللوحة. كانت الخمسةُ تُبنى معاً داخلَ
  /// `IndexedStack`، فيَفتحُ كلٌّ منها مستمِعاتِه واستعلاماتِه (الإحصاءاتُ
  /// وحدَها خمسةُ استعلامات) لحظةَ الدخولِ وإن لم يُفتَحْ إلّا الأوّل.
  ///
  /// وأُسقِطَ تبويبُ «خدماتنا» (`AdminServicesScreen`): ترويستُه نفسُها تقولُ
  /// إنّه «للعرض فقط» — مجموعةُ `services` لا يَقرؤها تطبيقُ العميلةِ إطلاقاً،
  /// وكلُّ ما يُضبَطُ فعلاً (الأسعارُ والتفعيلُ) في «المناطق والأسعار». تبويبٌ
  /// كاملٌ في الشريطِ السفليِّ لقائمةٍ لا أثرَ لها.
  List<Map<String, dynamic>> _getFilteredTabs() {
    final allTabs = <Map<String, dynamic>>[
      // نمرّر الدور كـ AdminMoreScreen: قواعد Firestore تمنع accountant/marketing من
      // قراءة store_orders، فتحتاج الشاشة للدور كي تتخطى ذلك الاستعلام بدل رفضٍ حتمي.
      {'build': () => AdminInsightsScreen(role: _role), 'label': ZyiarahStrings.dashboardTitle, 'icon': Icons.insights_rounded, 'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin']},
      {'build': () => const AdminOrdersScreen(), 'label': ZyiarahStrings.ordersManagement, 'icon': Icons.list_alt, 'roles': ['super_admin', 'orders_manager']},
      // المتجر: المنتجاتُ وطلباتُ المتجرِ معاً، وكلُّ شريحةٍ بأدوارِها السابقةِ
      // نفسِها (انظر AdminStoreHubScreen) — marketing_admin هو من تُجيز له القواعد
      // كتابة المنتجات، وaccountant_admin للاطلاع، ومدير الطلبات لطلبات المتجر.
      {'build': () => AdminStoreHubScreen(role: _role), 'label': ZyiarahStrings.storeManagement, 'icon': Icons.storefront, 'roles': AdminStoreHubScreen.tabRoles},
      {'build': () => AdminMoreScreen(role: _role), 'label': ZyiarahStrings.systemSettings, 'icon': Icons.grid_view_rounded, 'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin']},
    ];

    return allTabs.where((tab) => (tab['roles'] as List).contains(_role)).toList();
  }

  /// تبويباتٌ زِيرَت — تُبنى مرّةً وتُحفَظُ حالتُها في `IndexedStack`.
  final Set<int> _visitedTabs = {0};

  void _logout() async {
    // <bool> + ?? false: النقر خارج الحوار (barrier) يُرجع null، وبدونهما كان
    // الإسناد الضمني null→bool يرمي TypeError غير ملتقط (يُسجَّل fatal في Crashlytics).
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(ZyiarahStrings.logout),
          content: Text(ZyiarahStrings.isArabic ? "هل تريد بالتأكيد تسجيل الخروج من لوحة الإدارة؟" : "Are you sure you want to logout from admin panel?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(ZyiarahStrings.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(context, true), 
              child: const Text("نعم، متأكد", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (confirm && mounted) {
      // الخروج المركزي (B3): تنظيف كامل للذاكرة بدل FirebaseAuth.signOut() المباشرة
      await ZyiarahFirebaseService().signOut();
      // لا دفع يدوي: الراوتر مربوط بـ refreshListenable(authStateChanges)، فيعيد التقييم
      // فور الخروج ويعرض AuthWrapper شاشة الترحيب على '/'. الدفع اليدوي كان يضع نسخة
      // ثانية من الترحيب **فوق** الراوتر تبقى عالقة بعد الدخول التالي.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const ZyiarahSplashScreen();
    }

    if (_role == 'none') {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 120, color: Colors.grey),
                const SizedBox(height: 20),
                const Text(
                  "عذراً، لا تمتلك صلاحيات الوصول",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 10),
                Text(
                  "يرجى التواصل مع الإدارة العليا لتفعيل حسابك كمدير في النظام.\n\nالبريد الحالي المسجل:\n${FirebaseAuth.instance.currentUser?.email ?? 'لا يوجد بريد مسجل'}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: Text(ZyiarahStrings.logout),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF660033),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final filteredTabs = _getFilteredTabs();
    if (_currentIndex >= filteredTabs.length) _currentIndex = 0;
    _visitedTabs.add(_currentIndex);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ZyiarahStrings.adminPanel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AdminSearchScreen(role: _role))),
              tooltip: "بحث شامل",
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
              tooltip: "تسجيل الخروج",
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            for (var i = 0; i < filteredTabs.length; i++)
              _visitedTabs.contains(i)
                  ? (filteredTabs[i]['build'] as Widget Function())()
                  : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            HapticFeedback.lightImpact();
            setState(() {
              _currentIndex = index;
              _visitedTabs.add(index);
            });
          },
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          elevation: 8,
          indicatorColor: const Color(0xFF660033).withValues(alpha: 0.12),
          destinations: filteredTabs.map((t) => NavigationDestination(
            icon: Icon(t['icon'] as IconData),
            selectedIcon: Icon(t['icon'] as IconData, color: const Color(0xFF660033)),
            label: t['label'] as String,
          )).toList(),
        ),
      ),
    );
  }
}
