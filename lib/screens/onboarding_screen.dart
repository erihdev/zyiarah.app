import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  static const Color _brand = Color(0xFF660033);

  // أيقونات محلّية مميّزة لكل شريحة — بديل موثوق عن Lottie عبر الإنترنت الذي كان
  // يفشل فيسقط للمكنسة نفسها في الشرائح الثلاث.
  final List<Map<String, dynamic>> _data = [
    {
      "title": "أهلاً بكِ في زيارة",
      "desc": "المنصة الأولى لخدمات النظافة والصيانة في القطاع الجبلي بجازان.",
      "icon": Icons.cleaning_services_rounded,
    },
    {
      "title": "دفع آمن وتقسيط",
      "desc": "احجزي خدمتكِ الآن وادفعي بكل سهولة عبر تمارا بنظام التقسيط المريح.",
      "icon": Icons.credit_card_rounded,
    },
    {
      "title": "تتبع حي ودقيق",
      "desc": "تابعي موقع السائق والعاملة لحظة بلحظة حتى وصولهم لباب منزلكِ.",
      "icon": Icons.location_on_rounded,
    }
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToLogin() {
    ZyiarahCoreService.triggerHapticSelection();
    // عبر الراوتر لا Navigator.push: شاشة الدخول مسار في GoRouter ('/login')، ودفعها
    // فوق المكدّس يدوياً كان يجعلها تبقى معروضة بعد نجاح الدخول — لأن context.go('/')
    // يغيّر مسار الراوتر **تحتها** بينما هي فوق مكدّس Navigator. فيرى المستخدم شاشة
    // الدخول كما هي ويظنّ أن الزر لا يعمل، رغم أن الدخول نجح فعلاً.
    context.go('/login');
  }

  void _goToGuest() {
    ZyiarahCoreService.triggerHapticLight();
    // push لا go: نحتفظ بالترحيب تحتها ليعمل زر الرجوع. والأهم أنها عبر الراوتر —
    // فشاشة التصفّح تستدعي context.go('/login')، ودفعها عبر Navigator كان يجعل ذلك
    // الزر بلا أثر مرئي إطلاقاً (يتغيّر المسار تحتها وهي تبقى فوقه).
    context.push('/guest');
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _data.length - 1;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: TextButton(
                      onPressed: _goToLogin,
                      child: Text(
                        'تخطي',
                        style: GoogleFonts.tajawal(color: Colors.grey[400], fontSize: 14),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: (v) => setState(() => _currentPage = v),
                    itemCount: _data.length,
                    itemBuilder: (context, i) => _buildPage(_data[i]),
                  ),
                ),
                _buildBottomControls(isLast),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: _brand.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(item['icon'] as IconData, size: 96, color: _brand),
          ),
          const SizedBox(height: 48),
          Text(
            item['title'] as String,
            style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold, color: _brand),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            item['desc'] as String,
            style: GoogleFonts.tajawal(fontSize: 15, color: Colors.grey[600], height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isLast) {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 36),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_data.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == i ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == i ? _brand : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: isLast
                  ? _buildActionButton('ابدأ الآن', _goToLogin)
                  : _buildActionButton('التالي', () {
                      ZyiarahCoreService.triggerHapticSelection();
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOutExpo,
                      );
                    }),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _goToGuest,
              child: Text(
                'تصفّح بدون تسجيل',
                style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onTap) {
    // نصّ واضح بلا سهم اتجاهي: الشيفرون في RTL كان يُقرأ كـ«رجوع» فيربك.
    return ElevatedButton(
      key: ValueKey(label),
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Text(label,
          style: GoogleFonts.tajawal(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
    );
  }
}
