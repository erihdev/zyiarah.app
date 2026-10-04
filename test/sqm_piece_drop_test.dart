// حارس: **قطعةٌ مضافةٌ بلا مقاسات لا تُسقَط بصمت.**
//
// وُجد بتشغيل التطبيق (2026-10-04، «تنظيف الكنب والزل»): إضافةُ قطعةٍ تُنشئ
// بطاقةً كاملةً في الشاشة — اسمٌ («كنب 1»)، وسعرُ الوحدة، وحقلُ مقاسٍ فارغ،
// وزرُّ حذفٍ خاصٌّ بها — فتقرأ كأنّها مطلوبة. وحمولةُ الطلب تُرشِّح
// `.where((p) => p.isComplete)`.
//
// فمن أضافت ثلاثَ قطعٍ وقاست اثنتين كانت تمضي — `totalAmount > 0` فالحارسُ
// الوحيدُ لا يمنعها — وتدفع ثمنَ اثنتين وتظنّ أنّها طلبت ثلاثاً، ويصل الفريقُ
// فينظّف اثنتين. ولا شيءَ يشي بالإسقاط إلّا «عدد القطع» في صفِّ الملخّص: رقمٌ
// لا يقول إنّ شيئاً يُهمَل.
//
// التصحيح يمنع المضيَّ ويُسمّي العدد: إمّا تُقاس أو تُحذف. وترتيبُ الفحوص
// مقصود — لو لم تُقَس **أيُّ** قطعةٍ سبقته رسالةُ «أدخلي مقاسات قطعة واحدة
// على الأقل»، وهي أوضحُ في تلك الحال.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/sqm_piece.dart';

void main() {
  group('نموذجُ القطعة: ما الذي يُعدّ مكتملاً', () {
    test('الكنب يكتمل بالطول وحده', () {
      expect(const SqmPiece(kind: SqmPieceKind.sofa, length: 2).isComplete,
          isTrue);
      expect(const SqmPiece(kind: SqmPieceKind.sofa).isComplete, isFalse);
    });

    test('السجاد يحتاج الطولَ والعرض', () {
      expect(const SqmPiece(kind: SqmPieceKind.rug, length: 2).isComplete,
          isFalse);
      expect(
          const SqmPiece(kind: SqmPieceKind.rug, length: 2, width: 3).isComplete,
          isTrue);
    });

    test('المقاسُ صفرٌ ليس مقاساً', () {
      expect(const SqmPiece(kind: SqmPieceKind.sofa, length: 0).isComplete,
          isFalse);
      expect(
          const SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 0).isComplete,
          isFalse);
    });
  });

  group('الشاشة تمنع المضيَّ بقطعةٍ غير مقيسة', () {
    final src = File('lib/screens/sofa_rug_details_screen.dart').readAsStringSync();
    final i = src.indexOf('void _handleNext()');
    final body = src.substring(i, src.indexOf('  void _snack(', i));

    test('يوجد فحصٌ لغيرِ المقيس', () {
      expect(body.contains('!p.isComplete'), isTrue,
          reason: 'عادت القطعةُ تُسقَط بصمت من الحمولة');
      expect(body.contains('بلا مقاسات'), isTrue);
    });

    test('الفحصُ يمنع المضيَّ لا يُنبّه فقط', () {
      final g = body.indexOf('!p.isComplete');
      expect(g, greaterThan(0));
      // `return;` بعد الرسالة مباشرةً — تنبيهٌ بلا منعٍ يترك الإسقاط قائماً.
      expect(body.substring(g, g + 420).contains('return;'), isTrue);
    });

    test('الفحصُ بعد «ولا قطعةَ مقيسة» لا قبله', () {
      // لو سبقه لقال «قطعتان بلا مقاسات» لمن لم تُدخل شيئاً أصلاً، والرسالةُ
      // الأخرى أوضحُ في تلك الحال.
      final zero = body.indexOf('أدخلي مقاسات قطعة واحدة على الأقل');
      final some = body.indexOf('بلا مقاسات —');
      expect(zero, greaterThan(0));
      expect(some, greaterThan(0));
      expect(zero, lessThan(some));
    });

    test('ويسبق فحصَ الموعد — العطلُ في السلّة لا في التقويم', () {
      final some = body.indexOf('بلا مقاسات —');
      final slot = body.indexOf('اختاري اليوم ووقت البدء');
      expect(slot, greaterThan(0));
      expect(some, lessThan(slot));
    });

    test('الحمولةُ ما زالت تُرشِّح (الفحصُ هو ما يحمي، لا حذفُ الترشيح)', () {
      // إبقاءُ الترشيح مقصود: لو مرّت قطعةٌ بلا مقاسٍ إلى الحمولة لذهب إلى
      // الخادم عنصرٌ بسعرِ صفر. الحارسُ هو الذي يمنع وصولَ تلك الحال.
      expect(body.contains('.where((p) => p.isComplete)'), isTrue);
    });

    test('العدد يُسمّى في الرسالة', () {
      expect(body.contains(r'$unmeasured'), isTrue,
          reason: 'رسالةٌ لا تقول «كم» تترك العميلةَ تبحث عن الفارغة');
    });
  });

  _cartNoticeGuard();
}

// ── السلّة: صنفٌ لم يعد متاحاً يُقال، لا يختفي ──
//
// `_CartSheet` يرشّح `snapshot.data!.where((p) => widget.cart.containsKey(p.id))`،
// فصنفٌ أُخفي أو حُذف بعد إضافته يختفي من القائمة بلا كلمة: العدّادُ على
// الأيقونة يقول «3» والورقةُ تعرض اثنين. و`_checkout` يتخطّاه صامتاً كذلك —
// لا يُنبّه إلّا حين يختفي **كلُّ** شيء («بعض المنتجات لم تعد متاحة»).
// الإجماليُّ صحيحٌ في الحالين فالعطلُ إفادةٌ لا مال، لكنّ «أين الثالث؟» سؤالٌ
// بلا جواب. نفسُ عائلةِ قطعةِ الكنب غير المقيسة.
void _cartNoticeGuard() {
  group('السلّة تقول إنّ صنفاً أُزيل', () {
    final src = File('lib/screens/store_screen.dart').readAsStringSync();

    test('الفارقُ محسوبٌ من السلّة نفسها لا من رقمٍ ثانٍ', () {
      expect(src.contains('widget.cart.length - cartProducts.length'), isTrue,
          reason: 'لا شيءَ يقارن ما في السلّة بما يُعرض');
    });

    test('ويُعرض نصّاً', () {
      expect(src.contains('لم يعد متاحاً وأُزيل من السلة'), isTrue);
      expect(src.contains('لم تعد متاحة وأُزيلت من السلة'), isTrue);
    });

    test('مشروطٌ بوجود فارق (لا تنبيهَ دائم)', () {
      expect(src.contains('if (gone > 0)'), isTrue,
          reason: 'تنبيهٌ يظهر دائماً يُدرَّب عليه القارئُ فيصير بلا معنى');
    });

    test('ورسالةُ «اختفى كلُّ شيء» باقيةٌ في المسار الآخر', () {
      expect(src.contains('بعض المنتجات لم تعد متاحة، يرجى تحديث السلة'), isTrue);
    });
  });
}
