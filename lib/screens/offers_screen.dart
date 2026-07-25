import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zyiarah/screens/hourly_details_screen.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/sofa_rug_details_screen.dart';
import 'package:zyiarah/screens/ac_service_details_screen.dart';
import 'package:zyiarah/screens/subscription_plans_screen.dart';

/// قسم «العروض» — يعرض البانرات التي اختارت لها الإدارة `placement == 'offers'`.
/// البانرات الرئيسية تبقى أعلى الرئيسية؛ هذا القسم لما تريده الإدارة تجميعه كعروض.
class ZyiarahOffersScreen extends StatelessWidget {
  const ZyiarahOffersScreen({super.key});

  static const Color _brand = Color(0xFF006FBA);

  Future<void> _handleTap(BuildContext context, Map<String, dynamic> data) async {
    final String routeType = data['routeType'] ?? 'none';
    final String actionUrl = data['actionUrl'] ?? '';
    if (routeType == 'whatsapp' && actionUrl.isNotEmpty) {
      final uri = Uri.parse(actionUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر فتح الرابط')));
      }
      return;
    }
    if (!context.mounted) return;
    Widget? dest;
    switch (routeType) {
      case '/hourly_cleaning':
        dest = const HourlyCleaningDetailsScreen(serviceName: 'نظافة بالساعة');
        break;
      case '/store':
        dest = const ZyiarahStoreScreen();
        break;
      case '/support':
        dest = const ZyiarahSupportScreen();
        break;
      case '/sofa_cleaning':
      case '/rug_cleaning':
        dest = const SofaRugCleaningDetailsScreen(serviceName: 'تنظيف الكنب والزل');
        break;
      case '/ac':
      case '/ac_service':
        dest = const AcServiceDetailsScreen();
        break;
      case '/subscriptions':
        dest = const ZyiarahSubscriptionPlansScreen();
        break;
    }
    if (dest != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => dest!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: Text('العروض',
              style: GoogleFonts.tajawal(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('promo_banners')
              .where('isActive', isEqualTo: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _brand));
            }
            if (snapshot.hasError) {
              return Center(
                  child: Text('تعذّر تحميل العروض، تحقّق من الاتصال',
                      style: GoogleFonts.tajawal(color: Colors.grey)));
            }
            // العروض = البانرات المخصّصة لقسم العروض (placement == 'offers').
            // التصفية محلية لأن Firestore لا يستعلم «= offers» مع بانرات بلا الحقل.
            final offers = (snapshot.data?.docs ?? []).where((d) {
              return (d.data() as Map<String, dynamic>)['placement'] == 'offers';
            }).toList();

            if (offers.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_offer_outlined,
                        size: 80, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('لا توجد عروض حالياً',
                        style: GoogleFonts.tajawal(
                            fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Text('تابعنا — عروضنا القادمة قريباً 🌿',
                        style: GoogleFonts.tajawal(
                            fontSize: 13, color: Colors.grey.shade400)),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: offers.length,
              itemBuilder: (context, index) {
                final data = offers[index].data() as Map<String, dynamic>;
                return GestureDetector(
                  onTap: () => _handleTap(context, data),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 5)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 2 / 1,
                        child: CachedNetworkImage(
                          imageUrl: data['imageUrl'] ?? '',
                          fit: BoxFit.cover,
                          placeholder: (c, u) =>
                              Container(color: Colors.grey.shade200),
                          errorWidget: (c, u, e) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.image_not_supported,
                                color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
