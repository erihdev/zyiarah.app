import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حرّاس إصلاحات تدقيق نظام السائق (2026-07-18): 17 ثغرة مؤكَّدة عبر ستة محاور،
/// أُصلحت جميعها. هذه الحرّاس تمنع عودة أبرزها (ظاهرة وصامتة).
String _strip(String src) {
  src = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return src.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}

void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final fn = File('functions/index.js').readAsStringSync();
  final dash = _strip(File('lib/screens/driver_dashboard.dart').readAsStringSync());
  final notif =
      File('lib/screens/driver_notifications_screen.dart').readAsStringSync();
  final tasks = File('lib/screens/driver_tasks_screen.dart').readAsStringSync();
  final profile =
      File('lib/screens/driver_profile_screen.dart').readAsStringSync();
  final orderSvc = File('lib/services/order_service.dart').readAsStringSync();

  test('القاعدة: بقاء الحالة (كتابة موقع) أو التقدّم فقط — لا رجوع للخلف', () {
    // كتابة الموقع تُبقي الحالة (كان طلب accepted يُرفَض صامتاً فتتجمّد الخريطة)،
    // وصياغة «البقاء أو التقدّم» تمنع الرجوع (in_progress → accepted) الذي تسمح
    // به قائمةٌ صرفة — كان انحداراً في الإصلاح الأول صحّحته المراجعة الثانية.
    expect(
        rules.contains(
            'request.resource.data.status == resource.data.status ||'),
        isTrue,
        reason: 'بقاء الحالة يجب أن يكون مسموحاً لكتابة الموقع في أي حالة نشطة');
    expect(
        rules.contains(
            "request.resource.data.status in ['on_the_way', 'in_progress', 'completed']"),
        isTrue,
        reason: 'التقدّم للأمام فقط — لا رجوع للخلف');
  });

  test('نوافذ الإسناد الخادمية موحّدة −24س (تلتقط العابر لمنتصف الليل والطويل)', () {
    // حدود اليوم التقويمي UTC كانت تُفوّت مهمة سائق في اليوم السابق فيُعاد اختياره
    // ويرفضه الفحص الذرّي فيبقى الطلب المدفوع عالقاً.
    expect(fn.contains('getFullYear(), startDateTime.getMonth()'), isFalse,
        reason: 'حدود اليوم التقويمي عادت — تُفوّت التعارض العابر لمنتصف الليل');
    final n24 = RegExp(r'startDateTime\.getTime\(\) - 24 \* 60 \* 60 \* 1000')
        .allMatches(fn)
        .length;
    expect(n24, greaterThanOrEqualTo(3),
        reason: 'المواضع الثلاثة (find/isFree/atomic) يجب أن تستخدم نافذة −24س');
  });

  test('تذكير السائق عبر queuePush لا _pushToUid (وارد يصل بلا توكن FCM)', () {
    final i = fn.indexOf('exports.remindDriversUpcomingTasks');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('queuePush('), isTrue,
        reason: '_pushToUid يتخطّى بصمت السائق بلا توكن فلا يصله تذكير');
    expect(body.contains('_pushToUid('), isFalse);
  });

  test('إشعار إلغاء المهمة للسائق خادميّ واحد (بلا ازدواج)', () {
    final i = fn.indexOf('exports.freeDriverOnOrderCancel');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('driver_task_removed'), isTrue,
        reason: 'الإلغاء المباشر (قائمة الأدمن) كان يحرّر السائق بلا إشعار');
    // أُزيل نداء العميل المُضاعِف.
    expect(orderSvc.contains("type: 'driver_order_cancelled'"), isFalse,
        reason: 'إبقاؤه يُضاعف الإشعار عند إلغاء العميل/الإدارة');
  });

  test('تصعيد الطلب المدفوع العالق للإدارة', () {
    final i = fn.indexOf('exports.sweepUnassignedPaidOrders');
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('stranded_alerted'), isTrue,
        reason: 'طلب مدفوع فات موعده بلا سائق كان يختفي خادميّاً بلا تنبيه');
  });

  test('وارد إشعارات السائق مرتّب بالأحدث (sentAt)', () {
    expect(notif.contains("orderBy('sentAt', descending: true)"), isTrue,
        reason: 'بلا ترتيب كان limit(50) يُرجع الأقدم بترتيب المعرّف فتختفي الجديدة');
  });

  test('تسميات مهام السائق تشمل scheduled و on_the_way', () {
    expect(tasks.contains("case 'scheduled':"), isTrue);
    expect(tasks.contains("case 'on_the_way':"), isTrue);
  });

  test('عدّاد إنجاز السائق = المكتملة فقط لا التقييمات', () {
    expect(
        profile.contains("(data['completed_orders_count'] as num?)?.toInt() ?? 0"),
        isTrue);
    expect(profile.contains("data['rating_count']"), isFalse,
        reason: 'السقوط على عدد التقييمات يعرض رقماً لا علاقة له بالإنجاز');
  });

  test('حراسة الويب: openAppSettings بحارس kIsWeb', () {
    expect(dash.contains('kIsWeb ? () {} : () => Geolocator.openAppSettings()'),
        isTrue,
        reason: 'openAppSettings ترمي UnimplementedError على الويب');
  });

  test('تدفّق GPS واحد للطلب النشط (ناقل مواقع المزامنة) بلا تعطّل إعادة الاشتراك', () {
    expect(dash.contains('_posHub'), isTrue);
    expect(dash.contains('_syncSub != null ? _posHub.stream : _locationStream'),
        isTrue,
        reason: 'تدفّقا GPS متزامنان يضاعفان استهلاك البطارية');
    // asBroadcastStream إلزامي: تدفّق getPositionStream أحادي الاشتراك، وإعادة
    // بناء بطاقة التركيز تعيد الاشتراك ⇒ «Stream has already been listened to»
    // (شاشة حمراء ظاهرة). البثّ يسمح بإعادة الاشتراك بأمان.
    expect(dash.contains('.asBroadcastStream()'), isTrue,
        reason: 'بدون البثّ يتعطّل تدفّق الموقع بإعادة الاشتراك ويعرض شاشة حمراء');
  });

  test('بدء الأسبوع في الإحصاءات مُقتطع لمنتصف الليل', () {
    expect(dash.contains('todayStart.subtract(Duration(days: now.weekday - 1))'),
        isTrue);
  });
}
