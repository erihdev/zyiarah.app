import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ZyiarahSplashScreen extends StatefulWidget {
  const ZyiarahSplashScreen({super.key});

  @override
  State<ZyiarahSplashScreen> createState() => _ZyiarahSplashScreenState();
}

class _ZyiarahSplashScreenState extends State<ZyiarahSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _pinController;
  late AnimationController _textController;
  late AnimationController _pulseController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pin1Drop;
  late Animation<double> _pin2Drop;
  late Animation<double> _pin3Drop;
  late Animation<double> _pin1Opacity;
  late Animation<double> _pin2Opacity;
  late Animation<double> _pin3Opacity;
  late Animation<double> _textOpacity;
  late Animation<double> _textSlide;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _pinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Pin 1 (top-left, above ز)
    _pin1Drop = Tween<double>(begin: -40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.0, 0.5, curve: Curves.bounceOut),
      ),
    );
    _pin1Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    // Pin 2 (top-right, above ة)
    _pin2Drop = Tween<double>(begin: -40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.2, 0.7, curve: Curves.bounceOut),
      ),
    );
    _pin2Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.2, 0.5, curve: Curves.easeIn),
      ),
    );

    // Pin 3 (side, next to ZYIARAH text)
    _pin3Drop = Tween<double>(begin: -30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.4, 0.9, curve: Curves.bounceOut),
      ),
    );
    _pin3Opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pinController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );
    _textSlide = Tween<double>(begin: 12.0, end: 0.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startAnimation();
  }

  Future<void> _startAnimation() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _pinController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pinController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _logoController,
            _pinController,
            _textController,
            _pulseController,
          ]),
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _pulseScale,
                      child: _buildLogo(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _textOpacity,
                  child: Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: _buildTagline(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 220,
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Arabic text "زيارة"
          Center(
            child: Text(
              'زيارة',
              style: GoogleFonts.tajawal(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF5D1B5E),
                height: 1.0,
              ),
            ),
          ),

          // Pin 1 — top left (above ز)
          Positioned(
            top: 0,
            left: 30,
            child: Transform.translate(
              offset: Offset(0, _pin1Drop.value),
              child: Opacity(
                opacity: _pin1Opacity.value,
                child: _buildLocationPin(size: 22),
              ),
            ),
          ),

          // Pin 2 — top right (above ة) - smaller
          Positioned(
            top: 4,
            right: 15,
            child: Transform.translate(
              offset: Offset(0, _pin2Drop.value),
              child: Opacity(
                opacity: _pin2Opacity.value,
                child: _buildLocationPin(size: 18),
              ),
            ),
          ),

          // ZYIARAH latin text + pin3
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'ZYIARAH',
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7AB51D),
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(width: 4),
                Transform.translate(
                  offset: Offset(0, _pin3Drop.value),
                  child: Opacity(
                    opacity: _pin3Opacity.value,
                    child: _buildLocationPin(size: 16),
                  ),
                ),
              ],
            ),
          ),

          // Two green dots (bottom right, dot decoration)
          Positioned(
            bottom: 10,
            right: 12,
            child: Opacity(
              opacity: _pin3Opacity.value,
              child: Row(
                children: [
                  _buildDot(6),
                  const SizedBox(width: 3),
                  _buildDot(4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPin({required double size}) {
    return CustomPaint(
      size: Size(size, size * 1.4),
      painter: _LocationPinPainter(),
    );
  }

  Widget _buildDot(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF7AB51D),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTagline() {
    return Text(
      'خدمات المنزل بكل سهولة',
      style: GoogleFonts.tajawal(
        fontSize: 14,
        color: const Color(0xFF94A3B8),
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _LocationPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7AB51D)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Teardrop / pin shape
    final path = Path();
    final cx = w / 2;
    final r = w / 2;
    final bodyHeight = h * 0.65;

    // Circle top
    path.addOval(Rect.fromCircle(center: Offset(cx, r), radius: r));

    // Triangle bottom pointing down
    path.moveTo(cx - r * 0.5, bodyHeight * 0.75);
    path.lineTo(cx + r * 0.5, bodyHeight * 0.75);
    path.lineTo(cx, h);
    path.close();

    canvas.drawPath(path, paint);

    // White circle inside
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, r), r * 0.42, innerPaint);

    // Inner purple dot — like a water drop
    final dotPaint = Paint()
      ..color = const Color(0xFF5D1B5E).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, r), r * 0.2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
