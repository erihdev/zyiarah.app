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
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(item['lottie']!, height: 280, repeat: true),
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
              ZyiarahCoreService.triggerHapticSelection();
              if (_currentPage == _data.length - 1) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ZyiarahLoginScreen()));
              } else {
                _controller.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOutExpo);
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
