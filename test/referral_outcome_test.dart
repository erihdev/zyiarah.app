// حارس: **كودُ إحالةٍ لم يُطبَّق يُقال، ويُسجَّل.**
//
// `applyReferralCode` كانت `Future<void>` تبتلع كلَّ خطأٍ في `catch` وتطبع ردَّ
// الخادم بـ`debugPrint` ثمّ ترميه. والخادمُ يردّ `{ok, reason}` بثلاثة أسبابٍ
// مميَّزة — `not_found` و`self` و`already` — كانت كلُّها تذهب إلى اللاشيء.
//
// فالعميلةُ التي تُدخل كوداً خاطئاً عند التسجيل تنتظر خصمَ 10% على أوّل طلب
// ولا يأتي، ولا تعرف لماذا. ولا نعرف نحن: `debugPrint` **لا يُجمَع ولا
// يُرسَل** (قاعدةُ `reportSilent`)، والإحالةُ مالٌ — 50 ر.س للمُحيل.
//
// وشاشةُ التسجيل كانت تلفّ النداءَ بـ`try/catch` معلّقاً عليه «نتجاهله بصمت»،
// و`catch` ذاك **غيرُ قابلٍ للوصول**: الدالّةُ لا ترمي أصلاً.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/zyiarah_referral_service.dart';

void main() {
  group('النتيجةُ نوعٌ لا فراغ', () {
    test('كلُّ حالاتِ الخادم ممثَّلة', () {
      // not_found / self / already من `exports.applyReferralCode`، ومعها
      // «لا كود» و«نجح» و«تعذّر».
      expect(ReferralApplyOutcome.values.toSet(), {
        ReferralApplyOutcome.none,
        ReferralApplyOutcome.applied,
        ReferralApplyOutcome.notFound,
        ReferralApplyOutcome.ownCode,
        ReferralApplyOutcome.already,
        ReferralApplyOutcome.failed,
      });
    });

    test('الخدمةُ تُعيد النوعَ لا void', () {
      final src =
          File('lib/services/zyiarah_referral_service.dart').readAsStringSync();
      expect(src.contains('Future<ReferralApplyOutcome> applyReferralCode('),
          isTrue);
      // ترجمةُ أسباب الخادم حرفاً بحرف — تغييرُ اسمٍ هناك يسقط هنا بصمت.
      for (final r in ['not_found', 'self', 'already']) {
        expect(src.contains("'$r' =>"), isTrue, reason: 'سببٌ غيرُ مترجَم: $r');
      }
    });

    test('ولا تبتلع الفشلَ بـdebugPrint وحده', () {
      final src =
          File('lib/services/zyiarah_referral_service.dart').readAsStringSync();
      final i = src.indexOf('Future<ReferralApplyOutcome> applyReferralCode(');
      // **القوسُ المغلق على سطرٍ وحده**: `'\n  }'` وحدَها تطابق نهايةَ قائمة
      // الوسائط `\n  }) async {` فتقتطع الجسمَ قبل أن يبدأ — وقع ذلك فعلاً.
      final body = src.substring(i, src.indexOf('\n  }\n', i));
      expect(body.contains("reason: 'referral_apply_failed'"), isTrue,
          reason: 'مسارٌ يمسّ المال بلا أثرٍ في Crashlytics');
      expect(body.contains('debugPrint'), isFalse,
          reason: 'debugPrint لا يُجمَع — كان هو كلَّ ما يُسجَّل');
    });
  });

  group('شاشةُ التسجيل تقول النتيجة', () {
    final src = File('lib/screens/signup_screen.dart').readAsStringSync();

    test('تقرأ النتيجةَ ولا تلفُّ النداءَ بـcatch ميّت', () {
      expect(src.contains('var referral = ReferralApplyOutcome.none;'), isTrue);
      expect(src.contains('catch (_) {/* إحالة غير صالحة'), isFalse,
          reason: 'عاد الـcatch غيرُ القابل للوصول');
    });

    test('وتعرض حواراً لا شريطَ إشعار', () {
      // الشاشةُ تنتقل في السطر التالي، والشريطُ يختفي مع الانتقال فلا يُقرأ.
      final i = src.indexOf('referral != ReferralApplyOutcome.applied');
      expect(i, greaterThan(0));
      expect(src.substring(i, i + 400).contains('showDialog'), isTrue);
    });

    test('لكلِّ سببٍ نصُّه، والحسابُ يبقى منشأً', () {
      expect(src.contains('تم إنشاء حسابك ✅'), isTrue,
          reason: 'الرسالةُ يجب ألّا تقرأ كفشلِ تسجيل');
      expect(src.contains('غير صحيح، فلم يُطبَّق'), isTrue);
      expect(src.contains('لا يمكن إحالةُ النفس'), isTrue);
      expect(src.contains('مرتبطٌ بإحالةٍ سابقة'), isTrue);
      expect(src.contains('تواصلي مع الدعم'), isTrue);
    });

    test('ولا حوارَ حين لا كودَ أصلاً أو حين طُبِّق', () {
      expect(src.contains('referral != ReferralApplyOutcome.none &&'), isTrue);
    });
  });
}
