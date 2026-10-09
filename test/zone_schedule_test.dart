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

import 'package:zyiarah/utils/zone_schedule.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

String _read(String p) => File(p).readAsStringSync();
// النسخة الواحدة المختبَرة: تَحفظ النصوص (الفحوص تَشدّ حروفاً عربيّة) وتفهم
// الكتل والقوالب — والصياغة المحلّيّة السابقة كانت تَقتطع نصّاً فيه `https://`.
String _code(String p) => stripComments(_read(p));

/// **كلُّ سطحٍ يَسأل `getHourlyAvailability`** — مُشتَقٌّ لا مكتوبٌ بيد.
///
/// محرِّرُ جدولِ المنطقةِ مُستثنىً بسببِه: كاتبٌ إداريٌّ يُعاين جدولَه هو، لا
/// سطحَ حجزٍ يَرسم للعميلةِ يوماً وساعة (ولا يُمرّر `zoneName` أصلاً).
final List<String> _availabilityConsumers = () {
  final out = <String>[];
  for (final f in [
    ...sourcesIn('lib/screens', atLeast: 40),
    ...sourcesIn('lib/widgets', atLeast: 8),
  ]) {
    final code = stripComments(f.readAsStringSync());
    if (!code.contains("httpsCallable('getHourlyAvailability')")) continue;
    final p = f.path.replaceAll(r'\', '/');
    if (p.endsWith('admin/admin_zone_schedule_editor.dart')) continue;
    out.add(p);
  }
  out.sort();
  // أرضيّةٌ متدنّيةٌ بقصد: سؤالُها «أجرى المسحُ شيئاً؟»، وأمّا **العضويّةُ**
  // فيَحكمها الفحصُ (و) بالأسماء — فأرضيّةٌ عند العددِ الحقيقيِّ (٥) كانت
  // تَحجبه: أيُّ نقصٍ يَرمي هنا قبلَ أن يَبلغَ المقارنةَ بالأسماء.
  if (out.length < 3) {
    throw StateError('مستهلكو الإتاحة ${out.length} — الاشتقاقُ انحلّ.');
  }
  return out;
}();

/// الأسطحُ التي **تُحدِّد منطقتَها بنفسِها** (GPS أو خريطة) ثمّ تَسأل الإتاحة:
/// الجلبُ الأوّلُ يَسبق معرفةَ المنطقةِ، فلها وحدَها يَلزم جلبٌ ثانٍ.
final List<String> _selfLocatingConsumers = _availabilityConsumers
    .where((p) => RegExp(r'_(?:user|selected)ZoneName\s*=\s*(?!=)')
        .hasMatch(stripComments(File(p).readAsStringSync())))
    .toList();

void main() {
  group('الخادم مرجعيّ لجدول الفتح', () {
    final fn = _read('functions/index.js');

    test('يحسب ساعات الفتح لكل تاريخ', () {
      expect(fn.contains('function zoneDayScheduleForDate'), isTrue);
      expect(fn.contains('function zoneOpenHoursForDate'), isTrue,
          reason: 'الغلاف التوافقي يبقى لأي مستهلك قديم');
      expect(fn.contains('closedDates'), isTrue);
      expect(fn.contains('openHours'), isTrue);
      // (تحكم المالك ساعة-بساعة) الاستجابة تحمل الساعات المقفلة لكل تاريخ.
      expect(fn.contains('closedHours'), isTrue);
    });

    test('الأولوية: إغلاق ثم نافذة فتح ثم أسبوعي', () {
      final i = fn.indexOf('function zoneDayScheduleForDate');
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
      final i = fn.indexOf('function zoneDayScheduleForDate');
      final body = fn.substring(i, fn.indexOf('\n}', i));
      expect(body.contains('{range: DEFAULT_OPEN, closed: []}'), isTrue,
          reason: 'المناطق القائمة بلا schedule يجب أن تبقى مفتوحة كما كانت');
    });

    test('الساعات المقفلة تُقرأ من weekly والنوافذ وتُبث للعميل', () {
      final i = fn.indexOf('function zoneDayScheduleForDate');
      final body = fn.substring(i, fn.indexOf('\n}', i));
      expect(body.contains('closedOf'), isTrue,
          reason: 'closed تُقرأ من مدخل اليوم/النافذة المطابق');
      expect(fn.contains('closedHours[ds] = daySched.closed'), isTrue,
          reason: 'الاستجابة تبث الساعات المقفلة لكل تاريخ');
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
      // الحقيقةُ المقصودةُ «البوّابةُ تَرفُض يوماً مغلقاً»، لا شكلُ القراءة:
      // كان الفحصُ يَشدّ `data['closedDates']` فسقطَ لحظةَ انتقالِ التحليلِ إلى
      // `ZoneSchedule` — بالنقل لا بالانحراف. والآن على القاعدةِ حيث تَسكن.
      expect(gate.contains('sched.dateIsClosed(bookingDate)'), isTrue,
          reason: 'البوّابةُ تَسأل القاعدةَ المشتركةَ لا تُحلّل الحقلَ بنفسِها');
      expect(gate.contains('لا نخدم منطقتك في هذا اليوم'), isTrue);
    });
    test('بوابة مزدوجة: باقات السكن باليوم، والخدمات المجدولة بخانتها المحددة', () {
      // باقات السكن (home_package): العميل اختار اليوم فقط — الشرط وجود **أي**
      // فترة بطول الخدمة دون عدد السائقين ضمن ساعات الفتح.
      expect(gate.contains('sched.openHoursFor(bookingDate)'), isTrue,
          reason: 'نطاقُ الفتحِ من القاعدةِ المشتركة — لا 8..22 مكتوبةً هنا');
      expect(gate.contains("== 'home_package'"), isTrue,
          reason: 'التفريع بنوع الطلب — لا بوابة واحدة للجميع');
      expect(gate.contains('anyWindowFree'), isTrue);
      expect(gate.contains('لا يوجد فريق متاح لمدة الخدمة'), isTrue);
      // بقية الخدمات المجدولة (كنب/مكيفات/سيارات/متجر) اختارت خانةً محددة —
      // تُفحص خانتها هي: ضمن الفتح + سائق حرّ طوالها (كما كان دائماً).
      expect(gate.contains('خارج ساعات عمل منطقتك'), isTrue);
      expect(gate.contains('يرجى اختيار وقت بدء آخر'), isTrue);
    });
    test('تمرّر zoneName لجلب الجدول', () {
      final i = gate.indexOf('Future<String?> _checkHourlyCapacity');
      final body = gate.substring(i, gate.indexOf('Future<void> _handlePayment', i));
      expect(body.contains("'zoneName': widget.zoneName"), isTrue);
    });
  });

  group('العرض يميّز مغلق عن ممتلئ', () {
    // **نطاقٌ مُشتَقٌّ لا ملفّان بأسمائهما**: كان الفحصُ على اثنَين، وشاشتا
    // العقدِ — وهما أطولُ أثراً (زياراتٌ لأسابيع) — خارجَه، فكانتا تَقولانِ
    // «محجوز بالكامل» عن يومٍ لا نخدمه أصلاً.
    for (final p in _availabilityConsumers) {
      test('$p: حالة إغلاق منفصلة برسالة مختلفة', () {
        final s = _code(p);
        expect(s.contains('dateIsClosed('), isTrue,
            reason: '$p يَسأل القاعدةَ عن اليومِ المغلق');
        expect(s.contains('لا نخدم منطقتك في هذا اليوم'), isTrue,
            reason: '$p يعرض «مغلق» برسالته الخاصة لا كـ«ممتلئ»');
      });
    }

    test('خانات البدء محصورة بساعات الفتح لا 8..22 دائماً', () {
      final s = _code('lib/widgets/booking_slot_picker.dart');
      expect(s.contains('_openHoursFor'), isTrue);
      // (باقات السكن) الإرساء الداخلي يبدأ من ساعة فتح المنطقة ولا يتجاوز
      // (الإغلاق − المدة) — نفس القيد بلا واجهة أوقات.
      final hourly = _code('lib/screens/hourly_details_screen.dart');
      expect(hourly.contains('_openHoursFor(d)'), isTrue);
      // القيدُ المحروس هو **القيد** لا اسمُ الحقل: الإرساءُ لا يتجاوز
      // (الإغلاق − المدة). والمدّةُ صارت مشتقّةً من باقات المنطقة
      // (`_availabilityHours` ← `homeStripDurationHours`) بدل الحقل المباشر،
      // فلا يُلوَّن الشريطُ بمدّةِ باقةٍ من منطقةٍ أخرى — والشرطُ هنا أضيق
      // من سابقه: يثبّت المشتقَّ ويمنع رقماً ثابتاً.
      expect(hourly.contains('final int hours = _availabilityHours;'), isTrue,
          reason: 'المدّةُ تُشتقّ من الباقات المسعّرة لا من الحقل');
      expect(hourly.contains('open[1] - hours'), isTrue,
          reason: 'الإرساءُ محصورٌ بـ(الإغلاق − المدة)');
      expect(RegExp(r'open\[1\] - \d').hasMatch(hourly), isFalse,
          reason: 'مدّةٌ مكتوبةٌ رقماً تتجاهل باقةَ المنطقة');
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
    test('تحكم ساعة-بساعة: المحرر يبني closed داخل النطاق فقط', () {
      expect(ed.contains("'closed'"), isTrue,
          reason: 'طلب المالك: قفل/فتح ساعات محددة لكل يوم');
      expect(ed.contains('h >= e.value.start && h < e.value.end'), isTrue,
          reason: 'تغيير النطاق لا يُبقي أشباح ساعات مقفلة خارجه');
    });
  });

  group('الساعات المقفلة تُفرض على كل مستهلكي الإتاحة', () {
    // الحقن كخانات ممتلئة يجعل كل منطق الجدوى/الشرائح القائم يستبعدها بلا أي
    // تعديل. وكان الفحصُ قائمةً مكتوبةً بيدٍ من **أربعةٍ من خمسة** — تعليقُه
    // يَقول «حارس ضد نسيان مستهلكٍ عند إضافة شاشة حجز جديدة» والمنسيُّ
    // (`event_worker_packages_screen`) شاشةُ عقد. فالنطاقُ مُشتَقٌّ الآن.
    for (final p in _availabilityConsumers) {
      test(p, () {
        final s = _code(p);
        expect(s.contains('markClosedHoursFull('), isTrue,
            reason: '$p يَحقن الساعاتِ المقفلةَ عبر القاعدةِ المشتركة');
      });
    }
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
    // النقر على الخريطة يضع المركز — بعد حارس حدود جازان (النقرة خارجها تُرفض).
    expect(s.contains('onTap: (tapPos, ll) {'), isTrue);
    expect(s.contains('isInJazan(ll)'), isTrue,
        reason: 'المناطق محصورة بمنطقة جازان — نقرة خارج حدودها لا تضع مركزاً');
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

  test('حوارا المناطق (تطبيق وويب) لا يكتبان prices — أسعار الساعات القديمة تُصان', () {
    // حُذفت حقول أسعار الساعات من اللوحتين بطلب المالك («باقات السكن» بديلها).
    // الحارس: الحفظ/التطبيق-على-المناطق يجب ألا يكتب مفتاح prices إطلاقاً —
    // كتابةُ خريطةٍ من نموذجٍ بلا حقول = أصفار تمسح تسعيرة المناطق القائمة
    // التي ما زالت تقرؤها النسخ القديمة وزيارات العقود.
    final zones = File('lib/screens/admin/admin_hourly_zones_screen.dart').readAsStringSync();
    expect(zones.contains("'prices':"), isFalse,
        reason: 'كتابة prices من حوارٍ بلا حقول ساعات تصفّر تسعيرة المنطقة');
    expect(zones.contains('hourCtrls'), isFalse,
        reason: 'حقول الساعات حُذفت — لا بقايا متحكّمات');
    final web = File('admin_panel/src/pages/Settings.tsx').readAsStringSync();
    expect(web.contains('prices:'), isFalse,
        reason: 'نموذج الويب أيضاً لا يكتب prices');
    expect(web.contains('hourPrices'), isFalse);
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

  group('القاعدةُ المشتركةُ لجدولِ المنطقة', () {
    const data = {
      'openHours': {
        '2026-10-10': [10, 18],
        '2026-10-11': [6, 23],
      },
      'closedDates': ['2026-10-12'],
      'closedHours': {
        '2026-10-10': [13, 14],
      },
      'defaultOpen': [9, 21],
    };

    test('(أ) تقرأ الحِمْل، والافتراضيُّ من الخادمِ لا من حرفيٍّ في الشاشة', () {
      final z = ZoneSchedule.fromAvailability(data);
      expect(z.openHoursFor('2026-10-10'), [10, 18]);
      // يومٌ بلا نطاقٍ ⇒ افتراضيُّ الخادمِ (9..21) لا 8..22 المكتوبةُ في الشاشات.
      expect(z.openHoursFor('2026-12-31'), [9, 21]);
      expect(z.dateIsClosed('2026-10-12'), isTrue);
      expect(z.dateIsClosed('2026-10-10'), isFalse);
    });

    test('(ب) حِمْلٌ ناقصٌ يُقرأ «بلا جدول» ولا يَرمي في منتصفِ الرسم', () {
      final bads = <Map?>[
        null,
        {},
        {'openHours': 'nope', 'closedDates': 7, 'closedHours': null},
        {
          'openHours': {'d': 'x'},
          'defaultOpen': 'x',
        },
        {'defaultOpen': [5]}, // طرفٌ واحدٌ ليس نطاقاً
      ];
      for (final bad in bads) {
        final z = ZoneSchedule.fromAvailability(bad);
        expect(z.openHoursFor('2026-10-10'), kFallbackOpenHours);
        expect(z.dateIsClosed('2026-10-10'), isFalse);
        // 8..22 بمدّةِ ٤ ⇒ 8..18 — وهو **بعينِه** ما كان يُنتجه الشكلُ القديم
        // (`startHour = 8; endHour = 22; last = endHour - visitHours`).
        expect(z.startHoursFor('2026-10-10', 4),
            [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]);
      }
    });

    test('(ج) ساعاتُ البدءِ محصورةٌ بنطاقِ الفتحِ — ولا قَصَّ إلى 8..22', () {
      final z = ZoneSchedule.fromAvailability(data);
      // منطقةٌ تفتح 10..18 ومدّةٌ ٤: كانت الشاشتانِ تَعرضانِ 08 و09.
      expect(z.startHoursFor('2026-10-10', 4), [10, 11, 12, 13, 14]);
      // ومنطقةٌ تفتح 6..23: القَصُّ إلى 8..22 كان يَحجب 6 و7 و18 و19 —
      // وبوّابةُ الدفعِ تَقبلها، و`_isSlotFree` في المُنتقي نفسِه يَقبلها.
      expect(z.startHoursFor('2026-10-11', 4),
          [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);
      // يومٌ مغلقٌ ⇒ لا ساعةَ بدءٍ أصلاً
      expect(z.startHoursFor('2026-10-12', 4), isEmpty);
      // مدّةٌ لا تتّسع للنطاق، ومدّةٌ غيرُ موجبة
      expect(z.startHoursFor('2026-10-10', 9), isEmpty);
      expect(z.startHoursFor('2026-10-10', 0), isEmpty);
      expect(z.startHoursFor('2026-10-10', -1), isEmpty);
      // الحدُّ الأعلى شامل: 10..18 بمدّةِ ٨ ⇒ البدءُ 10 وحدَه
      expect(z.startHoursFor('2026-10-10', 8), [10]);
    });

    test('(د) الساعاتُ المقفلةُ تُحقَن ممتلئةً بمفاتيحِ الخانات', () {
      final slots = <String, int>{'2026-10-10_09:00': 1};
      ZoneSchedule.fromAvailability(data).markClosedHoursFull(slots);
      expect(slots['2026-10-10_13:00'], kClosedHourSlotSentinel);
      expect(slots['2026-10-10_14:00'], kClosedHourSlotSentinel);
      expect(slots['2026-10-10_09:00'], 1, reason: 'لا تَمسّ ما ليس مقفلاً');
      expect(slots.length, 3);
    });

    test('(هـ) الافتراضيُّ الأخيرُ = DEFAULT_OPEN خادميّاً', () {
      // النطاقُ الافتراضيُّ كان مكتوباً بيدٍ في خمسةِ مواضع، والخادمُ يُعيد
      // `defaultOpen` **ولا يَقرؤه أحد** — فتغييرُه خادميّاً كان يَترُك خمسَ
      // نسخٍ تَقول 8..22. الآن موضعٌ واحدٌ، ويُقابَل بالمصدرِ الخادميّ.
      final m = RegExp(r'const DEFAULT_OPEN = \[(\d+), (\d+)\];')
          .firstMatch(_read('functions/index.js'));
      expect(m, isNotNull, reason: 'DEFAULT_OPEN انتقلَ أو تغيّرَ شكلُه');
      expect(kFallbackOpenHours,
          [int.parse(m!.group(1)!), int.parse(m.group(2)!)]);
    });
  });

  group('الجدولُ يَصِل كلَّ سطحِ حجز', () {
    test('(و) النطاقُ مُشتَقٌّ ويَضمّ شاشتَي العقد', () {
      expect(
          _availabilityConsumers,
          containsAll(<String>[
            'lib/screens/event_worker_packages_screen.dart',
            'lib/screens/hourly_details_screen.dart',
            'lib/screens/payment_summary_screen.dart',
            'lib/screens/subscription_plans_screen.dart',
            'lib/widgets/booking_slot_picker.dart',
          ]));
    });

    for (final p in _availabilityConsumers) {
      test('(ز) $p يَمُرّ بالقاعدةِ ولا يُحلّل الحقولَ بنفسِه', () {
        final s = _code(p);
        expect(s.contains('ZoneSchedule.fromAvailability('), isTrue,
            reason: '$p يَبني الجدولَ من القاعدةِ المشتركة');
        for (final k in ['closedHours', 'closedDates', 'openHours']) {
          expect(s.contains("data['$k']"), isFalse,
              reason: '$p يُحلّل $k بنفسِه — نسخةٌ سادسةٌ تَنحرِف');
        }
        // ولا نطاقَ فتحٍ مكتوبٌ بيدٍ: كان 8 و22 في خمسةِ مواضع.
        expect(RegExp(r'_workStart|_workEnd|const startHour\s*=').hasMatch(s),
            isFalse,
            reason: '$p يَكتب نطاقَ الفتحِ بيدِه');
      });
    }

    for (final p in _selfLocatingConsumers) {
      test('(ح) $p يُعيد الجلبَ متى تغيّرت المنطقة', () {
        final s = _code(p);
        final loader = RegExp(
                r'Future<void>\s+(_load[A-Za-z0-9_]*Availability[A-Za-z0-9_]*)\s*\(')
            .firstMatch(s);
        expect(loader, isNotNull, reason: '$p: لم يُعرَف اسمُ جالبِ الإتاحة');
        final name = loader!.group(1)!;
        // كلُّ دالّةٍ تُسنِد المنطقةَ يَجبُ أن تُعيد الجلبَ من جسمِها نفسِه —
        // وهذا ما كان مفقوداً في `subscription_plans_screen`: الجلبُ الوحيدُ
        // في `initState` قبلَ معرفةِ المنطقة، فلا `zoneName` يُرسَل أبداً.
        var zones = 0;
        for (final m
            in RegExp(r'_(?:user|selected)ZoneName\s*=\s*(?!=)').allMatches(s)) {
          final body = _enclosingFunctionBody(s, m.start);
          if (body == null) continue;
          zones++;
          expect(body.contains(name) || body.contains('IfZoneChanged'), isTrue,
              reason: '$p: إسنادُ منطقةٍ لا يُعيد الجلبَ — '
                  'سقفُ المنطقةِ وجدولُها لا يَصِلان أبداً');
        }
        expect(zones, greaterThanOrEqualTo(2),
            reason: '$p: لم يُعثَر على مسارَي التحديد (تلقائيّ + خريطة)');
      });
    }

    test('(ط) الكاشفُ يَعضّ على الأشكالِ التي أعمَته', () {
      // المصدرُ بعدَ التوحيدِ نظيفٌ، فنجاحُ (ز) و(ح) وحدَه لا يُبرهِن أنّهما
      // يَرَيان شيئاً — فيُجرَّبان على شكلٍ مُصطنَعٍ يَحمل العطلَ بعينِه.
      const bad = 'Future<void> _loadAvailabilityFromServer() async {\n'
          '  final data = await x();\n'
          "  (data['closedHours'] as Map? ?? {}).forEach((k, v) {});\n"
          '}\n'
          'Future<void> _pickLocation({bool userInitiated = false}) async {\n'
          '  _userZoneName = z;\n'
          '}\n';
      expect(bad.contains("data['closedHours']"), isTrue);
      final b = _enclosingFunctionBody(bad, bad.indexOf('_userZoneName ='));
      expect(b, isNotNull, reason: 'اقتطاعُ الجسمِ انحلّ');
      expect(b!.contains('_loadAvailabilityFromServer'), isFalse,
          reason: 'الكاشفُ يَجب أن يَرى مسارَ منطقةٍ بلا إعادةِ جلب');
      // والقوسُ المُوازَن: أوّلُ `{` بعدَ الاسمِ هو قوسُ المعامَلاتِ المُسمّاة.
      expect(b.contains('userInitiated'), isFalse,
          reason: 'الجسمُ اقتُطِع من قوسِ المعامَلاتِ لا من الجسم');
      // ولا إيجابيّةَ كاذبة: الجسمُ الصحيحُ يُقرأ صحيحاً.
      const good = 'Future<void> _pickLocation() async {\n'
          '  _userZoneName = z;\n'
          '  _reloadAvailabilityIfZoneChanged(before);\n'
          '}\n';
      final g = _enclosingFunctionBody(good, good.indexOf('_userZoneName ='));
      expect(g, isNotNull);
      expect(g!.contains('IfZoneChanged'), isTrue);
      // ولا يَقرأ كتلةَ `if` دالّةً.
      const inIf = 'Future<void> f() async {\n'
          '  if (ok) {\n'
          '    _userZoneName = z;\n'
          '  }\n'
          '}\n';
      final q = _enclosingFunctionBody(inIf, inIf.indexOf('_userZoneName ='));
      expect(q, isNotNull);
      expect(q!.startsWith('{\n  if (ok)'), isTrue,
          reason: 'يَصعد من كتلةِ if إلى جسمِ الدالّة');
    });

    test('(ي) شاهدُ التعليل: بلا zoneName يَعود الجدولُ افتراضيّاً', () {
      final fn = _read('functions/index.js');
      // الجدولُ وسقفُ المنطقةِ داخلَ `if (zoneName)` — فغيابُه يَترُكهما null.
      expect(fn.contains('if (zoneName) {'), isTrue);
      expect(fn.contains('let zoneSchedule = null;'), isTrue);
      expect(fn.contains('let zoneMaxOrdersPerDay = null;'), isTrue);
      // و`null` تُقرأ «مفتوحٌ بالنطاقِ الافتراضيِّ بلا ساعاتٍ مقفلة».
      expect(fn.contains('if (!schedule || schedule.enabled !== true) {'), isTrue);
      expect(fn.contains('return {range: DEFAULT_OPEN, closed: []};'), isTrue,
          reason: 'لو صارَ الغيابُ «مغلقاً» لَزِمَ مراجعةُ تعليلِ هذه الشريحة');
      // ولا فحصَ خادميّاً للجدولِ على مسارِ العقد: قارئا `zoneDayScheduleForDate`
      // هما الإتاحةُ نفسُها والغلافُ التوافقيُّ بلا مُنادٍ — فشاشةُ العقدِ هي
      // الحارسُ الوحيدُ، وهو سببُ وزنِ هذه الشريحة.
      expect(RegExp(r'zoneDayScheduleForDate\(').allMatches(fn).length, 3,
          reason: 'ظهرَ قارئٌ ثالثٌ — يُراجَع: قد يَكون فحصاً خادميّاً فعليّاً');
    });
  });
}

/// جسمُ الدالّةِ المُحيطةِ بموضعٍ — بالصعودِ من أقربِ كتلةٍ حاويةٍ حتى كتلةٍ
/// ترويستُها دالّةٌ لا `if`/`for`/`catch`.
///
/// وموازنةُ قائمةِ المعامَلاتِ أوّلاً ليست زينةً: أوّلُ `{` بعدَ اسمِ دالّةٍ قد
/// يَكون قوسَ معامَلاتٍ مُسمّاة (`{bool userInitiated = false}`) لا الجسمَ —
/// فخُّ الحدِّ غيرِ المُوازَنِ المسجَّلُ في هذا المستودعِ مرّاتٍ. و«بقيّةُ
/// الكتلةِ الحاوية» وحدَها لا تَكفي: إسنادٌ داخلَ `if` تَنتهي كتلتُه قبلَ
/// نداءٍ يَليه على مستوى الدالّة.
String? _enclosingFunctionBody(String src, int at) {
  var open = -1;
  var depth = 0;
  for (var i = at; i >= 0; i--) {
    final c = src[i];
    if (c == '}') {
      depth++;
    } else if (c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      open = i;
      if (_headIsFunction(src.substring(0, i))) break;
      open = -1; // كتلةٌ ليست دالّةً — اصعد
    }
  }
  if (open < 0) return null;
  var e = 0;
  for (var k = open; k < src.length; k++) {
    if (src[k] == '{') {
      e++;
    } else if (src[k] == '}') {
      e--;
      if (e == 0) return src.substring(open, k + 1);
    }
  }
  return src.substring(open);
}

/// هل ما قبلَ `{` ترويسةُ دالّةٍ؟ — قائمةُ معامَلاتٍ مُوازَنةٌ يَسبقها اسمٌ
/// ليس من كلماتِ التحكّم.
bool _headIsFunction(String head) {
  final tail = head.trimRight().replaceAll(RegExp(r'\basync\*?$'), '').trimRight();
  if (!tail.endsWith(')')) return false;
  var d = 0;
  var j = tail.length - 1;
  for (; j >= 0; j--) {
    if (tail[j] == ')') {
      d++;
    } else if (tail[j] == '(') {
      d--;
      if (d == 0) break;
    }
  }
  if (j < 0) return false;
  final name = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*$').firstMatch(tail.substring(0, j));
  if (name == null) return false;
  return !const {'if', 'for', 'while', 'switch', 'catch'}.contains(name.group(1));
}
