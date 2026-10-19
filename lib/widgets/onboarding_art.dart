import 'dart:math' as math;

import 'package:flutter/material.dart';

/// رسومُ شاشةِ الترحيبِ مرسومةً بالشفرة لا صوراً: حادّةٌ في كلِّ مقاس، بلا
/// شبكة ولا وزنٍ يُضافُ إلى الحزمة، وبألوانِ العلامةِ نفسِها. (صورُ الخدماتِ
/// في `assets/images` تحملُ شعاراتِ شركاتٍ أخرى على الزيّ فلا تصلحُ هنا.)
enum OnboardingArtKind { home, payment, tracking }

class OnboardingArt extends StatelessWidget {
  final OnboardingArtKind kind;

  /// من 0 إلى 1: تقدّمُ حركةِ الدخولِ (العناصرُ الصغيرةُ تطفو وتظهر تباعاً).
  final double progress;

  const OnboardingArt({super.key, required this.kind, this.progress = 1});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(painter: _ArtPainter(kind, progress)),
    );
  }
}

const _brand = Color(0xFF660033);
const _brandLight = Color(0xFF8B3D8C);
const _accent = Color(0xFFE8427A);
const _gold = Color(0xFFF5B841);
const _mint = Color(0xFF34D399);
const _ink = Color(0xFF0F172A);

class _ArtPainter extends CustomPainter {
  final OnboardingArtKind kind;
  final double t;
  _ArtPainter(this.kind, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    _backdrop(canvas, s);
    switch (kind) {
      case OnboardingArtKind.home:
        _home(canvas, s);
      case OnboardingArtKind.payment:
        _payment(canvas, s);
      case OnboardingArtKind.tracking:
        _tracking(canvas, s);
    }
  }

  // ── الخلفيّة: دائرةٌ متدرّجةٌ ناعمةٌ وحلقةٌ منقّطةٌ تدور ببطء ─────────────
  void _backdrop(Canvas c, double s) {
    final center = Offset(s / 2, s / 2);
    c.drawCircle(
      center,
      s * 0.46,
      Paint()
        ..shader = RadialGradient(colors: [
          _brand.withValues(alpha: 0.10),
          _brandLight.withValues(alpha: 0.04),
        ]).createShader(Rect.fromCircle(center: center, radius: s * 0.46)),
    );
    final ring = Paint()
      ..color = _brand.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    const dots = 36;
    for (var i = 0; i < dots; i++) {
      final a = i * 2 * math.pi / dots + t * 0.6;
      c.drawCircle(center + Offset(math.cos(a), math.sin(a)) * s * 0.49, s * 0.006, ring);
    }
  }

  double _appear(double start) => ((t - start) / (1 - start)).clamp(0.0, 1.0);

  void _sparkle(Canvas c, Offset o, double r, Color color, double start) {
    final k = Curves.easeOutBack.transform(_appear(start));
    if (k <= 0) return;
    final rr = r * k;
    final p = Path()
      ..moveTo(o.dx, o.dy - rr)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + rr, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + rr)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - rr, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - rr)
      ..close();
    c.drawPath(p, Paint()..color = color);
  }

  Paint get _shadow => Paint()
    ..color = _ink.withValues(alpha: 0.10)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

  // ── ١. البيتُ النظيف ──────────────────────────────────────────────────────
  void _home(Canvas c, double s) {
    final base = s * 0.70;
    // أرضٌ بيضاويّة
    c.drawOval(Rect.fromCenter(center: Offset(s * 0.5, base + s * 0.03), width: s * 0.62, height: s * 0.07),
        Paint()..color = _brand.withValues(alpha: 0.10));

    final body = RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.30, s * 0.44, s * 0.70, base), Radius.circular(s * 0.03));
    c.drawRRect(body.shift(Offset(0, s * 0.015)), _shadow);
    c.drawRRect(body, Paint()..color = Colors.white);

    // سقف
    final roof = Path()
      ..moveTo(s * 0.25, s * 0.47)
      ..lineTo(s * 0.50, s * 0.27)
      ..lineTo(s * 0.75, s * 0.47)
      ..close();
    c.drawPath(
        roof,
        Paint()
          ..shader = const LinearGradient(colors: [_brandLight, _brand])
              .createShader(Rect.fromLTRB(s * 0.25, s * 0.27, s * 0.75, s * 0.47)));
    c.drawPath(
        roof,
        Paint()
          ..color = _brand
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.012
          ..strokeJoin = StrokeJoin.round);

    // باب ونافذتان
    c.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(s * 0.455, s * 0.56, s * 0.545, base),
            topLeft: Radius.circular(s * 0.045), topRight: Radius.circular(s * 0.045)),
        Paint()..color = _brand);
    c.drawCircle(Offset(s * 0.528, s * 0.635), s * 0.008, Paint()..color = _gold);
    for (final x in [s * 0.335, s * 0.585]) {
      final w = RRect.fromRectAndRadius(Rect.fromLTWH(x, s * 0.52, s * 0.08, s * 0.08), Radius.circular(s * 0.012));
      c.drawRRect(w, Paint()..color = const Color(0xFFDBEAFE));
      c.drawRRect(
          w,
          Paint()
            ..color = _brand.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.006);
      c.drawLine(Offset(x + s * 0.04, s * 0.52), Offset(x + s * 0.04, s * 0.60),
          Paint()
            ..color = _brand.withValues(alpha: 0.35)
            ..strokeWidth = s * 0.005);
    }

    // فقاعات صابون تطفو
    final bubble = Paint()
      ..color = _accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006;
    final lift = (1 - _appear(0.2)) * s * 0.06;
    for (final b in [
      [0.22, 0.36, 0.035],
      [0.17, 0.50, 0.022],
      [0.80, 0.33, 0.028],
      [0.84, 0.55, 0.04],
    ]) {
      final o = Offset(s * b[0], s * b[1] + lift);
      c.drawCircle(o, s * b[2], bubble);
      c.drawCircle(o + Offset(-s * b[2] * 0.35, -s * b[2] * 0.35), s * b[2] * 0.22,
          Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
    _sparkle(c, Offset(s * 0.66, s * 0.24), s * 0.045, _gold, 0.25);
    _sparkle(c, Offset(s * 0.30, s * 0.25), s * 0.03, _accent, 0.4);
    _sparkle(c, Offset(s * 0.76, s * 0.66), s * 0.025, _gold, 0.55);
  }

  // ── ٢. الدفعُ الآمن ───────────────────────────────────────────────────────
  void _payment(Canvas c, double s) {
    // بطاقةٌ خلفيّةٌ مائلة
    c.save();
    c.translate(s * 0.5, s * 0.5);
    c.rotate(-0.18);
    final back = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(-s * 0.04, -s * 0.06), width: s * 0.56, height: s * 0.34), Radius.circular(s * 0.04));
    c.drawRRect(back, Paint()..color = _accent.withValues(alpha: 0.85));
    c.restore();

    // البطاقةُ الأماميّة
    c.save();
    c.translate(s * 0.5, s * 0.5);
    c.rotate(0.06);
    final card = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, s * 0.02), width: s * 0.58, height: s * 0.35), Radius.circular(s * 0.04));
    c.drawRRect(card.shift(Offset(0, s * 0.02)), _shadow);
    c.drawRRect(
        card,
        Paint()
          ..shader = const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_brandLight, _brand])
              .createShader(card.outerRect));
    // شريحة
    final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(card.left + s * 0.05, card.top + s * 0.08, s * 0.09, s * 0.07), Radius.circular(s * 0.012));
    c.drawRRect(chip, Paint()..color = _gold);
    // خطوطُ الرقم
    final line = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (var i = 0; i < 4; i++) {
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(card.left + s * 0.05 + i * s * 0.12, card.top + s * 0.20, s * 0.09, s * 0.022),
              Radius.circular(s * 0.01)),
          line);
    }
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(card.left + s * 0.05, card.top + s * 0.26, s * 0.18, s * 0.02),
            Radius.circular(s * 0.01)),
        Paint()..color = Colors.white.withValues(alpha: 0.45));
    // دائرتا الشبكة
    c.drawCircle(Offset(card.right - s * 0.10, card.bottom - s * 0.07), s * 0.035, Paint()..color = Colors.white.withValues(alpha: 0.5));
    c.drawCircle(Offset(card.right - s * 0.065, card.bottom - s * 0.07), s * 0.035, Paint()..color = Colors.white.withValues(alpha: 0.3));
    c.restore();

    // درعُ الحماية بعلامةِ صح
    final k = Curves.easeOutBack.transform(_appear(0.25));
    if (k > 0) {
      final o = Offset(s * 0.72, s * 0.70);
      final r = s * 0.12 * k;
      final shield = Path()
        ..moveTo(o.dx, o.dy - r)
        ..quadraticBezierTo(o.dx + r * 0.9, o.dy - r * 0.8, o.dx + r * 0.85, o.dy - r * 0.6)
        ..quadraticBezierTo(o.dx + r * 0.85, o.dy + r * 0.6, o.dx, o.dy + r)
        ..quadraticBezierTo(o.dx - r * 0.85, o.dy + r * 0.6, o.dx - r * 0.85, o.dy - r * 0.6)
        ..quadraticBezierTo(o.dx - r * 0.9, o.dy - r * 0.8, o.dx, o.dy - r)
        ..close();
      c.drawPath(shield.shift(Offset(0, s * 0.01)), _shadow);
      c.drawPath(shield, Paint()..color = _mint);
      final check = Path()
        ..moveTo(o.dx - r * 0.38, o.dy)
        ..lineTo(o.dx - r * 0.08, o.dy + r * 0.3)
        ..lineTo(o.dx + r * 0.42, o.dy - r * 0.28);
      c.drawPath(
          check,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.022
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    // عملاتٌ ذهبيّة
    for (final (i, p) in [
      [0.24, 0.72],
      [0.31, 0.78],
    ].indexed) {
      final kk = Curves.easeOut.transform(_appear(0.35 + i * 0.12));
      if (kk <= 0) continue;
      final o = Offset(s * p[0], s * p[1] - (1 - kk) * s * 0.08);
      c.drawCircle(o, s * 0.05, Paint()..color = const Color(0xFFE8A317));
      c.drawCircle(o, s * 0.038, Paint()..color = _gold);
    }
    _sparkle(c, Offset(s * 0.22, s * 0.27), s * 0.035, _gold, 0.45);
    _sparkle(c, Offset(s * 0.82, s * 0.30), s * 0.025, _accent, 0.55);
  }

  // ── ٣. التتبّعُ الحيّ ─────────────────────────────────────────────────────
  void _tracking(Canvas c, double s) {
    final map = RRect.fromRectAndRadius(Rect.fromLTRB(s * 0.17, s * 0.20, s * 0.83, s * 0.80), Radius.circular(s * 0.06));
    c.drawRRect(map.shift(Offset(0, s * 0.015)), _shadow);
    c.drawRRect(map, Paint()..color = Colors.white);

    c.save();
    c.clipRRect(map);
    // كتلُ الأحياء
    final block = Paint()..color = const Color(0xFFF1F5F9);
    for (final r in [
      [0.20, 0.23, 0.36, 0.38],
      [0.42, 0.23, 0.80, 0.38],
      [0.20, 0.44, 0.46, 0.60],
      [0.52, 0.44, 0.80, 0.60],
      [0.20, 0.66, 0.58, 0.78],
      [0.64, 0.66, 0.80, 0.78],
    ]) {
      c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(s * r[0], s * r[1], s * r[2], s * r[3]), Radius.circular(s * 0.02)),
          block);
    }
    // حديقة
    c.drawCircle(Offset(s * 0.66, s * 0.52), s * 0.05, Paint()..color = _mint.withValues(alpha: 0.30));
    c.restore();

    // المسارُ المتقطّع يُرسَمُ بالتدريج
    final route = Path()
      ..moveTo(s * 0.28, s * 0.72)
      ..cubicTo(s * 0.32, s * 0.50, s * 0.55, s * 0.62, s * 0.58, s * 0.46)
      ..cubicTo(s * 0.60, s * 0.36, s * 0.66, s * 0.34, s * 0.68, s * 0.33);
    final metric = route.computeMetrics().first;
    final drawn = metric.length * _appear(0.1);
    final dash = Paint()
      ..color = _brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round;
    for (double d = 0; d < drawn; d += s * 0.045) {
      c.drawPath(metric.extractPath(d, math.min(d + s * 0.025, drawn)), dash);
    }

    // نقطةُ الفريق (تتحرّك على المسار)
    final pos = metric.getTangentForOffset(math.max(0.0, drawn - 0.001))?.position ?? Offset(s * 0.28, s * 0.72);
    c.drawCircle(pos, s * 0.055, Paint()..color = _accent.withValues(alpha: 0.18));
    c.drawCircle(pos, s * 0.032, Paint()..color = Colors.white);
    c.drawCircle(pos, s * 0.022, Paint()..color = _accent);

    // دبّوسُ البيت
    final k = Curves.easeOutBack.transform(_appear(0.3));
    if (k > 0) {
      final tip = Offset(s * 0.68, s * 0.40);
      final r = s * 0.075 * k;
      final head = tip - Offset(0, r * 1.9);
      final pin = Path()
        ..moveTo(tip.dx, tip.dy)
        ..cubicTo(tip.dx - r * 0.4, tip.dy - r * 0.6, head.dx - r, head.dy + r * 0.6, head.dx - r, head.dy)
        ..arcToPoint(Offset(head.dx + r, head.dy), radius: Radius.circular(r))
        ..cubicTo(head.dx + r, head.dy + r * 0.6, tip.dx + r * 0.4, tip.dy - r * 0.6, tip.dx, tip.dy)
        ..close();
      c.drawPath(pin.shift(Offset(0, s * 0.01)), _shadow);
      c.drawPath(
          pin,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_brandLight, _brand])
                .createShader(Rect.fromCircle(center: head, radius: r * 2)));
      // بيتٌ صغيرٌ داخلَ الدبّوس
      final hp = Paint()..color = Colors.white;
      final hr = r * 0.5;
      c.drawPath(
          Path()
            ..moveTo(head.dx - hr, head.dy)
            ..lineTo(head.dx, head.dy - hr * 0.85)
            ..lineTo(head.dx + hr, head.dy)
            ..close(),
          hp);
      c.drawRect(Rect.fromLTRB(head.dx - hr * 0.7, head.dy, head.dx + hr * 0.7, head.dy + hr * 0.75), hp);
    }
    _sparkle(c, Offset(s * 0.84, s * 0.18), s * 0.03, _gold, 0.5);
    _sparkle(c, Offset(s * 0.14, s * 0.30), s * 0.025, _accent, 0.6);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.t != t || old.kind != kind;
}
