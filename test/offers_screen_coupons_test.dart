import 'dart:async';
import 'dart:io';
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
    expect(find.text('سجّلي الدخول لرؤية كوبوناتك وكود الإحالة'), findsOneWidget);
    expect(find.text('برنامج سفراء زيارة'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('فشل بثّ الكوبونات → خطأ مضمَّن في قسمه فقط', (t) async {
    await pumpOffers(t, coupons: Stream.error(StateError('offline')));
    expect(find.text('تعذّر تحميل الكوبونات، تحقّقي من الاتصال'), findsOneWidget);
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // **«جارٍ» و«تعذّر» حالتان لا واحدة (2026-10-07).** كانت البطاقةُ
  // `FutureBuilder` على وعدٍ يَبتلعُ الفشلَ إلى `null`
  // (`.catchError((_) => null)`)، فتَرسمُ «…» في الحالتَين وزرُّ النسخِ
  // معطَّلٌ **إلى الأبدِ** بلا كلمةٍ ولا إعادةِ محاولة — على السطحِ الذي
  // يَبدأُ به برنامجُ الإحالة. وكان هذا الفحصُ يُثبّتُ ذلك السلوكَ بعينِه.
  testWidgets('كودُ الإحالة: جارٍ ⇒ «…» وزرُّ النسخِ معطَّل', (t) async {
    // وعدٌ لا يَكتمِل — حالةُ التحميل.
    await pumpOffers(t,
        coupons: Stream.value(const []),
        referral: Completer<String?>().future);
    expect(find.text('برنامج سفراء زيارة'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('تعذّر التحميل'), findsNothing,
        reason: 'التحميلُ يُقرأُ فشلاً');
    final btn = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy_rounded));
    expect(btn.onPressed, isNull);
  });

  testWidgets('كودُ الإحالة: فشلٌ ⇒ «تعذّر التحميل» وإعادةٌ لا نسخٌ ميّت',
      (t) async {
    // الخطأُ يُكمَلُ **بعد** تركيبِ الشاشة: `Future.error` يُنشَأُ قبلَها
    // فيَبقى بلا مُعالِجٍ دورةَ microtask، فيُسقِطُ مِرفَقُ الاختبارِ الفحصَ
    // بخطأٍ غيرِ ملتقَطٍ وإن كانت الشفرةُ تُعالِجُه فعلاً.
    final c = Completer<String?>();
    await pumpOffers(t, coupons: Stream.value(const []), referral: c.future);
    c.completeError(Exception('boom'));
    await t.pump();
    await t.pump();
    expect(find.text('تعذّر التحميل'), findsOneWidget,
        reason: 'الفشلُ يُرسَمُ «…» كالتحميل — لا تَعرفُ أنّ شيئاً تعذّر');
    expect(find.text('…'), findsNothing);
    // زرُّ النسخِ المعطَّلُ يُستبدَلُ بإعادةٍ فعّالة.
    expect(find.widgetWithIcon(IconButton, Icons.content_copy_rounded),
        findsNothing);
    final retry = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh_rounded));
    expect(retry.onPressed, isNotNull, reason: 'إعادةٌ بلا أثر');
  });

  testWidgets('كودُ الإحالة: وعدٌ بـ null يُقرأُ فشلاً لا كوداً فارغاً',
      (t) async {
    // الخدمةُ تَرمي عند غيابِ الكود، لكنّ `null` من أيِّ مصدرٍ يَعني
    // «لا كودَ» — وهو فشلٌ من منظورِ العميلة لا حالةٌ سليمة.
    await pumpOffers(t,
        coupons: Stream.value(const []), referral: Future<String?>.value(null));
    expect(find.text('تعذّر التحميل'), findsOneWidget);
  });

  test('ولا يُبتلَعُ خطأُ الخدمةِ قبلَ أن يُبلَّغَ عنه', () {
    // `code == null` و«فشلٌ» يَنتهيانِ إلى الشاشةِ نفسِها — وهو حسنٌ —
    // لكنّ `.catchError` على مسارِ الخدمةِ يَضيعُ معه **الإبلاغ**: لا
    // Crashlytics ولا `debugPrint`. فلا اختبارُ واجهةٍ يَكشفُه، ويَكشفُه
    // هذا الفحصُ ومعه `error_visibility_test` (سببُ البلاغ).
    final src = File('lib/screens/offers_screen.dart').readAsStringSync();
    final int i = src.indexOf('Future<void> _loadReferral(');
    expect(i, greaterThan(0));
    final String body = src.substring(i, src.indexOf('\n  }', i));
    expect(body.contains('catchError'), isFalse,
        reason: 'عادَ ابتلاعُ الفشلِ في مسارِ جلبِ الكود — يَضيعُ البلاغ');
    expect(body.contains("reason: 'referral_code_fetch_failed'"), isTrue,
        reason: 'الفشلُ بلا إبلاغ');
  });

  testWidgets('كودُ الإحالة: نجاحٌ ⇒ الكودُ ونسخٌ فعّال', (t) async {
    await pumpOffers(t,
        coupons: Stream.value(const []),
        referral: Future<String?>.value('ZYXYZ99'));
    expect(find.text('ZYXYZ99'), findsOneWidget);
    expect(find.text('تعذّر التحميل'), findsNothing);
    expect(find.widgetWithIcon(IconButton, Icons.refresh_rounded), findsNothing);
    final btn = t.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.content_copy_rounded));
    expect(btn.onPressed, isNotNull);
  });
}
