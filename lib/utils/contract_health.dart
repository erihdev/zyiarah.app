/// **عقدٌ مدفوعٌ لم يُفعَّل، ووسمٌ خادميٌّ بلا قارئ (2026-10-05).**
///
/// `activateContractOnPaid` يُفعّلُ العقدَ عند قلبِ `is_paid`. وله ثلاثُ
/// نهاياتٍ غيرِ ناجحةٍ تُكتَبُ على المستند، **ولم يَقرأْها أيُّ سطح**: صفرُ
/// ورودٍ لـ`plan_validation_failed` في `lib/` و`admin_panel/src/`، وصفرُ
/// ورودٍ لـ`visits_generated`. فالأدمنُ يَتلقّى دفعةً نصُّها «لم يُفعَّل —
/// راجعه يدوياً»، يَفتحُ شاشةَ العقودِ فيَرى عقداً **يُشبهُ أيَّ عقدٍ معلَّقٍ
/// غيرِ مدفوع**: لا وسمَ، ولا سبباً، ولا إشارةَ إلى أنّه مدفوعٌ أصلاً — مع
/// أنّ `plan_validation_error` يَحملُ السببَ نصّاً. وهي قصّةُ
/// `price_mismatch` بحرفِها، مجموعةً واحدةً إلى الجانب.
///
/// ولذلك تَسكنُ القاعدةُ هنا نقيّةً: الحالةُ تُشتَقُّ من المستندِ وحدَه
/// فتُختبَرُ بلا Firebase.
library;

/// حالةُ صحّةِ العقدِ من منظورِ التفعيل.
enum ContractHealth {
  /// لا شيء يَستحقُّ انتباهَ الأدمن.
  ok,

  /// مدفوعٌ ولم يُفعَّل لأنّ سعرَه/زياراته لا تُطابقُ الباقة — عدمُ تفعيلٍ
  /// **مقصودٌ** (Tier B للعقود). لا تُعادُ محاولتُه، والقرارُ بشريّ.
  planMismatch,

  /// مدفوعٌ وفشلَت معامَلةُ التفعيل — لا زياراتٍ ولا بطاقةَ اشتراكٍ عندها.
  /// تُعادُ المحاولةُ دوريّاً.
  activationFailed,

  /// مدفوعٌ وما زال `pending` بلا علَمٍ يُفسّر — الحالةُ المتناقضةُ التي
  /// تَستعلمُها المكنسة. (قد يَفتحَه الأدمنُ قبل أن تَدورَ.)
  activationStuck,

  /// فُعِّلَ ومُنِحَت زياراتُه، لكنّ توليدَ الزياراتِ فشلَ: رصيدٌ بلا مواعيد.
  visitsMissing,
}

/// حالاتُ العقدِ **قبلَ التفعيل** — أي ما يَعني وجودُها مع `is_paid: true`
/// أنّ المالَ قُبِضَ والعقدُ لم يُفعَّلْ بعد.
///
/// مرآةٌ لِما تَستعلمُه مكنسةُ الإنقاذِ في `functions/index.js`
/// (`status in [...]` مع `is_paid == true`)، ويَشدُّ التطابقَ
/// `test/contract_stuck_scope_test.dart`: مجموعتانِ تَفترقانِ تَعنيان عقداً
/// مدفوعاً لا تَراه البطاقةُ ولا تُعيدُ المكنسةُ محاولتَه.
const Set<String> kContractPreActiveStatuses = {
  'pending',
  'approved_waiting_payment',
};

/// نصُّ البطاقةِ لكلِّ حالة — موجَّهٌ للأدمنِ (المالكُ يَقرأُ هذه الشاشة).
const Map<ContractHealth, String> kContractHealthTitles =
    <ContractHealth, String>{
  ContractHealth.planMismatch: 'مدفوع ولم يُفعَّل: السعر أو عدد الزيارات '
      'لا يطابق الباقة',
  ContractHealth.activationFailed: 'مدفوع وفشل تفعيله — لا زيارات ولا بطاقة '
      'اشتراك عند العميلة. تُعاد المحاولة دوريّاً',
  ContractHealth.activationStuck: 'مدفوع وما زال معلَّقاً — لم يُفعَّل بعد. '
      'تُعاد المحاولة دوريّاً',
  ContractHealth.visitsMissing: 'فُعِّل ومُنِحت زياراته، لكن مواعيد الزيارات '
      'لم تُولَّد — رصيد بلا مواعيد',
};

/// هل تَحتاجُ الحالةُ قراراً بشريّاً (لا تُصلِحُها المكنسة).
bool contractNeedsHuman(ContractHealth h) => h == ContractHealth.planMismatch;

/// يَقرأُ حالةَ العقدِ من مستندِه.
///
/// الأولويّةُ مقصودةٌ: `planMismatch` أوّلاً لأنّه **قرارٌ** لا عطلٌ عابر —
/// عقدٌ يَحملُه لا تُعادُ محاولتُه، فإظهارُ «تُعاد المحاولة» فوقَه كذب.
ContractHealth contractHealthOf(Map<String, dynamic> c) {
  final bool paid = c['is_paid'] == true;
  final String status = (c['status'] as String?) ?? 'pending';
  if (c['plan_validation_failed'] == true) return ContractHealth.planMismatch;
  if (c['contract_visits_pending'] == true) return ContractHealth.visitsMissing;
  if (c['contract_activation_failed'] == true) {
    return ContractHealth.activationFailed;
  }
  // المتناقضةُ: **مدفوعٌ ولم يُفعَّلْ بعد**. لا تُقاسُ بـ`visits_generated`
  // لأنّ عقداً قديماً سابقاً للراية لا يَحملُها، فيُقرأُ عاطلاً وهو سليم.
  //
  // **وكانت `status == 'pending'` وحدَها، وهي ليست الحالةَ التي يَترُكُها
  // المسارُ الطبيعيّ.** الدفعُ يَقعُ من `approved_waiting_payment` (زرُّ
  // «دفع وتفعيل العقد» مشروطٌ بها)، وكاتبُ الدفعِ لا يَمَسُّ `status`
  // إطلاقاً، و`_activateContractNow` لا يَكتبُ `active` إلّا عند النجاح —
  // فعقدٌ فشلَ تفعيلُه يَستقرُّ على **`approved_waiting_payment` +
  // `is_paid: true`**، وهي الحالةُ التي كانت تُفلِتُ من البطاقةِ ومن
  // مكنسةِ الإنقاذِ معاً. أمّا `pending` + مدفوع فتَقعُ متى دُفِعَ قبلَ
  // الاعتماد (`payContractWithWallet` بلا شرطِ حالة) — فهي الطرَفُ النادر،
  // وكانت وحدَها المَحروسة.
  if (paid && kContractPreActiveStatuses.contains(status)) {
    return ContractHealth.activationStuck;
  }
  return ContractHealth.ok;
}

/// السببُ الذي كتبَه الخادمُ، إن وُجد — يُعرَضُ تحت العنوان.
String? contractHealthReason(Map<String, dynamic> c) {
  for (final String k in const [
    'plan_validation_error',
    'contract_visits_error',
    'contract_activation_error',
  ]) {
    final Object? v = c[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// ─────────────────────────────────────────────────────────────────────────
/// **زرُّ «اعتماد العقد» كان يُخرِجُ عقداً مدفوعاً من إعادةِ المحاولةِ
/// التلقائيّة، ويُطالِبُ مَن دفعَ بالدفعِ مرّةً أخرى (2026-10-05).**
///
/// الاعتمادُ خطوةٌ **قبلَ** الدفع: `pending ⇒ approved_waiting_payment ⇒
/// دفعٌ ⇒ active`. وكان الزرُّ مشروطاً بـ`status == 'pending'` **وحدَها** في
/// السطحَين الإداريَّين، وعقدٌ فشلَ تفعيلُه يَسكنُ تلك الحالةَ بعينِها
/// (`is_paid: true` و`status: 'pending'` — وهي `activationStuck` أعلاه).
/// فالضغطةُ:
///
///  1. تَكتبُ `status: 'approved_waiting_payment'`؛
///  2. وتَدفعُ للعميلةِ «تم اعتماد عقد… **يرجى إتمام الدفع** لتفعيل الباقة»
///     — وقد دفعت؛
///  3. و`activateContractOnPaid` لا يُطلَقُ ثانيةً أبداً (شرطُه
///     `before.is_paid !== true` وهو `true` سلفاً).
///
/// فالعقدُ — وهو أكبرُ مبلغٍ في التطبيق — يَبقى مدفوعاً بلا زياراتٍ ولا
/// بطاقةٍ، والأدمنُ يَحسبُ أنّه اعتمدَه للتوّ.
///
/// **وتصحيحٌ لِما كُتبَ هنا (2026-10-07):** كان بنداً ثالثاً يَقولُ إنّ
/// الضغطةَ «تُخرِجُه من نافذةِ الإنقاذ» التي تَستعلمُ
/// `is_paid == true && status == "pending"`. وقد تبيّنَ أنّ
/// `approved_waiting_payment` + `is_paid: true` هي الحالةُ التي يَترُكُها
/// **المسارُ الطبيعيُّ** عند فشلِ التفعيل: الدفعُ يَقعُ من تلك الحالةِ
/// بعينِها، و`payContractWithWallet` لا يَمَسُّ `status`،
/// و`_activateContractNow` لا يَكتبُ `active` إلّا عند النجاح. فالنافذةُ
/// كانت تُفلِتُ **الشكلَ الغالبَ** لا الضغطةَ وحدَها — ووُسِّعت إلى
/// `kContractPreActiveStatuses` أدناه، فسقطَ ذلك البندُ وبَقيَ البندانِ
/// الآخرانِ وهما كافيان.
///
/// والإخفاءُ وحدَه لا يَكفي: صفٌّ بلا زرٍّ ولا سببٍ يُقرأُ عطلاً في الشاشة،
/// فـ`contractApproveBlockedReason` تَقولُ لماذا في موضعِه.
/// ─────────────────────────────────────────────────────────────────────────

/// هل يُعرَضُ زرُّ الاعتماد؟ — الاعتمادُ لِما لم يُدفَع بعد.
bool contractApproveAllowed(Map<String, dynamic> c) {
  final String status = (c['status'] as String?) ?? 'pending';
  return status == 'pending' && c['is_paid'] != true;
}

/// سببُ حجبِ الزرِّ، أو `null` حين لا يَكونُ موضعُه أصلاً (حالةٌ أخرى).
String? contractApproveBlockedReason(Map<String, dynamic> c) {
  final String status = (c['status'] as String?) ?? 'pending';
  if (status != 'pending') return null;
  if (c['is_paid'] == true) {
    return 'مدفوع سلفاً — الاعتماد خطوة قبل الدفع. اعتماده الآن يطالب '
        'العميلة بالدفع مرة أخرى ويُخرجه من إعادة المحاولة التلقائية.';
  }
  return null;
}
