import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:zyiarah/screens/admin/admin_store_screen.dart';
import 'package:zyiarah/screens/admin/admin_store_orders_screen.dart';

/// تبويبُ «المتجر» في لوحةِ الإدارة: المنتجاتُ وطلباتُ المتجرِ في موضعٍ واحد.
///
/// كانت «طلبات المتجر» بلاطةً في «المزيد» بعيدةً عن تبويبِ المتجرِ نفسِه.
/// والشريحتانِ تَتبعانِ الأدوارَ كما كانت **حرفيّاً** — لا يُوسَّعُ وصولٌ:
///   • المنتجاتُ: المديرُ العامُّ والمحاسبُ والتسويق (الشاشةُ تُخفي أدواتِ
///     الكتابةِ لمن لا تُجيزُه القواعدُ — `_canWriteProducts`).
///   • الطلباتُ: المديرُ العامُّ ومديرُ الطلبات (تحديثُ `store_orders` =
///     `isOrdersManager` في القواعد) — وهو ما كانت تَحملُه بلاطتُها.
/// دورٌ يَملكُ شريحةً واحدةً يَراها وحدَها بلا مُبدِّل.
class AdminStoreHubScreen extends StatelessWidget {
  final String role;
  const AdminStoreHubScreen({super.key, required this.role});

  static const productRoles = ['super_admin', 'accountant_admin', 'marketing_admin'];
  static const orderRoles = ['super_admin', 'orders_manager'];

  /// الأدوارُ التي يَظهرُ لها التبويبُ أصلاً — اتّحادُ الشريحتَين.
  static List<String> get tabRoles =>
      {...productRoles, ...orderRoles}.toList();

  static const Color _brand = Color(0xFF660033);

  @override
  Widget build(BuildContext context) {
    final showProducts = productRoles.contains(role);
    final showOrders = orderRoles.contains(role);

    // الشاشتانِ تُرسَمانِ **مُضمَّنتَين** (بلا `AppBar` خاصّ): اللوحةُ
    // تَحملُ شريطَها فوقَهما، وكان كلٌّ منهما يَرسمُ شريطاً ثانياً تحتَه.
    if (showProducts && !showOrders) {
      return AdminStoreScreen(role: role, embedded: true);
    }
    if (showOrders && !showProducts) {
      return const AdminStoreOrdersScreen(embedded: true);
    }
    if (!showProducts && !showOrders) return const SizedBox.shrink();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Material(
              color: Colors.white,
              child: TabBar(
                labelColor: _brand,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: _brand,
                labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(icon: Icon(Icons.inventory_2_outlined), text: 'المنتجات'),
                  Tab(
                      icon: Icon(Icons.shopping_cart_checkout_outlined),
                      text: 'طلبات المتجر'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AdminStoreScreen(role: role, embedded: true),
                  const AdminStoreOrdersScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
