import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/broadcast_target.dart';

import 'helpers/notifications_log_writers.dart';
import 'helpers/strip_comments.dart';

/// **جمهورُ البثِّ: قيمةُ الحقلِ شيءٌ واسمُ موضوعِ FCM شيءٌ آخر (2026-10-07).**
///
/// الخادمُ يَعرفُ أربعاً (`validTargets`): `all`/`clients`/`drivers`/`admins`.
/// و`all_users` اسمُ **موضوعٍ** يَشترِكُ فيه الجهازُ، ويَستعملُه الخادمُ
/// موضوعاً لا حقلاً (`target === "all" ? "all_users"`). وشاشةُ البثِّ تَحملُه
/// قيمةَ واجهةٍ ثمّ تُحوّلُها قبلَ الكتابة — **في اثنَين من ثلاثةِ كُتّاب**:
/// المسارانِ الفوريُّ والمنبثقُ يُحوّلان، والمجدولُ يُمرّرُ `_target` كما هو
/// إلى `scheduleBroadcast` فيُكتَبُ `all_users` في الحقل.
///
/// وأثرُه شيئان: التسليمُ صحيحٌ **بفالِّ** `_deliverBroadcast` إلى «بلا
/// مُرشِّح» لا بقرارٍ (ففرعٌ رابعٌ أو تحقّقٌ هناك يُحوّلُ كلَّ بثٍّ مجدولٍ
/// «للجميع» إلى جمهورٍ آخرَ بصمت)، وسجلُّ لوحةِ الويبِ يَطبعُ الرمزَ
/// الداخليَّ حرفيّاً في واجهةٍ عربيّة.
void main() {
  group('القاعدة — سلوكاً', () {
    test('اسمُ الموضوعِ يُحوَّلُ إلى قيمةِ الحقل', () {
      expect(broadcastTargetOf('all_users'), 'all');
    });

    test('القيمُ المعروفةُ تَمُرُّ كما هي', () {
      for (final t in kBroadcastTargets) {
        expect(broadcastTargetOf(t), t, reason: '$t تغيّرَ بالمرور');
      }
    });

    test('المجهولُ «الجميع» — قرارٌ لا تسامُح', () {
      // بثٌّ لا يَصِلُ أحداً أسوأُ من بثٍّ يَصِلُ أكثرَ من المقصود، وهو ما
      // يَفعلُه الخادمُ للمستنداتِ القائمة.
      expect(broadcastTargetOf(''), 'all');
      expect(broadcastTargetOf('clients '), 'clients');
      expect(broadcastTargetOf('whatever'), 'all');
    });

    test('ومجموعةُ القيمِ = `validTargets` في الخادمِ حرفاً', () {
      final String idx = File('functions/index.js').readAsStringSync();
      final m = RegExp(r'validTargets\s*=\s*\[([^\]]*)\]').firstMatch(idx);
      expect(m, isNotNull, reason: 'validTargets اختفت من الخادم');
      final server = RegExp(r'"([a-z_]+)"')
          .allMatches(m!.group(1)!)
          .map((x) => x.group(1)!)
          .toSet();
      expect(kBroadcastTargets, server,
          reason: 'القيمُ المُعلَنةُ والخادمُ افترقا');
    });
  });

  group('الوصل — كلُّ كاتبٍ يَمُرُّ بالقاعدة', () {
    /// كُتّابُ الحقلِ — نطاقٌ مُشتَقٌّ يَسكنُ
    /// `test/helpers/notifications_log_writers.dart`، لأنّ حارسَ حضورِ
    /// `sent_at` يَسألُ السؤالَ نفسَه («مَن يَكتبُ هذه المجموعة؟») ونسختانِ
    /// من الاستخراجِ تَنحرِفان. وفيه مزلقانِ مسجَّلانِ: الاقتطاعُ من `({`
    /// الحِملِ نفسِه لا «أقربُ ذكرٍ للمجموعة» (أوّلُ صياغةٍ نسبَت
    /// `'target': _target` في سجلِّ التدقيقِ إلى الكتابةِ التي تَسبقُه)،
    /// وبدايةُ الحِملِ `brace + 2` لا `+ 1` (وإلّا قُرئَت صفرُ حقول).
    List<({String file, String expr})> writers() => notificationsLogWrites()
        .where((w) => w.fields.containsKey('target'))
        .map((w) => (file: w.file, expr: w.fields['target']!))
        .toList();

    test('النطاقُ انحلَّ إلى كاتبَين على الأقلّ', () {
      final w = writers();
      expect(w.length, greaterThanOrEqualTo(2),
          reason: 'لم يُعثر على كُتّابِ الحقل — اشتقاقٌ أجوف: $w');
    });

    test('ولا كاتبٌ يَكتبُ القيمةَ خامّاً', () {
      final bad = writers()
          .where((w) => !w.expr.contains('broadcastTargetOf(') &&
              !w.expr.contains('mappedTarget'))
          .toList();
      expect(bad, isEmpty,
          reason: 'كاتبٌ يَكتبُ الجمهورَ بلا تحويل — '
              '${bad.map((b) => '${b.file}: ${b.expr}').join(', ')}');
    });

    test('ولا تحويلٌ إنلاين باقٍ (نسخةٌ ثانيةٌ تَنحرِف)', () {
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.path.endsWith('utils/broadcast_target.dart')) continue;
        final src = stripComments(e.readAsStringSync());
        expect(src.contains("== 'all_users' ? 'all'"), isFalse,
            reason: '${e.path}: تحويلٌ إنلاين عادَ');
      }
      // مضادّةٌ: الشرحُ الذي يَحكي الصيغةَ القديمةَ ما زال في الخامّ.
      final raw =
          File('lib/utils/broadcast_target.dart').readAsStringSync();
      expect(raw.contains('all_users'), isTrue,
          reason: 'شرحُ الصيغةِ القديمةِ زال');
    });
  });

  group('الخادمُ واللوحة', () {
    test('فالُّ «الجميع» صارَ مُعلَناً ومُسجَّلاً', () {
      final String idx = stripComments(
          File('functions/index.js').readAsStringSync());
      final int i = idx.indexOf('async function _deliverBroadcast');
      expect(i, greaterThan(0));
      final int j = idx.indexOf('\nasync function ', i + 10);
      final String body = idx.substring(i, j < 0 ? idx.length : j);
      expect(body.contains('KNOWN_TARGETS'), isTrue,
          reason: 'الفالُّ عادَ مصادفةً — لا قائمةَ معروفةٍ ولا سطرَ سجلّ');
      expect(body.contains('unknown target'), isTrue,
          reason: 'المجهولُ يُسلَّمُ للجميعِ بلا أثرٍ في السجلّ');
      // ولا رفضَ: مستنداتُ الإنتاجِ القائمةُ تَحملُ `all_users`.
      final int k = body.indexOf('KNOWN_TARGETS');
      expect(body.substring(k, k + 420).contains('return'), isFalse,
          reason: 'المجهولُ صارَ مرفوضاً — يَكسِرُ المجدولَ القائمَ في الإنتاج');
    });

    /// واللوحةُ كاتبٌ رابعٌ لهذا الحقل (`addDoc(collection(db,
    /// 'notifications_log'), { target, … })`) — وقيمُها **قانونيّةٌ
    /// بالبناءِ** لأنّ قائمةَ أزرارِها تَحملُ القيمَ نفسَها ولا تَعرِفُ اسمَ
    /// موضوعِ FCM أصلاً. فلا مرآةَ لها في TypeScript (تصديرٌ بلا مُنادٍ هو
    /// ما يَرفُضُه `no_dead_code_test` على الجهةِ الأخرى)، والمشدودُ أنّ
    /// قيمَها تَبقى **داخلَ** المجموعة: زرٌّ رابعٌ بقيمةٍ من عندِه يُكتَبُ
    /// خامّاً كما كُتبَ `all_users` من الجهةِ الدارتيّة.
    /// **ومُرشِّحُ الدورِ كان مكتوباً مرّتَين، والنسختانِ افترقتا.** داخلَ
    /// `_deliverBroadcast` نفسِه: استعلامُ `fcm_tokens` بثلاثةِ فروعٍ
    /// واستعلامُ `users` — الذي يُكتَبُ منه صندوقُ الإشعاراتِ — بفرعَين،
    /// فـ`admins` يَسقطُ إلى «بلا مُرشِّح» فيُكتَبُ سطرُ الصندوقِ **لكلِّ
    /// مستخدمٍ في النظام**. كامنٌ (لا مُحرِّرَ يُنتجُ `admins`) ومسدودٌ الآن
    /// بقاعدةٍ واحدةٍ، والمشدودُ أنّها تَبقى واحدة.
    test('ومُرشِّحُ الدورِ قاعدةٌ واحدةٌ للمجموعتَين', () {
      final String idx = stripComments(
          File('functions/index.js').readAsStringSync());
      final int i = idx.indexOf('async function _deliverBroadcast');
      expect(i, greaterThan(0));
      final int j = idx.indexOf('\nasync function ', i + 10);
      final String body = idx.substring(i, j < 0 ? idx.length : j);

      expect(body.contains('where("role"'), isFalse,
          reason: 'مُرشِّحٌ إنلاين عادَ — ومن ثَمَّ نسختانِ تَنحرِفان');
      for (final c in const ['fcm_tokens', 'users']) {
        expect(
            body.contains('_applyAudienceRoleFilter(\n'
                '        getFirestore().collection("$c")'),
            isTrue,
            reason: '$c لا يَمُرُّ بالقاعدة');
      }

      // ولكلِّ جمهورٍ غيرِ «الجميع» فرعٌ في القاعدة، و«الجميع» يَفُلُّ.
      final int h = idx.indexOf('function _applyAudienceRoleFilter');
      expect(h, greaterThan(0));
      final String fn = idx.substring(h, idx.indexOf('\n}', h));
      final branches = RegExp(r'target === "([a-z_]+)"')
          .allMatches(fn)
          .map((m) => m.group(1)!)
          .toSet();
      expect(branches, kBroadcastTargets.difference({'all'}),
          reason: 'جمهورٌ بلا فرعٍ يَسقطُ إلى «بلا مُرشِّح» — '
              'أي إلى كلِّ مستخدمٍ في النظام');
      expect(fn.contains('"admin", "super_admin"'), isTrue,
          reason: 'المدير العامُّ المُؤسِّسُ يَحملُ `super_admin` في `role`');
    });

    test('وقيمُ أزرارِ اللوحةِ داخلَ المجموعةِ (كاتبٌ رابع)', () {
      final String src = File('admin_panel/src/pages/Notifications.tsx')
          .readAsStringSync();
      final int i = src.indexOf("name=\"target\"");
      expect(i, greaterThan(0), reason: 'مُنتقي الجمهورِ في اللوحةِ اختفى');
      // الكتلةُ الحرفيّةُ التي تُبنى منها الأزرارُ تَسبقُ الوَسمَ.
      // المِرساةُ `{[` لا `[{`: الكتلةُ تُفتَحُ بتعبيرِ JSX ثمّ المصفوفة،
      // وأوّلُ صياغةٍ عكسَت المحرفَين فلم تُقتطَع شيئاً (أمسكَها `greaterThan`).
      final int open = src.lastIndexOf('{[', i);
      expect(open, greaterThan(0), reason: 'قائمةُ الأزرارِ لم تُقتطَع');
      final List<String> vals = RegExp(r"val:\s*'([a-z_]+)'")
          .allMatches(src.substring(open, i))
          .map((m) => m.group(1)!)
          .toList();
      expect(vals.length, greaterThanOrEqualTo(3),
          reason: 'اقتطاعٌ أجوف — لم تُقرأ قيمُ الأزرار: $vals');
      expect(vals.where((v) => !kBroadcastTargets.contains(v)).toList(), isEmpty,
          reason: 'زرٌّ يَكتبُ قيمةً لا يَعرفُها الخادم — $vals');
    });

    test('وتسميةُ اللوحةِ لا تَطبعُ رمزاً داخليّاً', () {
      final String src = File('admin_panel/src/pages/Notifications.tsx')
          .readAsStringSync();
      final int i = src.indexOf('const targetLabel');
      expect(i, greaterThan(0));
      final String body = src.substring(i, src.indexOf('};', i) + 2);
      expect(body.contains('return t;'), isFalse,
          reason: 'تُعيدُ ما لا تَعرفُه كما هو — `all_users` في واجهةٍ عربيّة');
      for (final t in const ['clients', 'drivers', 'admins']) {
        expect(body.contains("'$t'"), isTrue, reason: '$t بلا تسمية');
      }
      expect(body.contains('الجميع'), isTrue);
    });
  });
}
