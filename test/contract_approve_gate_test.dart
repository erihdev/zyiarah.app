// ════════════════════════════════════════════════════════════════════════
// «اعتماد العقد» كان يُخرِجُ عقداً مدفوعاً من إعادةِ المحاولةِ التلقائيّة،
// ويُطالِبُ مَن دفعَ بالدفعِ مرّةً أخرى (2026-10-05)
//
// الاعتمادُ خطوةٌ **قبلَ** الدفع، والزرُّ كان مشروطاً بـ`status == 'pending'`
// وحدَها في السطحَين الإداريَّين — وعقدٌ فشلَ تفعيلُه يَسكنُ تلك الحالةَ
// بعينِها. فالضغطةُ تَكتبُ `approved_waiting_payment`، وتَدفعُ «يرجى إتمام
// الدفع» لمن دفعت، و**تُخرِجُه من نافذةِ الإنقاذ**: مكنسةُ `opsHealthSweep`
// تَستعلمُ `is_paid == true && status == "pending"` بعينِها، و
// `activateContractOnPaid` لا يُطلَقُ ثانيةً أبداً (`before.is_paid !== true`).
//
// ولوحةُ الويبِ كانت أعمى تماماً: `StatusBadge(contract.status)` وحدَه، فلا
// رقاقةَ صحّةٍ ولا بطاقةً ولا سبباً — «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد»
// مرّةً أخرى، وشاشةُ Flutter تَعرضُهما منذ إصلاحِ وسمِ التفعيل.
//
// وجدولُ الحالاتِ **واحدٌ بين اللغتَين**: الكتلةُ بين العلامتَين أدناه
// يَقرؤها `contractHealth.test.ts` ويُقارِنُها `JSON.parse`اً، فحالةٌ تُضافُ
// لجهةٍ دون الأخرى تَسقط.
// ════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_health.dart';

// ── CONTRACT_HEALTH_CASES_BEGIN ──
const String kCasesJson = '''
[
  [{}, "ok", true],
  [{"status": "pending"}, "ok", true],
  [{"status": "pending", "is_paid": false}, "ok", true],
  [{"status": "pending", "is_paid": true}, "activationStuck", false],
  [{"status": "approved_waiting_payment"}, "ok", false],
  [{"status": "approved_waiting_payment", "is_paid": true}, "ok", false],
  [{"status": "active", "is_paid": true}, "ok", false],
  [{"status": "pending", "is_paid": true, "plan_validation_failed": true},
   "planMismatch", false],
  [{"status": "pending", "is_paid": true, "contract_activation_failed": true},
   "activationFailed", false],
  [{"status": "active", "is_paid": true, "contract_visits_pending": true},
   "visitsMissing", false],
  [{"status": "pending", "is_paid": true, "contract_visits_pending": true,
    "plan_validation_failed": true}, "planMismatch", false],
  [{"status": "pending", "is_paid": true, "contract_activation_failed": true,
    "contract_visits_pending": true}, "visitsMissing", false]
]
''';
// ── CONTRACT_HEALTH_CASES_END ──

const Map<String, ContractHealth> _byName = <String, ContractHealth>{
  'ok': ContractHealth.ok,
  'planMismatch': ContractHealth.planMismatch,
  'activationFailed': ContractHealth.activationFailed,
  'activationStuck': ContractHealth.activationStuck,
  'visitsMissing': ContractHealth.visitsMissing,
};

String _mask(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      return (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*') ||
              t.startsWith('{/*'))
          ? ' ' * l.length
          : l;
    })
    .join('\n');

void main() {
  final cases = (jsonDecode(kCasesJson) as List).cast<List<dynamic>>();

  group('القاعدةُ سلوكاً', () {
    test('الجدولُ نفسُه في اللوحةِ حرفاً بحرف — مرآةٌ لا دعوى', () {
      // القراءةُ من هنا لا من TS: `node:fs` بلا أنواعٍ تحتَ
      // `tsconfig.app.json` فيَسقطُ `npm run build` — فخٌّ مسجَّلٌ في هذا
      // المستودعِ وقعتُ فيه ثالثَ مرّة. (نمطُ `buildGate`/`serviceMeta`.)
      const String webTest = 'admin_panel/src/utils/contractHealth.test.ts';
      final String web = File(webTest).readAsStringSync();
      final int a = web.indexOf('CONTRACT_HEALTH_CASES_BEGIN');
      final int b = web.indexOf('CONTRACT_HEALTH_CASES_END');
      expect(a, greaterThan(0), reason: 'علامةُ بدايةِ الجدولِ غابت عن $webTest');
      expect(b, greaterThan(a), reason: 'علامةُ النهايةِ غابت');
      final String block = web.substring(a, b);
      // **من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس** — `indexOf('[')` يَلتقطُ
      // قوسَ تعليقِ النوعِ (`Row[]`)، وهو الفخُّ المسجَّلُ في `serviceMeta`.
      final int end = block.lastIndexOf(']');
      expect(end, greaterThan(0), reason: 'لا مصفوفةَ حالاتٍ بين العلامتَين');
      int depth = 0;
      int start = -1;
      for (int i = end; i >= 0; i--) {
        if (block[i] == ']') depth++;
        if (block[i] == '[') {
          depth--;
          if (depth == 0) {
            start = i;
            break;
          }
        }
      }
      expect(start, greaterThanOrEqualTo(0), reason: 'قوسٌ غيرُ مُوازَن');
      final webCases = jsonDecode(block.substring(start, end + 1)) as List;
      expect(webCases.length, cases.length,
          reason: 'عددُ الحالاتِ يَختلفُ بين اللغتَين');
      expect(jsonEncode(webCases), jsonEncode(cases),
          reason: 'جدولُ الحالاتِ انحرفَ — حالةٌ أُضيفت لجهةٍ دون الأخرى');
    });

    test('الجدولُ يَصِفُ الحالاتِ الخمسَ كلَّها — فلا فحصَ على زاويةٍ واحدة', () {
      expect(cases.length, greaterThanOrEqualTo(10));
      final seen = cases.map((c) => c[1] as String).toSet();
      expect(seen, _byName.keys.toSet(),
          reason: 'حالةٌ في `ContractHealth` بلا شاهدٍ في الجدول');
    });

    for (var i = 0; i < cases.length; i++) {
      final pos = i;
      test('[$pos] ${cases[pos][0]} ⇒ ${cases[pos][1]} / اعتماد=${cases[pos][2]}',
          () {
        final doc = Map<String, dynamic>.from(cases[pos][0] as Map);
        expect(contractHealthOf(doc), _byName[cases[pos][1] as String],
            reason: 'حالةُ الصحّةِ لا تُطابقُ الجدول');
        expect(contractApproveAllowed(doc), cases[pos][2] as bool,
            reason: 'بوّابةُ الاعتمادِ لا تُطابقُ الجدول');
      });
    }

    test('المدفوعُ المعلَّقُ وحدَه يُحجَبُ بسببٍ منطوق، وغيرُ موضعِه بلا سبب', () {
      expect(contractApproveBlockedReason({'status': 'pending', 'is_paid': true}),
          isNotNull);
      expect(contractApproveBlockedReason({'status': 'pending'}), isNull);
      // ليس موضعَ الزرِّ أصلاً ⇒ لا سببَ يُعرَض (وإلّا ظهرَ نصُّ حجبٍ على
      // كلِّ عقدٍ فاعل).
      expect(contractApproveBlockedReason({'status': 'active', 'is_paid': true}),
          isNull);
      expect(
          contractApproveBlockedReason(
              {'status': 'approved_waiting_payment', 'is_paid': true}),
          isNull);
    });
  });

  group('السطحانِ يُنادِيانِ القاعدةَ ولا يُعيدانِ تعدادَها', () {
    final flutter =
        _mask(File('lib/screens/admin/admin_contracts_screen.dart').readAsStringSync());
    final panelRaw = File('admin_panel/src/pages/Contracts.tsx').readAsStringSync();
    final panel = _mask(panelRaw);

    test('(أ) شاشةُ Flutter: البوّابةُ في الرسمِ وفي الضغطةِ معاً', () {
      expect(RegExp(r'if \(contractApproveAllowed\(data\) && _canApproveContracts\)')
              .hasMatch(flutter),
          isTrue,
          reason: 'زرُّ الاعتمادِ لا يُنادي البوّابة');
      expect(flutter.contains("status == 'pending' && _canApproveContracts"), isFalse,
          reason: 'عادَ الشرطُ القديمُ — وهو العطلُ بعينِه');
      // الضغطةُ تُعيدُ الفحصَ: لقطةٌ قديمةٌ تَحرُسُها البوّابةُ في الرسمِ
      // وحدَها لا تَمنعُ كتابةً.
      final body = flutter.substring(flutter.indexOf('void _approveContract('));
      final gate = body.indexOf('contractApproveBlockedReason(');
      final write = body.indexOf("'status': 'approved_waiting_payment'");
      expect(gate, greaterThan(0), reason: 'لا فحصَ عند الضغطة');
      expect(write, greaterThan(0));
      expect(gate, lessThan(write),
          reason: 'الفحصُ بعد الكتابةِ لا يَمنعُ شيئاً — الترتيبُ هو الإصلاح');
    });

    test('(ب) اللوحةُ: الزرُّ مشروطٌ بالقاعدةِ لا بالحالةِ وحدَها', () {
      expect(panel.contains("from '../utils/contractHealth.ts'"), isTrue,
          reason: 'المرآةُ غيرُ مستورَدة');
      expect(RegExp(r'contractApproveAllowed\(contract\) && \(').hasMatch(panel),
          isTrue,
          reason: 'زرُّ الاعتمادِ لا يُنادي البوّابة');
      expect(panel.contains("contract.status === 'pending' && ("), isFalse,
          reason: 'عادَ الشرطُ القديم');
    });

    test('(ج) اللوحةُ تَقرأُ طازجاً داخلَ معامَلةٍ قبلَ الكتابة', () {
      // `updateDoc` أعمى: صفحةٌ مفتوحةٌ من قبلِ وصولِ الدفعةِ تَكتبُ على
      // لقطةٍ قديمةٍ، وهذه الكتابةُ بعينِها تُخرِجُ العقدَ من نافذةِ الإنقاذ.
      final h = panel.substring(panel.indexOf('const handleApprove = async'));
      final body = h.substring(0, h.indexOf('\n    };'));
      expect(body.contains('runTransaction(db'), isTrue,
          reason: 'الاعتمادُ ليس معامَلة');
      final gate = body.indexOf('contractApproveBlockedReason(');
      final write = body.indexOf("status: 'approved_waiting_payment'");
      expect(gate, greaterThan(0), reason: 'لا فحصَ داخلَ المعامَلة');
      expect(gate, lessThan(write), reason: 'الفحصُ بعد الكتابة');
      // ورسالةُ المعامَلةِ هي الخبر: نصٌّ عامٌّ يَبتلعُ السببَ فيُقرأُ عطلَ
      // شبكةٍ فيُعيدُ الأدمنُ المحاولة.
      expect(body.contains('error instanceof Error ? error.message'), isTrue,
          reason: 'سببُ الرفضِ يُبتلَعُ برسالةٍ عامّة');
    });

    test('(د) اللوحةُ تَعرضُ صحّةَ التفعيلِ — كانت `status` وحدَه', () {
      expect(panel.contains('<HealthBanner c={contract} />'), isTrue,
          reason: 'بطاقةُ الصحّةِ غيرُ مرسومة');
      expect(panel.contains('contractHealthOf(c)'), isTrue);
      expect(panel.contains('contractHealthReason(c)'), isTrue,
          reason: 'السببُ الذي كتبَه الخادمُ لا يُعرَض');
      expect(panel.contains('CONTRACT_HEALTH_TITLES['), isTrue);
    });

    test('(هـ) شاشةُ Flutter ما زالت تَعرضُ الرقاقةَ والبطاقة', () {
      expect(flutter.contains('_contractHealthChip('), isTrue);
      expect(flutter.contains('_contractHealthBanner('), isTrue);
      expect(flutter.contains('contractHealthOf(data)'), isTrue);
    });

    test('(و) السببُ يُقالُ مكانَ الزرِّ في السطحَين — الإخفاءُ وحدَه يُقرأُ عطلاً', () {
      expect(flutter.contains('contractApproveBlockedReason(data)!'), isTrue,
          reason: 'شاشةُ Flutter تُخفي الزرَّ بلا سبب');
      expect(panel.contains('contractApproveBlockedReason(contract)}'), isTrue,
          reason: 'اللوحةُ تُخفي الزرَّ بلا سبب');
    });
  });

  group('التعليلُ الخادميُّ ما زال قائماً — فالقاعدةُ ليست تخميناً', () {
    final idx = File('functions/index.js').readAsStringSync();
    final idxMasked = idx
        .split('\n')
        .map((l) => l.trimLeft().startsWith('//') ? ' ' * l.length : l)
        .join('\n');

    test('(ز) نافذةُ الإنقاذِ ما زالت `is_paid == true && status == pending`', () {
      // هذا بعينُه سببُ خطورةِ الضغطة: الكتابةُ تُخرِجُ العقدَ منها.
      expect(
          RegExp(r'\.where\("is_paid", "==", true\)\s*\n\s*\.where\("status", "==", "pending"\)')
              .hasMatch(idxMasked),
          isTrue,
          reason: 'تغيّرت نافذةُ الإنقاذ — فيُراجَعُ التعليلُ لا يُسكَت');
    });

    test('(ح) المُشغّلُ لا يُعادُ إطلاقُه على عقدٍ مدفوعٍ سلفاً', () {
      // **مقصورٌ على جسمِ المُشغّلِ نفسِه.** أوّلُ صياغةٍ كانت
      // `contains('before.is_paid !== true')` على الملفِّ كلِّه — والعبارةُ
      // تَرِدُ في ثلاثةِ مُشغّلاتٍ أخرى وفي تعليق، فمرَّ اختبارُ قضمٍ غيَّرَ
      // شرطَ هذا المُشغّلِ **أخضرَ**: فحصُ حضورٍ يُرضيه موضعٌ لا علاقةَ له.
      final int i = idxMasked.indexOf('exports.activateContractOnPaid =');
      expect(i, greaterThan(0), reason: 'المُشغّلُ اختفى');
      final int j = idxMasked.indexOf('\nexports.', i + 10);
      final String body = idxMasked.substring(i, j > i ? j : idxMasked.length);
      expect(body.length, lessThan(2000),
          reason: 'الاقتطاعُ ابتلعَ ما بعدَ المُشغّل — فالفحصُ يَفقدُ دقّتَه');
      expect(body.contains('contracts/{contractId}'), isTrue,
          reason: 'الاقتطاعُ لم يُصِبِ المُشغّل');
      expect(
          body.contains(
              'if (before.is_paid === true || after.is_paid !== true) return null;'),
          isTrue,
          reason: 'شرطُ المُشغّلِ تغيّرَ — فقد يَصيرُ الإنقاذُ تلقائيّاً، '
              'فيُراجَعُ تعليلُ خطورةِ الاعتمادِ لا يُسكَت');
    });

    test('(ط) القواعدُ تَمنعُ الانتقالَ على عقدٍ مدفوع', () {
      final rulesRaw = File('firestore.rules').readAsStringSync();
      final rules = rulesRaw
          .split('\n')
          .map((l) => l.trimLeft().startsWith('//') ? ' ' * l.length : l)
          .join('\n');
      expect(
          RegExp(r"request\.resource\.data\.get\('status', ''\) == 'approved_waiting_payment'")
              .hasMatch(rules),
          isTrue,
          reason: 'القاعدةُ لا تَعرفُ الانتقال');
      expect(rules.contains("resource.data.get('is_paid', false) == true"), isTrue,
          reason: 'القاعدةُ لا تَقرأُ `is_paid` للمستندِ القائم');
      // على **الانتقالِ** لا على الحالةِ الناتجة، وإلّا حُجِبَ كلُّ تعديلٍ
      // إداريٍّ على عقدٍ مدفوعٍ يَحملُ تلك الحالةَ سلفاً.
      expect(rules.contains("affectedKeys()\n            .hasAny(['status'])"), isTrue,
          reason: 'المنعُ على الحالةِ الناتجةِ يَحجبُ تعديلاتٍ مشروعة');
      expect(rulesRaw.contains('نافذةِ الإنقاذ'), isTrue,
          reason: 'شرحُ القرارِ زال من القاعدة');
    });
  });
}
