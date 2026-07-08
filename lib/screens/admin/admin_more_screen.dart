import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:zyiarah/screens/admin/admin_settings_screen.dart';
import 'package:zyiarah/screens/admin/admin_users_screen.dart';
import 'package:zyiarah/screens/admin/admin_drivers_screen.dart';
import 'package:zyiarah/screens/admin/admin_support_screen.dart';
import 'package:zyiarah/screens/admin/admin_marketing_screen.dart';
import 'package:zyiarah/screens/admin/admin_banners_screen.dart';
import 'package:zyiarah/screens/admin/admin_coupons_screen.dart';
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
    final sections = _buildSections();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: sections.length,
          itemBuilder: (context, i) {
            final section = sections[i];
            final items = (section['items'] as List<Map<String, dynamic>>)
                .where((item) =>
                    (item['roles'] as List).contains(role))
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return _buildSection(
              context,
              label: section['label'] as String,
              icon: section['icon'] as IconData,
              color: section['color'] as Color,
              items: items,
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _buildSections() {
    return [
      {
        'label': 'الأشخاص',
        'icon': Icons.people_alt_outlined,
        'color': Colors.blue,
        'items': [
          {
            'title': 'المستخدمين',
            'icon': Icons.person_outline,
            'color': Colors.blue,
            'page': const AdminUsersScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': 'السائقين والعمال',
            'icon': Icons.engineering_outlined,
            'color': Colors.orange,
            'page': const AdminDriversScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': ZyiarahStrings.unifiedStaffManagement,
            'icon': Icons.admin_panel_settings_outlined,
            'color': Colors.indigo,
            'page': const AdminManagersScreen(),
            'roles': ['super_admin'],
          },
          {
            'title': 'الدعم الفني',
            'icon': Icons.support_agent_outlined,
            'color': Colors.purple,
            'page': const AdminSupportScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
        ],
      },
      {
        'label': 'الطلبات والعقود',
        'icon': Icons.assignment_outlined,
        'color': Colors.teal,
        'items': [
          {
            'title': 'طلبات الصيانة',
            'icon': Icons.build_circle_outlined,
            'color': Colors.brown,
            'page': const AdminMaintenanceScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': 'العقود الإلكترونية',
            'icon': Icons.description_outlined,
            'color': Colors.green,
            'page': const AdminContractsScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': 'طلبات المتجر',
            'icon': Icons.shopping_cart_checkout_outlined,
            'color': Colors.teal,
            'page': const AdminStoreOrdersScreen(),
            // القواعد: تحديث store_orders = isOrdersManager (لا المحاسب)
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': 'طلبات الحذف',
            'icon': Icons.person_remove_outlined,
            'color': Colors.red,
            'page': const AdminDeletionsScreen(),
            'roles': ['super_admin'],
          },
        ],
      },
      {
        'label': 'التسويق والباقات',
        'icon': Icons.campaign_outlined,
        'color': Colors.redAccent,
        'items': [
          {
            'title': 'الكوبونات',
            'icon': Icons.discount_outlined,
            'color': Colors.redAccent,
            'page': const AdminCouponsScreen(),
            'roles': ['super_admin', 'marketing_admin'],
          },
          {
            'title': 'البانرات الترويجية',
            'icon': Icons.image_outlined,
            'color': Colors.orange,
            'page': const AdminBannersScreen(),
            'roles': ['super_admin', 'marketing_admin'],
          },
          {
            'title': 'باقات الاشتراك',
            'icon': Icons.card_giftcard_outlined,
            'color': Colors.deepPurple,
            'page': const AdminSubscriptionsScreen(),
            // القواعد: كتابة subscription_packages = isMarketingAdmin (لا المحاسب)
            'roles': ['super_admin', 'marketing_admin'],
          },
          {
            'title': 'الإشعارات والحملات',
            'icon': Icons.campaign_outlined,
            'color': Colors.pink,
            'page': const AdminMarketingScreen(),
            'roles': ['super_admin', 'orders_manager', 'accountant_admin', 'marketing_admin'],
          },
        ],
      },
      {
        'label': 'التقارير والمالية',
        'icon': Icons.bar_chart_outlined,
        'color': Colors.teal,
        'items': [
          {
            'title': 'لوحة الإحصائيات والأرباح',
            'icon': Icons.insert_chart_outlined,
            'color': Colors.teal,
            'page': const AdminAnalyticsScreen(),
            'roles': ['super_admin', 'accountant_admin', 'orders_manager'],
          },
          {
            'title': 'سجل العمليات الإدارية',
            'icon': Icons.history_edu_rounded,
            'color': const Color(0xFF1E293B),
            'page': const AdminAuditLogsScreen(),
            'roles': ['super_admin'],
          },
        ],
      },
      {
        'label': 'الإعدادات',
        'icon': Icons.settings_outlined,
        'color': Colors.grey,
        'items': [
          {
            'title': 'المناطق والأسعار',
            'icon': Icons.map_outlined,
            'color': Colors.blueAccent,
            'page': const AdminHourlyZonesScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          {
            'title': 'إعدادات النظام',
            'icon': Icons.settings_suggest_outlined,
            'color': Colors.grey,
            'page': const AdminSettingsScreen(),
            'roles': ['super_admin'],
          },
        ],
      },
    ];
  }

  Widget _buildSection(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: const Color(0xFF374151),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: Colors.grey.shade200,
                    thickness: 1,
                  ),
                ),
              ],
            ),
          ),
          // Items row — 2 per row
          ...List.generate((items.length / 2).ceil(), (rowIndex) {
            final first = items[rowIndex * 2];
            final second = rowIndex * 2 + 1 < items.length
                ? items[rowIndex * 2 + 1]
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(child: _buildItem(context, first)),
                  const SizedBox(width: 12),
                  second != null
                      ? Expanded(child: _buildItem(context, second))
                      : const Expanded(child: SizedBox.shrink()),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> item) {
    final color = item['color'] as Color;
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => item['page'] as Widget),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item['icon'] as IconData, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item['title'] as String,
                style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: const Color(0xFF1E293B),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
