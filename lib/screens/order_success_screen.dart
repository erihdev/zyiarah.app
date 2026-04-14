import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/orders_list_screen.dart';

class ZyiarahOrderSuccessScreen extends StatefulWidget {
  final String orderCode;
  final String title;
  final String subtitle;

  const ZyiarahOrderSuccessScreen({
    super.key,
    required this.orderCode,
    this.title = "تم استلام طلبك بنجاح!",
    this.subtitle = "شكراً لثقتك بزيارة، طلبك الآن قيد المعالجة وسنقوم بإخطارك بكل جديد.",
  });

  @override
  State<ZyiarahOrderSuccessScreen> createState() => _ZyiarahOrderSuccessScreenState();
}

class _ZyiarahOrderSuccessScreenState extends State<ZyiarahOrderSuccessScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _checkAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE1F0E4),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FadeTransition(
                      opacity: _checkAnimation,
                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 80),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 24, color: const Color(0xFF1E293B)),
              ),
              const SizedBox(height: 15),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Text("رقم التتبع الخاص بك", style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 5),
                    Text(
                      widget.orderCode,
                      style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: 2, color: const Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const OrdersListScreen()),
                    );
                  },
                  child: Text("تتبع الطلب الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Text("العودة للرئيسية", style: GoogleFonts.tajawal(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
