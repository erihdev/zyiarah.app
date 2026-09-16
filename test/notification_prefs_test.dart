import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/notification_item.dart';
import 'package:zyiarah/screens/client_notifications_screen.dart';

/// تفضيلات التنبيهات (Stitch `_52`): مفتاح «العروض والتسويق» وحده — الطلبات
/// والمدفوعات والمواعيد تصل دائماً. الخادم يُسقط من أوقفها من كل بثّ تسويقي،
/// والبثّ التشغيلي يصل الجميع.
String _read(String p) => File(p).readAsStringSync();

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final sample = [
    NotificationItem.fromMap('n1', {
      'title': 'تم تعيين سائق',
      'body': 'الكابتن في الطريق',
      'type': 'order_update',
      'isRead': false,
      'sentAt': DateTime(2026, 9, 16, 10),
    }),
  ];

  Future<List<bool>> pump(WidgetTester t, {bool initial = true, bool failSave = false}) async {
    final saved = <bool>[];
    await t.pumpWidget(MaterialApp(
      home: ClientNotificationsScreen(
        items: Stream.value(sample),
        uid: 'u1',
        markRead: (_) async {},
        navigate: (_, __) {},
        loadMarketingPref: () async => initial,
        saveMarketingPref: (v) async {
          if (failSave) throw StateError('offline');
          saved.add(v);
        },
      ),
    ));
    await t.pump();
    await t.pump();
    return saved;
  }

  testWidgets('زر التفضيلات يفتح الورقة، والمفتاح يحفظ الإيقاف ويشرح أثره', (t) async {
    final saved = await pump(t);
    await t.tap(find.byTooltip('تفضيلات التنبيهات'));
    await t.pumpAndSettle();
    expect(find.text('العروض والتسويق'), findsOneWidget);
    expect(find.textContaining('تصلك دائماً'), findsOneWidget,
        reason: 'الورقة توضح أن التشغيلي لا يُوقَف');
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(saved, [false]);
    expect(find.textContaining('لن يصلك أي بثّ تسويقي'), findsOneWidget);
  });

  testWidgets('فشل الحفظ يعيد المفتاح لحاله ويُظهر رسالة', (t) async {
    await pump(t, failSave: true);
    await t.tap(find.byTooltip('تفضيلات التنبيهات'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(find.textContaining('تعذّر حفظ التفضيل'), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch).first).value, isTrue,
        reason: 'لا يُعرض إيقافٌ لم يُحفظ');
  });

  test('المصدر: الخادم يُسقط من أوقف التسويق من البثّ (بوش وصندوق) إلا التشغيلي، والأدمن يعلّم التشغيلي', () {
    final fn = _read('functions/index.js');
    expect(fn.contains('require("./notify_prefs")'), isTrue);
    expect(fn.contains('.where("notification_prefs.marketing", "==", false)'), isTrue);
    expect(fn.contains('excludeOptedOut(tokSnap.docs, optOut)'), isTrue, reason: 'بوش');
    expect(fn.contains('excludeOptedOut(usersSnap.docs, optOut)'), isTrue, reason: 'صندوق داخل التطبيق');
    expect(fn.contains('isMarketingBroadcast(data) ? await _marketingOptOutUids() : new Set()'), isTrue);
    final prefs = _read('functions/notify_prefs.js');
    expect(prefs.contains('data.operational !== true'), isTrue);

    final bc = _read('lib/screens/admin/admin_broadcast_screen.dart');
    expect(bc.contains("'operational': _operational,"), isTrue, reason: 'البثّ الفوري');
    expect(bc.contains('operational: _operational,'), isTrue, reason: 'البثّ المجدول');
    final svc = _read('lib/services/zyiarah_messaging_service.dart');
    expect(svc.contains("'operational': operational,"), isTrue);

    // العميل يكتب تفضيله على مستنده — القواعد لا تمنع notification_prefs للمالك.
    final screen = _read('lib/screens/client_notifications_screen.dart');
    expect(screen.contains("{'notification_prefs': {'marketing': enabled}}"), isTrue);
    expect(screen.contains('SetOptions(merge: true)'), isTrue);
    final rules = _read('firestore.rules');
    final u = rules.indexOf('match /users/{userId}');
    final block = rules.substring(u, rules.indexOf('allow delete', u));
    expect(block.contains('notification_prefs'), isFalse,
        reason: 'لو أُضيف يوماً لقائمة الممنوع على المالك انكسر الحفظ من التطبيق');
  });
}
