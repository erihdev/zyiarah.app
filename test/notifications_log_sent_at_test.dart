import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/notifications_log_writers.dart';
import 'helpers/strip_comments.dart';

/// **حقلُ الترتيبِ الغائبُ يُخرِجُ المستندَ من السجلِّ إلى الأبد
/// (2026-10-07).**
///
/// سجلُّ لوحةِ الويبِ هو `orderBy('sent_at','desc').limit(20)`، و**Firestore
/// تُستثني كلَّ مستندٍ لا يَحملُ حقلَ الترتيب** — لا تُرتّبُه آخراً، بل
/// تُسقطُه. وثلاثةُ كُتّابٍ دارتيّين لـ`notifications_log`، **واحدٌ منهم
/// وحدَه كان يَكتبُ `sent_at`** (مسارُ المنبثقِ). فالنتيجة:
///
///   * كلُّ بثٍّ **فوريٍّ** أُرسِلَ من تطبيقِ الإدارةِ غائبٌ عن «سجل
///     الإشعارات» في اللوحة — وصلَ العملاءَ ولا سطرَ له.
///   * وكلُّ بثٍّ **مجدولٍ** من التطبيقِ غائبٌ قبلَ الإرسالِ وبعدَه —
///     وشاشةُ التطبيقِ نفسُها تُرشِّحُ `status == 'scheduled'` فتُسقِطُه
///     لحظةَ إرسالِه: **فلا سطرَ له في أيِّ سطحٍ إطلاقاً**.
///
/// ولوحةُ الويبِ كانت تَكتبُ `sent_at: null` لمجدولِها — **حاضرٌ لا غائب**،
/// فيَظهرُ (آخراً تنازليّاً). أي أنّ القاعدةَ كانت مُنفَّذةً في سطحٍ واحدٍ
/// من ثلاثة، وهو النمطُ المتكرّرُ هنا.
///
/// الدلالةُ نفسُها مُثبَتةٌ على المُحاكي لا مُستنتَجةً من التوثيق — فحصٌ في
/// `functions/test/rules.notifications.test.js` يَكتبُ ثلاثةَ مستنداتٍ
/// (طابعٌ، و`null`، وبلا حقل) ويُثبِتُ أنّ الثالثَ وحدَه يَسقط.
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  final writes = notificationsLogWrites();

  group('حضورُ حقلِ الترتيب — نطاقٌ مُشتَقّ', () {
    test('الاشتقاقُ انحلَّ إلى ثلاثةِ كُتّابٍ بحقولٍ مقروءة', () {
      expect(writes.length, greaterThanOrEqualTo(3),
          reason: 'لم يُعثر على كُتّابِ المجموعة — اشتقاقٌ أجوف');
      for (final w in writes) {
        expect(w.fields.length, greaterThanOrEqualTo(5),
            reason: '${w.file}: حِملٌ قُرئَ بلا حقولٍ — اقتطاعٌ أجوف '
                '(${w.fields.keys.toList()})');
        expect(w.fields.containsKey('title'), isTrue,
            reason: '${w.file}: ليس حِملَ بثٍّ — الاقتطاعُ أصابَ غيرَ موضعِه');
      }
    });

    test('وكلُّ كاتبٍ دارتيٍّ يَكتبُ `sent_at`', () {
      final bad = writes.where((w) => !w.fields.containsKey('sent_at'));
      expect(bad.map((b) => b.file).toList(), isEmpty,
          reason: 'كاتبٌ بلا حقلِ الترتيبِ — مستندُه غائبٌ عن السجلِّ '
              'إلى الأبد، ولا رسالةَ خطأٍ في أيِّ مكان');
    });

    test('والمجدولُ `null` صريحاً — حاضرٌ لا غائب', () {
      final sched = writes.firstWhere(
          (w) => w.fields.containsKey('scheduled_at'),
          orElse: () => throw StateError('مسارُ الجدولةِ اختفى'));
      expect(sched.fields['sent_at'], 'null',
          reason: 'المجدولُ لم يُرسَل بعدُ فلا طابعَ له — والغيابُ '
              'يُسقِطُه من `orderBy`، فالقيمةُ `null` لا الحذف');
      // و`null` لا يُطابقُ `<=` فلا يُحرّكُ مكنسةَ الإفراجِ (مُثبَتٌ على
      // المُحاكي في سجلِّ القرارات) — ومكنسةُ الإفراجِ ما زالت على `scheduled_at`.
      final idx = stripComments(read('functions/index.js'));
      expect(idx, contains('where("scheduled_at", "<=", now)'),
          reason: 'مكنسةُ الإفراجِ تغيّرت — فتعليلُ `null` يُراجَعُ لا يُسكَت');
    });

    test('ولوحةُ الويبِ كاتبٌ رابعٌ تَكتبُه كذلك', () {
      final src = read('admin_panel/src/pages/Notifications.tsx');
      expect(src, contains('sent_at: isScheduled ? null : serverTimestamp()'),
          reason: 'كاتبُ اللوحةِ هو الذي كان يَفعلُ الصوابَ — '
              'فزوالُه يَفتحُ العطلَ من جهةٍ ثالثة');
    });
  });

  group('القُرّاء — ما يَجعلُ الحضورَ شرطاً', () {
    test('سجلُّ اللوحةِ يُرتّبُ بـ`sent_at`', () {
      final src = read('admin_panel/src/pages/Notifications.tsx');
      expect(src, contains("orderBy('sent_at', 'desc')"),
          reason: 'لو تغيّرَ حقلُ الترتيبِ فالحقلُ المطلوبُ يُراجَع');
    });

    test('ومنبثقُ العميلةِ يُرتّبُ به أيضاً — قارئانِ لا واحد', () {
      final svc = stripComments(read('lib/services/popup_service.dart'));
      expect(svc, contains("orderBy('sent_at', descending: true)"));
      // والبوّابةُ تَرفُضُ ما لا طابعَ له أصلاً (عمرٌ مجهول)، فالحضورُ شرطٌ
      // من جهتَين: الاستعلامُ والقاعدة.
      final gate = stripComments(read('lib/utils/popup_gate.dart'));
      expect(gate, contains('if (sentAt == null) return false;'));
    });

    test('والخادمُ يَملأُ الغائبَ ولا يَطمِسُ القائم', () {
      final idx = stripComments(read('functions/index.js'));
      expect(
          idx,
          contains('...(data.sent_at ? {} : '
              '{sent_at: FieldValue.serverTimestamp()})'),
          reason: 'إمّا لا يُملأُ (فالمجدولُ يَبقى `null` بلا لحظةِ إرسال) '
              'أو يُطمَسُ الفوريُّ بلحظةِ تسليمٍ متأخّرة');
    });
  });
}
