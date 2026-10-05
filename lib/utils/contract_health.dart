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
  // المتناقضةُ: مدفوعٌ وما زال `pending`. **لا تُقاسُ بـ`visits_generated`**
  // لأنّ عقداً قديماً سابقاً للراية لا يَحملُها، فيُقرأُ عاطلاً وهو سليم.
  if (paid && status == 'pending') return ContractHealth.activationStuck;
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
