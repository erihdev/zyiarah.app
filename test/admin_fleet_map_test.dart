import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/fleet_vehicle.dart';
import 'package:zyiarah/screens/admin/admin_fleet_map_screen.dart';

/// رادار الأسطول المباشر (Stitch `_21`): النموذج النقيّ، والشاشة بتدفّق محقون
/// وطبقة بلاطات بديلة (لا شبكة ولا Firebase هنا).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final now = DateTime(2026, 9, 16, 12, 0);

  Map<String, dynamic> order({
    required String driverId,
    required String name,
    String status = 'on_the_way',
    double lat = 16.90,
    double lng = 42.55,
    DateTime? updated,
    String code = 'ZY-1001',
    String zone = 'صبيا',
    String client = 'أم خالد',
    String service = 'تنظيف منزلي',
  }) =>
      {
        'driver_id': driverId,
        'driver_name': name,
        'status': status,
        'driver_location': GeoPoint(lat, lng),
        if (updated != null) 'last_location_update': Timestamp.fromDate(updated),
        'code': code,
        'zone_name': zone,
        'client_name': client,
        'service_name': service,
      };

  group('FleetVehicle', () {
    test('fromOrder: GeoPoint + Timestamp، وبلا موقع أو سائق = null', () {
      final v = FleetVehicle.fromOrder(
          'o1',
          order(
              driverId: 'd1',
              name: 'أحمد يحيى الفيفي',
              updated: now.subtract(const Duration(minutes: 2))))!;
      expect(v.lat, 16.90);
      expect(v.lng, 42.55);
      expect(v.driverName, 'أحمد يحيى الفيفي');
      expect(v.initials, 'أي');
      expect(v.orderCode, 'ZY-1001');
      expect(v.taskLine, 'طلب #ZY-1001 · تنظيف منزلي · صبيا');
      expect(v.updatedAt, now.subtract(const Duration(minutes: 2)));
      expect(v.isMoving, isTrue);
      expect(v.isWorking, isFalse);

      // بلا موقع بعد (طلب مُسند لم ينطلق سائقه) ⇒ لا علامة.
      final noLoc = order(driverId: 'd1', name: 'x')..remove('driver_location');
      expect(FleetVehicle.fromOrder('o2', noLoc), isNull);
      // بلا سائق ⇒ لا علامة.
      final noDriver = order(driverId: '', name: 'x');
      expect(FleetVehicle.fromOrder('o3', noDriver), isNull);
      // خريطة {lat,lng} (كتابة قديمة) تُقرأ أيضاً، والاسم الفارغ/None يسقط للبديل.
      final legacy = order(driverId: 'd9', name: 'None')
        ..['driver_location'] = {'lat': 17.0, 'lng': 42.6}
        ..['assigned_driver'] = 'سليمان المالكي';
      final lv = FleetVehicle.fromOrder('o4', legacy)!;
      expect(lv.lat, 17.0);
      expect(lv.driverName, 'سليمان المالكي');
    });

    test('latestPerDriver: علامة واحدة لكل سائق — الأحدث موقعاً، مرتّبة بالحالة', () {
      final a1 = FleetVehicle.fromOrder(
          'a1',
          order(
              driverId: 'dA',
              name: 'أحمد',
              lat: 16.1,
              updated: now.subtract(const Duration(minutes: 30))))!;
      final a2 = FleetVehicle.fromOrder(
          'a2',
          order(
              driverId: 'dA',
              name: 'أحمد',
              lat: 16.2,
              updated: now.subtract(const Duration(minutes: 1))))!;
      final a3 = FleetVehicle.fromOrder(
          'a3', order(driverId: 'dA', name: 'أحمد', lat: 16.3))!; // بلا تحديث
      final b = FleetVehicle.fromOrder(
          'b1',
          order(
              driverId: 'dB',
              name: 'بدر',
              status: 'in_progress',
              updated: now))!;
      final list = FleetVehicle.latestPerDriver([a1, a3, b, a2]);
      expect(list.map((v) => v.driverId), ['dB', 'dA'],
          reason: 'قيد التنفيذ أولاً، وسائق واحد مرة واحدة');
      expect(list.last.lat, 16.2, reason: 'الأحدث تحديثاً يفوز، وبلا تحديث يخسر');
    });

    test('isStale / ageLabel / summarize', () {
      final fresh = FleetVehicle.fromOrder(
          'f', order(driverId: 'd1', name: 'أ', updated: now.subtract(const Duration(seconds: 20))))!;
      final old = FleetVehicle.fromOrder(
          'o',
          order(
              driverId: 'd2',
              name: 'ب',
              status: 'in_progress',
              updated: now.subtract(const Duration(minutes: 11))))!;
      final never = FleetVehicle.fromOrder('n', order(driverId: 'd3', name: 'ج'))!;
      expect(fresh.isStale(now), isFalse);
      expect(old.isStale(now), isTrue);
      expect(never.isStale(now), isTrue);
      expect(fresh.ageLabel(now), 'الآن');
      expect(old.ageLabel(now), 'قبل 11 د');
      expect(never.ageLabel(now), 'بلا تحديث');
      expect(fresh.ageLabel(now.add(const Duration(hours: 3))), 'قبل 3 س');
      final s = FleetVehicle.summarize([fresh, old, never], now);
      expect(s.total, 3);
      expect(s.working, 1);
      expect(s.moving, 2);
      expect(s.stale, 2);
    });
  });

  group('AdminFleetMapScreen', () {
    final vehicles = [
      FleetVehicle.fromOrder(
          'o-a',
          order(
              driverId: 'dA',
              name: 'أحمد الفيفي',
              code: 'ZY-8924',
              updated: now.subtract(const Duration(minutes: 2))))!,
      FleetVehicle.fromOrder(
          'o-b',
          order(
              driverId: 'dB',
              name: 'جابر الغزواني',
              status: 'in_progress',
              code: 'ZY-8930',
              lat: 17.30,
              lng: 43.10,
              zone: 'فيفاء',
              updated: now.subtract(const Duration(minutes: 30))))!,
    ];

    Future<List<FleetVehicle>> pump(WidgetTester t,
        {Stream<List<FleetVehicle>>? stream}) async {
      t.view.physicalSize = const Size(800, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final opened = <FleetVehicle>[];
      await t.pumpWidget(MaterialApp(
        home: AdminFleetMapScreen(
          vehicles: stream ?? Stream.value(vehicles),
          clock: () => now,
          tileLayer: const SizedBox.shrink(), // لا بلاطات من الشبكة في الاختبار
          openOrder: (_, v) => opened.add(v),
        ),
      ));
      await t.pump();
      await t.pump();
      return opened;
    }

    testWidgets('فارغ: لا سائق في مهمة الآن', (t) async {
      await pump(t, stream: Stream.value(const []));
      expect(find.text('لا سائق في مهمة الآن'), findsWidgets);
      expect(find.textContaining('تظهر المركبات هنا'), findsOneWidget);
    });

    testWidgets('سائقان: الملخص، القائمة بالحالة وعمر التحديث، والبلا-تحديث رمادي', (t) async {
      await pump(t);
      expect(find.text('2 في مهمة الآن • 1 قيد التنفيذ • 1 في الطريق • 1 بلا تحديث حديث'),
          findsOneWidget);
      expect(find.text('أحمد الفيفي'), findsOneWidget);
      expect(find.text('جابر الغزواني'), findsOneWidget);
      expect(find.text('في الطريق'), findsOneWidget);
      expect(find.text('بلا تحديث حديث'), findsOneWidget,
          reason: 'قيد التنفيذ لكن آخر موقع قبل 30 د ⇒ يُعرض كبلا تحديث حديث');
      expect(find.textContaining('قبل 2 د'), findsOneWidget);
      expect(find.textContaining('قبل 30 د'), findsOneWidget);
      expect(find.text('طلب #ZY-8924 · تنظيف منزلي · صبيا'), findsOneWidget);
      // حروف كل سائق مرتين: علامته على الخريطة + صورته الرمزية في القائمة.
      expect(find.text('أا'), findsNWidgets(2));
      expect(find.text('جا'), findsNWidgets(2));
      // لا بطاقة مختارة قبل النقر.
      expect(find.text('تفاصيل الطلب'), findsNothing);
    });

    testWidgets('النقر على سائق يختاره ويُظهر بطاقته فوق الخريطة', (t) async {
      await pump(t);
      await t.tap(find.text('أحمد الفيفي'));
      await t.pump();
      expect(find.text('تفاصيل الطلب'), findsOneWidget);
      expect(find.text('أحمد الفيفي — في الطريق'), findsOneWidget);
    });

    testWidgets('زر تفاصيل الطلب يسلّم الطلب الصحيح', (t) async {
      final opened = await pump(t);
      await t.tap(find.widgetWithIcon(IconButton, Icons.open_in_new_rounded).first);
      await t.pump();
      expect(opened.map((v) => v.orderId), ['o-a']);
    });

    testWidgets('فشل التدفّق: رسالة وإعادة محاولة — لا خريطة خضراء كاذبة', (t) async {
      await pump(t, stream: Stream<List<FleetVehicle>>.error(StateError('offline')));
      expect(find.textContaining('تعذّر تحميل الأسطول'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  test('المصدر: القائمة الإدارية بدورَي الطلبات، استعلام بلا فهرس جديد، والسائق يبثّ الموقع في الحالات نفسها',
      () {
    final more = File('lib/screens/admin/admin_more_screen.dart').readAsStringSync();
    final i = more.indexOf("'رادار الأسطول المباشر'");
    expect(i, greaterThan(-1));
    final entry = more.substring(i, more.indexOf('},', i));
    expect(entry.contains('const AdminFleetMapScreen()'), isTrue);
    expect(entry.contains("'super_admin'"), isTrue);
    expect(entry.contains("'orders_manager'"), isTrue);
    expect(entry.contains("'accountant_admin'"), isFalse);
    expect(entry.contains("'marketing_admin'"), isFalse);

    final screen = File('lib/screens/admin/admin_fleet_map_screen.dart').readAsStringSync();
    expect(screen.contains(".where('status', whereIn: FleetVehicle.activeStatuses)"), isTrue);
    expect(screen.contains('.orderBy('), isFalse,
        reason: 'whereIn + orderBy كان سيتطلب فهرساً مركّباً جديداً');
    expect(screen.contains('.snapshots()'), isTrue, reason: 'رادار حيّ لا لقطة');

    // حالات الرادار = الحالات التي يبدأ فيها تطبيق السائق بثّ موقعه.
    final dash = File('lib/screens/driver_dashboard.dart').readAsStringSync();
    for (final s in FleetVehicle.activeStatuses) {
      expect(dash.contains("focusStatus == '$s'"), isTrue,
          reason: 'driver_dashboard يبثّ الموقع في $s');
    }
    final svc = File('lib/services/order_service.dart').readAsStringSync();
    expect(svc.contains("'driver_location': location,"), isTrue);
    expect(svc.contains("'last_location_update': FieldValue.serverTimestamp(),"), isTrue);

    // الإدارة تقرأ كل الطلبات (isAdmin) — فالرادار لا يحتاج قاعدة جديدة.
    final rules = File('firestore.rules').readAsStringSync();
    final o = rules.indexOf('match /orders/{orderId}');
    final readBlock = rules.substring(o, rules.indexOf('allow create', o));
    expect(readBlock.contains('isAdmin()'), isTrue);
  });
}
