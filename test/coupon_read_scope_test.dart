import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/stream_combine.dart';

/// **كلُّ كودِ خصمٍ في المستودعِ كان مقروءاً لكلِّ عميلةٍ مسجَّلة (2026-10-05).**
///
/// قاعدةُ `promo_codes` كانت `allow read: if isLoggedIn()`، والتحقّقُ من
/// الكودِ يَجري **في العميل** (`order_service.validateCoupon` تَستعلمُ
/// المجموعةَ بالكود). فأيُّ عميلةٍ مسجَّلةٍ تَقرأُ كلَّ كودِ خصمٍ من الـSDK،
/// ومنها ما وسَمَته الإدارةُ `show_in_offers: false` بعينِه — وتعليقُ
/// `PromoCoupon` يَقولُ غرضَ ذلك الحقلِ نصّاً: «الغيابُ = لا، كي لا يُكشَفَ
/// كودُ قناةٍ خاصّة (شريك/مؤثّر) لعمومِ العملاء». قرارٌ مُنفَّذٌ في الواجهةِ
/// وحدَها، والبياناتُ مكشوفةٌ خلفَها. وسِرّيّةُ الكودِ هي كلُّ ما يَحرسُه.
///
/// **وادّعاءٌ ثانٍ كان كاذباً**: ترويسةُ `couponProblem` في
/// `functions/coupons.js` تَقول إنّها «تُطابقُ حرفيّاً ما يَفحصه
/// `order_service.validateCoupon` في العميل… **جهةٌ واحدةٌ تَقرّرُ والطرفانِ
/// يَسألانها**». ولم يَسألْها العميلُ قطّ: كانت نسخةً مكتوبةً بيدٍ بلغةٍ
/// أخرى — و**مختلفةً**: مُرشِّحُ `where('status','==','active')` يَحجبُ
/// مستنداً قديماً بلا `status`، بينما الخادمُ يَقبلُ غيابَه ويَقولُ عن
/// نفسِه «نفسُ تسامحِ العميل».
void main() {
  String read(String p) => File(p).readAsStringSync();
  String codeOnly(String p) => read(p)
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
      })
      .join('\n');

  group('التحقّقُ خادميٌّ ولا نسخةَ عميليّة', () {
    final String svc = codeOnly('lib/services/order_service.dart');

    test('العميلُ يُنادي الدالّةَ ولا يَستعلمُ المجموعةَ بالكود', () {
      expect(svc.contains("httpsCallable('validateCouponCode')"), isTrue,
          reason: 'لا نداءَ خادميّاً — فالنسخةُ العميليّةُ عادت');
      expect(svc.contains("collection('promo_codes')"), isFalse,
          reason: 'قراءةُ المجموعةِ من العميلِ هي الثغرةُ نفسُها');
      expect(svc.contains("where('code'"), isFalse);
      // والمضادّة: شرحُ الإزالةِ ما زال في الخامِّ (الفحصُ يَقرأُ المُجرَّد).
      expect(read('lib/services/order_service.dart')
          .contains("where('status','==','active')"), isTrue,
          reason: 'اختفى اقتباسُ المُرشِّحِ القديمِ من التوثيق');
    });

    test('ولا نسخةَ ثانيةً للشروطِ الستّةِ في العميل', () {
      for (final f in const [
        'target_user_id',
        'restricted_zones',
        'maxUses',
      ]) {
        expect(svc.contains(f), isFalse,
            reason: '$f يُفحَصُ في العميلِ مرّةً أخرى — والقاعدةُ في الخادم');
      }
    });

    test('والدالّةُ الخادميّةُ تَسألُ القاعدةَ الواحدةَ ولا تُعيدُ كتابتَها', () {
      final idx = codeOnly('functions/index.js');
      final i = idx.indexOf('exports.validateCouponCode');
      expect(i, greaterThan(-1), reason: 'الدالّةُ اختفت');
      final body = idx.substring(i, idx.indexOf('\nexports.', i + 10));
      expect(body.contains('coupons.couponProblem('), isTrue,
          reason: 'نسخةٌ ثالثةٌ من القاعدةِ داخلَ index.js');
      expect(body.contains('if (!request.auth)'), isTrue,
          reason: 'بلا مصادقةٍ يَقرأُ أيُّ أحدٍ أيَّ كود');
      // ولا مُرشِّحَ حالةٍ في الاستعلام: التسامحُ مع غيابِ `status` قرارُ
      // `couponProblem` وحدَها، وإقحامُه يُعيدُ الافتراقَ الذي أُزيل.
      expect(body.contains('.where("status"'), isFalse,
          reason: 'عادَ مُرشِّحُ الحالةِ فعادَ الافتراق');
      // ويُعيدُ حقولَ العرضِ لا المستندَ كلَّه.
      expect(body.contains('coupon: {'), isTrue);
      for (final secret in const ['uses:', 'target_user_id:']) {
        expect(body.contains(secret), isFalse,
            reason: 'حقلٌ لا شأنَ للعميلِ به يُعاد');
      }
    });

    test('وسقفُ max_discount يُطبَّقُ في الشاشةِ كما يُطبّقُه الخادم', () {
      // `couponDiscount` تُطبّقه، والشاشةُ كانت تَتجاهله — فتَعرضُ خصماً
      // أكبرَ ثمّ `trustedDiscount` تَأخذُ الأصغر، فيَصيرُ
      // `discount_amount` على الطلبِ أكبرَ من المحسوبِ ويَنخفضُ `ratio`.
      final pay = codeOnly('lib/screens/payment_summary_screen.dart');
      expect(pay.contains("couponData['max_discount']"), isTrue,
          reason: 'السقفُ مُتجاهَلٌ في العميل — ويُطبّقه الخادم');
      expect(codeOnly('functions/coupons.js').contains('coupon.max_discount'),
          isTrue, reason: 'لو زالَ من الخادمِ فالشاشةُ تُطبّقُ سقفاً وحدَها');
    });

    test('وسببُ الرفضِ يُقالُ لا رسالةٌ واحدةٌ لكلِّ سبب', () {
      final pay = codeOnly('lib/screens/payment_summary_screen.dart');
      expect(pay.contains('kCouponRejectReasons[result.reason]'), isTrue,
          reason: 'كوبونٌ محصورٌ بمنطقةٍ أخرى يُقرأُ «كود خاطئ»');
    });
  });

  group('شاشةُ العروضِ تَستعلمُ ما تُثبِتُه القاعدة', () {
    final String off = codeOnly('lib/screens/offers_screen.dart');

    test('استعلامانِ: المُعلَنُ، والموجَّهُ إليها', () {
      expect(off.contains("where('show_in_offers', isEqualTo: true)"), isTrue);
      expect(off.contains("where('target_user_id', isEqualTo: uid)"), isTrue);
      // ولا استعلامٌ يَقرأُ المجموعةَ كلَّها بـ`status` وحدَها.
      expect(off.contains("where('status', isEqualTo: 'active')"), isFalse,
          reason: 'الاستعلامُ القديمُ يَقرأُ كلَّ كوبونٍ نشط');
    });

    test('والدمجُ «آخرُ ما وصلَ من كلٍّ» لا مناوبةً', () {
      expect(off.contains('combineLatestById<PromoCoupon>('), isTrue);
      expect(off.contains('.firstEventTimeout()'), isTrue,
          reason: 'بثٌّ بذاكرةٍ باردةٍ لا يَرمي — يَنتظرُ للأبد');
    });

    test('والترشيحُ المحلّيُّ يَبقى: هو عن العرضِ لا عن الصلاحيّة', () {
      expect(codeOnly('lib/models/promo_coupon.dart')
          .contains('bool isListableFor('), isTrue);
      // وتعليقُ القرارِ الذي كانت القاعدةُ تُبطِله ما زال في الخامّ.
      expect(read('lib/models/promo_coupon.dart').contains('كود قناةٍ'), isTrue,
          reason: 'اختفى نصُّ القرارِ الذي يُفسّرُ التضييق');
    });
  });

  group('القاعدةُ نفسُها، وحجزُها', () {
    final String rules = read('firestore.rules');

    test('قراءةُ promo_codes مشروطةٌ بالعَلَمِ أو التوجيه', () {
      expect(rules.contains('allow get, list: if isAdmin() ||'), isTrue);
      expect(rules.contains('resource.data.show_in_offers == true'), isTrue);
      expect(
          rules.contains('resource.data.target_user_id == request.auth.uid'),
          isTrue);
      expect(rules.contains('match /promo_codes/{codeId} {\n      allow read:'),
          isFalse,
          reason: 'عادت القراءةُ المفتوحةُ لكلِّ مسجَّل');
    });

    test('والحجزُ مكتوبٌ حيث يُقرأ', () {
      // النسخةُ المنشورةُ تَستعلمُ بالكودِ وبـ`status`، وكلاهما لا يُثبِتُ
      // الشرطَ — فنشرٌ مبكّرٌ يَرفضُ كلَّ كوبونٍ لكلِّ عميلة.
      expect(rules.contains('لا تُنشَر هذه القاعدةُ قبلَ فرضِ الحدِّ الأدنى للإصدار'),
          isTrue, reason: 'تحذيرُ التتابعِ اختفى — والنشرُ المبكّرُ عطلٌ عامّ');
    });
  });

  group('combineLatestById', () {
    test('يُصدِرُ اتّحادَ آخرِ ما وصلَ من كلٍّ', () async {
      final a = StreamController<List<String>>();
      final b = StreamController<List<String>>();
      final out = <List<String>>[];
      final sub =
          combineLatestById<String>(a.stream, b.stream, (s) => s).listen(out.add);
      a.add(['x']);
      await Future<void>.delayed(Duration.zero);
      b.add(['y']);
      await Future<void>.delayed(Duration.zero);
      a.add(['x', 'z']);
      await Future<void>.delayed(Duration.zero);
      expect(out.map((l) => l.toSet()).toList(), [
        {'x'},
        {'x', 'y'},
        {'x', 'z', 'y'},
      ]);
      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('ويُزيلُ التكرارَ بالمعرّف', () async {
      // كوبونٌ مُعلَنٌ **و**موجَّهٌ إليها يُطابقُ الاستعلامَين.
      final a = StreamController<List<String>>();
      final b = StreamController<List<String>>();
      final out = <List<String>>[];
      final sub =
          combineLatestById<String>(a.stream, b.stream, (s) => s).listen(out.add);
      a.add(['same']);
      b.add(['same']);
      await Future<void>.delayed(Duration.zero);
      expect(out.last, ['same']);
      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('والخطأُ يُمرَّرُ ولا يُغلِقُ البثّ', () async {
      final a = StreamController<List<String>>();
      final b = StreamController<List<String>>();
      final events = <Object>[];
      final sub = combineLatestById<String>(a.stream, b.stream, (s) => s)
          .listen(events.add, onError: events.add);
      a.addError(StateError('boom'));
      await Future<void>.delayed(Duration.zero);
      b.add(['late']);
      await Future<void>.delayed(Duration.zero);
      expect(events.first, isA<StateError>());
      expect(events.last, ['late'],
          reason: 'البياناتُ المتأخّرةُ بعد عودةِ الشبكةِ يَجبُ أن تَصل');
      await sub.cancel();
      await a.close();
      await b.close();
    });

    test('والإلغاءُ يَنزلُ إلى المصدرَين', () async {
      var cancelledA = false;
      var cancelledB = false;
      final a = StreamController<List<String>>(
          onCancel: () => cancelledA = true);
      final b = StreamController<List<String>>(
          onCancel: () => cancelledB = true);
      final sub =
          combineLatestById<String>(a.stream, b.stream, (s) => s).listen((_) {});
      await sub.cancel();
      expect(cancelledA, isTrue, reason: 'مُستمِعٌ مفتوحٌ لكلِّ فتحةِ شاشة');
      expect(cancelledB, isTrue);
      await a.close();
      await b.close();
    });
  });
}
