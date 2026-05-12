import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/login_screen.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

class GuestExploreScreen extends StatelessWidget {
  const GuestExploreScreen({super.key});

  static const Color _brand = Color(0xFF5D1B5E);

  static const List<_ServiceItem> _services = [
    _ServiceItem(
      title: 'خدمة بالساعة',
      subtitle: 'عاملة منزلية بالساعة',
      price: 'من 50 ر.س',
      themeColor: Color(0xFF10B981),
      iconBgColor: Color(0xFFE1F0E4),
      icon: Icons.access_time_filled,
      imagePath: 'assets/images/hourly_cleaning.png',
    ),
    _ServiceItem(
      title: 'تنظيف الكنب والزل',
      subtitle: 'تنظيف عميق بالبخار',
      price: 'حسب المتر',
      themeColor: Color(0xFF8B5CF6),
      iconBgColor: Color(0xFFF1E9FE),
      icon: Icons.chair,
      imagePath: 'assets/images/sofa_cleaning.png',
    ),
    _ServiceItem(
      title: 'باقات الاشتراك',
      subtitle: 'زيارات مجدولة شهرية',
      price: 'باقات شهرية',
      themeColor: Color(0xFF10B981),
      iconBgColor: Color(0xFFE1F0E4),
      icon: Icons.workspace_premium,
      imagePath: 'assets/images/monthly_cleaning.png',
    ),
    _ServiceItem(
      title: 'صيانة وغسيل المكيفات',
      subtitle: 'تنظيف وصيانة شاملة',
      price: 'حسب الطلب',
      themeColor: Color(0xFF475569),
      iconBgColor: Color(0xFFF1F5F9),
      icon: Icons.handyman,
      imagePath: 'assets/images/company_cleaning.png',
    ),
    _ServiceItem(
      title: 'متجر المنظفات',
      subtitle: 'أدوات احترافية',
      price: 'عروض حصرية',
      themeColor: Color(0xFF5D1B5E),
      iconBgColor: Color(0xFFFCEEFA),
      icon: Icons.storefront,
      imagePath: 'assets/images/store.png',
    ),
  ];

  void _onServiceTap(BuildContext context) {
    ZyiarahCoreService.triggerHapticLight();
    _showLoginPrompt(context);
  }

  void _showLoginPrompt(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _LoginPromptSheet(brand: _brand),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: _buildAppBar(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuestBanner(context),
                const SizedBox(height: 24),
                _buildSectionTitle(),
                const SizedBox(height: 16),
                _buildServicesGrid(context),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.9),
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _brand,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.maps_home_work_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('زيارة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A))),
              Text('استعراض الخدمات', style: TextStyle(fontWeight: FontWeight.w400, fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextButton(
            onPressed: () => _navigateToLogin(context),
            style: TextButton.styleFrom(
              backgroundColor: _brand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('تسجيل الدخول', style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5D1B5E), Color(0xFF8B3D8C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: _brand.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أهلاً بكِ في زيارة',
                    style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                Text('تصفّحي خدماتنا واحجزي بكل سهولة\nبعد تسجيل الدخول',
                    style: GoogleFonts.tajawal(fontSize: 13, color: Colors.white70, height: 1.5)),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => _navigateToLogin(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text('سجّلي الدخول للحجز',
                        style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold, color: _brand)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.cleaning_services_rounded, color: Colors.white38, size: 64),
        ],
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 16),
        ),
        const SizedBox(width: 10),
        const Text('خدماتنا', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _buildServicesGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 500 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 15,
          crossAxisSpacing: 15,
          childAspectRatio: cols == 3 ? 0.85 : 0.75,
          children: _services.map((s) => _buildServiceCard(context, s)).toList(),
        );
      },
    );
  }

  Widget _buildServiceCard(BuildContext context, _ServiceItem s) {
    return InkWell(
      onTap: () => _onServiceTap(context),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Image.asset(
                s.imagePath,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 110,
                  color: s.iconBgColor,
                  child: Center(child: Icon(s.icon, color: s.themeColor, size: 40)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(s.subtitle,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: s.themeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(s.price,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: s.themeColor)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToLogin(BuildContext context) {
    ZyiarahCoreService.triggerHapticSelection();
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahLoginScreen()));
  }
}

class _LoginPromptSheet extends StatelessWidget {
  final Color brand;
  const _LoginPromptSheet({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded, color: brand, size: 32),
            ),
            const SizedBox(height: 20),
            Text('سجّلي الدخول أولاً',
                style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
            const SizedBox(height: 10),
            Text('لحجز الخدمة تحتاجين إلى حساب في زيارة.\nالتسجيل مجاني ولا يستغرق دقيقة.',
                style: GoogleFonts.tajawal(fontSize: 14, color: const Color(0xFF64748B), height: 1.6),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahLoginScreen()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text('تسجيل الدخول / إنشاء حساب',
                    style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('تصفّح بدون حجز', style: GoogleFonts.tajawal(fontSize: 14, color: const Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceItem {
  final String title;
  final String subtitle;
  final String price;
  final Color themeColor;
  final Color iconBgColor;
  final IconData icon;
  final String imagePath;

  const _ServiceItem({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.themeColor,
    required this.iconBgColor,
    required this.icon,
    required this.imagePath,
  });
}
