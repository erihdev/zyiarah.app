import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:zyiarah/screens/admin/admin_settings_screen.dart';
import 'package:zyiarah/screens/admin/admin_users_screen.dart';
import 'package:zyiarah/screens/admin/admin_drivers_screen.dart';
import 'package:zyiarah/screens/admin/admin_support_screen.dart';
import 'package:zyiarah/screens/admin/admin_banners_screen.dart';
import 'package:zyiarah/screens/admin/admin_policies_screen.dart';
import 'package:zyiarah/screens/admin/admin_coupons_screen.dart';
import 'package:zyiarah/screens/admin/admin_contracts_screen.dart';
import 'package:zyiarah/screens/admin/admin_managers_screen.dart';
import 'package:zyiarah/screens/admin/admin_deletions_screen.dart';
import 'package:zyiarah/screens/admin/admin_hourly_zones_screen.dart';
import 'package:zyiarah/screens/admin/admin_audit_logs_screen.dart';
import 'package:zyiarah/screens/admin/admin_fleet_map_screen.dart';
import 'package:zyiarah/screens/admin/admin_invoices_screen.dart';
import 'package:zyiarah/screens/admin/admin_schedule_board_screen.dart';
import 'package:zyiarah/screens/admin/admin_broadcast_screen.dart';
import 'package:zyiarah/screens/admin/admin_packages_screen.dart';
import 'package:zyiarah/utils/csv_export_util.dart';
import 'package:zyiarah/utils/pdf_report_util.dart';
import 'package:zyiarah/utils/zyiarah_strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/utils/net_timeout.dart';

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
              color: const Color(0xFF660033), // لون هوية موحّد لكل الأقسام
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
            'title': 'العقود الإلكترونية',
            'icon': Icons.description_outlined,
            'color': Colors.green,
            'page': const AdminContractsScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          // «طلبات المتجر» انتقلت إلى تبويبِ «المتجر» (AdminStoreHubScreen) بأدوارِها نفسِها.
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
            // باقاتُ الاشتراكِ وعاملاتِ المناسباتِ في شاشةٍ واحدةٍ بشريحتَين —
            // كانتا بلاطتَين بالأدوارِ نفسِها. القواعد: كتابة المجموعتَين =
            // isMarketingAdmin (لا المحاسب).
            'title': 'الباقات',
            'icon': Icons.card_giftcard_outlined,
            'color': Colors.deepPurple,
            'page': const AdminPackagesScreen(),
            'roles': ['super_admin', 'marketing_admin'],
          },
          {
            'title': 'بثّ إشعار جماعي',
            'icon': Icons.notifications_active_outlined,
            'color': const Color(0xFF7C3AED),
            'page': const AdminBroadcastScreen(),
            'roles': ['super_admin', 'orders_manager', 'marketing_admin'],
          },
        ],
      },
      {
        'label': 'التقارير والمالية',
        'icon': Icons.bar_chart_outlined,
        'color': Colors.teal,
        'items': [
          {
            // استشرافي لا تقريري: «ماذا أمامنا» مقابل «كم ربحنا» في لوحة الإحصائيات.
            'title': 'جدول المتابعة (يومي/أسبوعي/شهري)',
            'icon': Icons.event_note_rounded,
            'color': const Color(0xFF7C3AED),
            'page': const AdminScheduleBoardScreen(),
            'roles': ['super_admin', 'accountant_admin', 'orders_manager'],
          },
          {
            // رادار الأسطول: كل سائق في مهمة الآن على خريطة واحدة (Stitch _21).
            'title': 'رادار الأسطول المباشر',
            'icon': Icons.radar_rounded,
            'color': const Color(0xFF0369A1),
            'page': const AdminFleetMapScreen(),
            'roles': ['super_admin', 'orders_manager'],
          },
          // «لوحة الإحصائيات والأرباح» تُفتَحُ من تبويبِ الإحصاءاتِ نفسِه (بطاقةُ
          // «التحليلات المالية») — لا بلاطةٌ ثانيةٌ للأرقامِ في «المزيد».
          {
            // سجل فواتير ZATCA لكل الطلبات المدفوعة (خدمات ومتجر) بالشهر.
            'title': 'سجل الفواتير الإلكترونية (ZATCA)',
            'icon': Icons.receipt_long_outlined,
            'color': const Color(0xFF0F766E),
            'page': const AdminInvoicesScreen(),
            'roles': ['super_admin', 'accountant_admin'],
          },
          {
            'title': 'سجل العمليات الإدارية',
            'icon': Icons.history_edu_rounded,
            'color': const Color(0xFF1E293B),
            'page': const AdminAuditLogsScreen(),
            'roles': ['super_admin'],
          },
          {
            // بلاطةٌ واحدةٌ للتصدير بدل اثنتَين: التقريرُ الماليُّ PDF وجدولُ
            // الطلباتِ CSV، يُختارُ بينهما من ورقةٍ سفليّة.
            'title': 'تصدير التقارير (PDF / CSV)',
            'icon': Icons.file_download_outlined,
            'color': const Color(0xFF059669),
            'onTap': _showExportSheet,
            'roles': ['super_admin', 'accountant_admin', 'orders_manager'],
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
            // (تصميم Stitch) بنود الشروط المصنَّفة — الكتابة للسوبر وحده في
            // firestore.rules، فلا نعرضها لدور يعجز عن حفظ شيء.
            'title': 'شروط وضوابط الخدمة',
            'icon': Icons.gavel_rounded,
            'color': Colors.brown,
            'page': const AdminPoliciesScreen(),
            'roles': ['super_admin'],
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
    const color = Color(0xFF660033); // لون هوية موحّد لكل العناصر
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        final action = item['onTap'];
        if (action is Future<void> Function(BuildContext)) {
          action(context); // عنصر إجرائي (تصدير) — لا ينقل لصفحة
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => item['page'] as Widget),
          );
        }
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
                  fontWeight: FontWeight.w700,
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

  /// ورقةُ التصدير: خياران في موضعٍ واحد.
  static Future<void> _showExportSheet(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFDC2626)),
                title: const Text('تقرير مالي (PDF)'),
                subtitle: const Text('الإيراد المدفوع والطلبات النشطة لآخر 2000 طلب'),
                onTap: () => Navigator.pop(sheet, 'pdf'),
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined, color: Color(0xFF059669)),
                title: const Text('تصدير الطلبات (CSV)'),
                subtitle: const Text('يُنسخ إلى الحافظة لِلَصقه في جدول بيانات'),
                onTap: () => Navigator.pop(sheet, 'csv'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'pdf') {
      await _exportFinancialPdf(context);
    } else {
      await _exportOrdersCsv(context);
    }
  }

  // تصدير الطلبات CSV — **عبر `ZyiarahExportUtil` لا بناءٌ يدويّ.** كان هذا
  // الموضعُ يَبني السطرَ بفواصلَ عاريةٍ (`${d['client_name']},…`): اسمٌ فيه
  // فاصلةٌ يَكسِرُ الصفَّ، ونصٌّ يَبدأُ بـ`=` يُقيَّمُ صيغةً في جدولِ المالك —
  // وهو بعينِه ما أُصلحَ في `csv_export_util` لزرِّ شاشةِ الطلبات.
  static Future<void> _exportOrdersCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('جاري تجهيز التصدير...')));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .orderBy('created_at', descending: true)
          .limit(2000)
          .get().timeout(kNetCallTimeout);
      await Clipboard.setData(
          ClipboardData(text: ZyiarahExportUtil.convertToCsv(snap.docs)));
      messenger.showSnackBar(const SnackBar(
        content: Text('تم نسخ بيانات الطلبات (CSV) إلى الحافظة — الصقها في Excel أو Google Sheets ✅'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  // تقرير مالي PDF — نُقل من الرئيسية إلى «التقارير والمالية».
  static Future<void> _exportFinancialPdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('جاري تجهيز التقرير...')));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .orderBy('created_at', descending: true)
          .limit(2000)
          .get().timeout(kNetCallTimeout);
      double revenue = 0;
      int active = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['is_paid'] == true && d['amount'] is num) revenue += (d['amount'] as num).toDouble();
        final s = d['status'];
        if (s != 'completed' && s != 'cancelled') active++;
      }
      await ZyiarahPdfReportUtil.generateFinancialReport(
        orders: snap.docs.cast<DocumentSnapshot>(),
        totalRevenue: revenue,
        activeOrders: active,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('فشل إنشاء التقرير: $e')));
    }
  }
}
