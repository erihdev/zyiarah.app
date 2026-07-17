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

  test('العميلة لا تُرسل zoneName للسعة (لم تعد تعني شيئاً)', () {
    for (final p in [
      'lib/widgets/booking_slot_picker.dart',
      'lib/screens/hourly_details_screen.dart',
      'lib/screens/payment_summary_screen.dart',
    ]) {
      final s = _code(p);
      final i = s.indexOf('getHourlyAvailability');
      if (i == -1) continue;
      final window = s.substring(i, (i + 420).clamp(0, s.length));
      expect(window.contains("'zoneName'"), isFalse,
          reason: '$p ما زال يمرّر zoneName لدالة تتجاهلها — بارامتر يكذب');
    }
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
