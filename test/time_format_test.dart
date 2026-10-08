// حارس: العرض 12 ساعة، والتخزين 24 ساعة — لا يختلطان أبداً.
//
// طلب العميل: تغيير عرض الوقت من 24 إلى 12 ساعة.
//
// **الخطر:** `booking_time_slot` مخزَّن "HH:00" (24)، والدالة الخادمية تحلّله بـ
// `parseInt(slot.split(":")[0])` لتعدّ السعة وتكشف التداخل. لو خُزِّن بصيغة 12
// ("3:00 م") لقُرئ 3 صباحاً ⇒ سلوت المساء يُحسب على الفجر ⇒ حجوزات بلا سائق.
// فالتحويل عرضٌ فقط، والتخزين يبقى 24 حرفياً.
//
// ═══ ووُسِّع (2026-10-05): القاعدةُ عامّةٌ وكان الحارسُ ملفَّين ═══
//
// شقُّ **العرضِ** كان يَفحصُ ملفَّين مُسمَّيَين (`booking_slot_picker`
// و`subscription_plans`) بينما قاعدتُه — «العرضُ عبر دوالِ `time_format`
// وحدَها» — عامّةٌ على كلِّ ما تَراه العميلةُ والسائق. نمطُ «حارسٌ ضيّقٌ
// وقاعدةٌ عامّة» للمرّةِ الخامسةِ هنا، ونطاقُه المُشتَقُّ وجدَ **ستَّ نسخٍ
// أخرى** من التحويلِ (المجموعُ ثمانٍ)، واختلفت في كلمةِ الفترةِ وفي تبطينِ
// الساعة. فالعميلةُ كانت تَرى وقتَها بأربعِ صِيَغٍ في مسارِها الواحد:
//
//   • «3:00 م»            — مُنتقي الساعةِ (`formatHour12`)
//   • «3:00 مساءً»        — شريطُ الموعدِ في «طلباتي» (نسخةٌ مكتوبةٌ بيد)
//   • «الساعة 02:15 م»    — خطُّ زمنِ التتبّعِ (`tracking_steps`، نسخةٌ أخرى)
//   • «15:30»             — بطاقةُ الطلبِ وشاشةُ الدعمِ (`DateFormat('HH:mm')`)
//
// وتاريخَها بصيغتَين في الشاشةِ الواحدة: «الأحد 12/10» في شريطِ الأيّامِ ثم
// «2026-10-12» في رقاقةِ الزيارةِ المضافةِ تحتَه مباشرةً — أي أنّ الرقاقةَ
// التي تُؤكّدُ اختيارَها كانت تَعرضُ المخزَّنَ خامّاً لا المختار. وتهجئةُ
// «الاثنين» كانت تَختلفُ بين شاشةِ الحجزِ وشريطِ الموعد.
//
// فالنطاقُ الآن **مُشتَقٌّ** من الشجرةِ (`lib/screens|widgets|utils|models|
// services`) باستثناءَين مُسمَّيَين لكلٍّ سببُه، و`admin/` خارجَه عمداً
// (الصيغةُ المخزَّنةُ هي ما يُريدُه المالكُ هناك، كقرارِ حارسِ نصِّ
// الاستثناءِ وحارسِ المخاطبة). والوحدةُ **حافظةٌ للسلوك**: ما كان مُبطَّناً
// بقيَ مُبطَّناً وما كان طويلَ الفترةِ بقيَ كذلك — جمعُ ثماني نسخٍ لا يُعادُ
// به تنسيقُ ما كان صحيحاً، وتوحيدُ التبطينِ قرارُ صياغةٍ لا إصلاح.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/time_format.dart';

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
  group('تحويل 12 ساعة صحيح', () {
    test('منتصف الليل والظهر لا يصيران صفراً', () {
      expect(formatHour12(0), '12:00 ص');
      expect(formatHour12(12), '12:00 م');
    });
    test('الصباح', () {
      expect(formatHour12(8), '8:00 ص');
      expect(formatHour12(11), '11:00 ص');
    });
    test('المساء', () {
      expect(formatHour12(13), '1:00 م');
      expect(formatHour12(15), '3:00 م');
      expect(formatHour12(22), '10:00 م');
    });
    test('من خانة مخزَّنة', () {
      expect(formatSlot12('08:00'), '8:00 ص');
      expect(formatSlot12('15:00'), '3:00 م');
      expect(formatSlot12('00:00'), '12:00 ص');
    });
    test('خانة فارغة/تالفة لا تُسقط شيئاً', () {
      expect(formatSlot12(null), '');
      expect(formatSlot12(''), '');
      expect(formatSlot12('غير معروف'), 'غير معروف'); // تُعاد كما هي لا تُخفى
    });
    test('مدى', () {
      expect(formatRange12(8, 12), '8:00 ص – 12:00 م');
    });
  });

  group('التخزين يبقى 24 ساعة — حرج للسعة', () {
    test("كل كتابة لـ booking_time_slot بصيغة padLeft(2,'0'):00", () {
      // نفحص كل موضع يكتب الحقل: يجب أن يكون "HH:00" لا نصّ 12 ساعة.
      final writers = {
        'lib/screens/payment_summary_screen.dart',
        'lib/screens/checkout_screen.dart',
      };
      for (final p in writers) {
        final s = _code(p);
        final writeRe = RegExp(r"'booking_time_slot':\s*[\s\S]{0,120}?padLeft\(2, '0'\)\}:00");
        expect(writeRe.hasMatch(s), isTrue,
            reason: '$p يكتب booking_time_slot بصيغة غير 24 ساعة ⇒ تنهار السعة الخادمية');
        // ولا يكتبه بصيغة 12 ساعة (ص/م) إطلاقاً
        final badRe = RegExp(r"'booking_time_slot':[^,\n]*(ص|م|formatHour12|formatSlot12)");
        expect(badRe.hasMatch(s), isFalse,
            reason: '$p يخزّن وقتاً بصيغة 12 ساعة — يُقرأ خطأً في الخادم');
      }
    });

    test('الدالة الخادمية ما زالت تحلّل "HH:00"', () {
      // انتقل عدّ الفترات إلى functions/capacity.js (نقيّ ومختبَر بـ
      // capacity.test.js) — index.js يستدعيه من getHourlyAvailability.
      final cap = _code('functions/capacity.js');
      expect(cap.contains('parseInt(String(ts).split(":")[0]'), isTrue,
          reason: 'إن تغيّر التحليل فقد يكون التخزين تغيّر — تأكّد يدوياً');
      final fn = _code('functions/index.js');
      expect(fn.contains('require("./capacity")'), isTrue,
          reason: 'getHourlyAvailability يجب أن يعدّ عبر capacity.js');
    });
  });

  group('العرض يستعمل المُنسّق المشترك', () {
    test('لا شاشة تعرض HH:00 خاماً للعميلة', () {
      // (باقات السكن) hourly_details لم تعد تعرض أي ساعة للعميلة إطلاقاً —
      // العميل يختار اليوم فقط والوقت يُرسى داخلياً، فخرجت من هذا الحارس.
      for (final p in [
        'lib/widgets/booking_slot_picker.dart',
        'lib/screens/subscription_plans_screen.dart',
      ]) {
        final s = _code(p);
        expect(s.contains("formatHour12"), isTrue, reason: '$p لا يستعمل مُنسّق 12 ساعة');
        // لا label خام بصيغة 24
        expect(s.contains(r"final label = '${h.toString().padLeft(2, '0')}:00'"), isFalse,
            reason: '$p ما زال يعرض 24 ساعة للعميلة');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // المسحُ المُشتَقّ: القاعدةُ عامّةٌ، وكان الحارسُ ملفَّين
  //
  // القاعدةُ «العرضُ 12 ساعةً عبر هذه الدوالِ وحدَها» عامّةٌ على كلِّ ما
  // تَراه العميلةُ والسائق، وكان هذا الملفُّ يَفحصُ ملفَّين مُسمَّيَين —
  // نمطُ «حارسٌ ضيّقٌ وقاعدةٌ عامّة» للمرّةِ الخامسةِ في هذا المستودع.
  // ونطاقُه المُشتَقُّ وجدَ **ستَّ نسخٍ أخرى** من القاعدة.
  // ══════════════════════════════════════════════════════════════════════

  /// كلُّ ما تَراه العميلةُ أو السائق. `admin/` مُستثنىً عمداً (أدناه).
  List<String> clientFacingDartFiles() {
    final out = <String>[];
    for (final dir in const [
      'lib/screens',
      'lib/widgets',
      'lib/utils',
      'lib/models',
      'lib/services',
    ]) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: false).whereType<File>()) {
        if (f.path.endsWith('.dart')) out.add(f.path);
      }
    }
    out.sort();
    return out;
  }

  group('قاعدةُ العرضِ لها موضعٌ واحد — مسحٌ مُشتَقٌّ لا قائمةٌ مكتوبة', () {
    // تُستثنى بأسمائها ولكلٍّ سببُها — لا بعدَدٍ، فالعتبةُ العدديّةُ هي ما
    // أمَرَّ ثمانيَ شاشاتٍ مؤنَّثةٍ في حارسِ المخاطبة.
    const exempt = <String, String>{
      'lib/utils/time_format.dart': 'هو الموضعُ الواحد',
      'lib/services/zyiarah_pdf_service.dart':
          'الفاتورةُ مستندٌ ضريبيّ (ZATCA)، و24 ساعةً هو العُرفُ فيها',
    };

    test('لا نسخةَ ثانيةً من تحويلِ الفترة (ص/م، صباحاً/مساءً)', () {
      final offenders = <String>[];
      for (final p in clientFacingDartFiles()) {
        if (exempt.containsKey(p)) continue;
        final c = _code(p);
        if (RegExp(r"<\s*12\s*\?\s*'(ص|صباح)").hasMatch(c)) offenders.add(p);
      }
      expect(offenders, isEmpty,
          reason: 'نسخةٌ أخرى من قاعدةِ الفترة — ثمانٍ منها اختلفت في كلمةِ '
              'الفترةِ وفي تبطينِ الساعة، فرأت العميلةُ وقتَها بأربعِ صِيَغ: '
              '${offenders.join(", ")}');
    });

    test('ولا عرضَ 24 ساعةً عبر DateFormat', () {
      final offenders = <String>[];
      for (final p in clientFacingDartFiles()) {
        if (exempt.containsKey(p)) continue;
        final c = _code(p);
        if (RegExp(r"DateFormat\('[^']*HH").hasMatch(c)) offenders.add(p);
      }
      expect(offenders, isEmpty,
          reason: 'عرضُ 24 ساعةً للعميلةِ/السائقِ — بطاقةُ الطلبِ والدعمُ كانا '
              'كذلك بينما مُنتقي الساعةِ 12: ${offenders.join(", ")}');
    });

    test('ولا قائمةَ أيّامٍ مكتوبةً بيدٍ بترتيبِ الأحدِ أوّلاً', () {
      // كانت في أربعةِ ملفّاتٍ عميليّةٍ بترتيبَين وتهجئتَين لـ«الاثنين»:
      // تَحجزُ يومَ «الاثنين» ويَقولُ شريطُ موعدِها «الإثنين».
      final offenders = <String>[];
      for (final p in clientFacingDartFiles()) {
        if (exempt.containsKey(p)) continue;
        final c = _code(p);
        if (c.contains("'الأحد'") && c.contains("'الثلاثاء'")) offenders.add(p);
      }
      expect(offenders, equals(['lib/models/driver_schedule.dart']),
          reason: 'قائمةُ أيّامٍ مكتوبةٌ بيدٍ خارجَ الموضعِ الواحد. '
              'و`driver_schedule` وحدَه مُستثنىً بسببِه: قائمتُه تَبدأُ '
              '**بالسبت** لأنّ شبكتَه مُرتكِزةٌ عليه (`daysSinceSaturday`)، '
              'فهي تسميةُ شبكةٍ لا تسميةُ يومٍ مفرد: ${offenders.join(", ")}');
    });

    test('والمسحُ قرأَ ملفّاتٍ فعلاً — حارسٌ عقيمٌ أسوأُ من لا حارس', () {
      final files = clientFacingDartFiles();
      expect(files.length, greaterThanOrEqualTo(60),
          reason: 'المسحُ لم يَجد ما يَفحصُه (${files.length} ملفّاً) — '
              'انهارَ التعدادُ فالفحوصُ أعلاه فارغة');
      expect(files, contains('lib/screens/orders_list_screen.dart'));
      expect(files, contains('lib/models/tracking_steps.dart'));
      // والمستثنياتُ موجودةٌ فعلاً، وإلّا فالاستثناءُ يَخفي اسماً مَيْتاً
      for (final e in exempt.keys) {
        expect(File(e).existsSync(), isTrue, reason: '$e مُستثنىً ولا وجودَ له');
      }
    });

    test('وكلُّ كُتّابِ booking_time_slot معروفون — أربعةٌ لكلٍّ سببُه', () {
      // التمرير: `contract_signing_screen` يَكتبُ `widget.bookingTimeSlot`
      // مُمرَّراً، فلا يُطابِقُ نمطَ الـ24 حرفيّاً — ويُحرَسُ بمنادِيَيه.
      final writers = <String>[];
      for (final p in clientFacingDartFiles()) {
        if (_code(p).contains("'booking_time_slot':")) writers.add(p);
      }
      expect(
          writers,
          equals([
            'lib/screens/checkout_screen.dart',
            'lib/screens/contract_signing_screen.dart',
            'lib/screens/payment_summary_screen.dart',
            // الرابعُ ليس كاتبَ إنشاءٍ بل **موضعُ قاعدةِ تحريكِ الموعد**
            // (2026-10-08): يُعيدُ اشتقاقَ الحقلَين بصيغةِ 24 ويُصفّرُ
            // أعلامَ التذكير، ويُنادِيه سطحا الإدارةِ معاً. وصيغتُه
            // مشدودةٌ سلوكاً في `booking_fields_test`، وتفويضُه هنا.
            'lib/utils/booking_fields.dart',
          ]),
          reason: 'كاتبٌ خامسٌ لـbooking_time_slot — يُراجَعُ بدلَ أن يَمرّ، '
              'فصيغةُ 12 ساعةً هنا تُسقطُ حسابَ السعةِ خادميّاً: '
              '${writers.join(", ")}');
      // وموضعُ القاعدةِ يُفوّضُ إلى الدالّةِ النقيّةِ ولا يَبني الصيغةَ إنلاين
      expect(
          RegExp(r"'booking_time_slot':\s*bookingTimeSlotOf\(")
              .hasMatch(_code('lib/utils/booking_fields.dart')),
          isTrue,
          reason: 'قاعدةُ التحريكِ تَبني الساعةَ إنلاين بدلَ bookingTimeSlotOf '
              '— فصيغةُ 24 لم تَبقَ في موضعٍ واحدٍ مشدود');
      // ومُنادِيا شاشةِ التعاقدِ يَبنيانِ القيمةَ بصيغةِ 24
      for (final p in const [
        'lib/screens/subscription_plans_screen.dart',
        'lib/screens/event_worker_packages_screen.dart',
      ]) {
        final c = _code(p);
        expect(c.contains(r"final slot = '${_selectedStartHour!.toString().padLeft(2, '0')}:00'"),
            isTrue,
            reason: '$p يُمرّرُ bookingTimeSlot بصيغةٍ غيرِ 24 ⇒ تنهارُ السعة');
      }
    });
  });

  group('وقتُ لحظةٍ: صياغةٌ واحدةٌ بثلاثِ وجوه', () {
    test('formatTime12 — قصيرٌ، طويلٌ، ومُبطَّن', () {
      final t = DateTime(2026, 10, 5, 15, 30);
      expect(formatTime12(t), '3:30 م');
      expect(formatTime12(t, longPeriod: true), '3:30 مساءً');
      expect(formatTime12(t, padHour: true), '03:30 م');
    });
    test('منتصفُ الليلِ والظهرُ لا يصيرانِ صفراً', () {
      expect(formatTime12(DateTime(2026, 1, 1, 0, 5)), '12:05 ص');
      expect(formatTime12(DateTime(2026, 1, 1, 12, 0)), '12:00 م');
      expect(formatTime12(DateTime(2026, 1, 1, 0, 0), longPeriod: true),
          '12:00 صباحاً');
    });
    test('والنواةُ واحدةٌ: formatHour12/formatSlot12 تَمُرّانِ بها', () {
      // لو انفصلت إحداها عادت النسخةُ الثانيةُ من القاعدة.
      for (var h = 0; h < 24; h++) {
        expect(formatHour12(h), formatClock12(h, 0));
        expect(formatSlot12('${h.toString().padLeft(2, '0')}:45'),
            formatClock12(h, 45));
      }
    });
    test('حافظةٌ للسلوك: ما كان مُبطَّناً بقيَ مُبطَّناً', () {
      // النسختانِ المحذوفتانِ (بطاقةُ السائق، وخطُّ التتبّع) كانتا تُبطّنانِ
      // الساعة. الوحدةُ لا تُعيدُ تنسيقَ ما كان صحيحاً.
      for (var h = 0; h < 24; h++) {
        for (final m in const [0, 7, 30, 59]) {
          final h12 = h % 12 == 0 ? 12 : h % 12;
          final period = h < 12 ? 'ص' : 'م';
          final old = '${h12.toString().padLeft(2, '0')}:'
              '${m.toString().padLeft(2, '0')} $period';
          expect(formatClock12(h, m, padHour: true), old,
              reason: 'انحرفَ التبطينُ عند $h:$m');
        }
      }
    });
  });

  group('أسماءُ الأيّامِ والشهورِ موضعٌ واحد', () {
    test('arabicWeekday يُطابقُ ترتيبَ weekday % 7', () {
      // 2026-10-04 أحدٌ (weekday=7 ⇒ 0)
      expect(arabicWeekday(DateTime(2026, 10, 4)), 'الأحد');
      expect(arabicWeekday(DateTime(2026, 10, 5)), 'الاثنين');
      expect(arabicWeekday(DateTime(2026, 10, 10)), 'السبت');
      for (var i = 0; i < 14; i++) {
        final d = DateTime(2026, 10, 4).add(Duration(days: i));
        expect(arabicWeekday(d), arabicWeekdayNames[d.weekday % 7]);
      }
    });
    test('arabicMonth', () {
      expect(arabicMonth(DateTime(2026, 1, 1)), 'يناير');
      expect(arabicMonth(DateTime(2026, 12, 31)), 'ديسمبر');
      expect(arabicMonthNames.length, 12);
    });
    test('وتهجئةُ «الاثنين» واحدةٌ في وجهِ العميلة', () {
      // كانت «الاثنين» في شاشاتِ الحجزِ و«الإثنين» في شريطِ الموعد.
      expect(arabicWeekdayNames, contains('الاثنين'));
      expect(arabicWeekdayNames.contains('الإثنين'), isFalse);
      expect(_code('lib/screens/orders_list_screen.dart').contains('الإثنين'),
          isFalse,
          reason: 'عادت التهجئةُ الثانيةُ إلى شريطِ موعدِ العميلة');
    });
  });

  group('الرقاقةُ تُؤكّدُ ما اختارتْه لا ما خُزِّن', () {
    for (final p in const [
      'lib/screens/subscription_plans_screen.dart',
      'lib/screens/event_worker_packages_screen.dart',
    ]) {
      test('$p: الزيارةُ المضافةُ بصياغةِ الشريطِ والمُنتقي', () {
        final c = _code(p);
        expect(c.contains(r"${v['date']} • ${v['slot']}"), isFalse,
            reason: 'عادت الرقاقةُ تَعرضُ المخزَّنَ خامّاً — «2026-10-12 • 15:00» '
                'تحتَ شريطٍ يَقولُ «الأحد 12/10» ومُنتقٍ يَقولُ «3:00 م»');
        expect(c.contains('_visitLabel(v)'), isTrue,
            reason: 'الرقاقةُ لا تُنادي المُنسّق');
        expect(c.contains('formatSlot12(v[\'slot\'])'), isTrue,
            reason: 'الوقتُ في الرقاقةِ لا يَمرُّ بالمُنسّقِ المشترك');
        expect(c.contains('arabicWeekday(d)'), isTrue,
            reason: 'التاريخُ في الرقاقةِ لا يُطابقُ صياغةَ الشريط');
      });
    }
  });

  group('وقائمةُ الأيّامِ واحدةٌ بين اللغتَين', () {
    test('DAY_NAMES في اللوحةِ = arabicWeekdayNames قيمةً بقيمة', () {
      // **مرآةٌ غيرُ مشدودةٍ حتى اليومَ (2026-10-07):** `zoneSchedule.ts`
      // يُصدِّرُ `DAY_NAMES` وتَستورِدُها اللوحةُ لتُسمّيَ أعمدةَ محرِّرِ
      // جدولِ المنطقةِ، والمفتاحُ `weekday(0-6)` — فانحرافُ ترتيبٍ واحدٍ
      // يَجعلُ الأدمنَ يَضبطُ ساعاتَ السبتِ وهو يَحسبُها الأحد، بلا أن
      // يَكسِرَ شيءٌ ولا يَسقطَ فحص. وجدَه `panel_mirror_coverage_test`.
      final ts = File('admin_panel/src/utils/zoneSchedule.ts').readAsStringSync();
      final m = RegExp(r"export const DAY_NAMES = \[([^\]]*)\]").firstMatch(ts);
      expect(m, isNotNull, reason: 'تعذّرَ اقتطاعُ DAY_NAMES من المرآة');
      final panel = m!
          .group(1)!
          .split(',')
          .map((e) => e.trim().replaceAll("'", '').replaceAll('"', ''))
          .where((e) => e.isNotEmpty)
          .toList();
      expect(panel, arabicWeekdayNames,
          reason: 'قائمةُ أيّامِ اللوحةِ انحرفت عن المصدرِ الدارتيّ');
      // والنسخةُ الثالثةُ في محرِّرِ التطبيقِ تُطابقُهما كذلك — تُركت في
      // موضعِها بقرارٍ قائم (`admin/` خارجَ نطاقِ حارسِ الوقتِ عمداً)،
      // فتُشَدُّ قيمتُها هنا بدلَ أن تُنقَل: لمسُ شفرةٍ سليمةٍ بلا خللٍ
      // خلفَها مخاطرةٌ بلا مقابل.
      final ed = File('lib/screens/admin/admin_zone_schedule_editor.dart')
          .readAsStringSync();
      final em = RegExp(r"_dayNames = \[([^\]]*)\]").firstMatch(ed);
      expect(em, isNotNull);
      final editor = em!
          .group(1)!
          .split(',')
          .map((e) => e.trim().replaceAll("'", ''))
          .where((e) => e.isNotEmpty)
          .toList();
      expect(editor, arabicWeekdayNames,
          reason: 'نسخةُ محرِّرِ المناطقِ انحرفت — والمفتاحُ weekday(0-6)');
    });
  });
}
