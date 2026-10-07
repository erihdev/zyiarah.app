// حارسٌ دائم: **سببُ الخادمِ العربيُّ يَصِلُها، والنصُّ اللاتينيُّ لا يُسرَّب.**
//
// `payWithWallet` يَرمي سبعةَ أسبابٍ عربيّةٍ مكتوبةٍ لها، و`payContractWithWallet`
// ستّةً، و`redeemQatratPoints` ثلاثةً — وكان `GlobalErrorHandler.handleError`
// (ثلاثُ شاشاتٍ عميليّةٍ تَصُبُّ فيه، منها شاشةُ الدفع) يُطابِقُ ثلاثَ كلماتٍ
// في `toString()` **ويَطرحُ `message` كلَّه**، فتَقرأُ العميلةُ «حدث خطأ غير
// متوقع. يُرجى المحاولة مرة أخرى» عن «الرصيد غير كافٍ» — ونصيحةُ الإعادةِ هناك
// **خاطئةٌ**: إعادةُ المحاولةِ بالرصيدِ نفسِه تَفشلُ فشلاً مطابقاً أبداً.
//
// والقاعدةُ كانت مقرَّرةً ومُنفَّذةً في سطحَين من خمسة (`tamara_service` بأدقِّ
// صياغةٍ، وفرعُ القطراتِ ناقصاً بلا فحصِ عربيّة) — نمطُ «قاعدةٌ عامّةٌ مُنفَّذةٌ
// في سطحٍ واحد» المسجَّلُ في هذا المشروعِ مرّاتٍ.
//
// الفحوصُ: سلوكُ القاعدةِ أوّلاً (نقيّةٌ فتُختبَرُ بلا Firebase)، ثمّ أنّ كلَّ
// سطحٍ يُنادِيها ولا يَحملُ نسخةً، ثمّ **شواهدُ التعليلِ الخادميّة** — فلو زالت
// رسائلُ الخادمِ العربيّةُ يُراجَعُ التعليلُ لا يُسكَت.
import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/services/moyasar_service.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/utils/user_facing_error.dart';

String _read(String p) => File(p).readAsStringSync();

/// المُنشئُ في الحزمةِ `@protected` (تحذيرُ مُحلِّلٍ لا منعُ ترجمة)، فيُبنى من
/// فرعٍ واحدٍ هنا بدلَ تكرارِ التجاهلِ في كلِّ فحص.
class _Fx extends FirebaseFunctionsException {
  // ignore: invalid_use_of_protected_member
  _Fx(String code, String message) : super(code: code, message: message);
}

/// يَحجبُ أسطرَ التعليقِ قبلَ المسح: التعليقاتُ أدناه تَقتبسُ كلَّ نصٍّ
/// ممنوعٍ لتَشرحَ زوالَه، فالمسحُ على الخامِّ يَسقطُ على توثيقِه.
String _code(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

void main() {
  group('سببُ الخادمِ يَصِلُها (سلوك)', () {
    test('(أ) رسالةُ `HttpsError` العربيّةُ تُعرَضُ كما هي', () {
      // السبعةُ التي يَرميها `payWithWallet`، والثلاثةُ من استبدالِ القطرات.
      for (final m in const [
        'يجب تسجيل الدخول أولاً',
        'المبلغ غير صالح',
        'المبلغ لا يطابق السعر المعتمد لمنطقتك',
        'الطلب غير موجود',
        'لا يمكن الدفع لطلب مستخدم آخر',
        'المبلغ لا يطابق مبلغ الطلب',
        'الرصيد غير كافٍ',
        'نقاطك غير كافية',
        'الحد الأدنى للاستبدال 50 نقطة',
      ]) {
        expect(userFacingError(_Fx('failed-precondition', m)), m,
            reason: 'الخادمُ وحدَه يَعرفُ لماذا — ولا يُطرَحُ ما كتبَه');
      }
    });

    test('(ب) سببُ الخادمِ يَسبقُ التصنيفَ بالرمز', () {
      // `permission-denied` يَحملُ سبباً أدقَّ من «ليس لديك الصلاحية»، وكان
      // التصنيفُ بالرمزِ (مطابقةُ `toString()`) يَغلِبُه.
      expect(userFacingError(_Fx('permission-denied', 'لا يمكن الدفع لطلب مستخدم آخر')),
          'لا يمكن الدفع لطلب مستخدم آخر');
      // وبلا رسالةٍ عربيّةٍ يَبقى التصنيفُ عاملاً.
      expect(userFacingError(_Fx('permission-denied', 'PERMISSION_DENIED')),
          contains('الصلاحية'));
    });

    test('(ج) رسالةُ المنصّةِ الإنجليزيّةُ لا تُسرَّب', () {
      // «[firebase_functions/internal] internal» في شريطٍ عربيٍّ عطلٌ مسجَّلٌ
      // وله حارسُه — فشرطُ العربيّةِ ليس تزيّداً.
      for (final m in const ['internal', 'DEADLINE_EXCEEDED', 'unknown error']) {
        final out = userFacingError(_Fx('internal', m));
        expect(out, isNot(contains(m)));
        expect(RegExp(r'[A-Za-z]').hasMatch(out), isFalse,
            reason: 'لا حرفَ لاتينيٍّ في واجهةٍ عربيّة: $out');
      }
    });

    test('(د) حاملٌ يُعلِنُ جملتَه تُعرَضُ، وتشخيصُه لا', () {
      const f = MoyasarPayFailure('خدمة الدفع غير مُهيأة — يرجى التواصل مع الدعم',
          detail: 'declined: insufficient funds on card');
      expect(userFacingError(f), 'خدمة الدفع غير مُهيأة — يرجى التواصل مع الدعم');
      expect(userFacingError(f), isNot(contains('declined')));
      expect(userFacingError(const TamaraCheckoutFailure('بيانات الطلب ناقصة')),
          'بيانات الطلب ناقصة');
    });

    test('(ه) المهلةُ والمقبسُ يُقرآنِ انقطاعَ شبكةٍ لا «خطأً غير متوقع»', () {
      // `kNetCallTimeout` و`firstEventTimeout` حوّلت التعليقَ الأبديَّ إلى
      // `TimeoutException` — ونصُّها لا يَحملُ «network» ولا «unavailable»،
      // فكانت تَقعُ على الجملةِ العامّةِ بينما السببُ تَعرفُ العميلةُ علاجَه.
      expect(userFacingError(TimeoutException('x', const Duration(seconds: 20))),
          kNetworkErrorMessage);
      expect(
          userFacingError(const SocketException(
              'Failed host lookup: firestore.googleapis.com')),
          kNetworkErrorMessage);
      expect(userFacingError(_Fx('unavailable', 'unavailable')),
          contains('الخادم'));
    });

    test('(و) ليس كلُّ نصٍّ عربيٍّ جملةً لها', () {
      // `store_service` يَرمي «المنتج غير موجود في قاعدة البيانات: <id>» —
      // عربيٌّ، ويَحملُ معرّفَ مستندٍ واسمَ قاعدةِ بياناتٍ لا معنى لهما عندها.
      // فالقاعدةُ بالحاملِ لا باللغة.
      const leaky = 'المنتج غير موجود في قاعدة البيانات: aX9bQ2';
      expect(userFacingError(Exception(leaky)), isNot(contains('aX9bQ2')));
      expect(userFacingError(Exception(leaky)), kGenericErrorMessage);
      // وشاهدُ التعليلِ: الاستثناءُ ما زال كما هو في الخدمة.
      expect(_read('lib/services/store_service.dart'),
          contains('المنتج غير موجود في قاعدة البيانات'));
    });

    test('(ز) الاحتياطيُّ يُبدِلُ العامّةَ وحدَها', () {
      const gw = 'تعذّر بدء الدفع بالتقسيط';
      expect(userFacingError(Exception('x'), fallback: gw), gw);
      // ولا يَغلِبُ تصنيفاً صادقاً ولا سببَ خادم.
      expect(userFacingError(_Fx('unavailable', 'unavailable'), fallback: gw),
          contains('الخادم'));
      expect(userFacingError(_Fx('x', 'الرصيد غير كافٍ'), fallback: gw),
          'الرصيد غير كافٍ');
    });
  });

  group('كلُّ سطحٍ يُنادِي القاعدةَ ولا يَحملُ نسخةً', () {
    test('(ح) المُعالِجُ العامُّ يُنادِيها ولا يُطابِقُ نصّاً بنفسِه', () {
      final h = _code(_read('lib/utils/global_error_handler.dart'));
      expect(RegExp(r'\buserFacingError\s*\(').hasMatch(h), isTrue,
          reason: 'ثلاثُ شاشاتٍ عميليّةٍ تَصُبُّ فيه');
      // **قدرةٌ لا اسم:** حضورُ النداءِ لا يَمنعُ نسخةً إلى جانبِه.
      for (final gone in const [
        'contains("network")',
        'contains("offline")',
        'contains("unavailable")',
        'contains("permission-denied")',
      ]) {
        expect(h.contains(gone), isFalse,
            reason: 'التصنيفُ في القاعدةِ لا هنا: $gone');
      }
      expect(h.contains('حدث خطأ غير متوقع'), isFalse,
          reason: 'الجملةُ العامّةُ ثابتٌ في القاعدة (kGenericErrorMessage)');
    });

    test('(ط) كلُّ مُعالِجِ `FirebaseFunctionsException` عميليٍّ يُنادِيها', () {
      // النطاقُ **مُشتَقٌّ**: شاشاتُ الإدارةِ مُستثناةٌ بقرارٍ مسجَّلٍ (النصُّ
      // الخامُّ تشخيصٌ يُريدُه المالك)، وما عداها جمهورُه العميلة.
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final List<String> client = [];
      final List<String> admin = [];
      for (final f in files) {
        final src = _code(f.readAsStringSync());
        if (!src.contains('on FirebaseFunctionsException')) continue;
        (f.path.contains('/admin/') ? admin : client).add(f.path);
      }
      expect(client.length + admin.length, greaterThanOrEqualTo(4),
          reason: 'انهارَ المسح');
      for (final p in client) {
        expect(RegExp(r'\buserFacingError\s*\(').hasMatch(_code(_read(p))),
            isTrue,
            reason: '$p يَلتقطُ سببَ الخادمِ ولا يُمرِّرُه بالقاعدة');
      }
      expect(client, ['lib/screens/profile_screen.dart', 'lib/services/tamara_service.dart'],
          reason: 'مُعالِجٌ عميليٌّ جديدٌ يُراجَعُ بدلَ أن يَطرحَ سببَ الخادم');
    });

    test('(ي) خدمةُ تمارا تَرمي حاملاً موسوماً لا نصّاً', () {
      final t = _code(_read('lib/services/tamara_service.dart'));
      expect(t, contains('throw TamaraCheckoutFailure('));
      expect(RegExp(r'\buserFacingError\s*\(').hasMatch(t), isTrue);
      // النسخةُ المكتوبةُ بيدٍ زالت — وكانت تُطرَحُ عند المُنادِيَين كليهما.
      expect(t.contains(r'[ء-ي]'), isFalse,
          reason: 'فحصُ العربيّةِ في القاعدةِ مرّةً واحدة');
      expect(t.contains('throw Exception('), isFalse,
          reason: 'نصٌّ عارٍ لا يُميّزُه المُنادي عن استثناءٍ تشخيصيّ');
      // و`MoyasarPayFailure` تُعلِنُ العقدَ نفسَه.
      expect(_code(_read('lib/services/moyasar_service.dart')),
          contains('class MoyasarPayFailure implements UserFacingFailure'));
    });

    test('(ك) الثلاثةُ التي كانت تَطرحُ السببَ بنفسِها', () {
      // فرعُ تمارا في دفعِ المتجرِ: كان يَطبعُ احتياطيَّه **أيّاً كان** ما قالَه
      // الخادم، فلا يُغني عنه بلوغُ `GlobalErrorHandler` (لا يَمُرُّ به أصلاً).
      final sp = _code(_read('lib/screens/store_payment_screen.dart'));
      expect(RegExp(r'\buserFacingError\s*\(').hasMatch(sp), isTrue);
      expect(
          sp.contains(
              "const SnackBar(content: Text('تعذّر بدء الدفع بالتقسيط"),
          isFalse,
          reason: 'كان ثابتاً يَطرحُ سببَ الخادم');

      // ونهايةُ «لا رابطَ» في ملخّصِ الدفع: كانت `Exception` عارياً فتَقعُ على
      // الجملةِ العامّةِ عبرَ المُعالِج.
      final ps = _code(_read('lib/screens/payment_summary_screen.dart'));
      expect(ps, contains('throw const TamaraCheckoutFailure('));
      expect(ps.contains("throw Exception('خطأ في بدء جلسة تمارا')"), isFalse);

      // واستبدالُ القطرات: كان `e.message ??` بلا فحصِ عربيّة.
      final pr = _code(_read('lib/screens/profile_screen.dart'));
      expect(pr.contains('e.message ??'), isFalse,
          reason: 'رسالةُ منصّةٍ إنجليزيّةٌ كانت تُطبَعُ خامّةً');
      expect(pr, contains("userFacingError(e, fallback: 'تعذّر الاستبدال"));
    });
  });

  group('شواهدُ التعليلِ الخادميّة', () {
    test('(ل) الخادمُ ما زال يَكتبُ أسبابَه بالعربيّةِ لها', () {
      final idx = _read('functions/index.js');
      for (final m in const [
        'الرصيد غير كافٍ',
        'المبلغ لا يطابق السعر المعتمد لمنطقتك',
        'لا يمكن الدفع لطلب مستخدم آخر',
        'نقاطك غير كافية',
      ]) {
        expect(idx, contains(m),
            reason: 'لو زالت أسبابُ الخادمِ العربيّةُ فالقاعدةُ تُراجَعُ — '
                'لا تُسكَتُ: لم يَبقَ ما يُعرَضُ لها');
      }
    });

    test('(م) حاجبُ التعليقاتِ حاملٌ لا زينة', () {
      // كلُّ نصٍّ ممنوعٍ أعلاه مُقتبَسٌ في تعليقٍ يَشرحُ زوالَه، فبلا الحجبِ
      // يَسقطُ الحارسُ على توثيقِه — والمضادَّةُ تُثبِتُ أنّ الاقتباسَ باقٍ.
      final rawH = _read('lib/utils/global_error_handler.dart');
      expect(rawH, contains('حدث خطأ غير متوقع'),
          reason: 'شرحُ العطلِ يَذكرُ الجملةَ — والمسحُ على المُجرَّد');
      expect(_code(rawH).contains('حدث خطأ غير متوقع'), isFalse);

      final rawT = _read('lib/services/tamara_service.dart');
      expect(rawT, contains('Exception('),
          reason: 'التعليقُ يَذكرُ `Exception(نصٍّ)` شارحاً زوالَه');
    });
  });
}
