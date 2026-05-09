import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:zyiarah/screens/login_screen.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  static const Color _brand = Color(0xFF5D1B5E);

  final List<Map<String, String>> _data = [
    {
      "title": "أهلاً بكِ في زيارة",
      "desc": "المنصة الأولى لخدمات النظافة والصيانة في القطاع الجبلي بجازان.",
      "lottie": "https://lottie.host/9972352b-4780-4545-8f65-021199346747/XJzQitkR2f.json"
    },
    {
      "title": "دفع آمن وتقسيط",
      "desc": "احجزي خدمتكِ الآن وادفعي بكل سهولة عبر تمارا بنظام التقسيط المريح.",
      "lottie": "https://lottie.host/341f22e8-9614-4114-8785-30fa9831c238/X73rA1Z5a1.json"
    },
    {
      "title": "تتبع حي ودقيق",
      "desc": "تابعي موقع السائق والعاملة لحظة بلحظة حتى وصولهم لباب منزلكِ.",
      "lottie": "https://lottie.host/6429f55e-a61d-4519-94b2-0545cf026131/V088G0M8hS.json"
    }
  ];

  void _goToLogin() {
    ZyiarahCoreService.triggerHapticSelection();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ZyiarahLoginScreen()));
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

  Widget _buildPage(Map<String, String> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(item['lottie']!, height: 260, repeat: true, fit: BoxFit.contain),
          const SizedBox(height: 48),
          Text(
            item['title']!,
            style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold, color: _brand),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            item['desc']!,
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
                  ? _buildActionButton('ابدأ الآن', Icons.arrow_forward_rounded, _goToLogin)
                  : _buildActionButton('التالي', Icons.arrow_forward_ios_rounded, () {
                      ZyiarahCoreService.triggerHapticSelection();
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOutExpo,
                      );
                    }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      key: ValueKey(label),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    );
  }
}
