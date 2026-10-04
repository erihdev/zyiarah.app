import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/date_strip.dart';

/// شريط التواريخ في شاشات الحجز الثلاث: الحسابُ الخالص + **وصلُه**.
///
/// العيبُ الذي يحرسه هذا الملف مُصوَّرٌ من جهاز مختبِر: جدولُ المنطقة يفتح
/// السبتَ وحده، فينتقل الاختيار تلقائياً إلى الفهرس ٥ بينما الشريط باقٍ عند
/// أوّل عنصر — فيرى العميل الاثنين…الجمعة مغلقةً، والبطاقةَ المختارة مقتطعةً
/// عند حرف الشاشة أو خارجها تماماً، والملخّصَ أسفلَه يذكر تاريخاً لا يراه.
///
/// الحساب يُختبَر بخاصيّةٍ لا بأمثلة: البطاقةُ المختارة **تظهر كاملةً** لكل
/// فهرس ولكل عرضِ شاشةٍ معقول — لأنّ الثقب كان في طرفٍ واحد (الفهرس ٥ عند
/// حرف شاشةٍ بعينها)، والأمثلةُ تمرّ من فوق الأطراف.
void main() {
  group('dateStripOffsetFor — الحساب', () {
    test('الفهرس ٠ لا يُمرّر الشريط (البطاقة عند الحرف أصلاً)', () {
      expect(
          dateStripOffsetFor(index: 0, viewportWidth: 360, maxOffset: 1680), 0);
    });

    test('فهرسٌ سالب (تاريخ خارج الشريط) لا يُمرّر', () {
      expect(
          dateStripOffsetFor(index: -1, viewportWidth: 360, maxOffset: 1680), 0);
    });

    test('شريطٌ أقصرُ من الشاشة لا يُمرّر — لا ارتداد', () {
      expect(dateStripOffsetFor(index: 3, viewportWidth: 900, maxOffset: 0), 0);
      expect(dateStripOffsetFor(index: 3, viewportWidth: 900, maxOffset: -40), 0);
    });

    test('عرضُ شاشةٍ غير معروف بعد (صفر) لا يُمرّر', () {
      expect(
          dateStripOffsetFor(index: 12, viewportWidth: 0, maxOffset: 1680), 0);
    });

    test('يوسّط البطاقة حين يسمح المدى', () {
      // الفهرس ٥: مركزه ‎5.5 × 68 = 374‎، ونصفُ شاشةٍ ٣٦٠ = ١٨٠ ⇒ ١٩٤.
      expect(dateStripOffsetFor(index: 5, viewportWidth: 360, maxOffset: 1680),
          194);
    });

    test('آخرُ فهرسٍ يُقصّ عند maxScrollExtent ولا يتجاوزه', () {
      const double maxOffset = kDateStripDays * kDateStripItemExtent - 360;
      expect(
          dateStripOffsetFor(
              index: kDateStripDays - 1, viewportWidth: 360, maxOffset: maxOffset),
          maxOffset);
    });

    test('خاصيّة: البطاقة تظهر كاملةً لكل فهرس ولكل عرضِ شاشة', () {
      // عروضُ شاشاتٍ حقيقية (منقوصٌ منها حاشيةُ الصفحة) + أطرافٌ ضيقة وواسعة.
      const widths = <double>[
        200, 240, 280, 320, 328, 343, 360, 375, 390, 412, 428, 480, 600, 744,
        1024,
      ];
      for (final w in widths) {
        final double maxOffset =
            (kDateStripDays * kDateStripItemExtent - w).clamp(0.0, 1e9);
        for (int i = 0; i < kDateStripDays; i++) {
          final double off = dateStripOffsetFor(
              index: i, viewportWidth: w, maxOffset: maxOffset);
          expect(off, greaterThanOrEqualTo(0.0), reason: 'ارتداد يميني i=$i w=$w');
          expect(off, lessThanOrEqualTo(maxOffset),
              reason: 'ارتداد يساري i=$i w=$w');
          final double cardStart = i * kDateStripItemExtent;
          final double cardEnd = cardStart + kDateStripItemExtent;
          if (w < kDateStripItemExtent) continue; // لا تتسع الشاشة لبطاقة
          expect(cardStart, greaterThanOrEqualTo(off - 0.01),
              reason: 'بدايةُ البطاقة مقتطعة i=$i w=$w off=$off');
          expect(cardEnd, lessThanOrEqualTo(off + w + 0.01),
              reason: 'نهايةُ البطاقة مقتطعة i=$i w=$w off=$off');
        }
      }
    });
  });

  group('dateStripIndexOf — الفهرسة', () {
    final now = DateTime(2026, 10, 4, 9, 30);

    test('الغد هو الفهرس ٠', () {
      expect(dateStripIndexOf(DateTime(2026, 10, 5), now), 0);
    });

    test('اليومُ نفسه خارج الشريط (لا حجزَ في اليوم نفسه)', () {
      expect(dateStripIndexOf(DateTime(2026, 10, 4), now), -1);
    });

    test('الأمس خارج الشريط', () {
      expect(dateStripIndexOf(DateTime(2026, 10, 3), now), -1);
    });

    test('آخرُ يومٍ في الشريط هو ‎+٣٠‎ يوماً = الفهرس ٢٩', () {
      expect(dateStripIndexOf(DateTime(2026, 11, 3), now), kDateStripDays - 1);
    });

    test('ما بعد الشريط = ‎-١‎', () {
      expect(dateStripIndexOf(DateTime(2026, 11, 4), now), -1);
    });

    test('السبتُ في مثال المختبِر هو الفهرس ٥', () {
      // الأحد 2026-10-04 ⇒ الاثنين ٥ هو ٠ … السبت ١٠ هو ٥.
      expect(dateStripIndexOf(DateTime(2026, 10, 10), now), 5);
    });

    test('ساعةُ اليوم لا تُزحزح الفهرس', () {
      final late = DateTime(2026, 10, 4, 23, 59);
      final early = DateTime(2026, 10, 4, 0, 1);
      for (int i = 0; i < kDateStripDays; i++) {
        final d = DateTime(2026, 10, 5).add(Duration(days: i));
        expect(dateStripIndexOf(d, late), i);
        expect(dateStripIndexOf(d, early), i);
      }
    });

    test('يعبر حدّ الشهر والسنة', () {
      final dec = DateTime(2026, 12, 20, 15);
      expect(dateStripIndexOf(DateTime(2026, 12, 31), dec), 10);
      expect(dateStripIndexOf(DateTime(2027, 1, 1), dec), 11);
    });
  });

  // ───────────── الخاصيّة نفسها على تخطيطٍ حقيقيّ في RTL ─────────────
  // الحسابُ أعلاه حسابي؛ هذا يُجري عليه تمريرَ Flutter فعلاً داخل
  // `Directionality.rtl` — فيؤكّد أنّ الإزاحة **منطقية** (الصفر عند أوّل
  // عنصرٍ وهو اليمين في RTL) وأنّ القصَّ عند `maxScrollExtent` صحيح.
  group('تخطيطٌ حقيقيّ (RTL)', () {
    // `Directionality` **داخل** `MaterialApp` لا فوقه: المادّة تُركّب اتجاهها
    // من لغتها (الإنجليزية ⇒ LTR) فتُلغي أيَّ اتجاهٍ أعلى منها — والشاشاتُ
    // الثلاث تلفّ نفسها بـ RTL داخل الشجرة، فهذا هو ترتيبُها الحقيقي.
    Widget strip(ScrollController ctrl, double width) => MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: 82,
                  child: ListView.builder(
                    controller: ctrl,
                    scrollDirection: Axis.horizontal,
                    itemCount: kDateStripDays,
                    itemBuilder: (_, i) => Container(
                      key: ValueKey('day$i'),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 58,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('أوّلُ عنصرٍ عند اليمين — الإزاحة منطقية لا بصرية',
        (tester) async {
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(strip(ctrl, 360));
      final Rect first = tester.getRect(find.byKey(const ValueKey('day0')));
      final Rect second = tester.getRect(find.byKey(const ValueKey('day1')));
      expect(first.left, greaterThan(second.left),
          reason: 'في RTL أوّلُ يومٍ يجب أن يكون الأيمن');
      expect(ctrl.position.pixels, 0);
    });

    testWidgets('كلُّ فهرسٍ يظهر كاملاً بعد التمرير إلى إزاحته', (tester) async {
      for (final double w in <double>[320, 360, 412]) {
        final ctrl = ScrollController();
        await tester.pumpWidget(strip(ctrl, w));
        final Rect view = tester.getRect(find.byType(ListView));
        for (int i = 0; i < kDateStripDays; i++) {
          ctrl.jumpTo(dateStripOffsetFor(
            index: i,
            viewportWidth: ctrl.position.viewportDimension,
            maxOffset: ctrl.position.maxScrollExtent,
          ));
          await tester.pump();
          final finder = find.byKey(ValueKey('day$i'));
          expect(finder, findsOneWidget,
              reason: 'اليوم $i غير مبنيٍّ أصلاً (عرض $w)');
          final Rect card = tester.getRect(finder);
          expect(card.left, greaterThanOrEqualTo(view.left - 0.01),
              reason: 'اليوم $i مقتطعٌ يساراً (عرض $w)');
          expect(card.right, lessThanOrEqualTo(view.right + 0.01),
              reason: 'اليوم $i مقتطعٌ يميناً (عرض $w)');
        }
        ctrl.dispose();
      }
    });
  });

  // ─────────────────────────── وصلُ الحساب بالشاشات ───────────────────────────
  // حسابٌ صحيحٌ لا يُستدعى يترك اختباراتَه خضراء والعيبَ قائماً: الشاشاتُ
  // الثلاث هي التي كانت تفتقد `ScrollController` أصلاً.
  group('الوصل — الشاشات الثلاث', () {
    const screens = <String>[
      'lib/screens/hourly_details_screen.dart',
      'lib/screens/subscription_plans_screen.dart',
      'lib/screens/event_worker_packages_screen.dart',
    ];

    for (final path in screens) {
      final String src = File(path).readAsStringSync();
      final String name = path.split('/').last;

      test('$name — يستورد الوحدة ويملك ScrollController ويتخلّص منه', () {
        expect(src, contains("import 'package:zyiarah/utils/date_strip.dart';"),
            reason: '$name لا يستورد وحدة الشريط');
        expect(src, contains('ScrollController _dateStripCtrl'),
            reason: '$name بلا ScrollController للشريط');
        expect(src, contains('_dateStripCtrl.dispose();'),
            reason: '$name لا يتخلّص من المتحكّم (تسريب)');
      });

      test('$name — المتحكّم موصولٌ بشريط الـ ٣٠ يوماً نفسه', () {
        // `controller:` يسبق `itemCount: 30` في الـ ListView نفسه — لا في قائمةٍ أخرى.
        final int listIdx = src.indexOf('itemCount: 30');
        expect(listIdx, greaterThan(0), reason: '$name: لم يُعثر على شريط ٣٠ يوماً');
        final int builderIdx = src.lastIndexOf('ListView.builder(', listIdx);
        expect(builderIdx, greaterThan(0),
            reason: '$name: الشريط ليس ListView.builder');
        final String head = src.substring(builderIdx, listIdx);
        expect(head, contains('controller: _dateStripCtrl'),
            reason: '$name: شريط الـ ٣٠ يوماً بلا متحكّم — الاختيار يبقى خارج الشاشة');
      });

      test('$name — كلُّ انتقالٍ تلقائيّ للاختيار يُتبَع بإظهاره', () {
        // كلُّ موضعٍ يكتب `_selectedDate = candidate/c` داخل حلقةِ الانتقال
        // التلقائي يقابله استدعاءٌ لـ `_revealSelectedDate`.
        final int autoSites =
            RegExp(r'_selectedDate = (candidate|c);').allMatches(src).length;
        expect(autoSites, greaterThan(0),
            reason: '$name: لم يُعثر على الانتقال التلقائي');
        final int reveals =
            RegExp(r'_revealSelectedDate\(\);').allMatches(src).length;
        expect(reveals, autoSites,
            reason: '$name: $autoSites انتقالاً تلقائياً مقابل $reveals إظهاراً — '
                'انتقالٌ بلا إظهار يعيد العيب نفسه');
      });

      test('$name — الإظهار يمرّ بالوحدة لا بحسابٍ محليّ', () {
        expect(src, contains('dateStripOffsetFor('),
            reason: '$name لا يستعمل dateStripOffsetFor');
        expect(src, contains('dateStripIndexOf('),
            reason: '$name لا يستعمل dateStripIndexOf');
        // الهندسةُ تأتي من التخطيط الفعلي، لا من رقمٍ مكتوبٍ في الشاشة.
        expect(src, contains('maxOffset: _dateStripCtrl.position.maxScrollExtent'),
            reason: '$name: حدُّ التمرير ليس maxScrollExtent');
      });
    }

    test('عرضُ البطاقة في الوحدة يطابق الشاشات الثلاث', () {
      // 58 عرضاً + 5 هامشاً على كلّ جانب = 68. لو غُيّر العرض في شاشةٍ
      // وحدها لصار التوسيط كاذباً بصمت.
      for (final path in screens) {
        final String src = File(path).readAsStringSync();
        final int listIdx = src.indexOf('itemCount: 30');
        final String body = src.substring(listIdx, listIdx + 4000);
        expect(body, contains('margin: const EdgeInsets.symmetric(horizontal: 5)'),
            reason: '$path: هامشُ البطاقة تغيّر — راجع kDateStripItemExtent');
        expect(body, contains('width: 58'),
            reason: '$path: عرضُ البطاقة تغيّر — راجع kDateStripItemExtent');
      }
      expect(kDateStripItemExtent, 58.0 + 5.0 + 5.0);
    });
  });
}
