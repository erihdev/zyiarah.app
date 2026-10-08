// تحريكُ موعدٍ يُعيدُ اشتقاقَ حقلَي الحجزِ ويُصفّرُ أعلامَ التذكير —
// قاعدةٌ كانت مُنفَّذةً في اثنَين من أربعةِ كُتّاب.
//
// `service_date` ليس وحدَه ما يُقرأُ من الموعد:
//
//   • **`capacity.js` يَعُدُّ من `booking_date` و`booking_time_slot`** لا من
//     `service_date` — فتركُهما على اليومِ القديمِ يَعني أنّ الطلبَ يَستهلكُ
//     سعةَ يومٍ لم يَعُدْ له (يُعرَضُ ممتلئاً بلا طلب) ولا يَستهلكُ شيئاً من
//     يومِه الجديد (فيُباعُ أكثرَ من طاقتِه).
//   • و`booking_time_slot` هو **الساعةُ المعروضةُ** في بطاقةِ العميلةِ
//     وبطاقةِ السائقِ ونصِّ التذكير.
//   • و`remindClientsUpcomingAppointments` يَتخطّى ما عَلَمُه مرفوعٌ، و
//     `realAppointment` فيه `is_paid === true || driverAssigned` — فطلبٌ
//     **مدفوعٌ بلا سائق** يُذكَّرُ عنه ويُرفَعُ علَمُه، فموعدٌ يُحرَّكُ بعدَه
//     بلا تصفيرٍ **لا تذكيرَ له أبداً**.
//
// الكُتّابُ الأربعةُ وحالُهم قبلَ الشريحة: `rescheduleAssignedOrder` ✓،
// و`admin_order_details_screen` ✓ (إنلاين)، و`approveAndAssignOrder` حقلا
// الحجزِ ✓ **والأعلامُ ✗**، ولوحةُ الويبِ `service_date`/`scheduled_at`
// وحدَهما ✗.

import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/booking_fields.dart';
import 'helpers/strip_comments.dart';

/// جسمُ دالّةٍ خادميّةٍ مُصدَّرةٍ — من تصديرِها إلى التصديرِ الذي يَليها.
String _exportBlock(String idx, String name) {
  final i = idx.indexOf('exports.$name');
  expect(i, greaterThan(0), reason: 'التصديرُ $name غائب');
  final j = idx.indexOf('\nexports.', i + 10);
  expect(j, greaterThan(i), reason: 'اقتطاعُ $name غيرُ محدود');
  return idx.substring(i, j);
}

void main() {
  final idx = File('functions/index.js').readAsStringSync();
  final screen = stripComments(
      File('lib/screens/admin/admin_order_details_screen.dart')
          .readAsStringSync());
  final panel = stripComments(
      File('admin_panel/src/pages/Orders.tsx').readAsStringSync());

  group('القاعدةُ سلوكاً، وجدولُها واحدٌ بين اللغتَين', () {
    test('(أ) جدولُ الحالاتِ مشترَكٌ ومتطابق', () {
      // النسختانِ بين العلامتَين نفسِها، والدارتُ هو مَن يَقرأُ ملفَّ TS
      // ويُقارِن (`node:fs` بلا أنواعٍ تحت `tsconfig.app.json`).
      final ts = File('admin_panel/src/utils/bookingFields.test.ts')
          .readAsStringSync();
      const a = '// BOOKING_FIELDS_CASES_START';
      const b = '// BOOKING_FIELDS_CASES_END';
      final ia = ts.indexOf(a), ib = ts.indexOf(b);
      expect(ia, greaterThan(0), reason: 'علامةُ بدايةِ الجدولِ غائبة');
      expect(ib, greaterThan(ia), reason: 'علامةُ نهايةِ الجدولِ غائبة');
      // الاقتطاعُ من آخرِ `]` إلى الوراء: `indexOf('[')` يَلتقطُ قوسَ تعليقِ
      // النوعِ `[...][]` لا بدايةَ المصفوفة.
      final block = ts.substring(ia + a.length, ib);
      final close = block.lastIndexOf(']');
      expect(close, greaterThan(0));
      final open = _balBack(block, close);
      var json = block.substring(open, close + 1);
      // حجبُ أسطرِ التعليقِ كاملةً (لا `//` في أيِّ موضع) وتسويةُ الفواصلِ
      // المتدلّية.
      json = json
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n')
          .replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!)
          // نسخةُ TS تَستعملُ علامةَ اقتباسٍ مفردةً — و`jsonDecode` لا تَقبلُها.
          .replaceAll("'", '"');
      final rows = (jsonDecode(json) as List).cast<List<dynamic>>();
      expect(rows.length, greaterThanOrEqualTo(6),
          reason: 'الجدولُ المشترَكُ انحلَّ — الفحصُ عقيم');
      // **أصنافٌ مُسمّاةٌ لا حدٌّ عدديٌّ وحدَه**: الحدُّ لا يَكشفُ ضياعَ صنفٍ
      // (قضمةٌ تَنزِعُ صفّاً تُبقيه فوقَ الحدِّ فتَمُرّ)، والأصنافُ هي الأطرافُ
      // التي يَنكسِرُ عندَها الاشتقاقُ: منتصفُ الليلِ (`00:00` لا `0:00`)،
      // وآخرُ ساعةٍ في آخرِ يومٍ من السنة، ويومُ كبيسةٍ، ودقيقةٌ تُطرَح.
      final slots = rows.map((r) => r[6] as String).toSet();
      final dates = rows.map((r) => r[5] as String).toSet();
      expect(slots, contains('00:00'), reason: 'صنفُ منتصفِ الليلِ غائب');
      expect(slots, contains('23:00'), reason: 'صنفُ آخرِ ساعةٍ غائب');
      expect(dates.any((d) => d.endsWith('-12-31')), isTrue,
          reason: 'صنفُ آخرِ يومٍ في السنةِ غائب');
      expect(dates.any((d) => d.endsWith('-02-29')), isTrue,
          reason: 'صنفُ يومِ الكبيسةِ غائب');
      expect(rows.any((r) => (r[4] as int) > 0), isTrue,
          reason: 'لا صفَّ بدقيقةٍ غيرِ صفرٍ — طرحُ الدقيقةِ غيرُ مُختبَر');
      for (final r in rows) {
        final chosen = DateTime(
            r[0] as int, r[1] as int, r[2] as int, r[3] as int, r[4] as int);
        expect(bookingDateOf(chosen), r[5],
            reason: 'تاريخُ الحجزِ يُخالفُ نسخةَ TS: $r');
        expect(bookingTimeSlotOf(chosen), r[6],
            reason: 'خانةُ الساعةِ تُخالفُ نسخةَ TS: $r');
      }
    });

    test('(ب) والحِمْلُ الحقلانِ + الأعلامُ مصفَّرةً ولا شيءَ غيرُها', () {
      // **مجموعةُ الأعلامِ مثبّتةٌ بأسمائها هنا، لا مُشتَقّةً من
      // `kReminderFlags`**: اشتقاقُ الفحصِ من الشيءِ المفحوصِ دائريٌّ — قضمةٌ
      // تَنزِعُ علَماً من القائمةِ تَجعلُ كلَّ ما يَدورُ عليها أخضرَ (مُثبَتٌ
      // بقضمٍ لم يَعضَّ قبلَ هذا السطر). والأسماءُ الثلاثةُ هي ما يَقرؤه
      // `remindClientsUpcomingAppointments` و`remindDriversUpcomingJobs`.
      expect(
          kReminderFlags.toSet(),
          {
            'reminder_sent',
            'client_reminder_24h_sent',
            'client_reminder_soon_sent',
          },
          reason: 'مجموعةُ أعلامِ التذكيرِ تغيّرت — تُراجَعُ لا تُشتَقّ');
      final out = rescheduleDerivedFields(DateTime(2026, 10, 8, 14, 0));
      expect(out['booking_date'], '2026-10-08');
      expect(out['booking_time_slot'], '14:00');
      for (final f in kReminderFlags) {
        expect(out[f], isFalse, reason: '$f غيرُ مصفَّر');
      }
      // لا `service_date`: قيمةُ المُنادي لا مُشتقّة — وخلطُها هنا يَعني
      // كتابةَ موعدٍ من موضعَين.
      expect(out.containsKey('service_date'), isFalse);
      expect(out.length, 2 + kReminderFlags.length);
    });

    test('(ج) والدقائقُ تُطرَح: الخانةُ ساعةٌ كاملة', () {
      // `capacity.js` يَعُدُّ بالساعةِ من `HH:00` — دقيقةٌ في المفتاحِ تَجعلُه
      // لا يُطابقُ شيئاً.
      expect(bookingTimeSlotOf(DateTime(2026, 10, 8, 14, 59)), '14:00');
    });
  });

  group('الكُتّابُ الأربعةُ يَكتبونَ المجموعةَ كاملةً', () {
    test('(د) الخادم: الدالّتانِ تَكتبانِ الحقلَين والأعلامَ', () {
      for (final fn in const [
        'approveAndAssignOrder',
        'rescheduleAssignedOrder'
      ]) {
        final blk = stripComments(_exportBlock(idx, fn));
        expect(blk.contains('booking_date'), isTrue,
            reason: '$fn: لا تاريخَ حجز');
        expect(blk.contains('booking_time_slot'), isTrue,
            reason: '$fn: لا خانةَ ساعة');
        for (final f in kReminderFlags) {
          expect(blk.contains(f), isTrue,
              reason: '$fn: لا يُصفّرُ $f — فلا تذكيرَ للموعدِ الجديد');
        }
      }
    });

    test('(هـ) والسطحانِ يُنادِيانِ القاعدةَ ولا نسخةَ إنلاين', () {
      expect(RegExp(r'rescheduleDerivedFields\s*\(').hasMatch(screen), isTrue,
          reason: 'شاشةُ تفاصيلِ الطلبِ لا تُنادي القاعدة');
      expect(RegExp(r'rescheduleDerivedFields\s*\(').hasMatch(panel), isTrue,
          reason: 'لوحةُ الويبِ لا تُنادي القاعدة');
      // ولا اشتقاقٌ محلّيٌّ باقٍ: `'HH:00'` مبنيٌّ بيدٍ أو تصفيرُ علَمٍ مفرد.
      for (final e
          in <String, String>{'الشاشة': screen, 'اللوحة': panel}.entries) {
        expect(e.value.contains("padLeft(2, '0')}:00"), isFalse,
            reason: '${e.key}: خانةُ الساعةِ مبنيّةٌ بيدٍ من جديد');
        expect(
            RegExp(r"client_reminder_24h_sent'?\]?\s*[:=]\s*false")
                .hasMatch(e.value),
            isFalse,
            reason: '${e.key}: تصفيرٌ إنلاين — القاعدةُ تَحملُه');
      }
    });

    test('(و) وكلُّ كاتبٍ لـ`service_date` على `orders` خارجَ الإنشاءِ معروف',
        () {
      // النطاقُ مُشتَقٌّ: أيُّ كتابةٍ **تُحدّثُ** الموعدَ يَجبُ أن تَحملَ
      // المجموعةَ — فسطحٌ خامسٌ يُراجَعُ بدلَ أن يُخلّفَ عدَّ سعةٍ خاطئاً.
      final writers = <String>{};
      // دارت: `updatePayload['service_date']` أو حِمْلُ `update({…})`
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final c = stripComments(f.readAsStringSync());
        // `=` لا `==`: الصياغةُ الأولى طابقت `m['service_date'] == null` في
        // لوحِ المواعيدِ — وهو **قراءة** لا كتابة، فأبلغَ الحارسُ عن كاتبٍ
        // ثالثٍ لا وجودَ له (وإضافتُه للقائمةِ كانت ستَكونَ الإصلاحَ الخطأ).
        if (RegExp(r"\['service_date'\]\s*=(?!=)").hasMatch(c) ||
            RegExp(r"'service_date':\s*ts\b").hasMatch(c)) {
          writers.add(f.uri.pathSegments.last);
        }
      }
      // اللوحة
      if (RegExp(r'service_date:\s*ts\b').hasMatch(panel)) {
        writers.add('Orders.tsx');
      }
      expect(writers, {'admin_order_details_screen.dart', 'Orders.tsx'},
          reason: 'كاتبٌ جديدٌ للموعدِ خارجَ الإنشاء: $writers');
    });

    test('(ز) شواهدُ التعليلِ الخادميّةُ قائمة', () {
      // لو زالَ أيٌّ منها فالقاعدةُ تُراجَعُ لا تُسكَت.
      final cap = File('functions/capacity.js').readAsStringSync();
      expect(cap.contains('d.booking_date'), isTrue,
          reason: 'عدُّ السعةِ لم يَعُدْ يَقرأُ تاريخَ الحجز');
      expect(cap.contains('d.booking_time_slot'), isTrue,
          reason: 'عدُّ السعةِ لم يَعُدْ يَقرأُ خانةَ الساعة');
      final rem =
          stripComments(_exportBlock(idx, 'remindClientsUpcomingAppointments'));
      expect(rem.contains('d.is_paid === true || driverAssigned'), isTrue,
          reason: 'شرطُ «موعدٌ حقيقيّ» تغيّر — يُراجَعُ تعليلُ التصفير');
      expect(rem.contains("client_reminder_24h_sent !== true"), isTrue,
          reason: 'التذكيرُ لم يَعُدْ يَتخطّى المرفوعَ علَمُه');
    });
  });
}

/// بدايةُ القوسِ المُوازِنِ لـ`]` عندَ [close] — مشياً إلى الوراء.
int _balBack(String s, int close) {
  var d = 0;
  for (var k = close; k >= 0; k--) {
    if (s[k] == ']') {
      d++;
    } else if (s[k] == '[') {
      d--;
      if (d == 0) return k;
    }
  }
  return -1;
}
