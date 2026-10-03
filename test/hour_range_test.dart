// حارس: **نطاق ساعات العمل لا يكون طرفاه متساويين أبداً.**
//
// الخادم (`zoneDayScheduleForDate` في functions/index.js) يشترط حرفيّاً
// `Number.isInteger(s) && Number.isInteger(e) && e > s`، وإن لم يتحقّق أعاد
// `null` — أي **مغلق كلّ اليوم**. فلا رسالةَ رفضٍ هنا: يحفظ الأدمن «مفتوح»،
// وتقول الشاشة حُفظ، ويقرؤه الخادم إغلاقاً. لا إتاحة، ولا حجز، ولا خطأ.
//
// وقائمتا الساعات في المحرّر مستقلّتان على 0..23. ومحرّر التطبيق كان يُقيّدهما
// في الاتجاهين — تحريك البداية يدفع النهاية والعكس — **إلّا في طرف المدى**:
//
//   بداية 23 ⇒ النهاية `(23 + 1).clamp(1, 23)` = 23 ⇒ الطرفان متساويان ⇒ مغلق.
//
// ولم يُكتشف بقراءة الشفرة بل بفحص مرآة الويب (`zoneSchedule.test.ts`) على
// **كل** أزواج الساعات الـ576 لا على أمثلةٍ مختارة — لأن الثغرة كانت في زاويةٍ
// واحدة من المدى. فالفحص أدناه يفعل الشيء نفسه، وبنفس السبب.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/hour_range.dart';

/// شرط القارئ الخادمي، منقولاً كي يُقاس عليه.
bool serverAccepts(int start, int end) => end > start;

void main() {
  group('قيد نطاق الساعات', () {
    test('كل زوج ساعات على hourRangeWithStart يُنتج نطاقاً يقبله الخادم', () {
      final bad = <String>[];
      for (var s = 0; s < 24; s++) {
        for (var e = 0; e < 24; e++) {
          final r = hourRangeWithStart(s, e);
          if (!serverAccepts(r.start, r.end)) {
            bad.add('hourRangeWithStart($s,$e) ⇒ ${r.start}..${r.end}');
          }
        }
      }
      expect(bad, isEmpty,
          reason: 'نطاقات يقرؤها الخادم «مغلق»:\n${bad.join('\n')}');
    });

    test('كل زوج ساعات على hourRangeWithEnd يُنتج نطاقاً يقبله الخادم', () {
      final bad = <String>[];
      for (var s = 0; s < 24; s++) {
        for (var e = 0; e < 24; e++) {
          final r = hourRangeWithEnd(s, e);
          if (!serverAccepts(r.start, r.end)) {
            bad.add('hourRangeWithEnd($s,$e) ⇒ ${r.start}..${r.end}');
          }
        }
      }
      expect(bad, isEmpty,
          reason: 'نطاقات يقرؤها الخادم «مغلق»:\n${bad.join('\n')}');
    });

    test('النطاق يبقى داخل 0..23 — لا ساعة 24 ولا سالبة', () {
      for (var s = 0; s < 24; s++) {
        for (var e = 0; e < 24; e++) {
          for (final r in [hourRangeWithStart(s, e), hourRangeWithEnd(s, e)]) {
            expect(r.start, greaterThanOrEqualTo(0));
            expect(r.end, lessThanOrEqualTo(23));
          }
        }
      }
    });

    test('النطاق السليم لا يُمَسّ — القيد يصحّح ولا يتدخّل', () {
      expect(hourRangeWithStart(8, 22), (start: 8, end: 22));
      expect(hourRangeWithEnd(8, 22), (start: 8, end: 22));
    });

    test('تحريك البداية فوق النهاية يدفع النهاية', () {
      expect(hourRangeWithStart(20, 10), (start: 20, end: 21));
      expect(hourRangeWithStart(10, 10), (start: 10, end: 11));
    });

    test('تحريك النهاية تحت البداية يسحب البداية', () {
      expect(hourRangeWithEnd(20, 10), (start: 9, end: 10));
      expect(hourRangeWithEnd(10, 10), (start: 9, end: 10));
    });

    test('طرفا المدى — حيث كان القيد القديم يُخلّف نطاقاً مغلقاً', () {
      // كان: d.start = 23؛ d.end = (24).clamp(1,23) = 23 ⇒ متساويان ⇒ مغلق.
      expect(hourRangeWithStart(23, 23), (start: 22, end: 23));
      expect(hourRangeWithStart(23, 5), (start: 22, end: 23));
      expect(hourRangeWithEnd(0, 0), (start: 0, end: 1));
      expect(hourRangeWithEnd(15, 0), (start: 0, end: 1));
    });
  });

  group('المحرّر يمرّ كل تعديل ساعة على القيد', () {
    // القاعدة الصحيحة لا تنفع إن لم تُنادَ — ولو أُعيد `d.start = v` المباشر
    // لبقيت الفحوص أعلاه خضراء والعطل عاد. فالحارس على **موضع النداء**.
    // (نفس درس توحيد أهلية السائق: فحصُ القاعدة وحدها يترك المسار مكشوفاً.)
    const path = 'lib/screens/admin/admin_zone_schedule_editor.dart';

    test('أربع قوائم ساعات — يومية ونافذة، بدايةً ونهايةً — كلها عبر القيد', () {
      final src = _read(path);
      expect(RegExp('hourRangeWithStart').allMatches(src).length, 2,
          reason: 'بدايتان: اليوم الأسبوعي والنافذة الاستثنائية');
      expect(RegExp('hourRangeWithEnd').allMatches(src).length, 2,
          reason: 'نهايتان: اليوم الأسبوعي والنافذة الاستثنائية');
    });

    test('لا قيدٌ مكتوب إنلاين ثانيةً — القاعدة في موضع واحد', () {
      // الصيغة التي كانت: `if (d.end <= v) d.end = (v + 1).clamp(1, 23);`
      // وهي التي تحمل الثغرة. عودتها إنلاين تُعيد العطل بلا إسقاط فحصٍ آخر.
      final src = _read(path);
      expect(src.contains('.clamp(1, 23)'), isFalse,
          reason: 'قيدٌ إنلاين — استعمل hourRangeWithStart من utils/hour_range.dart');
      expect(src.contains('.clamp(0, 22)'), isFalse,
          reason: 'قيدٌ إنلاين — استعمل hourRangeWithEnd من utils/hour_range.dart');
    });
  });
}

String _read(String p) => File(p).readAsStringSync();
