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

const _picker = 'lib/screens/location_picker_screen.dart';

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

    test('الرفض الدائم لا يقبل إعادة محاولة عقيمة', () {
      expect(LocateFailure.permissionDeniedForever.canRetry, isFalse,
          reason: 'طلب الإذن لا يظهر بعد الرفض الدائم — إعادة المحاولة تفشل صامتة');
    });

    test('لا زرّ «إعدادات» على الويب — Geolocator.openAppSettings لا وجود لها هناك', () {
      // الاختبارات تعمل بمنصّة VM (kIsWeb=false)، فنفحص المصدر: الزر يجب أن يكون
      // محكوماً بـ !kIsWeb، والرسالة على الويب تشرح رفع الحظر من شريط العنوان.
      final s = _code('lib/services/zone_locator_service.dart');
      expect(s.contains('!kIsWeb && this == LocateFailure.permissionDeniedForever'), isTrue,
          reason: 'زرّ يستدعي openAppSettings في المتصفّح = زرّ ميت يبدو حلّاً');
      expect(s.contains('شريط') && s.contains('العنوان'), isTrue,
          reason: 'على الويب يُرفع الحظر من شريط العنوان لا من إعدادات تطبيق');
      final open = s.substring(s.indexOf('static Future<bool> openSettings'));
      expect(open.contains('if (kIsWeb)'), isTrue,
          reason: 'حارس صريح: الاستدعاء على الويب يرمي UnimplementedError');
    });

    test('needsSettings صحيح على الجوال (المنصّة الحقيقية للتطبيق)', () {
      // kIsWeb=false في بيئة الاختبار — أي أن هذا يؤكّد سلوك iOS/Android.
      expect(LocateFailure.permissionDeniedForever.needsSettings, isTrue);
      for (final f in LocateFailure.values) {
        if (f == LocateFailure.permissionDeniedForever) continue;
        expect(f.needsSettings, isFalse, reason: '$f لا يحتاج الإعدادات');
      }
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

  group('منتقي الخريطة: الدبوس عند المستخدم، ولا سقوط صامت على الرياض', () {
    test('يستعمل المُحدِّد المشترك لا Geolocator مباشرةً', () {
      final s = _code(_picker);
      expect(s.contains('ZyiarahZoneLocator.locate'), isTrue);
      expect(s.contains('Geolocator.'), isFalse);
    });

    test('زرّ «موقعي» موجود ويطلب الإذن صراحةً', () {
      // كان غائباً: إن فشل التحديد مرّة فلا سبيل لإعادة المحاولة بعد منح الإذن.
      final s = _code(_picker);
      expect(s.contains('locate_me_fab'), isTrue);
      expect(s.contains('_locateMe(userInitiated: true)'), isTrue);
    });

    test('يُعرض سبب بقاء الدبوس على الافتراضي', () {
      final s = _code(_picker);
      expect(s.contains('_locateFailure'), isTrue,
          reason: 'خريطة الرياض لمستخدم في جازان بلا سبب = يبدو عطلاً عشوائياً');
      expect(s.contains('_locateFailure!.message'), isTrue);
    });

    test('حارس الموقع الافتراضي باقٍ — لا يُرسَل الفريق لمدينة خاطئة', () {
      final s = _code(_picker);
      expect(s.contains('if (!_userSelected)'), isTrue,
          reason: 'تأكيد الرياض بصمت لمستخدم في جازان = فريق يصل لمدينة أخرى');
    });
  });
}
