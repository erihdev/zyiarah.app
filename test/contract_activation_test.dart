// حارسُ **تفعيلِ العقدِ المدفوع**: فشلٌ يُعادُ، ووسمٌ يُقرأ.
//
// ═══ العطلُ المَحروس (2026-10-05) ═══
//
// باقةُ الاشتراكِ أغلى مبلغٍ في التطبيق، و`activateContractOnPaid` مُشغّلٌ
// **بلا `retry`** ولا يَعودُ لمستندٍ فاته الحدث. وكان فيه ثلاثُ ثقوب:
//
// **(١) معامَلةُ التفعيلِ بلا `try`.** فشلُها يَرفعُ الاستثناءَ خارجَ
// المُعالِج: العقدُ يَبقى `is_paid: true` و`status: 'pending'` — لا تفعيلَ،
// ولا `visits_remaining`، ولا زيارةَ واحدة، ولا سائق، **ولا تنبيهَ من أيِّ
// نوع**، ولا محاولةَ ثانية. و`client_dashboard` يُرشِّحُ
// `m['status'] != 'active'` فيَحجبُ العقدَ: **بطاقةُ الاشتراكِ لا تَظهرُ
// أصلاً** لعميلةٍ دفعت.
//
// **(٢) فشلُ توليدِ الزياراتِ كان `console.error` وحدَه**، وتعليقُه يَقول
// «أي نقصٍ يُكمِله مسار إداري» — **وذلك المسارُ لا وجودَ له**:
// `generateSubscriptionVisits` نداءٌ بلا مُنادٍ في العميلِ (الموضعانِ في
// `contract_signing_screen` تعليقان) وهو على قائمةِ الحذفِ بملاحظةِ
// «استبدلها مُشغِّل activateContractOnPaid» — فالتعليقانِ يُشيرُ كلٌّ منهما
// إلى الآخرِ ولا يَعملُ أيٌّ منهما. والتوليدُ **تِباعيٌّ**، فاستثناءٌ عند
// الزيارةِ i يَترُكُ نقصاً جزئيّاً: رصيدٌ تَعرضُه بطاقتُها ولا مواعيدَ
// خلفَه، ولا مسارَ عميليٍّ يَخصِمُ ذلك الرصيد.
//
// **(٣) و`opsHealthSweep` لا يَمسُّ `contracts` إطلاقاً** — يَمسحُ `orders`
// و`store_orders` و`wallets` و`promo_codes` فقط.
//
// ═══ وثقبٌ كِدتُ أفتحُه بالإصلاح ═══
//
// مكنسةُ إعادةِ التوليدِ لو اكتفت بالعلَمِ لصارَ ضبطُه سلفاً على عقدٍ غيرِ
// مدفوعٍ **خدمةً مجّانيّةً**: `_generateContractVisits` يُنشئُ زياراتٍ بـ
// `is_paid: true` و`amount: 0` بعددِ `planVisits` الذي يَكتبُه العميل.
// فشرطُ `is_paid == true` في الاستعلامِ حاملٌ لا زينة — والقواعدُ تَحجبُ
// العلَمَ أيضاً لكنّها محجوزةٌ خلفَ STAGE-C فلا تُنشَرُ من الأتمتة.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_health.dart';
import 'helpers/sources_in.dart';

String _stripJs(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// جدولُ أسبابِ العقدِ **المشترَكُ** مع فحصِ اللوحة — يُقرَأُ من ملفِّه.
///
/// والاقتطاعُ من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس (`indexOf('[')` يَلتقطُ
/// قوسَ تعليقِ النوعِ `][]`)، ومع حجبِ أسطرِ التعليقِ الكاملةِ وحدَها.
List<List<Object?>> _sharedReasons() {
  final src =
      File('admin_panel/src/utils/contractHealth.test.ts').readAsStringSync();
  final a = src.indexOf('// ⟦REASONS⟧');
  final b = src.indexOf('// ⟦/REASONS⟧');
  if (a < 0 || b < 0 || b <= a) {
    throw StateError('علامتا جدولِ الأسبابِ مفقودتانِ من فحصِ الـTS');
  }
  final block = src.substring(a, b);
  final end = block.lastIndexOf(']');
  if (end < 0) throw StateError('لا قوسَ إغلاقٍ في جدولِ الأسباب');
  var depth = 0;
  var start = -1;
  for (var i = end; i >= 0; i--) {
    if (block[i] == ']') depth++;
    if (block[i] == '[') {
      depth--;
      if (depth == 0) {
        start = i;
        break;
      }
    }
  }
  if (start < 0) throw StateError('تعذّرَ موازنةُ أقواسِ جدولِ الأسباب');
  var json = block.substring(start, end + 1);
  json =
      json.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
  json = json.replaceAll("'", '"');
  json = json.replaceAll(RegExp(r'\bundefined\b'), 'null');
  // مفاتيحُ الكائناتِ في TS بلا اقتباس — وJSON يَلزمُه.
  json = json.replaceAllMapped(RegExp(r'([{,]\s*)([A-Za-z_]\w*)(\s*:)'),
      (m) => '${m[1]}"${m[2]}"${m[3]}');
  json = json.replaceAllMapped(RegExp(r',(\s*[\]\}])'), (m) => m.group(1)!);
  return (jsonDecode(json) as List<dynamic>)
      .map((r) => (r as List<dynamic>).cast<Object?>())
      .toList();
}

void main() {
  final js = File('functions/index.js').readAsStringSync();
  final jsCode = _stripJs(js);

  /// جسمُ دالّةٍ خادميّةٍ بحدِّه الحقيقيّ — لا بعدِّ أحرف. الشريحتانِ هنا
  /// (٥٠٠٠ و٦٠٠٠) تَتجاوزانِ `_activateContractNow` (٤٩٠٩) بـ٩١ و١٠٩١
  /// حرفاً، فتَقرآنِ شفرةَ دالّةٍ أخرى وتَحكمانِ بها. فخُّ الحدِّ مسجَّلٌ
  /// في هذا المستودعِ مرّاتٍ، وهذه صورتُه بعدِّ الأحرف.
  String fnBody(String src, String anchor) {
    final i = src.indexOf(anchor);
    expect(i, greaterThan(-1), reason: 'المِرساةُ «$anchor» اختفت');
    final ends = <int>[
      src.indexOf('\nexports.', i + 10),
      src.indexOf('\nasync function ', i + 10),
      src.indexOf('\nfunction ', i + 10),
    ].where((x) => x > 0);
    final j = ends.isEmpty ? src.length : ends.reduce((a, b) => a < b ? a : b);
    expect(j - i, greaterThan(400), reason: 'اقتطاعُ «$anchor» انهار');
    return src.substring(i, j);
  }

  // ── القاعدةُ نقيّةٌ: تُختبَرُ بلا Firebase ──
  group('حالةُ العقدِ تُشتَقُّ من مستندِه', () {
    test('عقدٌ سليمٌ مُفعَّلٌ لا يُظهِرُ شيئاً', () {
      expect(contractHealthOf({'is_paid': true, 'status': 'active'}),
          ContractHealth.ok);
    });

    test('غيرُ مدفوعٍ ومعلَّقٌ هو الحالةُ الطبيعيّةُ — لا وسم', () {
      expect(contractHealthOf({'is_paid': false, 'status': 'pending'}),
          ContractHealth.ok);
    });

    test('مدفوعٌ وما زال معلَّقاً = الحالةُ المتناقضةُ', () {
      expect(contractHealthOf({'is_paid': true, 'status': 'pending'}),
          ContractHealth.activationStuck);
    });

    test('فشلُ المعامَلةِ يُقرأُ قابلاً لإعادةِ المحاولةِ لا قراراً', () {
      final h = contractHealthOf({
        'is_paid': true,
        'status': 'pending',
        'contract_activation_failed': true,
      });
      expect(h, ContractHealth.activationFailed);
      expect(contractNeedsHuman(h), isFalse);
    });

    test('ونقصُ الزياراتِ يُقرأُ على عقدٍ مُفعَّلٍ — رصيدٌ بلا مواعيد', () {
      expect(
          contractHealthOf({
            'is_paid': true,
            'status': 'active',
            'contract_visits_pending': true,
          }),
          ContractHealth.visitsMissing);
    });

    test('وعدمُ تطابقِ الباقةِ قرارٌ بشريٌّ لا تُعادُ محاولتُه — وله الأولويّة',
        () {
      // الأولويّةُ مقصودة: عقدٌ يَحملُه لا تُعادُ محاولتُه، فإظهارُ «تُعاد
      // المحاولة» فوقَه كذب.
      final h = contractHealthOf({
        'is_paid': true,
        'status': 'pending',
        'plan_validation_failed': true,
        'contract_activation_failed': true,
      });
      expect(h, ContractHealth.planMismatch);
      expect(contractNeedsHuman(h), isTrue);
    });

    test('عقدٌ قديمٌ بلا رايةِ visits_generated لا يُقرأُ عاطلاً', () {
      // القياسُ على `status` لا على الراية: عقدٌ سابقٌ للراية سليمٌ وفاعل.
      expect(contractHealthOf({'is_paid': true, 'status': 'active'}),
          ContractHealth.ok);
    });

    test('والسببُ الذي كتبَه الخادمُ يُعرَضُ — وهو ما كان مكتوماً', () {
      expect(
          contractHealthReason({'plan_validation_error': 'planPrice mismatch'}),
          'planPrice mismatch');
      expect(contractHealthReason({'contract_visits_error': ' boom '}), 'boom');
      expect(contractHealthReason({'plan_validation_error': '   '}), isNull);
      expect(contractHealthReason({}), isNull);
    });

    test('ولكلِّ حالةٍ غيرِ سليمةٍ نصٌّ — لا بطاقةَ فارغة', () {
      for (final h in ContractHealth.values) {
        if (h == ContractHealth.ok) continue;
        expect(kContractHealthTitles[h]?.trim().isNotEmpty, isTrue,
            reason: 'الحالةُ $h بلا نصّ');
      }
    });
  });

  // ── الخادم: الفشلُ لا يَمضي صامتاً، والمحاولةُ تُعاد ──
  group('الخادم', () {
    test('معامَلةُ التفعيلِ داخلَ try — وفشلُها يُنبّهُ ويُوسَم', () {
      final seg = fnBody(jsCode, 'async function _activateContractNow');
      final iTry = seg.indexOf('try {');
      final iTxn = seg.indexOf('runTransaction');
      expect(iTry, greaterThan(0), reason: 'لا try في الدالّة');
      expect(iTry, lessThan(iTxn),
          reason: 'المعامَلةُ خارجَ try — فشلُها يَرفعُ الاستثناءَ ويَضيع');
      expect(seg.contains('contract_activation_failed'), isTrue,
          reason: 'الفشلُ لا يُوسَم');
      expect(seg.contains('تفعيل عقد مدفوع فشل'), isTrue,
          reason: 'الفشلُ لا يُنبَّهُ عنه');
    });

    test('ونقصُ الزياراتِ يَكتبُ علَمَه ويُنبّهُ مرّةً واحدة', () {
      final seg = fnBody(jsCode, 'async function _activateContractNow');
      expect(seg.contains('contract_visits_pending: true'), isTrue,
          reason: 'الفشلُ لا يَكتبُ علَمَه — فلا تَراه المكنسة');
      expect(seg.contains('contract_visits_alerted'), isTrue,
          reason: 'التصعيدُ بلا علَمٍ خاصٍّ يُكرَّرُ كلَّ دورة');
      // والنجاحُ يَمحو العلَمَ — بلاه يَبقى العقدُ في مجموعةِ الإعادةِ للأبد.
      expect(
          seg.contains('contract_visits_pending: FieldValue.delete()'), isTrue,
          reason: 'النجاحُ لا يَمحو العلَم');
    });

    test('والمكنسةُ تَمسحُ contracts — وكانت لا تَمسُّها إطلاقاً', () {
      final i = jsCode.indexOf('exports.opsHealthSweep');
      final sweep = jsCode.substring(i);
      expect(sweep.contains('db.collection("contracts")'), isTrue,
          reason: 'لا شبكةَ للعقودِ أصلاً');
      // الشقُّ الأوّلُ **على الحالةِ لا على علَم**: علَمُ الفشلِ يُكتَبُ بعد
      // فشلِ المعامَلةِ فقد يَفشلُ معها، أمّا «مدفوعٌ وما زال pending» فلا
      // تَحتاجُ أن يَنجحَ شيءٌ لتُرى.
      expect(
          sweep.contains('.where("is_paid", "==", true)') &&
              sweep.contains('.where("status", "==", "pending")'),
          isTrue,
          reason: 'استعلامُ الحالةِ المتناقضةِ تغيّر');
      // ويُتخطّى عدمُ التفعيلِ المقصود.
      expect(sweep.contains('plan_validation_failed === true'), isTrue,
          reason: 'المكنسةُ تُعيدُ محاولةَ قرارٍ بشريٍّ نُبِّه عنه سلفاً');
      expect(sweep.contains('_activateContractNow('), isTrue,
          reason: 'المكنسةُ لا تُنادي القاعدةَ — نسخةٌ ثانيةٌ تَنحرِف');
    });

    test('وإعادةُ التوليدِ مشروطةٌ بـis_paid — وإلّا فخدمةٌ مجّانيّة', () {
      final i = jsCode.indexOf('contract_visits_pending", "==", true');
      expect(i, greaterThan(0), reason: 'استعلامُ العلَمِ اختفى');
      final win = jsCode.substring(i, i + 200);
      expect(win.contains('.where("is_paid", "==", true)'), isTrue,
          reason: 'بلا هذا الشرطِ يُولَّدُ للعقدِ غيرِ المدفوعِ زياراتٌ '
              'is_paid:true و amount:0 بعددٍ يَكتبُه العميل');
    });

    test('والقاعدةُ مرّةٌ واحدةٌ بمُنادِيَين — لا نسخةَ في المكنسة', () {
      expect(
          RegExp(r'async function _activateContractNow')
              .allMatches(jsCode)
              .length,
          1);
      expect(RegExp(r'_activateContractNow\(').allMatches(jsCode).length,
          greaterThanOrEqualTo(3),
          reason: 'التعريفُ + المُشغّلُ + المكنسة');
    });

    test('ولا يُستثنى الاشتراكُ من التوليدِ الحتميِّ — الإعادةُ آمنةٌ بالمعرّف',
        () {
      // إعادةُ المحاولةِ لا تُكرّرُ الزياراتِ لأنّ المعرّفَ حتميّ. زوالُه
      // يَجعلُ كلَّ إعادةٍ تُنشئُ نسخةً — فالتعليلُ يُراجَعُ لا يُسكَت.
      expect(jsCode.contains(r'`sub_${contractRef.id}_${i + 1}`'), isTrue,
          reason: 'معرّفُ الزيارةِ لم يَبقَ حتميّاً');
    });

    test('والمسارُ الإداريُّ الذي كان التعليقُ يُحيلُ إليه ما زال بلا مُنادٍ',
        () {
      // التعليقُ القديمُ قال «أي نقصٍ يُكمِله مسار إداري» وهو
      // `generateSubscriptionVisits`. هذا الفحصُ يُثبّتُ أنّ الحجّةَ صحيحةٌ:
      // لو ظهرَ له مُنادٍ يوماً فالتعليلُ يُراجَعُ لا يُسكَت.
      final callers = sourcesIn('lib', atLeast: 100)
          .where((f) =>
              RegExp(r"httpsCallable\(\s*'generateSubscriptionVisits'")
                  .hasMatch(f.readAsStringSync()))
          .map((f) => f.path)
          .toList();
      expect(callers, isEmpty,
          reason: 'ظهرَ مُنادٍ — يُراجَعُ تعليلُ هذه الدفعة: $callers');
      expect(js.contains('exports.generateSubscriptionVisits'), isTrue,
          reason: 'المضادّة: الدالّةُ ما زالت مُصدَّرةً (حذفُها قرارٌ بشريّ)');
    });

    test('والمضادّة: التعليقُ المُزال ما زال مذكوراً في الخامّ', () {
      // الفحوصُ أعلاه تَقرأُ المُجرَّدَ من التعليقات. وهذا يُثبِتُ أنّ
      // التجريدَ لم يُفرِغ الملفَّ من معناه.
      expect(js.contains('مسار إداري'), isTrue,
          reason: 'شرحُ الحجّةِ القديمةِ زال، فلا يُعرَفُ لِمَ تغيّرَ السلوك');
    });
  });

  // ── الشاشةُ تَقرأُ الوسم — وكان بلا قارئٍ في أيِّ سطح ──
  group('شاشةُ العقودِ الإداريّة', () {
    final screen = File('lib/screens/admin/admin_contracts_screen.dart')
        .readAsStringSync();

    test('تُنادي القاعدةَ ولا تُعيدُ تعدادَ الحالاتِ بجوارِها', () {
      expect(screen.contains('contractHealthOf('), isTrue);
      expect(screen.contains('kContractHealthTitles'), isTrue);
      expect(screen.contains("data['plan_validation_failed'] =="), isFalse,
          reason: 'نسخةٌ إنلاين من القاعدة — تَنحرِف');
    });

    test('وتَعرضُها في الصفِّ **وفي** التفاصيل — فالدفعةُ تُسمّي معرّفاً', () {
      expect(screen.contains('_contractHealthChip(data)'), isTrue,
          reason: 'بلا شارةِ صفٍّ يَبحثُ الأدمنُ بعينِه في قائمةٍ متشابهة');
      expect(screen.contains('_contractHealthBanner(data)'), isTrue);
    });

    test('والسببُ الخادميُّ يُعرَض', () {
      expect(screen.contains('contractHealthReason('), isTrue,
          reason: 'السببُ مكتوبٌ على المستندِ ولا يُقرأ — وهو عينُ العطل');
    });
  });

  group('وجدولُ الأسبابِ واحدٌ للغتَين', () {
    test('contractHealthReason تُوافقُ مرآةَ اللوحةِ حالةً بحالة', () {
      // **ثغرةٌ في الحارسِ سدَّها الاشتقاقُ (2026-10-07):** اللوحةُ تَستورِدُ
      // `contractHealthReason` وتَعرضُه سبباً لفشلِ التفعيل، ولم يُشغّلْه فحصٌ
      // على جهتِها — فانحرافُ الترتيبِ أو التهذيبِ كان يَمُرُّ صامتاً.
      // والقاعدتانِ متّفقتانِ اليومَ، فهذا سدُّ ثغرةٍ لا إصلاحُ عطل.
      final cases = _sharedReasons();
      expect(cases.length, greaterThanOrEqualTo(8),
          reason: 'انهارَ قراءةُ جدولِ الأسباب');
      // أصنافٌ مُسمّاةٌ لا حدٌّ عدديٌّ وحدَه.
      expect(cases.any((c) => (c[0] as Map).isEmpty && c[1] == null), isTrue);
      expect(cases.any((c) => (c[0] as Map).length >= 3), isTrue,
          reason: 'الأولويّةُ بين الثلاثةِ غيرُ مُختبَرة');
      expect(cases.any((c) => c[1] == null && (c[0] as Map).isNotEmpty), isTrue,
          reason: 'الفراغُ ليس سبباً — غيرُ مُختبَر');
      for (final c in cases) {
        final doc = (c[0] as Map).cast<String, dynamic>();
        expect(contractHealthReason(doc), c[1],
            reason: 'القاعدتانِ افترقتا على $doc');
      }
    });
  });

  group('استرداد عقدٍ مدفوعٍ لم يُفعَّل', () {
    Map<String, dynamic> c(Map<String, dynamic> extra) => {
          'status': 'approved_waiting_payment',
          'is_paid': true,
          'plan_validation_failed': true,
          ...extra,
        };
    test('بطاقة ⇒ ميسر، وتقسيط ⇒ تمارا، ومحفظة ⇒ رسالة', () {
      expect(contractRefundRoute(c({'moyasar_payment_id': 'pay_1'})),
          ContractRefundRoute.moyasar);
      expect(contractRefundRoute(c({'payment_method': 'tamara'})),
          ContractRefundRoute.tamara);
      expect(contractRefundRoute(c({'payment_method': 'wallet'})),
          ContractRefundRoute.wallet);
      // الوسيلةُ المكتوبةُ تَغلِبُ معرّفاً باقياً من محاولةٍ سابقة.
      expect(
          contractRefundRoute(c({
            'payment_method': 'wallet',
            'moyasar_payment_id': 'pay_failed',
          })),
          ContractRefundRoute.wallet);
      expect(
          contractRefundRoute(c({
            'payment_method': 'card',
            'tamara_order_id': 'tm_old',
            'moyasar_payment_id': 'pay_1',
          })),
          ContractRefundRoute.moyasar);
    });
    test('لا زرَّ لعقدٍ غيرِ مدفوعٍ أو مُفعَّلٍ أو مُستردٍّ سلفاً', () {
      final m = {'moyasar_payment_id': 'pay_1'};
      expect(contractRefundRoute(c({...m, 'is_paid': false})),
          ContractRefundRoute.none);
      expect(contractRefundRoute(c({...m, 'status': 'active'})),
          ContractRefundRoute.none);
      expect(contractRefundRoute(c({...m, 'refund_claimed': true})),
          ContractRefundRoute.none);
      expect(contractRefundRoute(c({...m, 'payment_status': 'refunded'})),
          ContractRefundRoute.none);
    });
    test('الخادمُ يُغلِقُ العقدَ بعد استردادِه في المسارَين', () {
      final String idx = File('functions/index.js').readAsStringSync();
      expect(RegExp(r'\.\.\._contractRefundClose\(').allMatches(idx).length, 2);
      expect(
          idx,
          contains(
              'status: "rejected", rejected_reason: "refunded_before_activation"'));
      // دفعةُ ميسر مربوطةٌ بالعقدِ قبلَ أيِّ ردٍّ أو إغلاق: بلاهُ يُرَدُّ مالُ
      // دفعةٍ ويُغلَقُ عقدٌ لا تَخصُّه.
      final int fi = idx.indexOf('exports.moyasarRefundPayment');
      final int bind =
          idx.indexOf('existing.data.moyasar_payment_id !== paymentId', fi);
      expect(bind, greaterThan(fi));
      expect(bind, lessThan(idx.indexOf('moyasar.refund(', fi)));
      // والعقدُ يُطابَقُ مع ميسر نفسِها لا مع حقلٍ قد يكونُ زُرِع.
      final int vi = idx.indexOf('moyasar.getPayment(secret, paymentId)', fi);
      expect(vi, greaterThan(fi));
      expect(vi, lessThan(idx.indexOf('moyasar.refund(', fi)));
      expect(idx.indexOf('String(md.order_id) === String(orderId)', fi),
          greaterThan(vi));
      // والعقدُ المُغلَقُ لا يُدفَعُ ثانيةً من المحفظة.
      final int wi = idx.indexOf('exports.payContractWithWallet');
      final int gate = idx.indexOf('هذا العقد مغلق ولا يمكن دفعه', wi);
      expect(gate, greaterThan(wi));
      expect(gate, lessThan(idx.indexOf('t.update(contractRef', wi)));
      // وحدثُ تمارا المتأخّرُ لا يُعيدُ مستنداً مُستردّاً مدفوعاً.
      final int ti = idx.indexOf('async function _tamaraFlipPaid');
      final int tg = idx.indexOf('data.payment_status === "refunded"', ti);
      expect(tg, greaterThan(ti));
      expect(tg, lessThan(idx.indexOf('payment_status: "paid"', ti)));
    });
  });

  group('مرآةُ مسارِ الاستردادِ في لوحةِ الويب', () {
    test('جدولُ الحالاتِ المشترَكُ يُعطي الجوابَ نفسَه في الدارت', () {
      final String ts = File(
              'admin_panel/src/utils/contractHealth.test.ts')
          .readAsStringSync();
      const String begin = '// ── CONTRACT_REFUND_ROUTE_CASES_BEGIN ──';
      const String end = '// ── CONTRACT_REFUND_ROUTE_CASES_END ──';
      final int b = ts.indexOf(begin);
      final int e = ts.indexOf(end);
      expect(b, greaterThan(-1), reason: 'علامةُ بدايةِ الجدولِ زالت');
      expect(e, greaterThan(b), reason: 'علامةُ نهايةِ الجدولِ زالت');
      final String block = ts.substring(b + begin.length, e);
      // من آخرِ `]` إلى الوراءِ بموازنةِ الأقواس — `indexOf('[')` يَلتقطُ
      // قوسَ تعليقِ النوعِ `Row[]` لا بدايةَ المصفوفة.
      final int close = block.lastIndexOf(']');
      int depth = 0, open = -1;
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
      expect(open, greaterThan(-1));
      final String json = block
          .substring(open, close + 1)
          .replaceAllMapped(RegExp(r',(\s*[\]}])'), (m) => m.group(1)!);
      final List<dynamic> rows = jsonDecode(json) as List<dynamic>;
      expect(rows.length, greaterThanOrEqualTo(15),
          reason: 'الجدولُ انحلَّ — فالمقارنةُ بلا موضوع');
      for (final r in rows) {
        final Map<String, dynamic> doc =
            Map<String, dynamic>.from((r as List)[0] as Map);
        expect(contractRefundRoute(doc).name, r[1],
            reason: 'افترقت اللوحةُ عن التطبيقِ على: ${jsonEncode(doc)}');
      }
    });

    test('صفحةُ العقودِ في اللوحةِ تُنادي القاعدةَ والنداءَين بالوسائطِ نفسِها', () {
      final String p = File('admin_panel/src/pages/Contracts.tsx')
          .readAsStringSync();
      expect(p, contains('contractRefundRoute('),
          reason: 'الزرُّ يُقرّرُ ظهورَه بنفسِه لا بالقاعدة');
      expect(p, contains("'tamaraRefundPayment'"));
      expect(p, contains("'moyasarRefundPayment'"));
      expect(RegExp(r'paymentId:\s*String\(contract\.moyasar_payment_id').hasMatch(p),
          isTrue, reason: 'ميسر يَلزمُه معرّفُ الدفعةِ المخزَّنُ على العقد');
      expect(RegExp(r'orderId:\s*contract\.id').hasMatch(p), isTrue);
      expect(RegExp(r'order_id:\s*contract\.id').hasMatch(p), isTrue);
    });
  });
}
