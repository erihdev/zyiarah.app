import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/service_policy.dart';
import 'package:zyiarah/screens/terms_privacy_screens.dart';

/// شاشة الشروط للعميل بعد ربطها بـ service_policies (تصميم Stitch، 2026-09-16):
/// تعرض المفعّل مجمّعاً بتصنيفه مع شارة الإلزام، وتعود إلى النصّ القديم حين لا
/// بنود أو حين تفشل القراءة — فلا تُفتح فارغة أبداً (تُفتح من التسجيل قبل الدخول).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  ServicePolicy p(String id, String cat,
          {bool enabled = true, bool mandatory = false, int order = 0}) =>
      ServicePolicy(
        id: id,
        title: 'عنوان $id',
        body: 'نصّ البند $id',
        category: cat,
        enabled: enabled,
        mandatoryBeforeBooking: mandatory,
        order: order,
      );

  Future<void> pumpTerms(WidgetTester t, Stream<List<ServicePolicy>> s) async {
    await t.pumpWidget(MaterialApp(home: ZyiarahTermsScreen(policies: s)));
    await t.pump();
    await t.pump();
  }

  testWidgets('بنود مفعّلة → أقسام بتصنيفها، وشارة الإلزام، ولا نصّ قديم',
      (t) async {
    await pumpTerms(
        t,
        Stream.value([
          p('1', 'privacy_safety', mandatory: true),
          p('2', 'contracts'),
          p('3', 'mountain_routes', enabled: false),
        ]));
    expect(find.text('العقود والاشتراكات'), findsOneWidget);
    expect(find.text('الخصوصية والسلامة'), findsOneWidget);
    // تصنيف بلا بند مفعّل لا يظهر عنوانه.
    expect(find.text('المسارات الجبلية'), findsNothing);
    expect(find.text('عنوان 3'), findsNothing);
    expect(find.text('عنوان 1'), findsOneWidget);
    expect(find.text('نصّ البند 2'), findsOneWidget);
    expect(find.text('إلزامي قبل تأكيد الحجز'), findsOneWidget);
    expect(find.text('1. مقدمة'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('بلا بنود → النصّ القديم كما كان', (t) async {
    await pumpTerms(t, Stream.value(const []));
    expect(find.text('1. مقدمة'), findsOneWidget);
    expect(find.text('3. سياسة الدفع'), findsOneWidget);
  });

  testWidgets('كل البنود موقوفة → النصّ القديم أيضاً', (t) async {
    await pumpTerms(t, Stream.value([p('1', 'contracts', enabled: false)]));
    expect(find.text('1. مقدمة'), findsOneWidget);
    expect(find.text('عنوان 1'), findsNothing);
  });

  testWidgets('فشل القراءة → النصّ القديم لا شاشة خطأ', (t) async {
    await pumpTerms(t, Stream.error(StateError('offline')));
    expect(find.text('1. مقدمة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('قبل وصول أول بثّ → مؤشر تحميل', (t) async {
    final ctrl = StreamController<List<ServicePolicy>>();
    await t.pumpWidget(MaterialApp(home: ZyiarahTermsScreen(policies: ctrl.stream)));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await ctrl.close();
  });

  group('ZyiarahPrivacyScreen', () {
    testWidgets('النصّ المنشور من الإدارة يظهر بدل الثابت', (t) async {
      await t.pumpWidget(MaterialApp(
          home: ZyiarahPrivacyScreen(content: Stream.value('سياسة منشورة'))));
      await t.pump();
      await t.pump();
      expect(find.text('سياسة منشورة'), findsOneWidget);
      expect(find.text('خصوصيتك تهمنا'), findsNothing);
    });

    testWidgets('غياب المنشور (null أو فراغ) → الثابت', (t) async {
      await t.pumpWidget(
          MaterialApp(home: ZyiarahPrivacyScreen(content: Stream.value('  '))));
      await t.pump();
      await t.pump();
      expect(find.text('خصوصيتك تهمنا'), findsOneWidget);
    });
  });
}
