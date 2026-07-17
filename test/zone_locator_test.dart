// حارس: التحديد التلقائي **لا يفشل بصمت**، ومنطقه مصدر واحد لا ثلاث نسخ.
//
// ما رآه المالك: «لم يُحدَّد موقعك بعد — اختره من الزر بالأسفل» بلا أي سبب. وكل
// مسارات الفشل في _attemptAutoLocation كانت `return;` صامتة أو
// `catch { /* Silent error */ }` — فلا العميلة تعرف السبب ولا نحن نجده في سجلّ.
// أخدمة الموقع مطفأة؟ أم الإذن مرفوض؟ أم GPS لم يستجب (بلا مهلة أصلاً)؟ رسالة
// واحدة تصلح لكل شيء = لا تدلّ على شيء.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

const _screens = [
  'lib/screens/hourly_details_screen.dart',
  'lib/screens/sofa_rug_details_screen.dart',
  'lib/screens/ac_service_details_screen.dart',
];

void main() {
  group('لكل سبب رسالة وإجراء', () {
    test('كل حالات الفشل لها رسالة غير فارغة ومميّزة', () {
      final msgs = LocateFailure.values.map((f) => f.message).toList();
      for (final m in msgs) {
        expect(m.trim().isNotEmpty, isTrue);
      }
      expect(msgs.toSet().length, msgs.length,
          reason: 'رسالتان متطابقتان لسببين مختلفين = العميلة لا تعرف ما تفعل');
    });

    test('الرفض الدائم يقود للإعدادات لا لإعادة محاولة عقيمة', () {
      expect(LocateFailure.permissionDeniedForever.needsSettings, isTrue);
      expect(LocateFailure.permissionDeniedForever.canRetry, isFalse,
          reason: 'طلب الإذن لا يظهر بعد الرفض الدائم — إعادة المحاولة تفشل صامتة');
    });

    test('بقية الأسباب قابلة لإعادة المحاولة', () {
      for (final f in LocateFailure.values) {
        if (f == LocateFailure.permissionDeniedForever) continue;
        expect(f.canRetry, isTrue, reason: '$f يجب أن يقبل إعادة المحاولة');
      }
    });
  });

  group('المصدر: لا صمت ولا تكرار', () {
    test('GPS بمهلة — كان ينتظر بلا نهاية داخل المبنى', () {
      final s = _code('lib/services/zone_locator_service.dart');
      expect(s.contains('.timeout(gpsTimeout)'), isTrue);
      expect(ZyiarahZoneLocator.gpsTimeout.inSeconds, greaterThan(0));
    });

    test('لا catch صامت في خدمة التحديد', () {
      final s = _code('lib/services/zone_locator_service.dart');
      expect(RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}').hasMatch(s), isFalse);
      expect(s.contains('debugPrint'), isTrue, reason: 'الفشل يجب أن يصل السجلّ');
    });

    test('الشاشات الثلاث لا تستدعي Geolocator مباشرةً', () {
      for (final p in _screens) {
        final s = _code(p);
        expect(s.contains('Geolocator.'), isFalse,
            reason: '$p ينسخ منطق الموقع بدل استعمال المصدر المشترك — '
                'التكرار هو ما أنتج نظامَي تسعير وحسابَي سعة في هذا المشروع');
      }
    });

    test('الشاشات الثلاث تستعمل الخدمة والبطاقة المشتركتين', () {
      for (final p in _screens) {
        final s = _code(p);
        expect(s.contains('ZyiarahZoneLocator.locate'), isTrue, reason: p);
        expect(s.contains('ZyiarahZoneLocationCard'), isTrue, reason: p);
        expect(s.contains('_locateFailure'), isTrue,
            reason: '$p لا يحتفظ بالسبب ⇒ سيعرض رسالة عامة كالسابق');
      }
    });

    test('لا شاشة تعرض «لم يُحدَّد موقعك» كسبب وحيد لكل الأعطال', () {
      for (final p in _screens) {
        final s = _code(p);
        expect(s.contains('اختره من الزر بالأسفل'), isFalse,
            reason: '$p ما زال يعرض رسالة واحدة لكل الأسباب');
      }
    });

    test('زرّ «حدّد موقعي تلقائياً» يطلب الإذن صراحةً', () {
      for (final p in _screens) {
        final s = _code(p);
        expect(s.contains('userInitiated: true'), isTrue,
            reason: '$p: بدون طلب صريح لن يظهر مربّع الإذن بعد رفض سابق');
      }
    });
  });
}
