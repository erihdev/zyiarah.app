import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/admin/admin_services_screen.dart';
import 'package:zyiarah/screens/admin/admin_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_more_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_screen.dart';
import 'package:zyiarah/screens/onboarding_screen.dart';
import 'package:lottie/lottie.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String _role = 'none'; 
  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();
    _fetchAdminRole();
  }

  Future<void> _fetchAdminRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.email != null) {
        final doc = await FirebaseFirestore.instance.collection('admins').doc(user.email).get();
        if (doc.exists && mounted) {
          setState(() {
            _role = doc.data()?['role'] ?? 'none';
            _isLoadingRole = false;
          });
        } else if (mounted) {
          // Explicitly set to 'none' if admin record is missing
          setState(() {
            _role = 'none';
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
      {'page': const AdminServicesScreen(), 'label': 'الخدمات', 'icon': Icons.design_services, 'roles': ['super_admin', 'orders_manager']},
      {'page': const AdminOrdersScreen(), 'label': 'الطلبات', 'icon': Icons.list_alt, 'roles': ['super_admin', 'orders_manager']},
      {'page': const AdminStoreScreen(), 'label': 'المتجر', 'icon': Icons.storefront, 'roles': ['super_admin', 'accountant_admin']},
      {'page': AdminMoreScreen(role: _role), 'label': 'المزيد', 'icon': Icons.grid_view_rounded, 'roles': ['super_admin', 'orders_manager', 'accountant_admin']},
    ];

    return allTabs.where((tab) => (tab['roles'] as List).contains(_role)).toList();
  }

  void _logout() async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("تسجيل الخروج"),
          content: const Text("هل تريد بالتأكيد تسجيل الخروج من لوحة الإدارة؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Color(0xFF1E293B)),
              const SizedBox(height: 20),
              const Text("جاري التحقق من الصلاحيات...", style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
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
                const Text(
                  "يرجى التواصل مع الإدارة العليا لتفعيل حسابك كمدير في النظام.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text("تسجيل الخروج"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("لوحة التحكم (الإدارة)", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Slate 800
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: "تسجيل الخروج",
          )
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: filteredTabs.map((t) => t['page'] as Widget).toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF2563EB), // Blue 600
        unselectedItemColor: Colors.grey,
        items: filteredTabs.map((t) => BottomNavigationBarItem(icon: Icon(t['icon'] as IconData), label: t['label'] as String)).toList(),
      ),
    );
  }
}
