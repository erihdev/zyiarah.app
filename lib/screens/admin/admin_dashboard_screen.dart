import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/screens/admin/admin_services_screen.dart';
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_more_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_screen.dart';
import 'package:zyiarah/screens/admin/admin_insights_screen.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:zyiarah/screens/splash_screen.dart';
import 'package:lottie/lottie.dart';
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
        String role = await firebaseService.getUserRole(user.uid);
        
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

  List<Map<String, dynamic>> _getFilteredTabs() {
    final allTabs = [
      {'page': const AdminInsightsScreen(), 'label': ZyiarahStrings.dashboardTitle, 'icon': Icons.insights_rounded, 'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin']},
      {'page': const AdminServicesScreen(), 'label': ZyiarahStrings.servicesHeader, 'icon': Icons.design_services, 'roles': ['super_admin', 'orders_manager']},
      {'page': const AdminOrdersScreen(), 'label': ZyiarahStrings.ordersManagement, 'icon': Icons.list_alt, 'roles': ['super_admin', 'orders_manager']},
      {'page': const AdminStoreScreen(), 'label': ZyiarahStrings.storeManagement, 'icon': Icons.storefront, 'roles': ['super_admin', 'accountant_admin']},
      {'page': AdminMoreScreen(role: _role), 'label': ZyiarahStrings.systemSettings, 'icon': Icons.grid_view_rounded, 'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin']},
    ];

    return allTabs.where((tab) => (tab['roles'] as List).contains(_role)).toList();
  }

  void _logout() async {
    bool confirm = await showDialog(
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
    );

    if (confirm == true && mounted) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
          (Route<dynamic> route) => false,
        );
      }
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
                Lottie.network(
                  'https://lottie.host/85cc1144-6729-4d64-88aa-3e753456c636/Hw4h8Pndr5.json', // Error anim
                  width: 250,
                  height: 250,
                ),
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
                    backgroundColor: const Color(0xFF5D1B5E),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ZyiarahStrings.adminPanel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
              tooltip: "تسجيل الخروج",
            )
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: filteredTabs.map((t) => t['page'] as Widget).toList(),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            HapticFeedback.lightImpact();
            setState(() => _currentIndex = index);
          },
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          elevation: 8,
          indicatorColor: const Color(0xFF5D1B5E).withValues(alpha: 0.12),
          destinations: filteredTabs.map((t) => NavigationDestination(
            icon: Icon(t['icon'] as IconData),
            selectedIcon: Icon(t['icon'] as IconData, color: const Color(0xFF5D1B5E)),
            label: t['label'] as String,
          )).toList(),
        ),
      ),
    );
  }
}
