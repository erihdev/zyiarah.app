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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_health.dart';

String _stripJs(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final js = File('functions/index.js').readAsStringSync();
  final jsCode = _stripJs(js);

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
      final i = jsCode.indexOf('async function _activateContractNow');
      expect(i, greaterThan(0), reason: 'الدالّةُ المشتركةُ اختفت');
      final seg = jsCode.substring(i, i + 5000);
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
      final i = jsCode.indexOf('async function _activateContractNow');
      final seg = jsCode.substring(i, i + 6000);
      expect(seg.contains('contract_visits_pending: true'), isTrue,
          reason: 'الفشلُ لا يَكتبُ علَمَه — فلا تَراه المكنسة');
      expect(seg.contains('contract_visits_alerted'), isTrue,
          reason: 'التصعيدُ بلا علَمٍ خاصٍّ يُكرَّرُ كلَّ دورة');
      // والنجاحُ يَمحو العلَمَ — بلاه يَبقى العقدُ في مجموعةِ الإعادةِ للأبد.
      expect(seg.contains('contract_visits_pending: FieldValue.delete()'),
          isTrue,
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
          RegExp(r'async function _activateContractNow').allMatches(jsCode).length,
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
      final callers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => RegExp(r"httpsCallable\(\s*'generateSubscriptionVisits'")
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
    final screen =
        File('lib/screens/admin/admin_contracts_screen.dart').readAsStringSync();

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
}
