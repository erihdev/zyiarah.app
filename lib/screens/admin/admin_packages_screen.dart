import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:zyiarah/screens/admin/admin_subscriptions_screen.dart';
import 'package:zyiarah/screens/admin/admin_event_worker_packages_screen.dart';

/// «الباقات» — باقاتُ الاشتراكِ وباقاتُ عاملاتِ المناسباتِ في شاشةٍ واحدةٍ
/// بشريحتَين، بدلَ بلاطتَين متجاورتَين في «المزيد» لكتالوجَين من الشكلِ
/// نفسِه: الأدوارُ نفسُها (المديرُ العامُّ والتسويق — كتابةُ المجموعتَين
/// `isMarketingAdmin` في القواعد)، والمحرِّرُ نفسُه (سعرٌ وزياراتٌ وعاملاتٌ
/// عبرَ `packageFormError`). كلُّ شريحةٍ هي الشاشةُ القائمةُ بعينِها مُضمَّنةً
/// (`embedded: true`) فلا يُنسَخُ منطقُ حفظٍ ولا تحقّق.
///
/// و`TabBarView` لا يَبني إلّا الصفحةَ الظاهرة، فالشريحةُ الثانيةُ لا تَفتحُ
/// مستمِعَ Firestore حتى تُزار.
class AdminPackagesScreen extends StatelessWidget {
  const AdminPackagesScreen({super.key});

  static const Color _brand = Color(0xFF660033);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text('الباقات',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            backgroundColor: _brand,
            foregroundColor: Colors.white,
            bottom: TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.card_giftcard_outlined), text: 'الاشتراكات'),
                Tab(icon: Icon(Icons.celebration_rounded), text: 'عاملات المناسبات'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              AdminSubscriptionsScreen(embedded: true),
              AdminEventWorkerPackagesScreen(embedded: true),
            ],
          ),
        ),
      ),
    );
  }
}
