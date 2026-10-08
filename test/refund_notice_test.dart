import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/refund_notice.dart';

import 'helpers/sources_in.dart';
import 'helpers/strip_comments.dart';

/// **ثلاثةُ حوارِ تأكيدٍ تَقولُ «لا يمكن التراجع» ولا تَقولُ ما يَحدثُ
/// للخدمة.**
///
/// الاتّجاهُ المعاكسُ له قاعدةٌ مقرَّرةٌ على ثلاثةِ أسطح
/// (`cancel_refund_notice.dart`: حوارُ الإلغاءِ يُسمّي إلى أين يَذهبُ المال)،
/// والاتّجاهُ هذا كان بلا شيء — وهو **الأحدُّ**، لأنّ ما لا يُقالُ فيه ليس
/// مصيرَ المالِ بل مصيرَ الخدمة: العمليّاتُ الأربعُ
/// (`moyasarRefundPayment`، `moyasarVoidPayment`، `tamaraRefundPayment`،
/// `tabbyRefundPayment`) تَكتبُ `is_paid: false` و**لا تَمَسُّ `status`**،
/// فطلبٌ مفتوحٌ يَحملُ سائقاً يَبقى على هاتفِه فيَذهبُ الفريقُ وينفّذُ
/// الخدمةَ بلا مقابل.
void main() {
  final String tsRule =
      File('admin_panel/src/utils/refundNotice.ts').readAsStringSync();
  final String tsTest =
      File('admin_panel/src/utils/refundNotice.test.ts').readAsStringSync();
  final String scr = File('lib/screens/admin/admin_order_details_screen.dart')
      .readAsStringSync();
  final String panel =
      File('admin_panel/src/pages/Orders.tsx').readAsStringSync();
  final String idx = File('functions/index.js').readAsStringSync();
  final String idxCode = stripComments(idx);

  /// يَقتطعُ كتلةَ الحالاتِ بين علامتَين، **من آخرِ `]` إلى الوراءِ بموازنةِ
  /// الأقواس**: `indexOf('[')` يَلتقطُ قوسَ تعليقِ النوعِ (`[string, …][]`)
  /// لا بدايةَ المصفوفة — فخٌّ مسجَّلٌ في هذا المستودع.
  List<dynamic> casesBetween(String begin, String end) {
    final int b = tsTest.indexOf('// $begin');
    final int e = tsTest.indexOf('// $end');
    expect(b, greaterThan(-1), reason: 'علامةُ $begin زالت من فحصِ الـTS');
    expect(e, greaterThan(b), reason: 'علامةُ $end زالت من فحصِ الـTS');
    final String block = tsTest.substring(b, e);
    final int close = block.lastIndexOf(']');
    expect(close, greaterThan(-1));
    int depth = 0;
    int open = -1;
    for (int k = close; k >= 0; k--) {
      if (block[k] == ']') depth++;
      if (block[k] == '[') {
        depth--;
        if (depth == 0) {
          open = k;
          break;
        }
      }
    }
    expect(open, greaterThan(-1), reason: 'جدولٌ غيرُ متوازن: $begin');
    String json = block.substring(open, close + 1).replaceAll("'", '"');
    json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m[1]!);
    return jsonDecode(json) as List<dynamic>;
  }

  /// جسمُ دالّةٍ دارتيّةٍ بموازنةِ الأقواس — **لا شريحةَ عدِّ أحرف**: فخُّ
  /// الحدِّ غيرِ المُوازَنِ عضَّ في هذا المستودعِ عشرَ مرّات، و
  /// `guard_window_bound_test` يَمنعُه على مِرساةِ دالّة. وقائمةُ المعامَلاتِ
  /// تُوازَنُ **أوّلاً** وإلّا التُقطَ قوسُ المعامَلاتِ المُسمّاةِ لا الجسم.
  String fnBody(String src, String decl) {
    final int i = src.indexOf(decl);
    expect(i, greaterThan(-1), reason: 'لم يُعثر على $decl');
    int k = src.indexOf('(', i);
    int d = 0;
    for (; k < src.length; k++) {
      if (src[k] == '(') d++;
      if (src[k] == ')') {
        d--;
        if (d == 0) break;
      }
    }
    final int open = src.indexOf('{', k);
    expect(open, greaterThan(-1));
    d = 0;
    for (int q = open; q < src.length; q++) {
      if (src[q] == '{') d++;
      if (src[q] == '}') {
        d--;
        if (d == 0) return src.substring(open, q + 1);
      }
    }
    fail('جسمٌ غيرُ متوازنٍ لـ$decl');
  }

  /// وسائطُ نداءٍ بموازنةِ الأقواسِ من موضعِ مطابقةٍ داخلَه.
  String callArgs(String src, int inside) {
    int open = src.lastIndexOf('(', inside);
    expect(open, greaterThan(-1));
    int d = 0;
    for (int q = open; q < src.length; q++) {
      if (src[q] == '(') d++;
      if (src[q] == ')') {
        d--;
        if (d == 0) return src.substring(open, q + 1);
      }
    }
    fail('نداءٌ غيرُ متوازن');
  }

  group('جملةُ ما يَحدثُ للخدمةِ عند إعادةِ المال', () {
    test('(أ) الأثرُ على الخدمةِ — جدولُ الحالاتِ واحدٌ بين اللغتَين', () {
      final List<dynamic> rows = casesBetween('IMPACT_BEGIN', 'IMPACT_END');
      expect(rows.length, greaterThanOrEqualTo(11),
          reason: 'جدولُ الحالاتِ انهارَ — الفحصُ يَصيرُ أخضرَ أجوف');
      const Map<String, RefundServiceImpact> byName = {
        'crewStillAssigned': RefundServiceImpact.crewStillAssigned,
        'openWithoutCrew': RefundServiceImpact.openWithoutCrew,
        'serviceEnded': RefundServiceImpact.serviceEnded,
      };
      // أصنافٌ مُسمّاةٌ لا حدٌّ عدديٌّ وحدَه: فقدُ صنفٍ لا يُكشَفُ بالطول.
      final Set<String> seen =
          rows.map((r) => (r as List<dynamic>)[2] as String).toSet();
      expect(seen, byName.keys.toSet(),
          reason: 'صنفُ أثرٍ سقطَ من الجدولِ أو ظهرَ صنفٌ لا تَعرفُه القاعدة');
      for (final r in rows) {
        final List<dynamic> row = r as List<dynamic>;
        final String? status = row[0] as String?;
        final bool hasDriver = row[1] as bool;
        final String want = row[2] as String;
        expect(
            refundServiceImpact(status: status, hasDriver: hasDriver),
            byName[want],
            reason: 'الحالةُ «$status»/$hasDriver تَختلفُ عن جدولِ الـTS');
      }
    });

    test('(ب) والنصُّ — جدولُ الحالاتِ واحدٌ بين اللغتَين', () {
      final List<dynamic> rows = casesBetween('TEXT_BEGIN', 'TEXT_END');
      expect(rows.length, greaterThanOrEqualTo(8));
      const Map<String, RefundOp> ops = {
        'refund': RefundOp.refund,
        'voidAuth': RefundOp.voidAuth,
      };
      const Map<String, RefundServiceImpact> byName = {
        'crewStillAssigned': RefundServiceImpact.crewStillAssigned,
        'openWithoutCrew': RefundServiceImpact.openWithoutCrew,
        'serviceEnded': RefundServiceImpact.serviceEnded,
      };
      expect(rows.map((r) => (r as List<dynamic>)[0] as String).toSet(),
          ops.keys.toSet(),
          reason: 'عمليّةٌ سقطت من الجدول — الصياغةُ تَختلفُ بالفعل');
      for (final r in rows) {
        final List<dynamic> row = r as List<dynamic>;
        final String s = refundNoticeText(
          op: ops[row[0] as String]!,
          impact: byName[row[1] as String]!,
          partial: row[2] as bool,
        );
        expect(s.isNotEmpty, row[3] as bool,
            reason: 'قولٌ/صمتٌ يَختلفُ عن جدولِ الـTS: $row');
        final String verb = row[4] as String;
        if (verb.isNotEmpty) {
          expect(s, contains(verb), reason: 'كلمةُ الفعلِ لا تَتبعُ العمليّة');
        }
      }
    });

    test('(ج) والنصُّ مطابقٌ حرفاً بحرفٍ بين الجهتَين', () {
      // الجملتانِ الحامِلتانِ — لا نُقابلُ الملفَّ كلَّه، فالتعليقاتُ تَختلفُ.
      for (final frag in const [
        'لا يُلغي الطلب: يبقى بحالته وسائقُه مُسنَداً',
        'فيذهب الفريق إلى العميلة. ألغِ الطلب أيضاً إن كانت الخدمة',
        'يبقى مفتوحاً بلا سائق ولن يُسنَد له',
        'فريق بعدها (الإسناد يشترط الدفع). ألغِه أيضاً كي لا يبقى',
        'الاسترداد الجزئي يَسِم الطلب غير مدفوع بالكامل، فيخرج من',
        'عدّ السعة والتذكيرات والجوائز.',
        'إلغاءُ التفويض',
        'استردادُ المبلغ',
      ]) {
        expect(tsRule.contains(frag), isTrue,
            reason: 'نصُّ المرآةِ افترقَ عن الدارت: «$frag»');
      }
    });

    test('(د) والأسطحُ الثلاثةُ تُنادي القاعدةَ عند القرار', () {
      final String code = stripComments(scr);
      // تطبيقُ الإدارة: الحوارانِ معاً، كلٌّ بجسمِه المُوازَن.
      for (final decl in const [
        'Future<void> _moyasarOperation(',
        'Future<void> _bnplRefundOperation(',
      ]) {
        final String body = fnBody(code, decl);
        final int call = body.indexOf('refundNoticeText(');
        final int dialog = body.indexOf('showDialog<bool>(');
        expect(call, greaterThan(-1), reason: '$decl لا يُنادي القاعدة');
        expect(dialog, greaterThan(-1));
        expect(call, lessThan(dialog),
            reason: 'الجملةُ تُبنى بعدَ الحوارِ فلا تَظهرُ فيه');
        // **والأهمّ: أنّها تُعرَضُ فعلاً.** أوّلُ صياغةٍ لهذا الفحصِ طلبَت
        // النداءَ قبلَ الحوارِ وحدَه — فحسابُ الجملةِ ثمّ إهمالُها كان
        // يَمُرُّ أخضرَ («الاسمُ ليس القدرة»). فالمشدودُ وسيطُ `content:`
        // بعينِه، مُقتطَعاً بموازنةِ أقواسِه.
        final int ci = body.indexOf('content: ');
        expect(ci, greaterThan(dialog),
            reason: 'لا وسيطَ content في حوارِ $decl');
        // الموازنةُ من قوسِ `Text(` نفسِه: `callArgs` تَبحثُ إلى **الوراء**
        // فتَلتقطُ قوسَ الثلاثيّةِ المُغلَّفةِ داخلَه لا النداءَ — فخُّ
        // الحدِّ في ثوبِ اتّجاهٍ خاطئ، وقد أسقطَ هذا الفحصَ على شفرةٍ سليمة.
        final int po = body.indexOf('(', ci);
        expect(po, greaterThan(ci));
        int cd = 0;
        int ce = -1;
        for (int q = po; q < body.length; q++) {
          if (body[q] == '(') cd++;
          if (body[q] == ')') {
            cd--;
            if (cd == 0) {
              ce = q;
              break;
            }
          }
        }
        expect(ce, greaterThan(po), reason: 'وسيطُ content غيرُ متوازن');
        final String content = body.substring(po, ce + 1);
        expect(content.contains(r'$notice'), isTrue,
            reason: 'الجملةُ محسوبةٌ ولا تُعرَضُ في $decl — '
                'فالحوارُ يَبقى سطراً واحداً');
      }
      // لوحةُ الويب.
      final String pc = stripComments(panel);
      expect(pc.contains('refundNoticeText('), isTrue,
          reason: 'لوحةُ الويبِ لا تُنادي القاعدة');
      final int pCall = pc.indexOf('refundNoticeText(');
      final int pConfirm = pc.indexOf('await confirm(', pCall);
      expect(pConfirm, greaterThan(pCall),
          reason: 'الجملةُ بعدَ الحوارِ في اللوحة');
      expect(pc.contains(r'${notice}'), isTrue,
          reason: 'الجملةُ تُبنى ولا تُلحَقُ بالسؤال');
    });

    test('(هـ) و`capture` بلا جملةٍ — الاتّجاهُ المعاكس', () {
      final String code = stripComments(scr);
      final int at = code.indexOf("functionName: 'moyasarCapturePayment'");
      expect(at, greaterThan(-1));
      expect(callArgs(code, at).contains('moneyBackOp'), isFalse,
          reason: 'التحصيلُ يَأخذُ المالَ ولا يُعيدُه — لا تحذيرَ له');
      // والثلاثةُ الأخرى تُمرّرُها — بوسائطِ ندائِها المُوازَنةِ لا بشريحة.
      int sites = 0;
      for (final fn in const ['moyasarVoidPayment', 'moyasarRefundPayment']) {
        for (final m in RegExp("functionName: '$fn'").allMatches(code)) {
          sites++;
          expect(callArgs(code, m.start).contains('moneyBackOp:'), isTrue,
              reason: '$fn بلا جملةٍ في أحدِ مواضعِه');
        }
      }
      expect(sites, 3,
          reason: 'عددُ مواضعِ إعادةِ المالِ تغيّرَ ($sites) — راجِعْ الجديد');
    });

    test('(و) وشواهدُ التعليلِ: العمليّاتُ الأربعُ لا تَمَسُّ `status`', () {
      for (final fn in const [
        'moyasarRefundPayment',
        'moyasarVoidPayment',
        'tamaraRefundPayment',
        'tabbyRefundPayment',
      ]) {
        final int i = idxCode.indexOf('exports.$fn');
        expect(i, greaterThan(-1), reason: 'exports.$fn اختفى');
        final int j = idxCode.indexOf('\nexports.', i + 10);
        final String b = idxCode.substring(i, j < 0 ? idxCode.length : j);
        expect(RegExp(r'is_paid:\s*false').hasMatch(b), isTrue,
            reason: '$fn لم يَعُد يَكتبُ is_paid: false — يُراجَعُ التعليل');
        expect(RegExp(r'\bstatus:\s*"').hasMatch(b), isFalse,
            reason: '$fn صارَ يَكتبُ حالةً — فالجملةُ تُراجَعُ لا تُسكَت '
                '(ربّما صارَ يُلغي الطلبَ فعلاً)');
      }
      // ومضادّةٌ: التجريدُ لم يُزِلْ كلَّ شيء.
      expect(idx.length, greaterThan(idxCode.length));
    });

    test('(ز) ومجموعةُ أسطحِ عمليّاتِ البوّابةِ كاملةً هي الثلاثةُ وحدَها', () {
      final Set<String> surfaces = <String>{};
      final RegExp ops = RegExp(
          r"""['"](?:moyasarRefundPayment|moyasarVoidPayment|tamaraRefundPayment|tabbyRefundPayment)['"]""");
      for (final f in [
        ...sourcesIn('lib', atLeast: 120),
        ...sourcesIn('admin_panel/src', exts: const ['.ts', '.tsx'], atLeast: 20),
      ]) {
        final String c = stripComments(f.readAsStringSync());
        if (ops.hasMatch(c)) surfaces.add(f.path.replaceAll('\\', '/'));
      }
      expect(
          surfaces,
          {
            'lib/screens/admin/admin_order_details_screen.dart',
            'admin_panel/src/pages/Orders.tsx',
          },
          reason: 'سطحٌ ثالثٌ يُنادي عمليّاتَ البوّابةِ — يَلزمُه نفسُ الجملة');
    });
  });
}
