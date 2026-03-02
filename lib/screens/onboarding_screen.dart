import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _data = [
    {
      "title": "أهلاً بكِ في زيارة",
      "desc": "المنصة الأولى لخدمات النظافة والصيانة في القطاع الجبلي بجازان.",
      "icon": "🏡"
    },
    {
      "title": "دفع آمن وتقسيط",
      "desc": "احجزي خدمتكِ الآن وادفعي بكل سهولة عبر تمارا بنظام التقسيط المريح.",
      "icon": "💳"
    },
    {
      "title": "تتبع حي ودقيق",
      "desc": "تابعي موقع السائق والعاملة لحظة بلحظة حتى وصولهم لباب منزلكِ.",
      "icon": "📍"
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (v) => setState(() => _currentPage = v),
                itemCount: _data.length,
                itemBuilder: (context, i) => _buildPage(_data[i]),
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(Map<String, String> item) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(item['icon']!, style: const TextStyle(fontSize: 100)),
          const SizedBox(height: 40),
          Text(
            item['title']!,
            style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold, color: const Color(0xFF1E3A8A)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            item['desc']!,
            style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // النقاط (Indicators)
          Row(
            children: List.generate(_data.length, (i) => Container(
              margin: const EdgeInsets.all(4),
              width: _currentPage == i ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == i ? const Color(0xFF1E3A8A) : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
          // زر الانتقال
          ElevatedButton(
            onPressed: () {
              if (_currentPage == _data.length - 1) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ZyiarahLoginScreen()));
              } else {
                _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(20),
            ),
            child: const Icon(Icons.chevron_right, color: Colors.white),
          )
        ],
      ),
    );
  }
}
