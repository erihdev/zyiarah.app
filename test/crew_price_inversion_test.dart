// حارس: **خيارٌ بكوادرَ أكثرَ بسعرٍ أدنى يُرى قبل أن يُحفظ.**
//
// وُجد في بيانات الإنتاج بتشغيل التطبيق (2026-10-04، منطقة «فيفا»، نوع «فيلا
// أو دور»): «كادر واحد 347 ر.س» و«كادران 320 ر.س» معروضَين للعميلة جنباً إلى
// جنب. فهي تأخذ كادرَين بأقلَّ من كادر، والإدارةُ تخسر 27 ر.س على كلِّ طلبٍ
// يختار الأكثرَ كوادر — وهو الخيارُ الأرخص، فتختاره كلُّ عميلةٍ عاقلة.
//
// حقلُ السعرِ حرٌّ لكلِّ (نوع × كوادر) في المحرِّرَين — شاشةُ الإدارة ولوحةُ
// الويب — ولا مقارنةَ بينها في أيٍّ منهما. فالخطأُ المطبعيُّ (347/320 بدل
// 320/347) يُحفظ ويُعرض بلا أيِّ إشارة، لا عند الإدخال ولا بعده.
//
// **تنبيهٌ لا منع، صراحةً**: سعرٌ ترويجيٌّ مقصودٌ قرارٌ تجاريّ ليس للشيفرة أن
// تنقضه. القاعدةُ تُظهر الانقلابَ عند الإدخال وتترك القرارَ للإدارة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/crew_price_check.dart';

void main() {
  group('القاعدة', () {
    test('تصاعدٌ سليم ⇒ لا انقلاب', () {
      expect(crewPriceInversions({1: 301, 2: 515, 3: 700, 4: 900}), isEmpty);
    });

    test('تساوٍ ليس انقلاباً', () {
      // سعرٌ واحدٌ لخيارَين قرارٌ ممكن؛ الانقلابُ هو **الأقلّ**.
      expect(crewPriceInversions({1: 300, 2: 300}), isEmpty);
    });

    test('الحالةُ الحقيقيّة: 347 لكادرٍ و320 لكادرَين', () {
      final invs = crewPriceInversions({1: 347, 2: 320});
      expect(invs.length, 1);
      expect(invs.single.crews, 2);
      expect(invs.single.price, 347 - 27);
      expect(invs.single.lowerCrews, 1);
      expect(invs.single.lowerPrice, 347);
      expect(invs.single.gap, 27);
    });

    test('يُقارَن بأعلى سعرٍ أدنى كوادرَ لا بالسابق وحده', () {
      // 1:100، 2:500، 3:300 — الثالثُ أعلى من الأوّل وأدنى من الثاني:
      // انقلابٌ فعليّ، ولو قارنّا بالسابقِ فقط لظهر، ولو قارنّا بالأوّلِ فقط
      // لاختفى. المقارنةُ بالأعلى هي الصحيحة.
      final invs = crewPriceInversions({1: 100, 2: 500, 3: 300});
      expect(invs.length, 1);
      expect(invs.single.crews, 3);
      expect(invs.single.lowerCrews, 2);
      expect(invs.single.lowerPrice, 500);
    });

    test('تقريرٌ واحدٌ لكلِّ خيارٍ مخالفٍ لا لكلِّ زوج', () {
      // 1:500، 2:100، 3:200، 4:300 — ثلاثةُ خياراتٍ أدنى من الأوّل، وثلاثةُ
      // تنبيهاتٍ لا ستّة (الأزواجُ المخالفةُ ستّة).
      final invs = crewPriceInversions({1: 500, 2: 100, 3: 200, 4: 300});
      expect(invs.map((i) => i.crews).toList(), [2, 3, 4]);
      expect(invs.every((i) => i.lowerCrews == 1 && i.lowerPrice == 500), isTrue);
    });

    test('المعطَّل والصفر خارج المقارنة', () {
      // الصفرُ يعطّل الخيار («المعطَّل/الصفر لا يظهر للعميل») فليس انقلاباً —
      // وإلّا لصار كلُّ خيارٍ معطَّلٍ تنبيهاً دائماً يُدرَّب الأدمنُ على تجاهله.
      expect(crewPriceInversions({1: 300, 2: 0}), isEmpty);
      expect(crewPriceInversions({1: 300, 2: -5}), isEmpty);
      // ويبقى الانقلابُ بين المسعَّرَين وحدهما مرئيّاً.
      final invs = crewPriceInversions({1: 300, 2: 0, 3: 250});
      expect(invs.length, 1);
      expect(invs.single.crews, 3);
      expect(invs.single.lowerCrews, 1);
    });

    test('قيمةٌ غيرُ منتهية لا تُقارَن', () {
      expect(crewPriceInversions({1: 300, 2: double.nan}), isEmpty);
      expect(crewPriceInversions({1: 300, 2: double.infinity}), isEmpty);
    });

    test('خيارٌ واحدٌ أو لا شيء ⇒ لا انقلاب', () {
      expect(crewPriceInversions({}), isEmpty);
      expect(crewPriceInversions({3: 400}), isEmpty);
    });

    test('ثغراتُ الترقيم لا تُربك الترتيب', () {
      // 1 و4 مفعّلان و2و3 معطّلان: المقارنةُ بالمفتاحَين الحاضرَين.
      final invs = crewPriceInversions({1: 400, 4: 350});
      expect(invs.length, 1);
      expect(invs.single.crews, 4);
      expect(invs.single.lowerCrews, 1);
    });

    test('خاصّيّة: أيُّ ترتيبٍ تصاعديٍّ لا يُنتج انقلاباً', () {
      for (var a = 10; a <= 900; a += 70) {
        for (var b = a; b <= 1000; b += 90) {
          expect(crewPriceInversions({1: a.toDouble(), 2: b.toDouble()}),
              isEmpty,
              reason: 'a=$a b=$b');
        }
      }
    });

    test('خاصّيّة: كلُّ نزولٍ يُنتج انقلاباً واحداً بفارقٍ صحيح', () {
      for (var a = 100; a <= 900; a += 50) {
        for (var b = 1; b < a; b += 37) {
          final invs =
              crewPriceInversions({1: a.toDouble(), 2: b.toDouble()});
          expect(invs.length, 1, reason: 'a=$a b=$b');
          expect(invs.single.gap, (a - b).toDouble(), reason: 'a=$a b=$b');
        }
      }
    });
  });

  group('نصُّ التنبيه', () {
    test('يُسمّي الخيارَين بصياغة العميلة ويذكر السعرَين', () {
      final s = crewPriceInversionLabel(const CrewPriceInversion(
          crews: 2, price: 320, lowerCrews: 1, lowerPrice: 347));
      expect(s.contains('كادران'), isTrue);
      expect(s.contains('كادر واحد'), isTrue);
      expect(s.contains('320.00'), isTrue);
      expect(s.contains('347.00'), isTrue);
    });

    test('يستعمل crewLabel لا صياغةً ثانية', () {
      final s = crewPriceInversionLabel(const CrewPriceInversion(
          crews: 3, price: 10, lowerCrews: 1, lowerPrice: 20));
      // «3 كوادر» صياغةُ crewLabel؛ «3 كادر» لو كُتبت باليد.
      expect(s.contains('3 كوادر'), isTrue);
    });
  });

  group('المحرِّران يستدعيانها فعلاً', () {
    // قاعدةٌ صحيحةٌ لا يستدعيها أحدٌ تبقى اختباراتُها خضراء والعطلُ قائماً —
    // لذلك يُثبَّت موضعُ الاستدعاء في الجهتين، كما في حارسَي جدول المنطقة.
    test('شاشةُ الإدارة (Dart)', () {
      final src =
          File('lib/screens/admin/admin_hourly_zones_screen.dart')
              .readAsStringSync();
      expect(src.contains("import 'package:zyiarah/utils/crew_price_check.dart';"),
          isTrue);
      expect(src.contains('crewPriceInversions('), isTrue);
      expect(src.contains('crewPriceInversionLabel('), isTrue);
      // التنبيهُ يتحدّث مع الكتابة: بلا onChanged يبقى مخفيّاً حتى إعادةِ بناءٍ
      // من سببٍ آخر — فيُحفظ الانقلابُ دون أن يُرى.
      //
      // الفحصُ مقيَّدٌ بحقلِ **سعرِ الباقة** لا بالملفّ كلِّه: الشاشةُ فيها
      // `onChanged: (_) => setDialogState(() {})` آخرُ في حقلٍ مختلف، فلو
      // بحثنا في الملفِّ كلِّه لمرَّ الحارسُ على حقلٍ لا علاقةَ له بالتنبيه.
      final i = src.indexOf('controller: pkgPriceCtrls[type]![n],');
      expect(i, greaterThan(0), reason: 'لم يُعثر على حقلِ سعرِ الباقة');
      final window = src.substring(i, i + 600);
      expect(window.contains('onChanged: (_) => setDialogState(() {})'), isTrue,
          reason: 'حقلُ سعرِ الباقة لا يُعيد البناء — التنبيهُ لا يظهر عند '
              'الإدخال، فيُحفظ الانقلابُ دون أن يُرى');
    });

    test('لوحةُ الويب (TypeScript)', () {
      final src = File('admin_panel/src/pages/Settings.tsx').readAsStringSync();
      expect(src.contains("from '../utils/crewPriceCheck'"), isTrue);
      expect(src.contains('crewPriceInversions('), isTrue);
      expect(src.contains('crewPriceInversionLabel('), isTrue);
    });

    test('المرآةُ موجودة وتُعلن أنها مرآة', () {
      final ts = File('admin_panel/src/utils/crewPriceCheck.ts').readAsStringSync();
      expect(ts.contains('lib/utils/crew_price_check.dart'), isTrue,
          reason: 'المرآةُ التي لا تُسمّي أصلَها تنفصل عنه بصمت');
      expect(ts.contains('export function crewPriceInversions'), isTrue);
    });
  });
}
