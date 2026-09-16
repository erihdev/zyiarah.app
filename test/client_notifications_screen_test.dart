import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/notification_item.dart';
import 'package:zyiarah/screens/client_notifications_screen.dart';

/// مركز تنبيهات العميل (تصميم Stitch، 2026-09-16): عدّاد وقراءة الكل وتصفية
/// وسجل المقروء والنقر يفتح وجهة الإشعار. البثّ والتعليم والتنقّل محقونة.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  NotificationItem n(String id, String type,
          {bool read = false, String? related, DateTime? at}) =>
      NotificationItem(
        id: id,
        title: 'عنوان $id',
        body: 'نصّ $id',
        type: type,
        createdAt: at ?? DateTime.now().subtract(const Duration(minutes: 5)),
        isRead: read,
        relatedId: related,
      );

  final sample = [
    n('o1', 'order_update', related: 'AbCdEfGhIjKlMnOpQrSt'),
    n('o2', 'order_assignment', related: 'ZY-202600042'),
    n('p1', 'payment_update', related: 'AbCdEfGhIjKlMnOpQrSt'),
    n('f1', 'global_broadcast'),
    n('r1', 'order_update', read: true),
  ];

  Future<({List<List<String>> marked, List<String> routes})> pump(
    WidgetTester t, {
    List<NotificationItem>? items,
    String? uid = 'u1',
  }) async {
    final marked = <List<String>>[];
    final routes = <String>[];
    await t.pumpWidget(MaterialApp(
      home: ClientNotificationsScreen(
        items: Stream.value(items ?? sample),
        uid: uid,
        markRead: (ids) async => marked.add(ids),
        navigate: (_, route) => routes.add(route),
      ),
    ));
    await t.pump();
    await t.pump();
    return (marked: marked, routes: routes);
  }

  testWidgets('العدّاد والشرائح بأعدادها، والمقروء مخفي افتراضياً', (t) async {
    await pump(t);
    expect(find.text('4 جديدة'), findsOneWidget);
    expect(find.text('الكل (4)'), findsOneWidget);
    expect(find.text('الطلبات والميدان (2)'), findsOneWidget);
    expect(find.text('المدفوعات والمكافآت (1)'), findsOneWidget);
    expect(find.text('العروض والتعميمات (1)'), findsOneWidget);
    expect(find.text('عنوان r1'), findsNothing, reason: 'المقروء مخفي في وضع الجديدة');
    // أزرار الوجهة حسب النوع.
    expect(find.text('تتبع الطلب'), findsOneWidget);
    expect(find.text('طلباتي'), findsOneWidget);
    expect(find.text('عرض الطلب والفاتورة'), findsOneWidget);
    expect(find.text('العروض'), findsOneWidget);
  });

  testWidgets('تصفية بالتصنيف، وقسم فارغ له نصّه', (t) async {
    await pump(t);
    await t.tap(find.text('العروض والتعميمات (1)'));
    await t.pump();
    expect(find.text('عنوان f1'), findsOneWidget);
    expect(find.text('عنوان o1'), findsNothing);

    // بلا مدفوعات مقروءة → قسم فارغ بعد تعليم الكل.
    await t.tap(find.text('قراءة الكل'));
    await t.pump();
    await t.pump();
    expect(find.text('لا توجد إشعارات في هذا القسم'), findsOneWidget);
  });

  testWidgets('قراءة الكل تعلّم كل الجديد دفعةً واحدة ويختفي', (t) async {
    final r = await pump(t);
    await t.tap(find.text('قراءة الكل'));
    await t.pump();
    await t.pump();
    expect(r.marked, hasLength(1));
    expect(r.marked.single.toSet(), {'o1', 'o2', 'p1', 'f1'});
    expect(find.text('لا جديد'), findsOneWidget);
    expect(find.text('لا توجد إشعارات جديدة'), findsOneWidget);
  });

  testWidgets('مفتاح السجل يُظهر المقروء بلا نقطة', (t) async {
    await pump(t);
    await t.tap(find.byTooltip('عرض المقروءة أيضاً'));
    await t.pump();
    expect(find.text('عنوان r1'), findsOneWidget);
    expect(find.text('الكل (5)'), findsOneWidget);
  });

  testWidgets('النقر يعلّم مقروءاً ويفتح التتبّع بمعرّف المستند، وطلباتي للكود',
      (t) async {
    final r = await pump(t);
    await t.tap(find.text('عنوان o1'));
    await t.pump();
    await t.pump();
    expect(r.marked, [['o1']]);
    expect(r.routes, ['/track/AbCdEfGhIjKlMnOpQrSt']);

    await t.tap(find.text('عنوان o2'));
    await t.pump();
    await t.pump();
    expect(r.routes.last, '/orders');

    await t.tap(find.text('عنوان f1'));
    await t.pump();
    await t.pump();
    expect(r.routes.last, '/offers');
  });

  testWidgets('بلا حساب → طلب الدخول، وبلا إشعارات → الحالة الفارغة', (t) async {
    await pump(t, uid: null);
    expect(find.text('يرجى تسجيل الدخول'), findsOneWidget);

    await pump(t, items: const []);
    expect(find.text('لا توجد إشعارات جديدة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
