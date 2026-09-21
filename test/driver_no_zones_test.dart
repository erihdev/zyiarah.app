// حارس: السائقون بلا مناطق — والسعة رقم واحد للنشاط كلّه.
//
// قرار المالك: «لا أريد أي تحديد موقع لهم، أريده يقبل أي طلب يُسند له تلقائياً،
// وحسب السعة اليومية المتفق عليها مسبقاً».
//
// وأكّدته البيانات الحيّة: كلا السائقين بلا `zone_name`، و`assigned_zones` لم يُكتب
// في أي مكان قط — أي أن الترشيح الجغرافي كان يعمل دائماً على مسار «بلا منطقة».
//
// **الأهم — عطل حيّ أُصلح مع هذا التغيير:**
//   كان `getHourlyAvailability` يعدّ **السائقين عالمياً** (لأنهم بلا مناطق ⇒ مؤهّلون
//   لكل منطقة) بينما يعدّ **الطلبات بالمنطقة**. فالبسط من عالمٍ والمقام من عالمٍ آخر:
//   سائقان مشغولان بطلبَي «الدائر» الساعة 10، وعميلة «أبو السلع» ترى عدّادها صفراً
//   فتحجز نفس الساعة ⇒ 3 طلبات وسائقان ⇒ **طلب مدفوع بلا سائق** — وهو بالضبط ما
//   وُجدت بوابة السعة لتمنعه.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  final fn = _code('functions/index.js');

  test('تسجيل السائق بلا حقل منطقة', () {
    final s = _code('lib/screens/admin/admin_drivers_screen.dart');
    expect(s.contains('zoneCtrl'), isFalse);
    expect(s.contains("'zone_name'"), isFalse,
        reason: 'السائق لا يُسنَد لمنطقة — يقبل أي طلب');
  });

  test('محرّك الإسناد لا يرشّح السائقين بالمنطقة', () {
    final i = fn.indexOf('async function _findFreeDriverForSlot');
    expect(i, greaterThan(-1), reason: 'مُحدِّد السائق اختفى — حدِّث الحارس');
    final body = fn.substring(i, fn.indexOf('\n}', i));
    expect(body.contains('zoneName'), isFalse,
        reason: 'ترشيح جغرافي يمنع إسناد سائق حرّ لطلب خارج منطقته');
    expect(body.contains('assigned_zones'), isFalse,
        reason: 'assigned_zones حقل ميت لم يُكتب قط');
    expect(body.contains('is_active !== false'), isTrue,
        reason: 'المؤهّل = السائق النشط، لا أكثر');
  });

  test('السعة: البسط والمقام من العالم نفسه', () {
    final i = fn.indexOf('exports.getHourlyAvailability');
    final body = fn.substring(i, fn.indexOf('\n});', i));
    // المقام: كل السائقين النشطين
    expect(body.contains('assigned_zones'), isFalse);
    // البسط: كل الطلبات — لا ترشيح بالمنطقة
    expect(body.contains('d.zone_name !== zoneName'), isFalse,
        reason: 'عدّ طلبات منطقةٍ واحدة مقابل كل السائقين = حجز زائد = طلب بلا سائق');
    expect(body.contains('maxTeamsPerSlot: driverCount'), isTrue);
  });

  test('zoneName لا يُرشّح السائقين — لكنه مسموح لجلب جدول المنطقة', () {
    // تحديث: صار العميل **يمرّر** zoneName ليجلب **جدول فتح المنطقة**
    // (getHourlyAvailability يستعمله لذلك فقط، لا لعدّ السائقين). الثابت الحقيقي:
    // المنطقة لا تصفّي السائقين — لا أن العميل يمتنع عن إرسالها.
    final fn = _read('functions/index.js');
    final i = fn.indexOf('exports.getHourlyAvailability');
    final body = fn.substring(i, fn.indexOf('return {', i));
    // تُستعمل لجلب schedule
    expect(body.contains('zoneName'), isTrue);
    expect(body.contains('.where("name", "==", zoneName)'), isTrue,
        reason: 'zoneName يجلب مستند المنطقة لقراءة جدولها');
    // لكن لا تُرشِّح السائقين بها: كتلة عدّ السائقين (من استعلام drivers حتى
    // driverCount) لا تعرف zoneName إطلاقاً.
    final driverBlock = body.substring(
        body.indexOf('drivers'), body.indexOf('const driverCount'));
    expect(driverBlock.contains('zoneName'), isFalse,
        reason: 'عدّ السائقين يجب أن يبقى عالميّاً — المنطقة للجدول لا للسعة');
    // ولا تُرشِّح استعلام الطلبات بها: العدّ العام (dailyCounts/slotCounts) يشمل
    // **كل المناطق** لأن المقام (السائقون) عالمي. السقف الخاص بالمنطقة يُعدّ على
    // حدة داخل countBookings (zoneDailyCounts) ولا يمسّ العدّ العام.
    final ordersBlock = body.substring(body.indexOf('db.collection("orders")'));
    expect(ordersBlock.contains('.where("zone_name"'), isFalse,
        reason: 'ترشيح الطلبات بالمنطقة مقابل سائقين عالميين = حجز زائد');
    expect(ordersBlock.contains('countBookings('), isTrue);
  });

  test('لا طلب مدفوع بلا سائق: الإسناد يُطلق خادمياً لحظة انقلاب is_paid', () {
    // مبدأ المالك: «لا طلب بدون سائق متاح». كان الإسناد بيد تطبيق العميل بعد
    // الدفع والمكنسة كل 15 دقيقة ضماناً — فموت التطبيق لحظة النجاح يترك طلباً
    // مدفوعاً بلا سائق ربع ساعة. المشغّل الخادمي يقلّصها لثوانٍ.
    final i = fn.indexOf('exports.onOrderWritten');
    expect(i, greaterThan(-1));
    final body = fn.substring(i, fn.indexOf('exports.', i + 10));
    expect(body.contains('paidFlipped'), isTrue);
    expect(body.contains('_findFreeDriverForSlot'), isTrue);
    expect(body.contains('_assignDriverScheduled'), isTrue);
    // مسرحية 18 طلباً: السطر كان يقول «assigned» حتى حين ترفض المعاملة —
    // التسجيل يجب أن يحترم قيمة الإرجاع (res.assigned) في الكتلتين.
    expect(RegExp(r'res\.assigned').allMatches(body).length,
        greaterThanOrEqualTo(2),
        reason: 'سجلّ كاذب يخفي سباقات الحجز المزدوج المصدودة');
    // شرط عدم إعادة الإطلاق: لا إسناد إن وُجد سائق أصلاً.
    expect(body.contains('!afterData.driver_id'), isTrue,
        reason: 'بدونها تعيد كتابتُنا إطلاقَ المشغّل بلا نهاية');
    // والمكنسة الدورية تبقى الضمان الأخير — لا تُحذف.
    // (إيقاعها يفحصه no_admin_approval_test مُقيَّداً بجسم الدالة — فحص الملف
    // كله هنا سبق أن غطّى على استبدالٍ أصاب كروناً آخر.)
    expect(fn.contains('sweepUnassignedPaidOrders'), isTrue);
    // الضمان الحدثي: تحرُّر سائق (إلغاء/إكمال) يُعيد محاولة الإسناد فوراً.
    expect(fn.contains('driverFreed'), isTrue,
        reason: 'السائق يتحرّر بحدثٍ لا بمرور الوقت — فالمحاولة تُطلق بالحدث');
  });

  test('السقف اليومي يبقى من الإعدادات — هو «السعة المتفق عليها مسبقاً»', () {
    final i = fn.indexOf('exports.getHourlyAvailability');
    final body = fn.substring(i, fn.indexOf('\n});', i));
    expect(body.contains('max_orders_per_day'), isTrue);
    final admin = _code('lib/screens/admin/admin_settings_screen.dart');
    expect(admin.contains('max_orders_per_day'), isTrue,
        reason: 'المالك يجب أن يضبط السقف اليومي من لوحته');
  });
}
