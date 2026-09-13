import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';

/// shimmer 4.0.0 استبدل package:flutter/material.dart بحزمة material_ui وأعاد
/// ترتيب دورة الحركة (repeat() بدل forward() الأولى، وperiod متزامنة عند
/// تغيّرها). ولم يكن في المشروع اختبار واحد يرسم ويدجت Shimmer: الترقية كانت
/// تمرّ على ٣١٠ فحوص خضراء بلا أن يُنفَّذ سطر منها. الملف يرسم كل غلاف مشترك
/// ويقدّم إطارات من الحركة — فأي كسر في التصيير أو الدورة يظهر هنا لا على
/// جهاز العميل. (pumpAndSettle ممنوع: الحركة لا نهائية فيعلّق.)
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('ZyiarahShimmer.rectangular وcircular يرسمان ويتحرّكان',
      (t) async {
    await t.pumpWidget(host(const Column(children: [
      ZyiarahShimmer.rectangular(height: 20, width: 100),
      ZyiarahShimmer.circular(width: 40, height: 40),
    ])));
    expect(find.byType(Shimmer), findsNWidgets(2));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 1500));
    expect(t.takeException(), isNull);
  });

  testWidgets('buildListSkeleton يولّد count صفوف بثلاثة هياكل لكل صف',
      (t) async {
    await t.pumpWidget(host(ZyiarahShimmer.buildListSkeleton(count: 3)));
    // shrinkWrap يبني الصفوف الثلاثة كلها: 3 × (دائري + مستطيلان).
    expect(find.byType(Shimmer), findsNWidgets(9));
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
  });

  testWidgets('ShimmerCard وShimmerGridItem يرسمان بحركة period=1500ms',
      (t) async {
    await t.pumpWidget(host(const SingleChildScrollView(
      child: Column(children: [
        ShimmerCard(),
        SizedBox(width: 200, height: 220, child: ShimmerGridItem()),
      ]),
    )));
    // ShimmerCard ثلاثة أغلفة، ShimmerGridItem ثلاثة أغلفة.
    expect(find.byType(Shimmer), findsNWidgets(6));
    await t.pump(const Duration(milliseconds: 1500));
    await t.pump(const Duration(milliseconds: 1500));
    expect(t.takeException(), isNull);
  });
}
