import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/contract_signing_screen.dart';

class ZyiarahSubscriptionPlansScreen extends StatelessWidget {
  const ZyiarahSubscriptionPlansScreen({super.key});

  final Color brandPurple = const Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('سلة العائلة (الاشتراكات)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoSection(),
              const SizedBox(height: 30),
              _buildPlanCard(
                'الباقة اليومية',
                'زيارة واحدة في اليوم المختار',
                '99 ر.س',
                ['تنظيف شامل لمدة 4 ساعات', 'تشمل جميع الأدوات', 'مقدمة خدمة واحدة'],
                Colors.blue.shade600,
              ),
              const SizedBox(height: 20),
              _buildPlanCard(
                'الباقة الأسبوعية',
                'زيارة واحدة اسبوعياً (4 زيارات)',
                '349 ر.س',
                ['توفير 15%', 'تحديد موعد ثابت أسبوعياً', 'خصومات على الخدمات الإضافية'],
                brandPurple,
              ),
              const SizedBox(height: 20),
              _buildPlanCard(
                'الباقة الشهرية (جولد)',
                'زيارتين اسبوعياً (8 زيارات)',
                '649 ر.س',
                ['توفير 25%', 'مقدمة خدمة ثابتة ومفضلة', 'أولوية في الحجز', 'عقد إلكتروني موثق'],
                Colors.amber.shade700,
                isPremium: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brandPurple.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: brandPurple, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'اختر الباقة المناسبة لعائلتك. بعد اختيار الباقة سيتم توجيه طلبك للإدارة للموافقة عليه قبل توقيع العقد الإلكتروني.',
              style: GoogleFonts.tajawal(fontSize: 13, height: 1.5, color: Colors.blueGrey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String title, String subtitle, String price, List<String> features, Color color, {bool isPremium = false}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: isPremium ? Border.all(color: color, width: 2) : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
              Text(price, style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color, size: 18),
                const SizedBox(width: 10),
                Text(f, style: GoogleFonts.tajawal(fontSize: 14, color: Colors.blueGrey[700])),
              ],
            ),
          )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ZyiarahContractSigningScreen(planName: title)),
            );
          },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text('اطلب الان', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
