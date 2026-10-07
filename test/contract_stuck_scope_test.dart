// حارس دائم: **«مدفوعٌ ولم يُفعَّل» حالتان لا واحدة — والمكنسةُ والبطاقةُ
// والزرُّ يَقرأونها جميعاً.**
//
// `activateContractOnPaid` يُفعّلُ العقدَ عند قلبِ `is_paid`؛ وفشلُه يَترُكُ
// `status` **كما هو**، لأنّ `_activateContractNow` لا يَكتبُ `active` إلّا
// عند النجاح، و`payContractWithWallet` لا يَمَسُّ `status` إطلاقاً.
//
// فالحالةُ التي يَتركُها المسارُ الطبيعيُّ هي **`approved_waiting_payment`
// + `is_paid: true`** — لأنّ الدفعَ يَقعُ من تلك الحالةِ بعينِها (زرُّ
// «دفع وتفعيل العقد» مشروطٌ بها). وكانت مكنسةُ الإنقاذِ وبطاقةُ الصحّةِ
// تَستعلمانِ **`pending` وحدَها**، وهي لا تَقعُ إلّا متى دُفِعَ قبلَ
// الاعتماد (`payContractWithWallet` بلا شرطِ حالة) — أي الطرَفُ النادر.
// فالشبكةُ كانت تُمسِكُ النادرَ وتُفلِتُ الغالب.
//
// **وأثقلُ من ذلك ما تَراه العميلة:** بطاقتُها كانت تَقولُ «بانتظار الدفع»
// وتَعرضُ زرَّ «دفع وتفعيل العقد» على عقدٍ **دَفعَته**. والمحفظةُ تَرُدُّ
// `alreadyPaid` فلا تَخصِمُ مرّتَين — لكنّ الزرَّ يَقودُ إلى شاشةِ الدفع،
// و**البطاقةُ تُخصَمُ عند بوّابةِ ميسر قبلَ أيِّ فحصٍ خادميّ**. فعقدٌ فشلَ
// تفعيلُه (ولا مكنسةَ تَراه) يَدعوها إلى دفعةٍ ثانيةٍ حقيقيّة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/utils/contract_health.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('القاعدةُ: مدفوعٌ وفي حالةٍ قبلَ التفعيل ⇒ عالِق', () {
    for (final s in kContractPreActiveStatuses) {
      expect(contractHealthOf({'is_paid': true, 'status': s}),
          ContractHealth.activationStuck,
          reason: 'عقدٌ مدفوعٌ بحالة «$s» لا يُقرأُ عالقاً');
    }
    // والمُفعَّلُ سليم، وغيرُ المدفوعِ سليمٌ مهما كانت حالتُه.
    expect(contractHealthOf({'is_paid': true, 'status': 'active'}),
        ContractHealth.ok);
    for (final s in kContractPreActiveStatuses) {
      expect(contractHealthOf({'is_paid': false, 'status': s}),
          ContractHealth.ok);
    }
    // والقرارُ البشريُّ يَغلِبُ: عقدٌ رُفِضَ تفعيلُه لتباينِ الباقةِ لا
    // تُعادُ محاولتُه، فلا يُقالُ فوقَه «تُعاد المحاولة».
    expect(
        contractHealthOf({
          'is_paid': true,
          'status': 'approved_waiting_payment',
          'plan_validation_failed': true,
        }),
        ContractHealth.planMismatch);
  });

  test('ومجموعةُ المكنسةِ الخادميّةِ هي هذه المجموعةُ بعينِها', () {
    // **الاستعلامُ داخلَ المكنسةِ بعينِها**: `db.collection("contracts")`
    // يَرِدُ مراراً في الملفّ، فأوّلُ ورودٍ ليس هذا — أنقُصُ من ذلك أنّ أوّلَ
    // صياغةٍ أخذَته فسقطَ الفحصُ على استعلامٍ آخر. فالنطاقُ من تصديرِ
    // `opsHealthSweep` إلى التصديرِ الذي يَليه.
    final idx = _read('functions/index.js');
    final sweepAt = idx.indexOf('exports.opsHealthSweep');
    expect(sweepAt, greaterThan(-1), reason: 'المكنسةُ اختفت');
    final sweep = idx.substring(
        sweepAt, idx.indexOf('\nexports.', sweepAt + 10));
    final i = sweep.indexOf('db.collection("contracts")');
    expect(i, greaterThan(-1), reason: 'استعلامُ إنقاذِ العقودِ اختفى');
    final q = sweep.substring(i, sweep.indexOf('.get()', i) + 6);
    expect(q.contains('.where("is_paid", "==", true)'), isTrue,
        reason: 'المكنسةُ لم تَعُدْ تَشترطُ الدفع — تَغرقُ في كلِّ عقدٍ معلَّق');
    final inSet = RegExp(r'\.where\("status", "in", \[([^\]]*)\]\)')
        .firstMatch(q);
    expect(inSet, isNotNull,
        reason: 'المكنسةُ عادت إلى حالةٍ واحدة — فالشكلُ الغالبُ يُفلِتُ');
    final server = RegExp(r'"([a-z_]+)"')
        .allMatches(inSet!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();
    expect(server, kContractPreActiveStatuses,
        reason: 'افترقت مجموعةُ المكنسةِ عن مجموعةِ البطاقة: حالةٌ عند أحدِهما '
            'دونَ الآخرِ تَعني عقداً مدفوعاً لا تَراه البطاقةُ أو لا تُعيدُ '
            'المكنسةُ محاولتَه');
  });

  test('والتعليلُ مأخوذٌ من الشفرة: الدفعُ لا يَمَسُّ الحالة', () {
    final idx = _read('functions/index.js');
    final i = idx.indexOf('exports.payContractWithWallet');
    final body = idx.substring(i, idx.indexOf('\nexports.', i + 10));
    expect(body.contains('is_paid: true'), isTrue);
    expect(RegExp(r'status:\s*"').hasMatch(body), isFalse,
        reason: 'صارَ الدفعُ يَكتبُ الحالة — فالتعليلُ أعلاه يُراجَعُ، وقد '
            'تَصيرُ الحالةُ المَحروسةُ غيرَها');
    // والتفعيلُ لا يَكتبُ `active` إلّا عند النجاح.
    expect(idx.contains('status: "active"'), isTrue);
  });

  test('وبطاقةُ العميلةِ لا تَقولُ «بانتظار الدفع» لمن دَفعت', () {
    final s = _read('lib/screens/contracts_list_screen.dart');
    // **والشرطُ هو القاعدةُ لا حالةٌ واحدة (2026-10-07).** كان الفرعُ
    // مشروطاً بـ`approved_waiting_payment` وحدَها، فعقدٌ دُفِعَ وهو
    // `pending` — أو وُسِمَ `plan_validation_failed` / `contract_activation_failed`
    // — كان يُقرأُ «بانتظار الاعتماد» فلا تَعرفُ أنّ مالَها وصل. والنصُّ
    // في الوحدةِ لا في الشاشة: نسخةٌ ثانيةٌ تَنحرِفُ عن بطاقةِ الأدمن.
    expect(s.contains('kContractPaidNotActiveClientText'), isTrue,
        reason: 'البطاقةُ تَكتبُ النصَّ بنفسِها — أو عادَ الفرعُ القديم');
    expect(s.contains('kContractPaidNotActive.contains(contractHealthOf(data))'),
        isTrue,
        reason: 'البطاقةُ لا تَسألُ القاعدةَ — فحالةٌ من الثلاثِ تُفلِت');
    expect(kContractPaidNotActiveClientText, contains('مدفوع'),
        reason: 'نصُّ العميلةِ لا يَقولُ إنّ المالَ قُبِض');
    // المجموعةُ ثلاثٌ بعينِها، و`visitsMissing` خارجَها بقصد: العقدُ
    // مُفعَّلٌ هناك والرصيدُ عندها.
    expect(kContractPaidNotActive, {
      ContractHealth.planMismatch,
      ContractHealth.activationFailed,
      ContractHealth.activationStuck,
    });
    expect(kContractPaidNotActive.contains(ContractHealth.visitsMissing),
        isFalse,
        reason: 'عقدٌ مُفعَّلٌ يُقرأُ «جارٍ التفعيل» — دعوى معاكسة');
    // والزرُّ مشروطٌ بأنّها لم تَدفعْ — وإلّا قادَها إلى خصمٍ ثانٍ بالبطاقة.
    expect(
        s.contains("status == 'approved_waiting_payment' &&\n"
            "                          data['is_paid'] != true"),
        isTrue,
        reason: 'زرُّ «دفع وتفعيل العقد» بلا شرطِ `is_paid` — '
            'عقدٌ فشلَ تفعيلُه يَدعو العميلةَ إلى دفعةٍ ثانية');
  });

  test('والمحفظةُ وحدَها عديمةُ الأثرِ التكراريّ — لا البطاقة', () {
    // سببُ أنّ الزرَّ خطرٌ: مسارُ المحفظةِ يَرُدُّ `alreadyPaid`، أمّا
    // البطاقةُ فتُخصَمُ عند البوّابةِ قبلَ أيِّ فحص. فلو زالَ هذا الحارسُ
    // الخادميُّ صارَ الخصمُ المزدوجُ ممكناً في المسارَين.
    final idx = _read('functions/index.js');
    final i = idx.indexOf('exports.payContractWithWallet');
    final body = idx.substring(i, idx.indexOf('\nexports.', i + 10));
    expect(body.contains('alreadyPaid'), isTrue,
        reason: 'زالَ حارسُ الدفعِ المكرَّرِ من مسارِ المحفظة');
  });
}
