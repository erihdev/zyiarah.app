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
import 'package:zyiarah/screens/admin/admin_accountants_screen.dart';
import 'package:zyiarah/screens/admin/admin_deletions_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_orders_screen.dart';
import 'package:zyiarah/screens/admin/admin_hourly_zones_screen.dart';
import 'package:zyiarah/screens/admin/admin_subscriptions_screen.dart';
import 'package:zyiarah/screens/admin/admin_analytics_screen.dart';

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: GridView(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          children: [
            _buildGridItem(context, 'لوحة الإحصائيات والأرباح', Icons.insert_chart_outlined, Colors.teal, const AdminAnalyticsScreen()),
            _buildGridItem(context, 'المستخدمين', Icons.people_outline, Colors.blue, const AdminUsersScreen()),
            _buildGridItem(context, 'السائقين والعمال', Icons.engineering_outlined, Colors.orange, const AdminDriversScreen()),
            _buildGridItem(context, 'الدعم الفني', Icons.support_agent, Colors.purple, const AdminSupportScreen()),
            _buildGridItem(context, 'الإشعارات والتسويق', Icons.campaign_outlined, Colors.redAccent, const AdminMarketingScreen()),
            _buildGridItem(context, 'طلبات الصيانة', Icons.build_circle_outlined, Colors.brown, const AdminMaintenanceScreen()),
            _buildGridItem(context, 'العقود الإلكترونية', Icons.history_edu, Colors.green, const AdminContractsScreen()),
            _buildGridItem(context, 'طلبات المتجر', Icons.shopping_cart_checkout, Colors.teal, const AdminStoreOrdersScreen()),
             _buildGridItem(context, 'المدراء', Icons.admin_panel_settings_outlined, Colors.indigo, const AdminManagersScreen()),
            _buildGridItem(context, 'المحاسبون', Icons.account_balance_wallet_outlined, Colors.blueGrey, const AdminAccountantsScreen()),
            _buildGridItem(context, 'طلبات الحذف', Icons.delete_sweep_outlined, Colors.red, const AdminDeletionsScreen()),
            _buildGridItem(context, 'باقات الاشتراك', Icons.card_giftcard_outlined, Colors.deepPurple, const AdminSubscriptionsScreen()),
            _buildGridItem(context, 'المناطق والأسعار', Icons.map_outlined, Colors.blueAccent, const AdminHourlyZonesScreen()),
            _buildGridItem(context, 'إعدادات النظام', Icons.settings_suggest_outlined, Colors.grey[800]!, const AdminSettingsScreen()),
          ],
        )
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
