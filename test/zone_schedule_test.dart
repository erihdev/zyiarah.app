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

  test('نسخ الأسعار لمناطق مختارة — الأسعار فقط، باختيار صريح من قائمة', () {
    // طلب المالك بعد تجربة نسخة «الكل»: قائمة بكل المدن يختار منها ما يُطبَّق عليه.
    // حصرُ الحقول في الأسعار هو الضمانة ألا يمسح النسخ أسماء المناطق أو مواقعها
    // أو جداول فتحها.
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(s.contains('_applyPricesToZones'), isTrue);
    expect(s.contains('_pickTargetZones'), isTrue);
    expect(s.contains('اختر المناطق لتطبيق الأسعار'), isTrue,
        reason: 'القائمة تعرض كل المدن للاختيار');
    expect(s.contains('تحديد الكل'), isTrue,
        reason: 'اختصار «الكل» يبقي سلوك التعميم الكامل متاحاً بنقرة');
    expect(s.contains('CheckboxListTile'), isTrue);

    final i = s.indexOf('Future<int> _applyPricesToZones');
    expect(i, greaterThan(-1));
    final body = s.substring(i, s.indexOf('\n  }', i));
    for (final forbidden in ["'name'", "'centerLoc'", "'radiusKm'", "'enabled'", "'schedule'", "'rank'"]) {
      expect(body.contains(forbidden), isFalse,
          reason: 'النسخ كتب $forbidden — يجب أن يقتصر على الأسعار');
    }
    // زرّ الحفظ معطّل بلا اختيار — لا نسخ صفري ولا نسخ بالخطأ.
    expect(s.contains('selected.isEmpty'), isTrue);
  });

  test('قائمة «نسخ الأسعار من منطقة سابقة» تملأ الحقول ولا تكتب على أحد', () {
    // طلب المالك: عند إضافة مدينة جديدة، منسدلة بالمدن السابقة — يختار واحدة
    // فتُنسخ أسعارها إلى حقول النموذج فوراً («تنتسخ وتلتصق») ثم يحفظ عادي.
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(s.contains('نسخ الأسعار من منطقة سابقة'), isTrue);
    expect(s.contains('DropdownButtonFormField<String>'), isTrue);
    // تعبئة نموذج فقط: الاختيار يكتب في المتحكّمات لا في Firestore.
    final i = s.indexOf('نسخ الأسعار من منطقة سابقة');
    // حتى نهاية onChanged — نافذة ثابتة (2600) كانت أقصر من الشيفرة فسقط الحارس
    // على حقولٍ موجودة فعلاً عند 2879+.
    final end = s.indexOf('const SizedBox(height: 12)', i);
    final region = s.substring(i, end > i ? end : i + 5000);
    expect(region.contains('pSofaSqmCtrl.text ='), isTrue,
        reason: 'النسخ يملأ حقول م² لا الساعات فقط');
    expect(region.contains('pAcWashSplitCtrl.text ='), isTrue,
        reason: 'النسخ يملأ أسعار المكيفات الأربعة');
    expect(region.contains('.update(') || region.contains('.set('), isFalse,
        reason: 'الاختيار من المنسدلة تعبئة نموذج — لا كتابة على أي منطقة');
    // المنطقة الحالية لا تظهر في قائمة النسخ من نفسها.
    expect(s.contains('d.id != doc?.id'), isTrue);
  });

  test('حوار المنطقة بعرض مضبوط — وإلا انفجر قياس IntrinsicWidth على الخريطة', () {
    // AlertDialog يقيس محتواه بـ IntrinsicWidth، وخريطة المعاينة (FlutterMap =
    // LayoutBuilder) لا تدعم الأبعاد الذاتية — فيُبنى الحوار بلا مقاس، غير مرئي،
    // يبتلع النقرات ⇒ زرّ تعديل يبدو ميتاً (شوهد في وحدة تحكم متصفح المالك).
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    final i = s.indexOf('content: SizedBox(');
    expect(i, greaterThan(-1),
        reason: 'محتوى الحوار يجب أن يبدأ بعرض صريح يوقف القياس الذاتي قبل الخريطة');
    expect(s.substring(i, i + 80).contains('width:'), isTrue);
  });

  test('خريطة المنطقة حيّة: ظاهرة دائماً، نقرة تحدّد المركز، والدائرة تتبع نصف القطر', () {
    // طلب المالك: عند إضافة مدينة تظهر الخريطة تحت الاسم مباشرة بمركزها وقطرها،
    // وتغيير نصف القطر يُصغّر/يُكبّر الدائرة حيّاً — لا خريطة مخفيّة خلف زرّ.
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    // ليست مشروطة بتحديد سابق: المركز nullable مع مركز افتراضي لجازان.
    expect(s.contains('final GeoPoint? center;'), isTrue);
    expect(s.contains('_fallbackCenter'), isTrue);
    // النقر على الخريطة يضع المركز.
    expect(s.contains('onTap: (tapPos, ll) =>'), isTrue);
    expect(s.contains('onPick(GeoPoint(ll.latitude, ll.longitude))'), isTrue);
    // الدائرة تقرأ نصف القطر من الحقل حيّاً (الحقل يعيد الرسم عند كل تغيير).
    expect(s.contains('onChanged: (_) => setDialogState(() {})'), isTrue,
        reason: 'بدونها لا تتحدث الدائرة أثناء الكتابة');
    expect(s.contains('radius: radiusKm * 1000'), isTrue);
    // إرشاد ظاهر قبل التحديد بدل خريطة صامتة.
    expect(s.contains('اضغط لوضع المركز هنا'), isTrue);
  });

  test('كتابة اسم المنطقة تنقل الخريطة إليه تلقائياً', () {
    // طلب المالك: «كتبت صبيا — المفترض ينقلني مباشرة إلى صبيا». الاسم يُرمَّز
    // جغرافياً (مؤجَّلاً كي لا نستعلم عند كل حرف) ويضع المركز على الخريطة.
    final s = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(s.contains('_geocodeZoneName'), isTrue);
    expect(s.contains('nameDebounce'), isTrue,
        reason: 'بلا تأجيل نستعلم Mapbox عند كل حرف');
    expect(s.contains('country=sa'), isTrue,
        reason: 'التقييد بالسعودية يمنع القفز لتشابهات خارجها');
    expect(s.contains('proximity=43.0505,17.3023'), isTrue,
        reason: 'الانحياز لجازان يقدّم صبيا-جازان على أي تشابه أبعد');
    expect(s.contains('.timeout(const Duration(seconds: 8))'), isTrue,
        reason: 'استعلام معلّق يجب ألا يعلّق شيئاً');
    // الفشل مساعدة صامتة مقصودة لكنه يُسجَّل — لا ابتلاع أعمى.
    expect(s.contains('[ZoneGeocode] failed'), isTrue);
  });

  test('السبلاش لا يُحرّك متحكّماً بعد الإتلاف', () {
    // AuthWrapper يستبدل السبلاش فور جاهزية الدور — قبل انقضاء مهلات الحركة.
    final s = File('lib/screens/splash_screen.dart').readAsStringSync();
    final i = s.indexOf('_startAnimation() async');
    final body = s.substring(i, s.indexOf('  }', i));
    final guards = RegExp(r'if \(!mounted\) return;').allMatches(body).length;
    final forwards = RegExp(r'_\w+Controller\.forward').allMatches(body).length;
    expect(forwards, greaterThan(0),
        reason: 'صفر forward = الحارس يفحس نصاً خاطئاً وينجح كذباً (درس \\b السابق)');
    expect(guards, forwards,
        reason: 'كل forward بعد await يحتاج حارس mounted — وإلا رمى بعد dispose');
  });
}
