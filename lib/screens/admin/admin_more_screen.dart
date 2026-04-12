import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:zyiarah/screens/admin/admin_settings_screen.dart';
import 'package:zyiarah/screens/admin/admin_users_screen.dart';
import 'package:zyiarah/screens/admin/admin_drivers_screen.dart';
import 'package:zyiarah/screens/admin/admin_support_screen.dart';
import 'package:zyiarah/screens/admin/admin_marketing_screen.dart';
import 'package:zyiarah/screens/admin/admin_contracts_screen.dart';
import 'package:zyiarah/screens/admin/admin_maintenance_screen.dart';
import 'package:zyiarah/screens/admin/admin_managers_screen.dart';
import 'package:zyiarah/screens/admin/admin_deletions_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_hourly_zones_screen.dart';
import 'package:zyiarah/screens/admin/admin_subscriptions_screen.dart';
import 'package:zyiarah/screens/admin/admin_audit_logs_screen.dart';
import 'package:zyiarah/screens/admin/admin_analytics_screen.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';

class AdminMoreScreen extends StatelessWidget {
  final String role;
  const AdminMoreScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> items = [
      {
        'title': 'لوحة الإحصائيات والأرباح',
        'icon': Icons.insert_chart_outlined,
        'color': Colors.teal,
        'page': const AdminAnalyticsScreen(),
        'roles': ['super_admin', 'accountant_admin', 'orders_manager']
      },
      {
        'title': 'المستخدمين',
        'icon': Icons.people_outline,
        'color': Colors.blue,
        'page': const AdminUsersScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'السائقين والعمال',
        'icon': Icons.engineering_outlined,
        'color': Colors.orange,
        'page': const AdminDriversScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'الدعم الفني',
        'icon': Icons.support_agent,
        'color': Colors.purple,
        'page': const AdminSupportScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'سجل العمليات الإدارية',
        'icon': Icons.history_edu_rounded,
        'color': const Color(0xFF1E293B),
        'page': const AdminAuditLogsScreen(),
        'roles': ['super_admin']
      },
      {
        'title': 'الإشعارات والتسويق',
        'icon': Icons.campaign_outlined,
        'color': Colors.redAccent,
        'page': const AdminMarketingScreen(),
        'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin']
      },
      {
        'title': 'طلبات الصيانة',
        'icon': Icons.build_circle_outlined,
        'color': Colors.brown,
        'page': const AdminMaintenanceScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'العقود الإلكترونية',
        'icon': Icons.history_edu,
        'color': Colors.green,
        'page': const AdminContractsScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'طلبات المتجر',
        'icon': Icons.shopping_cart_checkout,
        'color': Colors.teal,
        'page': const AdminStoreOrdersScreen(),
        'roles': ['super_admin', 'accountant_admin']
      },
      {
        'title': ZyiarahStrings.unifiedStaffManagement,
        'icon': Icons.admin_panel_settings_rounded,
        'color': Colors.indigo,
        'page': const AdminManagersScreen(),
        'roles': ['super_admin']
      },
      {
        'title': 'طلبات الحذف',
        'icon': Icons.delete_sweep_outlined,
        'color': Colors.red,
        'page': const AdminDeletionsScreen(),
        'roles': ['super_admin']
      },
      {
        'title': 'باقات الاشتراك',
        'icon': Icons.card_giftcard_outlined,
        'color': Colors.deepPurple,
        'page': const AdminSubscriptionsScreen(),
        'roles': ['super_admin', 'accountant_admin']
      },
      {
        'title': 'المناطق والأسعار',
        'icon': Icons.map_outlined,
        'color': Colors.blueAccent,
        'page': const AdminHourlyZonesScreen(),
        'roles': ['super_admin', 'orders_manager']
      },
      {
        'title': 'إعدادات النظام',
        'icon': Icons.settings_suggest_outlined,
        'color': Colors.grey[800]!,
        'page': const AdminSettingsScreen(),
        'roles': ['super_admin']
      },
    ];

    final filteredItems = items.where((i) => (i['roles'] as List).contains(role)).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: filteredItems.length,
          itemBuilder: (context, index) {
            final item = filteredItems[index];
            return _buildGridItem(
              context,
              item['title'],
              item['icon'],
              item['color'],
              item['page'],
            );
          },
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, String title, IconData icon, Color color, Widget destination) {
    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => destination));
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
