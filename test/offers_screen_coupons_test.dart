import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/promo_coupon.dart';
import 'package:zyiarah/screens/offers_screen.dart';

/// قسم «العروض» بعد إضافة الكوبونات وبطاقة الإحالة (تصميم Stitch، 2026-09-16).
/// البثوث محقونة فلا Firebase هنا؛ النسخ يُلتقط من قناة النظام.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  PromoCoupon c(String code,
          {String? target, String desc = '', List<String> zones = const []}) =>
      PromoCoupon(
        id: code,
        code: code,
        type: 'percentage',
        value: 25,
        maxUses: 0,
        uses: 0,
        expiry: DateTime(2030, 1, 1),
        status: 'active',
        restrictedZones: zones,
        targetUserId: target,
        showInOffers: true,
        description: desc,
      );

  Future<List<MethodCall>> mockClipboard(WidgetTester t) async {
    final calls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    return calls;
  }

  Future<void> pumpOffers(
    WidgetTester t, {
    required Stream<List<PromoCoupon>> coupons,
    Stream<List<Map<String, dynamic>>>? banners,
    String? uid = 'u1',
    Future<String?>? referral,
  }) async {
    await t.pumpWidget(MaterialApp(
      home: ZyiarahOffersScreen(
        banners: banners ?? Stream.value(const []),
        coupons: coupons,
        currentUid: uid,
        referralCode: referral ?? Future.value('ZYABC123'),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('الكوبونات المعروضة: العنوان والكود والوصف والمنطقة، والشخصي بشارته',
      (t) async {
    await pumpOffers(t,
        coupons: Stream.value([
          c('JAZAN25', desc: 'على أول طلب', zones: ['الداير', 'فيفاء']),
          c('MINE', target: 'u1'),
          c('THEIRS', target: 'u2'),
        ]));
    expect(find.text('كوبونات الخصم المعتمدة'), findsOneWidget);
    expect(find.text('JAZAN25'), findsOneWidget);
    expect(find.text('على أول طلب'), findsOneWidget);
    expect(find.text('الداير • فيفاء'), findsOneWidget);
    expect(find.text('MINE'), findsOneWidget);
    expect(find.text('كوبون خاص بك'), findsOneWidget);
    expect(find.text('THEIRS'), findsNothing,
        reason: 'كوبون موجَّه لغيري لا يظهر لي');
    expect(find.text('خصم 25%'), findsNWidgets(2));
    // بطاقة الإحالة بكود العميل والأرقام من الخدمة (50 ر.س / 10%).
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
    expect(find.text('ZYABC123'), findsOneWidget);
    expect(find.textContaining('50 ر.س'), findsOneWidget);
    expect(find.textContaining('خصم 10%'), findsOneWidget);
    expect(find.text('لا توجد عروض حالياً'), findsNothing);
  });

  testWidgets('زر النسخ يضع الكود في الحافظة ويُظهر «تم نسخ الكود»', (t) async {
    final calls = await mockClipboard(t);
    await pumpOffers(t, coupons: Stream.value([c('WINTER')]));
    await t.tap(find.widgetWithText(FilledButton, 'نسخ الكود'));
    await t.pump();
    final set = calls.where((m) => m.method == 'Clipboard.setData').toList();
    expect(set, hasLength(1));
    expect((set.single.arguments as Map)['text'], 'WINTER');
    expect(find.textContaining('تم نسخ الكود بنجاح'), findsOneWidget);
  });

  testWidgets('بلا بانرات ولا كوبونات → حالة فارغة + تلميح، وبطاقة الإحالة تبقى',
      (t) async {
    await pumpOffers(t, coupons: Stream.value(const []));
    expect(find.text('لا توجد عروض حالياً'), findsOneWidget);
    expect(find.text('لا توجد كوبونات متاحة حالياً'), findsOneWidget);
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
  });

  testWidgets('زائر بلا حساب → تلميح الدخول ولا بطاقة إحالة ولا انهيار', (t) async {
    await pumpOffers(t, coupons: Stream.value([c('X')]), uid: null);
    expect(find.text('سجّل الدخول لرؤية كوبوناتك وكود الإحالة'), findsOneWidget);
    expect(find.text('برنامج سفراء زيارة'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('فشل بثّ الكوبونات → خطأ مضمَّن في قسمه فقط', (t) async {
    await pumpOffers(t, coupons: Stream.error(StateError('offline')));
    expect(find.text('تعذّر تحميل الكوبونات، تحقّق من الاتصال'), findsOneWidget);
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('فشل جلب كود الإحالة → البطاقة تبقى بلا كود وزر النسخ معطّل',
      (t) async {
    await pumpOffers(t,
        coupons: Stream.value(const []), referral: Future.value(null));
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    // لا كوبونات في هذا الفحص، فأيقونة النسخ الوحيدة هي أيقونة الإحالة.
    final btn = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy_rounded));
    expect(btn.onPressed, isNull);
  });
}
