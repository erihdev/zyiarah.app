// حرّاس لثلاث ثغرات صامتة أكّدها التدقيق الشامل، وشاشةٍ كانت تكذب على الإدارة.
//
// كلها من عائلة واحدة: **الواجهة تقول شيئاً والواقع شيء آخر، بلا استثناء ولا سجلّ.**
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// يزيل التعليقات قبل الفحص.
///
/// ضروري: التعليقات في هذا المشروع **تشرح ما أُزيل** («كان يقول تم إخفاء الخدمة…»)،
/// ففحص المصدر الخام يجد النصّ داخل الشرح ويسقط الحارس على نفسه — إنذار كاذب يدفع
/// المطوّر لتعطيل الحارس، فيصير أسوأ من لا شيء.
String _code(String path) {
  final src = File(path).readAsStringSync();
  final noBlock = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

void main() {
  // حارس «حوار الدفع عند الاستلام لا يحبس السائق» أُزيل مع الميزة نفسها:
  // الدفع عند الاستلام حُذف من الجذور، فلا حوار ولا رمز ولا احتمال حبس. يحرس
  // test/no_cod_test.dart ما هو أقوى: ألّا تعود الميزة إطلاقاً — بما فيها منع
  // السائق من كتابة أي حقل دفع في firestore.rules.
  //
  // (الحارس هو من أبلغ عن نفسه: أسقط نفسه برسالة «تنظيف الرمز اختفى — حدِّث
  //  الحارس» فور حذف الميزة. حارسٌ يتعفّن بصمت أسوأ من غيابه.)

  group('المحفظة تقول الحقيقة', () {
    test('الخدمة لا تبتلع خطأ الدالة الخادمية', () {
      final s = _code('lib/services/zyiarah_wallet_service.dart');
      final i = s.indexOf('Future<bool> redeemQatratPoints');
      final body = s.substring(i, s.indexOf('\n  }', i));
      expect(RegExp(r'catch\s*\([^)]*\)\s*\{\s*return false;').hasMatch(body), isFalse,
          reason: 'ابتلاع الخطأ يرمي رسالة الخادم العربية ويُظهر رسالة مخترَعة');
    });

    test('الواجهة تعرض سبب الخادم ولا تخترع «تحتاج 50 نقطة»', () {
      final s = _code('lib/screens/profile_screen.dart');
      final i = s.indexOf('Future<void> _redeemQatrat');
      final body = s.substring(i, s.indexOf('\n  Future<void> _showEditProfileDialog', i));
      expect(body.contains('on FirebaseFunctionsException'), isTrue,
          reason: 'الخادم يرمي سبباً عربياً دقيقاً — يجب عرضه لا ابتلاعه');
      expect(body.contains('e.message'), isTrue);
      expect(body.contains('تحتاج 50 نقطة على الأقل'), isFalse,
          reason: 'رسالة خاطئة: الزر لا يعمل أصلاً دون 50 نقطة، فالمستخدمة تملكها');
    });
  });

  group('منتقي الموقع لا يعلّق بصمت', () {
    final src = _code('lib/screens/location_picker_screen.dart');

    test('تحديد الموقع الابتدائي بمهلة وبحارس mounted', () {
      // ‎_setInitialLocation صارت ‎_locateMe وانتقلت المهلة إلى المُحدِّد المشترك
      // (ZyiarahZoneLocator.gpsTimeout) — نفحص الواقع لا الشكل القديم.
      final i = src.indexOf('Future<void> _locateMe(');
      expect(i, greaterThan(-1), reason: 'دالة التحديد اختفت أو أُعيدت تسميتها');
      final body = src.substring(i, src.indexOf('\n  void _onSearchChanged', i));
      expect(body.contains('ZyiarahZoneLocator.locate'), isTrue,
          reason: 'المهلة وتصنيف الأسباب في المُحدِّد المشترك — لا نسخة محلّية');
      expect(body.contains('if (!mounted) return'), isTrue,
          reason: 'setState بعد await وقد أُغلقت الشاشة يرمي');
      expect(body.contains('_isMapReady = true'), isTrue,
          reason: 'الخريطة تُعرض في كل الأحوال — التحديد اليدوي متاح دائماً');
      // المهلة نفسها مثبَّتة في zone_locator_test؛ نتأكّد هنا أنها لم تُلتَفّ محلياً.
      final locator = _code('lib/services/zone_locator_service.dart');
      expect(locator.contains('.timeout(gpsTimeout)'), isTrue,
          reason: 'بلا مهلة: GPS لا يُحسم داخل مبنى ⇒ الشاشة عالقة إلى الأبد');
    });

    test('دوّار بدل شاشة بيضاء أثناء الانتظار', () {
      expect(src.contains('if (!_isMapReady)'), isTrue,
          reason: 'كان لا يُرسَم شيء إطلاقاً ريثما يُحسم الموقع — يبدو التطبيق معلّقاً');
      expect(src.contains('جارٍ تحديد موقعك'), isTrue);
    });

    test('البحث بمهلة وبحارس mounted في مسار الخطأ', () {
      final i = src.indexOf('Future<void> _performSearch');
      final body = src.substring(i, src.indexOf('\n  void _selectSearchResult', i));
      expect(body.contains('.timeout('), isTrue);
      // كان setState داخل catch بلا حارس ⇒ استثناء ثانٍ داخل معالجة الخطأ نفسها.
      expect(RegExp(r'catch[\s\S]{0,160}if \(!mounted\) return;').hasMatch(body), isTrue,
          reason: 'setState داخل catch بلا حارس mounted يرمي استثناءً لا يلتقطه أحد');
    });
  });

  group('كتالوج الخدمات لا يكذب على الإدارة', () {
    final src = _code('lib/screens/admin/admin_services_screen.dart');

    test('لا مفتاح «إخفاء الخدمة» — لا أحد يقرأ is_active', () {
      // الشبكة المعروضة للعميلة نصوص ثابتة في الشيفرة، فالمفتاح كان يقول
      // «تم إخفاء الخدمة» والخدمة تبقى معروضة وتُطلب. مفتاح يكذب أسوأ من غيابه.
      expect(src.contains("'is_active'"), isFalse);
      expect(src.contains('تم إخفاء الخدمة'), isFalse);
      expect(src.contains('Switch('), isFalse);
    });

    test('لا تعديل تسعير — الأسعار في service_zones لكل منطقة', () {
      expect(src.contains("'base_price'"), isFalse);
      expect(src.contains("'price_text'"), isFalse);
      expect(src.contains('تعديل تسعير'), isFalse);
      expect(src.contains('التحديث الجذري'), isFalse);
    });

    test('لا شارة «الأكثر طلباً» ملفّقة', () {
      // كان شرطها title.contains("تنظيف") — لا علاقة لها بالطلبات إطلاقاً.
      expect(src.contains('الأكثر طلباً'), isFalse);
      expect(src.contains('contains("تنظيف")'), isFalse);
    });

    test('بيان صريح يقول أين تُضبط الأسعار فعلاً', () {
      expect(src.contains('نطاقات التغطية'), isTrue);
      expect(src.contains('للعرض فقط'), isTrue);
    });
  });

  // BUG-003 من ZIYARAH_QA_AUDIT: زرّ الردّ في الدعم ينادي setInternalState داخل
  // finally بعد انتظارَين شبكيَّين. إن أُغلقت البطاقة خلالهما صار عنصر
  // StatefulBuilder مُتلَفاً و«setState() called after dispose()» ينفجر في وجه
  // المستخدم. كتلة catch نالت حارسها في إصلاح سابق، وfinally بقيت بلا حارس.
  group('ردّ الدعم لا ينفجر بعد إتلاف البطاقة', () {
    final src = _code('lib/screens/support_screen.dart');

    test('إطفاء مؤشّر الإرسال محروس بـ context.mounted', () {
      const call = 'setInternalState(() => isSendingReply = false)';
      final i = src.indexOf(call);
      expect(i, greaterThan(-1),
          reason: 'بنية زرّ الردّ تغيّرت — راجع هذا الحارس، لا تحذفه');
      // النافذة تسبق النداء مباشرةً: الحارس يجب أن يلفّه لا أن يقع في مكان آخر.
      final before = src.substring((i - 120).clamp(0, i), i);
      expect(before.contains('context.mounted'), isTrue,
          reason: 'النداء يقع في finally بعد انتظارَين شبكيَّين وبلا حارس — '
              'بطاقة مُغلقة أثناءهما تعني setState() called after dispose()');
    });

    test('مسار الخطأ يُخبر المستخدم ولا يبتلع الفشل', () {
      expect(src.contains('فشل إرسال الرسالة'), isTrue,
          reason: 'فشل الإرسال صار صامتاً مجدداً');
    });
  });
}
