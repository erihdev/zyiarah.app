import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/booking_fields.dart';
import 'package:zyiarah/utils/ksa_instant.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **الموعدُ يُخزَّنُ مرّتَين، وتمثيلٌ واحدٌ منهما كان يَتبعُ منطقةَ الجهاز.**
///
/// حقلا الحجزِ (`booking_date`/`booking_time_slot`) ساعةُ حائطٍ مستقلّةٌ عن
/// المنطقةِ **بقرارٍ مُسجَّلٍ** في `lib/utils/booking_fields.dart` («ولا
/// يَتأثّرُ بمنطقةِ جهازِه»)، و`service_date` لحظةٌ مطلقةٌ كانت
/// `Timestamp.fromDate(<ساعةُ حائطٍ محلّيّة>)` — فجهازٌ خارجَ +03 يُخزّنُ
/// لحظةً تُخالِفُ ساعتَه المعلَنةَ في الكتابةِ نفسِها.
///
/// **والقرارُ كان مُنفَّذاً في المسارِ المقابلِ من كلِّ سطح:** بيانات الدفعِ
/// تُرسِلُ الموعدَ نصّاً ساذجاً و`parseKsaIso` تَقرؤه رياضاً («قصدُ المرسِلِ
/// توقيتُ الرياض» بنصِّها)، وفرعا النداءِ الخادميِّ في سطحَي الإدارةِ
/// يُمرّرانِ `scheduledIso` ساذجاً — فالفروعُ المباشرةُ وحدَها كانت تَخرجُ
/// على القرار. ولوحةُ الويبِ تَشرحُ العطلَ بنصِّه على بُعدِ أربعةِ أسطرٍ من
/// الفرعِ الذي يَحملُه.
void main() {
  /// كاتبُ `service_date`: مُدخَلُ خريطةٍ (`'service_date':`) أو إسنادٌ
  /// بالقوسِ (`['service_date'] =`). والنظرةُ السالبةُ تُخرِجُ `== null`.
  final RegExp fieldWrite =
      RegExp('[\'"]?service_date[\'"]?' r'\s*(?:\]\s*=(?!=)|:)\s*');
  // ── جدولُ الحالاتِ المشترَكُ (نسخةٌ مطابقةٌ في `ksaInstant.test.ts`) ──
  // KSA_INSTANT_CASES_START
  const String casesJson = '''
[
  [[2026, 10, 9, 14, 0], "2026-10-09T11:00:00.000Z"],
  [[2026, 10, 9, 0, 0], "2026-10-08T21:00:00.000Z"],
  [[2026, 10, 9, 2, 59], "2026-10-08T23:59:00.000Z"],
  [[2026, 10, 9, 3, 0], "2026-10-09T00:00:00.000Z"],
  [[2026, 10, 9, 23, 30], "2026-10-09T20:30:00.000Z"],
  [[2026, 1, 1, 1, 15], "2025-12-31T22:15:00.000Z"],
  [[2026, 12, 31, 23, 0], "2026-12-31T20:00:00.000Z"],
  [[2026, 6, 15, 12, 45], "2026-06-15T09:45:00.000Z"]
]
''';
  // KSA_INSTANT_CASES_END

  final List<dynamic> cases = jsonDecode(casesJson) as List<dynamic>;

  group('لحظةُ الموعدِ بتوقيتِ الرياض', () {
    test('(أ) القاعدةُ سلوكاً — جدولٌ مشترَكٌ ومستقلٌّ عن منطقةِ المِحَكّ', () {
      expect(cases.length, greaterThanOrEqualTo(6));
      for (final dynamic raw in cases) {
        final row = raw as List<dynamic>;
        final w = (row[0] as List<dynamic>).map((dynamic x) => x as int).toList();
        final String want = row[1] as String;
        // المكوّناتُ هي ما يُقرَأ، فالمِحَكُّ قد يَعملُ في أيِّ منطقةٍ.
        final got = ksaInstantOf(DateTime(w[0], w[1], w[2], w[3], w[4]));
        expect(got.toUtc().toIso8601String(), want,
            reason: 'ساعةُ الحائطِ ${w.join(",")} ⇒ لحظةٌ خاطئة');
      }
    });

    test('(ب) التمثيلانِ يَتّفقانِ بالبناءِ — وهو جوهرُ الإصلاح', () {
      // `riyadhBookingFields` خادميّاً: أزِحْ +03 ثمّ اقرأْ مكوّناتِ UTC.
      // فلو خالفَت اللحظةُ حقلَي الحجزِ لَعَدَّ `capacity.js` ساعةً وحَجزَ
      // المُسنِدُ أخرى — وهي الحادثةُ المسجَّلة.
      for (int d = 8; d <= 10; d++) {
        for (int h = 0; h < 24; h++) {
          final w = DateTime(2026, 10, d, h, 0);
          final r = ksaInstantOf(w).add(kKsaUtcOffset).toUtc();
          expect(
              '${r.year}-${r.month.toString().padLeft(2, '0')}-'
              '${r.day.toString().padLeft(2, '0')}',
              bookingDateOf(w),
              reason: 'يومُ اللحظةِ يُخالِفُ `booking_date` عند $h');
          expect('${r.hour.toString().padLeft(2, '0')}:00', bookingTimeSlotOf(w),
              reason: 'ساعةُ اللحظةِ تُخالِفُ `booking_time_slot` عند $h');
        }
      }
    });

    test('(ج) الإزاحةُ واحدةٌ في اللغاتِ الثلاث', () {
      final js = File('functions/ksa_time.js').readAsStringSync();
      expect(js.contains('const KSA_OFFSET_MS = 3 * 60 * 60 * 1000;'), isTrue,
          reason: 'إزاحةُ الخادمِ تغيّرت — القاعدةُ الدارتيّةُ تَتبعُها');
      final ts = File('admin_panel/src/utils/ksaInstant.ts').readAsStringSync();
      expect(ts.contains('export const KSA_UTC_OFFSET_MS = 3 * 60 * 60 * 1000;'),
          isTrue, reason: 'إزاحةُ اللوحةِ تغيّرت');
      expect(kKsaUtcOffset.inMilliseconds, 3 * 60 * 60 * 1000);
    });

    test('(د) كلُّ كاتبٍ للموعدِ يَمُرُّ بالقاعدة — نطاقٌ مُشتَقّ', () {
      /// كتابةٌ يُستثنى منها، **ولكلٍّ سببُه**. المفتاحُ `ملفّ|سطرٌ مُقتطَع`.
      const Map<String, String> allowed = {
        // نصٌّ ساذجٌ في بيانات الدفعِ — وهو **التوأمُ الصحيحُ** الذي تَتبعُه
        // القاعدةُ: `parseKsaIso` يَقرؤه رياضاً، فلا تُزاحُ لحظةٌ هنا أصلاً.
        'lib/screens/payment_summary_screen.dart|toIso8601String':
            'نصٌّ ساذجٌ يَقرؤه `parseKsaIso` رياضاً',
      };
      final writers = <String, List<String>>{};
      final files = <String, String>{
        for (final f in sourcesIn('lib', atLeast: 100)) f.path: f.readAsStringSync(),
        for (final f in sourcesIn('admin_panel/src',
            atLeast: 20, exts: const ['.ts', '.tsx']))
          f.path: f.readAsStringSync(),
      };
      for (final e in files.entries) {
        if (e.key.contains('ksa_instant') || e.key.contains('ksaInstant')) continue;
        final code = stripComments(e.value);
        // **الصيغتانِ معاً: مُدخَلُ خريطةٍ وإسنادٌ بالقوسِ.** كاتبُ تطبيقِ
        // الإدارةِ هو `updatePayload['service_date'] = ts;` — بلا نقطتَين،
        // فكان **غيرَ مرئيٍّ** للكاشفِ وأوّلُ قضمةٍ عليه مرَّت خضراء. و
        // `== null` يُستثنى بنظرةٍ سالبةٍ وإلّا قُرئت قراءةٌ كتابةً.
        for (final m in fieldWrite.allMatches(code)) {
          // **قيمةُ الحقلِ بموازنةِ الأقواسِ حتى فاصلةِ العمقِ صفر، لا بسطر.**
          // التعبيرُ ثلاثيٌّ في العميلِ ويَمتدُّ ثلاثةَ أسطر، فحدُّ السطرِ
          // كان يَقتطِعُ `widget.serviceDate != null` وحدَها — إبلاغٌ خاطئٌ
          // عن شفرةٍ سليمة.
          int i = m.end, depth = 0;
          final sb = StringBuffer();
          while (i < code.length) {
            final c = code[i];
            if ('([{'.contains(c)) depth++;
            if (')]}'.contains(c)) {
              if (depth == 0) break;
              depth--;
            }
            if ((c == ',' || c == ';') && depth == 0) break;
            sb.write(c);
            i++;
          }
          String val = sb.toString().trim();
          if (val.isEmpty) continue;
          // **ومُعرِّفٌ مفردٌ يُحَلُّ إلى تعريفِه في الملفِّ نفسِه.** لوحةُ
          // الويبِ تَكتبُ `service_date: ts` و`ts` مُعرَّفٌ ثلاثةَ أسطرٍ
          // أعلاه — فقائمةُ أسماءٍ مسموحةٍ هنا تَتعفّن.
          if (RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(val)) {
            final def = RegExp('(?:const|final|var|let)\\s+(?:[\\w<>?, ]+\\s+)?'
                    '${RegExp.escape(val)}\\s*=\\s*([^;\n]+)')
                .firstMatch(code);
            if (def != null) val = '$val = ${def.group(1)!.trim()}';
          }
          (writers[e.key] ??= <String>[]).add(val);
        }
      }
      expect(writers.length, greaterThanOrEqualTo(2),
          reason: 'لم يُستخرَجْ كاتبٌ واحدٌ — فحصٌ أجوف');

      final offenders = <String>[];
      for (final e in writers.entries) {
        for (final val in e.value) {
          if (val.contains('ksaInstantOf')) continue;
          final hit = allowed.keys.firstWhere(
              (k) => k.split('|')[0] == e.key && val.contains(k.split('|')[1]),
              orElse: () => '');
          if (hit.isEmpty) offenders.add('${e.key}  ←  $val');
        }
      }
      expect(offenders, isEmpty,
          reason: '\n\nكتابةُ موعدٍ بلحظةٍ من منطقةِ الجهاز:\n  • '
              '${offenders.join('\n  • ')}\n');
    });

    test('(و) الجدولُ واحدٌ بين اللغتَين — فلا حالةٌ تُضافُ لجهةٍ وحدَها', () {
      final ts = File('admin_panel/src/utils/ksaInstant.test.ts')
          .readAsStringSync();
      final int a = ts.indexOf('KSA_INSTANT_CASES_START');
      final int b = ts.indexOf('KSA_INSTANT_CASES_END');
      expect(a, greaterThan(-1), reason: 'علامةُ بدءِ الجدولِ زالت من اللوحة');
      expect(b, greaterThan(a), reason: 'علامةُ ختمِ الجدولِ زالت');
      final String blk = ts.substring(a, b);
      // **الاقتطاعُ من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس**: المِرساةُ
      // `indexOf('[')` تَلتقطُ قوسَ تعليقِ النوعِ (`[number[], string][]`) —
      // الفخُّ المسجَّلُ في مرايا أخرى.
      final int end = blk.lastIndexOf(']');
      expect(end, greaterThan(-1), reason: 'لا مصفوفةَ في كتلةِ الجدول');
      int depth = 0, start = -1;
      for (int i = end; i >= 0; i--) {
        if (blk[i] == ']') depth++;
        if (blk[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThan(-1), reason: 'الاقتطاعُ لم يُوازَن');
      final String arr = blk
          .substring(start, end + 1)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n')
          .replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
      expect(jsonDecode(arr), cases,
          reason: 'جدولُ الحالاتِ افترقَ بين الدارتِ واللوحة');
    });

    test('(ز) والعرضُ يَتبعُ التسميةَ لا اللحظةَ — نصفُ الإصلاحِ الآخر', () {
      // الكتابةُ وحدَها لا تَكفي: جهازٌ خارجَ +03 يَرسمُ اللحظةَ الرياضيّةَ
      // بمنطقتِه، فتَرى العميلةُ في بطاقتِها ساعةً لم تَختَرْها (وساعاتُ
      // جدولِ المنطقةِ ساعاتُ الرياض). فأسبقيّةُ `orderAppointment` لحقلَي
      // الحجزِ هي ما يُبقي العنوانَ هو المُختار.
      final s = File('lib/utils/order_tracking.dart').readAsStringSync();
      final int iFn = s.indexOf('DateTime? orderAppointment(');
      expect(iFn, greaterThan(-1), reason: 'قاعدةُ الموعدِ زالت');
      final int iPair = s.indexOf('bookingDate != null', iFn);
      final int iInst = s.indexOf('return serviceDate;', iFn);
      expect(iPair, greaterThan(-1), reason: 'فرعُ حقلَي الحجزِ زال');
      expect(iInst, greaterThan(-1), reason: 'احتياطُ اللحظةِ زال');
      expect(iPair, lessThan(iInst),
          reason: 'عادت اللحظةُ تَتقدّمُ التسميةَ — فجهازٌ خارجَ +03 يَرسمُ '
              'ساعةً لم تَختَرْها العميلة');
      // وسطرُ «تأخّر إسنادُ فريقكِ» يَبقى على `service_date` بعينِه: شرطُ
      // الخادمِ هو الحقلُ نفسُه، والاحتياطُ بلا خانةِ وقتٍ منتصفُ الليل.
      final o = File('lib/screens/orders_list_screen.dart').readAsStringSync();
      expect(o.contains("appointment: (order['service_date'] as Timestamp?)?.toDate()"),
          isTrue,
          reason: 'سطرُ التأخّرِ لم يَعُدْ يَقرأُ الحقلَ الذي يَقرؤه الخادم');
    });

    test('(هـ) شواهدُ التعليلِ قائمةٌ — فالقاعدةُ تَتبعُ قراراً لا ذوقاً', () {
      final js = File('functions/ksa_time.js').readAsStringSync();
      // `parseKsaIso` ما زالت تَقرأُ الساذجَ رياضاً — وهي التوأمُ الذي
      // تُطابِقُه القاعدة. لو تغيّرَت فالقاعدةُ تُراجَعُ لا تُسكَت.
      expect(js.contains(r'/(?:Z|[+-]\d{2}:?\d{2})$/'), isTrue,
          reason: 'كاشفُ لاحقةِ المنطقةِ زال من `parseKsaIso`');
      expect(js.contains('d : new Date(d.getTime() - KSA_OFFSET_MS)'), isTrue,
          reason: '`parseKsaIso` لم تَعُدْ تَقرأُ الساذجَ رياضاً');
      // وحقلا الحجزِ ما زالا يُشتَقّانِ من المكوّناتِ (مستقلّانِ عن المنطقة).
      final bf = File('lib/utils/booking_fields.dart').readAsStringSync();
      expect(bf.contains('chosen.hour.toString().padLeft(2'), isTrue,
          reason: 'حقلا الحجزِ لم يَعودا من مكوّناتِ ما اختارَه الإنسان');
      // والمسارانِ الخادميّانِ يَبنيانِ اللحظةَ من `parseKsaIso` لا من نصٍّ.
      final idx = File('functions/index.js').readAsStringSync();
      expect(RegExp(r'parseKsaIso\(\s*scheduledIso\s*\)').hasMatch(idx), isTrue,
          reason: 'الفرعُ الخادميُّ لم يَعُدْ يَقرأُ `scheduledIso` رياضاً');
    });
  });
}
