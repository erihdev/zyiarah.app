// حرّاس لثلاث ثغرات صامتة أكّدها التدقيق الشامل، وشاشةٍ كانت تكذب على الإدارة.
//
// كلها من عائلة واحدة: **الواجهة تقول شيئاً والواقع شيء آخر، بلا استثناء ولا سجلّ.**
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/sources_in.dart';

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
      // صارت تُعيد `QatratRedeemResult?` لا `bool`: الشاشةُ كانت تَحسبُ المبلغَ
      // المعروضَ بنفسِها وتُهمل `newBalance` الذي يُعيدُه الخادم. القرارُ
      // المحروسُ هنا لم يتغيّر — **لا ابتلاعَ لرسالةِ الخادمِ العربيّة** —
      // فنُعيد توجيهَ الحارسِ ونُوسّعه: `return null` داخلَ `catch` هو ابتلاعُ
      // الشكلِ الجديد، تماماً كما كان `return false`.
      final i = s.indexOf('Future<QatratRedeemResult?> redeemQatratPoints');
      expect(i, greaterThan(-1),
          reason: 'توقيعُ الدالّةِ تغيّر — راجِع ما يَحرسُه هذا الفحص');
      final body = s.substring(i, s.indexOf('\n  }', i));
      for (final swallow in ['return false;', 'return null;']) {
        expect(
            RegExp('catch\\s*\\([^)]*\\)\\s*\\{\\s*${RegExp.escape(swallow)}')
                .hasMatch(body),
            isFalse,
            reason: 'ابتلاع الخطأ يرمي رسالة الخادم العربية ويُظهر رسالة مخترَعة');
      }
    });

    test('الواجهة تعرض سبب الخادم ولا تخترع «تحتاج 50 نقطة»', () {
      final s = _code('lib/screens/profile_screen.dart');
      final i = s.indexOf('Future<void> _redeemQatrat');
      final body = s.substring(i, s.indexOf('\n  Future<void> _showEditProfileDialog', i));
      expect(body.contains('on FirebaseFunctionsException'), isTrue,
          reason: 'الخادم يرمي سبباً عربياً دقيقاً — يجب عرضه لا ابتلاعه');
      // **كان هذا الفحصُ يَشدُّ `e.message` هنا — أي الصيغةَ الأضعفَ (2026-10-07).**
      // `e.message ??` بلا فحصِ عربيّةٍ يَطبعُ رسالةَ المنصّةِ الإنجليزيّةَ
      // (`internal`، `DEADLINE_EXCEEDED`) خامّةً في شريطٍ عربيّ — وهو عطلٌ
      // له حارسُه في `net_timeout_guard_test`. فكان الحارسُ **يُقاومُ**
      // التشديد. والمشدودُ الآن أنّ الفرعَ يَبلغُ القرارَ، وأنّ القرارَ
      // يَقرأُ الرسالةَ — فالعرضُ قائمٌ والتسريبُ مسدود.
      expect(RegExp(r'\buserFacingError\s*\(').hasMatch(body), isTrue,
          reason: 'سببُ الخادمِ يُعرَضُ عبرَ القرارِ الواحد');
      expect(_code('lib/utils/user_facing_error.dart').contains('error.message'),
          isTrue);
      expect(body.contains('e.message'), isFalse,
          reason: 'قراءةٌ خامّةٌ بلا فحصِ عربيّةٍ تُسرّبُ نصَّ المنصّة');
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

  // **أُعيد توجيهُ هذه المجموعةِ لا إسكاتُها (2026-10-11).** كانت تَحرُسُ
  // `admin_services_screen` من ثلاثِ دعاوى كاذبة (مفتاحُ إخفاءٍ لا يَقرؤه أحد،
  // وتعديلُ تسعيرٍ على مجموعةٍ لا تُقرأ، وشارةٌ مُلفَّقة) — وبعدَ نزعِها لم يَبقَ
  // في الشاشةِ إلّا بيانٌ يقول «هذه القائمة للعرض فقط». فحُذفت الشاشةُ وتبويبُها
  // من لوحةِ الإدارة: تبويبٌ كاملٌ لقائمةٍ لا أثرَ لها. والحقيقةُ التي كانت
  // تَحرُسُها باقيةٌ وتُشَدُّ هنا: مجموعةُ `services` لا يَقرؤها تطبيقُ العميلة،
  // فأيُّ شاشةٍ تعودُ إليها تُعيدُ الكذبةَ نفسَها.
  group('كتالوج الخدمات الميّت لا يعود', () {
    test('لا شاشةَ ولا تبويبَ للكتالوج', () {
      expect(File('lib/screens/admin/admin_services_screen.dart').existsSync(),
          isFalse);
      expect(
          _code('lib/screens/admin/admin_dashboard_screen.dart')
              .contains('AdminServicesScreen'),
          isFalse);
    });

    test('لا موضعَ في lib يَقرأ أو يَكتبُ مجموعةَ services', () {
      final hits = <String>[];
      // أرضيّةٌ: فحصٌ سالبٌ على مسحٍ انحلَّ يَمُرُّ أخضرَ على لا شيء.
      for (final f in sourcesIn('lib', atLeast: 150)) {
        if (RegExp(r"""collection\(\s*['"]services['"]\s*\)""")
            .hasMatch(_code(f.path))) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty,
          reason: 'مجموعةُ services لا يَقرؤها تطبيقُ العميلة — الأسعارُ '
              'والتفعيلُ في service_zones');
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
