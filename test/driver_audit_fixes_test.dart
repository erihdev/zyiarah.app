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

  test('تدفّق GPS واحد فعليّ (geolocator يسمح بواحد ويتجاهل إعدادات اللاحق)', () {
    // تدفّقان (خفيف للواجهة + تتبّع للرفع) = إعدادات الخدمة الأمامية لا تُطبَّق
    // فيتجمّد تتبّع العميل عند تصغير التطبيق. مصدرٌ واحد يُلغى ويُعاد إنشاؤه.
    expect(dash.contains('_startPositionStream'), isTrue);
    expect(dash.contains('_syncSub'), isFalse,
        reason: 'تدفّق ثانٍ يبطل إعدادات التتبّع الخلفي');
    expect(dash.contains('_locationStream'), isFalse,
        reason: 'التدفّق الثاني للواجهة أُزيل — الكل عبر _posHub');
    // الإلغاء قبل إعادة الإنشاء إلزامي كي تُطبَّق الإعدادات الجديدة فعلاً.
    expect(dash.contains('await _posSub?.cancel()'), isTrue,
        reason: 'بلا إلغاء يعيد geolocator استخدام إعدادات التدفّق القديم');
    // الواجهة تقرأ من البثّ دائماً (لا تدفّق أحادي الاشتراك يتعطّل بإعادة البناء).
    expect(dash.contains('stream: _posHub.stream'), isTrue);
    expect(dash.contains('.asBroadcastStream()'), isFalse);
  });

  test('توكن FCM يُحفظ عند تسجيل الدخول (لا فجوة لأول إسناد)', () {
    final ns = File('lib/services/notification_service.dart').readAsStringSync();
    final i = ns.indexOf('authStateChanges().listen');
    final region = ns.substring(i, i + 900);
    expect(region.contains('_saveTokenToFirestore'), isTrue,
        reason: 'من يسجّل الدخول دون إعادة تشغيل لا يُكتب توكنه فلا تصله بانرات');
  });

  test('كادر التنظيف (worker) كادرٌ ميداني لا عميل', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains("role == 'driver' || role == 'worker'"), isTrue,
        reason: 'worker كان يصل لوحة العميل (يُنشأ بدور = نوعه)');
    final router = File('lib/router.dart').readAsStringSync();
    expect(router.contains("role != 'driver' && role != 'worker'"), isTrue);
  });

  test('getUserRole يرجع null عند خطأ صلب (تفعيل شاشة إعادة المحاولة)', () {
    final fs = File('lib/services/firebase_service.dart').readAsStringSync();
    expect(fs.contains('Future<String?> getUserRole'), isTrue);
    // القدرة على تمييز «خطأ» عن «عميل فعلاً» — كان يرجع client دائماً.
    final ci = fs.indexOf('catch (e) {');
    // أول catch بعد توقيع getUserRole
    final gi = fs.indexOf('getUserRole');
    final after = fs.substring(gi);
    expect(after.contains('return null;'), isTrue,
        reason: 'إرجاع client عند الخطأ يصل السائق لوحة العميل بصمت');
  });

  test('بطاقة التركيز تعرض موعد المهمة للسائق', () {
    final i = dash.indexOf('_buildStateGuidedCard');
    final body = dash.substring(i, i + 4600);
    expect(body.contains("formatSlot12(data['booking_time_slot']"), isTrue,
        reason: 'كان الموعد يظهر على بطاقات القائمة لا على بطاقة التركيز');
  });

  test('كل بطاقات السائق تعرض تفصيل الطلب (موقع/عاملات/تفصيل الخدمة)', () {
    // طلب المالك: السائق يستوعب طلب العميل ولا يخلط أو ينسى — الموقع وعدد
    // العاملات وتفصيل الخدمة على البطاقة نفسها لا خلف نقرة.
    expect(dash.contains('_orderDetailStrip(data)'), isTrue,
        reason: 'بطاقة التركيز يجب أن تعرض شريط التفصيل الكامل');
    expect(dash.contains('_orderDetailStrip(data, compact: true)'), isTrue,
        reason: 'بطاقة القائمة يجب أن تعرض شريط التفصيل المختصر');
    // عدد العاملات للساعية، وملخّص service_meta للمكيفات/الكنب/السيارة.
    expect(dash.contains('_workersLabel(data['), isTrue);
    expect(dash.contains("zyiarahServiceMetaSummary(data['service_meta'])"),
        isTrue);
    // الموقع (المنطقة) بأيقونة على كل بطاقة.
    expect(dash.contains("data['zone_name']"), isTrue);
  });

  test('بدء الأسبوع في الإحصاءات مُقتطع لمنتصف الليل', () {
    expect(dash.contains('todayStart.subtract(Duration(days: now.weekday - 1))'),
        isTrue);
  });
}
