// حارس ميزة جدول فتح المنطقة: الخادم مرجعيّ، والعرض يميّز «مغلق» عن «ممتلئ».
//
// طلب العميل: بطاقة تسمح باختيار المنطقة + التاريخ + الوقت — فتح منطقة بتواريخ
// وساعات معيّنة (وجدول أسبوعي متكرر). النموذج المختار: الأسبوعي + windows (فتح
// استثنائي) + blackouts (إغلاق استثنائي).
//
// **مبدآن مثبَّتان:**
// 1. **الخادم هو المرجع.** getHourlyAvailability يحسب closedDates/openHours، وبوابة
//    الدفع تفرضها — فلا يمكن حجز موعد خارج ساعات عمل المنطقة ولو تُجووِز العرض.
// 2. **«مغلق» ≠ «ممتلئ».** يومٌ لا تُخدَم فيه المنطقة (رمادي) سببٌ مختلف عن يومٍ
//    محجوز بالكامل (أحمر) — عرضهما بلون واحد هو نفس مرض «رسالة واحدة لكل شيء».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();
String _code(String p) => _read(p)
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  group('الخادم مرجعيّ لجدول الفتح', () {
    final fn = _read('functions/index.js');

    test('يحسب ساعات الفتح لكل تاريخ', () {
      expect(fn.contains('function zoneOpenHoursForDate'), isTrue);
      expect(fn.contains('closedDates'), isTrue);
      expect(fn.contains('openHours'), isTrue);
    });

    test('الأولوية: إغلاق ثم نافذة فتح ثم أسبوعي', () {
      final i = fn.indexOf('function zoneOpenHoursForDate');
      final body = fn.substring(i, fn.indexOf('\n}', i));
      // blackout يُفحص أولاً (يتقدّم)
      final blackoutAt = body.indexOf('blackouts');
      final windowAt = body.indexOf('windows');
      final weeklyAt = body.indexOf('weekly');
      expect(blackoutAt, greaterThan(-1));
      expect(blackoutAt < windowAt && windowAt < weeklyAt, isTrue,
          reason: 'الترتيب: الإغلاق يتقدّم الفتح الاستثنائي يتقدّم الأسبوعي');
    });

    test('توافق خلفي: بلا جدول ⇒ مفتوحة 8..22', () {
      expect(fn.contains('const DEFAULT_OPEN = [8, 22]'), isTrue);
      final i = fn.indexOf('function zoneOpenHoursForDate');
      final body = fn.substring(i, fn.indexOf('\n}', i));
      expect(body.contains('schedule.enabled !== true) return DEFAULT_OPEN'), isTrue,
          reason: 'المناطق القائمة بلا schedule يجب أن تبقى مفتوحة كما كانت');
    });

    test('zoneName تُستعمل للجدول لا لترشيح السائقين', () {
      final i = fn.indexOf('exports.getHourlyAvailability');
      final body = fn.substring(i, fn.indexOf('return {', i));
      expect(body.contains('zoneName'), isTrue, reason: 'نحتاجها لجلب schedule');
      // لا ترشيح سائقين بالمنطقة (السائقون بلا مناطق)
      expect(body.contains('assigned_zones'), isFalse);
    });
  });

  group('بوابة الدفع تفرض الجدول خادميّاً', () {
    final gate = _code('lib/screens/payment_summary_screen.dart');
    test('اليوم المغلق يُمنع', () {
      expect(gate.contains("data['closedDates']"), isTrue);
      expect(gate.contains('لا نخدم منطقتك في هذا اليوم'), isTrue);
    });
    test('الساعة خارج نطاق الفتح تُمنع', () {
      expect(gate.contains("data['openHours']") || gate.contains("openHoursMap"), isTrue);
      expect(gate.contains('خارج ساعات عمل منطقتك'), isTrue);
    });
    test('تمرّر zoneName لجلب الجدول', () {
      final i = gate.indexOf('Future<String?> _checkHourlyCapacity');
      final body = gate.substring(i, gate.indexOf('Future<void> _handlePayment', i));
      expect(body.contains("'zoneName': widget.zoneName"), isTrue);
    });
  });

  group('العرض يميّز مغلق عن ممتلئ', () {
    for (final p in [
      'lib/widgets/booking_slot_picker.dart',
      'lib/screens/hourly_details_screen.dart',
    ]) {
      test('$p: حالة إغلاق منفصلة برسالة مختلفة', () {
        final s = _code(p);
        expect(s.contains('_closedDates') || s.contains('closedDates'), isTrue, reason: p);
        expect(s.contains('لا نخدم منطقتك في هذا اليوم'), isTrue,
            reason: '$p يعرض «مغلق» برسالته الخاصة لا كـ«ممتلئ»');
      });
    }

    test('خانات البدء محصورة بساعات الفتح لا 8..22 دائماً', () {
      final s = _code('lib/widgets/booking_slot_picker.dart');
      expect(s.contains('_openHoursFor'), isTrue);
      final hourly = _code('lib/screens/hourly_details_screen.dart');
      expect(hourly.contains('_openHoursForSelected'), isTrue);
    });
  });

  group('محرّر الجدول في لوحة الإدارة', () {
    final ed = _code('lib/screens/admin/admin_zone_schedule_editor.dart');
    test('يبني weekly + windows + blackouts', () {
      expect(ed.contains("'weekly'"), isTrue);
      expect(ed.contains("'windows'"), isTrue);
      expect(ed.contains("'blackouts'"), isTrue);
      expect(ed.contains("'enabled'"), isTrue);
    });
    test('الساعات تُعرَض 12 وتُخزَّن 24 (int لا نص)', () {
      expect(ed.contains('formatHour12'), isTrue, reason: 'العرض 12 ساعة');
      expect(ed.contains("'start': e.value.start"), isTrue,
          reason: 'التخزين رقم ساعة 24 — الخادم يحلّله رقميّاً');
    });
    test('مدموج في حوار المنطقة ويُحفَظ في schedule', () {
      final zones = _code('lib/screens/admin/admin_hourly_zones_screen.dart');
      expect(zones.contains('ZoneScheduleEditor'), isTrue);
      expect(zones.contains("'schedule': scheduleData"), isTrue);
    });
  });

  test('«تطبيق على كل المناطق» يعمّم الأسعار فقط — لا الهوية ولا الجدول', () {
    // زرّ التعميم يستبدل أسعار كل المناطق بضغطة. حصرُ حقوله في الأسعار هو الضمانة
    // ألا يمسح تعميمٌ عابر أسماء المناطق أو مواقعها أو جداول فتحها.
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(s.contains('تطبيق على كل المناطق'), isTrue);
    expect(s.contains('_applyPricesToAllZones'), isTrue);

    final i = s.indexOf('Future<int> _applyPricesToAllZones');
    expect(i, greaterThan(-1));
    final body = s.substring(i, s.indexOf('\n  }', i));
    for (final forbidden in ["'name'", "'centerLoc'", "'radiusKm'", "'enabled'", "'schedule'", "'rank'"]) {
      expect(body.contains(forbidden), isFalse,
          reason: 'التعميم كتب $forbidden — يجب أن يقتصر على الأسعار');
    }
    // والتأكيد الصريح قبل الاستبدال الجماعي.
    expect(s.contains('تطبيق على كل المناطق؟'), isTrue,
        reason: 'استبدال جماعي بلا تأكيد = ضغطة خاطئة تمسح أسعار كل المناطق');
  });
}
