import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/driver_schedule.dart';
import 'package:zyiarah/screens/driver_tasks_screen.dart';

/// شاشة جدول المهام والمناوبات (تصميم Stitch `_39`): مؤشرات الأسبوع، شريط
/// الأيام بأعدادها و«راحة»، مهام اليوم المختار، الشبكة الشهرية، والسجل.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // الأربعاء 16 سبتمبر 2026؛ الأسبوع: السبت 12 → الجمعة 18.
  final now = DateTime(2026, 9, 16, 11);
  DriverTask t(String id, DateTime when, {String status = 'scheduled', String? slot}) =>
      DriverTask(
        id: id, code: 'ZY-$id', serviceName: 'خدمة $id', clientName: 'عميل $id',
        zoneName: 'الداير', status: status, when: when, timeSlot: slot,
      );
  final tasks = [
    t('a', DateTime(2026, 9, 16), status: 'completed', slot: '09:30'),
    t('b', DateTime(2026, 9, 16), status: 'in_progress', slot: '13:00'),
    t('c', DateTime(2026, 9, 17), slot: '16:30'),
    t('d', DateTime(2026, 9, 12), status: 'completed'),
    t('e', DateTime(2026, 10, 3)),
    t('f', DateTime(2026, 9, 14), status: 'cancelled'),
  ];

  Future<void> pump(WidgetTester t, {List<DriverTask>? items, String? uid = 'd1'}) async {
    await t.pumpWidget(MaterialApp(
      home: DriverTasksScreen(items: Stream.value(items ?? tasks), uid: uid, now: now),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('الأسبوعي: المؤشرات، شريط الأيام بالأعداد و«راحة»، ومهام اليوم بوقتها',
      (t) async {
    await pump(t);
    // الأسبوع: a,b,c,d,f → مجدولة 4 (بلا الملغاة)، منجزة 2، متبقية 2.
    expect(find.text('المجدولة'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.text('أسبوع 12 - 18 سبتمبر'), findsOneWidget);
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('2 مهام'), findsOneWidget, reason: 'الأربعاء');
    // الأحد والثلاثاء والجمعة بلا مهام، والإثنين فيه ملغاة فقط — الملغاة لا تُعدّ.
    expect(find.text('راحة'), findsNWidgets(4));
    expect(find.text('مهام اليوم (الأربعاء 16 سبتمبر)'), findsOneWidget);
    expect(find.text('2 زيارات ميدانية مسندة'), findsOneWidget);
    expect(find.text('خدمة a'), findsOneWidget);
    expect(find.text('09:30 ص'), findsOneWidget);
    expect(find.text('01:00 م'), findsOneWidget);
    expect(find.text('مكتملة بنجاح ✓'), findsOneWidget);
    expect(find.text('جارية الآن ⚡'), findsOneWidget);
    expect(find.text('خدمة c'), findsNothing);
  });

  testWidgets('اختيار يوم آخر يعرض مهامه، والفارغ «راحة»', (t) async {
    await pump(t);
    await t.tap(find.text('الخميس'));
    await t.pump();
    expect(find.text('مهام الخميس 17 سبتمبر'), findsOneWidget);
    expect(find.text('خدمة c'), findsOneWidget);
    expect(find.text('قادمة ⏳'), findsOneWidget);
    await t.tap(find.text('الأحد'));
    await t.pump();
    expect(find.text('لا مهام في هذا اليوم — راحة'), findsOneWidget);
  });

  testWidgets('التنقّل للأسبوع التالي', (t) async {
    await pump(t);
    await t.tap(find.byTooltip('التالي'));
    await t.pump();
    expect(find.text('أسبوع 19 - 25 سبتمبر'), findsOneWidget);
    expect(find.text('اليوم'), findsNothing);
  });

  testWidgets('الشهري: شبكة بأسماء الأيام وعدّ الشهر كاملاً', (t) async {
    await pump(t);
    await t.tap(find.text('الجدول الشهري'));
    await t.pump();
    expect(find.text('سبتمبر 2026'), findsOneWidget);
    for (final n in DriverSchedule.dayNames) {
      expect(find.text(n), findsWidgets, reason: n);
    }
    // سبتمبر: a,b,c,d,f → مجدولة 4.
    expect(find.text('المتبقية'), findsOneWidget);
    await t.tap(find.byTooltip('التالي'));
    await t.pump();
    expect(find.text('أكتوبر 2026'), findsOneWidget);
  });

  testWidgets('السجل: المكتملة والملغاة الأحدث أولاً بتاريخها', (t) async {
    await pump(t);
    await t.tap(find.text('السجل'));
    await t.pump();
    expect(find.text('خدمة a'), findsOneWidget);
    expect(find.text('خدمة d'), findsOneWidget);
    expect(find.text('خدمة f'), findsOneWidget);
    expect(find.text('ملغاة'), findsOneWidget);
    expect(find.text('خدمة b'), findsNothing);
    expect(find.textContaining('2026/09/16 ·'), findsOneWidget);
  });

  testWidgets('بلا حساب → طلب الدخول', (t) async {
    await pump(t, uid: null);
    expect(find.text('يرجى تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('بلا مهام → راحة وبلا انهيار', (t) async {
    await pump(t, items: const []);
    expect(find.text('لا مهام في هذا اليوم — راحة'), findsOneWidget);
    expect(find.text('راحة'), findsNWidgets(7));
    expect(t.takeException(), isNull);
  });
}
