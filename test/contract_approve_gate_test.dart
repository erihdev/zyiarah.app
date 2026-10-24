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
  [{"status": "approved_waiting_payment"}, "ok", true],
  [{"status": "approved_waiting_payment", "is_paid": true},
   "activationStuck", false],
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
      test('[$pos] ${cases[pos][0]} ⇒ ${cases[pos][1]} / بانتظار الدفع=${cases[pos][2]}',
          () {
        final doc = Map<String, dynamic>.from(cases[pos][0] as Map);
        expect(contractHealthOf(doc), _byName[cases[pos][1] as String],
            reason: 'حالةُ الصحّةِ لا تُطابقُ الجدول');
        expect(contractAwaitingPayment(doc), cases[pos][2] as bool,
            reason: '«بانتظار الدفع» لا يُطابقُ الجدول');
      });
    }

  });

  group('السطحانِ يُنادِيانِ القاعدةَ ولا يُعيدانِ تعدادَها', () {
    final flutter =
        _mask(File('lib/screens/admin/admin_contracts_screen.dart').readAsStringSync());
    final panelRaw = File('admin_panel/src/pages/Contracts.tsx').readAsStringSync();
    final panel = _mask(panelRaw);

    test('(أ) لا زرَّ «اعتماد العقد» ولا كتابةَ اعتمادٍ في السطحَين', () {
      // قرار المالك 2026-10-24: التوقيعُ والدفعُ من العميلةِ يكفيان، والعقدُ
      // يَتفعّلُ لحظةَ الدفع. عودةُ الزرِّ تُعيدُ خطوةً لا ينتظرها شيء.
      for (final src in [flutter, panel]) {
        expect(src.contains('اعتماد العقد'), isFalse);
        expect(src.contains('اعتماد الباقة'), isFalse);
        expect(src.contains("'status': 'approved_waiting_payment'"), isFalse);
        expect(src.contains("status: 'approved_waiting_payment'"), isFalse,
            reason: 'كتابةُ اعتمادٍ عادت');
      }
      expect(flutter.contains('void _approveContract('), isFalse);
      expect(panel.contains('const handleApprove = async'), isFalse);
    });

    test('(ب) ما لم يُدفَع يُقالُ عنه ذلك — بالقاعدةِ في السطحَين', () {
      expect(flutter.contains('if (contractAwaitingPayment(data))'), isTrue);
      expect(flutter.contains('kContractAwaitingPaymentNote'), isTrue);
      expect(panel.contains("from '../utils/contractHealth.ts'"), isTrue,
          reason: 'المرآةُ غيرُ مستورَدة');
      expect(panel.contains('contractAwaitingPayment(contract) ?'), isTrue);
      expect(panel.contains('CONTRACT_AWAITING_PAYMENT_NOTE'), isTrue);
    });

    test('(ج) العميلةُ تُكمِلُ دفعَ عقدٍ موقَّعٍ من «عقودي»', () {
      // كان الزرُّ مشروطاً بـ`approved_waiting_payment` وحدَها — فتوقيعٌ لم
      // يُدفَع (`pending`) بلا زرٍّ إلى الأبد بعد إلغاءِ الاعتماد.
      final list = _mask(File('lib/screens/contracts_list_screen.dart')
          .readAsStringSync());
      expect(list.contains('if (contractAwaitingPayment(data))'), isTrue);
      expect(list.contains("status == 'approved_waiting_payment' &&"), isFalse);
    });

    test('(ج٢) الرادارُ يَعُدُّ المدفوعَ الذي لم يَتفعّل وحدَه', () {
      final insights = _mask(File('lib/screens/admin/admin_insights_screen.dart')
          .readAsStringSync());
      expect(insights.contains(".where('is_paid', isEqualTo: true)"), isTrue,
          reason: 'توقيعاتٌ لم تُدفَع تُعَدُّ «بانتظار المراجعة»');
      expect(insights.contains('عقود بانتظار المراجعة'), isFalse);
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

  });

  group('التعليلُ الخادميُّ ما زال قائماً — فالقاعدةُ ليست تخميناً', () {
    final idx = File('functions/index.js').readAsStringSync();
    final idxMasked = idx
        .split('\n')
        .map((l) => l.trimLeft().startsWith('//') ? ' ' * l.length : l)
        .join('\n');

    test('(ز) نافذةُ الإنقاذِ تَشملُ حالتَي ما قبلَ التفعيلِ معاً', () {
      // **تغيّرت هذه النافذةُ في 2026-10-07، فيُراجَعُ التعليلُ لا يُسكَت**
      // — وهو ما كان مكتوباً في سببِ هذا الفحصِ نفسِه.
      //
      // كانت `status == "pending"` وحدَها، وكان أحدُ أسبابِ خطورةِ ضغطةِ
      // الاعتمادِ أنّها تَكتبُ `approved_waiting_payment` **فتُخرِجُ العقدَ
      // من النافذة**. وقد تبيّنَ أنّ تلك الحالةَ هي ما يَترُكُه المسارُ
      // الطبيعيُّ أصلاً عند فشلِ التفعيل (الدفعُ يَقعُ منها، وكاتبُه لا
      // يَمَسُّ `status`) — فالنافذةُ كانت تُفلِتُ الشكلَ الغالبَ لا الضغطةَ
      // وحدَها. ووُسِّعت لتَشملَ الاثنتَين.
      //
      // فذلك السببُ بعينُه **سقط**: الاعتمادُ لم يَعُدْ يُخرِجُ العقدَ من
      // النافذة. والبوّابةُ باقيةٌ لسببَيها الآخرَين، وهما كافيان: الضغطةُ
      // تَدفعُ «يرجى إتمام الدفع» لمن دَفعت، و`activateContractOnPaid` لا
      // يُعادُ إطلاقُه (شرطُه `before.is_paid !== true`) — يُثبِتُهما (ح)
      // و(ج) أدناه.
      expect(
          RegExp(r'\.where\("is_paid", "==", true\)\s*\n\s*'
                  r'\.where\("status", "in", \[([^\]]*)\]\)')
              .firstMatch(idxMasked),
          isNotNull,
          reason: 'ضاقت نافذةُ الإنقاذ — فعقدٌ مدفوعٌ فشلَ تفعيلُه يُفلِتُها');
      // والمجموعةُ هي مجموعةُ القاعدةِ المشترَكةِ بعينِها — يَشدُّها
      // `contract_stuck_scope_test` في الجهتَين.
      expect(idxMasked.contains('"pending", "approved_waiting_payment"'), isTrue,
          reason: 'افترقت نافذةُ الإنقاذِ عن kContractPreActiveStatuses');
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
