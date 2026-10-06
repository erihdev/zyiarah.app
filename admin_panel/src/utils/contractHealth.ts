// مرآةُ `lib/utils/contract_health.dart` — صحّةُ تفعيلِ العقدِ، وبوّابةُ
// زرِّ الاعتماد.
//
// **العطلُ المُصلَح (2026-10-05):** هذه الصفحةُ كانت تَعرضُ `contract.status`
// وحدَه، فعقدٌ **مدفوعٌ فشلَ تفعيلُه** (`is_paid: true` و`status: 'pending'`)
// يُقرأُ «قيد المراجعة» كأيِّ عقدٍ معلَّقٍ غيرِ مدفوع — بلا وسمٍ ولا سبب،
// مع أنّ الخادمَ كتبَ السببَ نصّاً في `*_error`. وشاشةُ Flutter الإداريّةُ
// تَعرضُ رقاقةً وبطاقةً لذلك منذ إصلاحِ وسمِ التفعيل؛ هذه الصفحةُ كانت
// الشاذّة — «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد».
//
// والأسوأُ أنّ الصفحةَ تَحملُ **فعلاً** على تلك الحالةِ بعينِها: زرُّ «اعتماد
// الباقة» مشروطٌ بـ`status === 'pending'` وحدَها، فضغطُه على عقدٍ مدفوعٍ
// يَكتبُ `approved_waiting_payment` ويَدفعُ للعميلةِ «يرجى إتمام الدفع» —
// وقد دفعت — **ويُخرِجُه من نافذةِ الإنقاذ** التي تَستعلمُ
// `is_paid == true && status == "pending"`، فلا مكنسةَ تَبلغُه ولا مُشغّلَ
// يُعادُ إطلاقُه. التفصيلُ في رأسِ الملفِّ الدارتيّ.

export type ContractHealth =
  | 'ok'
  | 'planMismatch'
  | 'activationFailed'
  | 'activationStuck'
  | 'visitsMissing';

export interface ContractDoc {
  is_paid?: boolean;
  status?: string;
  plan_validation_failed?: boolean;
  plan_validation_error?: string;
  contract_visits_pending?: boolean;
  contract_visits_error?: string;
  contract_activation_failed?: boolean;
  contract_activation_error?: string;
}

/** نصُّ البطاقةِ لكلِّ حالة — حرفيّاً كما في `kContractHealthTitles`. */
export const CONTRACT_HEALTH_TITLES: Record<ContractHealth, string> = {
  ok: '',
  planMismatch: 'مدفوع ولم يُفعَّل: السعر أو عدد الزيارات لا يطابق الباقة',
  activationFailed:
    'مدفوع وفشل تفعيله — لا زيارات ولا بطاقة اشتراك عند العميلة. تُعاد المحاولة دوريّاً',
  activationStuck:
    'مدفوع وما زال معلَّقاً — لم يُفعَّل بعد. تُعاد المحاولة دوريّاً',
  visitsMissing:
    'فُعِّل ومُنِحت زياراته، لكن مواعيد الزيارات لم تُولَّد — رصيد بلا مواعيد',
};

/** هل تَحتاجُ الحالةُ قراراً بشريّاً (لا تُصلِحُها المكنسة). */
export function contractNeedsHuman(h: ContractHealth): boolean {
  return h === 'planMismatch';
}

/**
 * الأولويّةُ مقصودةٌ ومطابقةٌ للدارت: `planMismatch` أوّلاً لأنّه **قرارٌ**
 * لا عطلٌ عابر — فإظهارُ «تُعاد المحاولة» فوقَه كذب.
 */
export function contractHealthOf(c: ContractDoc | null | undefined): ContractHealth {
  if (!c) return 'ok';
  const paid = c.is_paid === true;
  const status = c.status ?? 'pending';
  if (c.plan_validation_failed === true) return 'planMismatch';
  if (c.contract_visits_pending === true) return 'visitsMissing';
  if (c.contract_activation_failed === true) return 'activationFailed';
  // المتناقضةُ: مدفوعٌ وما زال `pending`. لا تُقاسُ بـ`visits_generated`
  // لأنّ عقداً قديماً سابقاً للراية لا يَحملُها فيُقرأُ عاطلاً وهو سليم.
  if (paid && status === 'pending') return 'activationStuck';
  return 'ok';
}

/** السببُ الذي كتبَه الخادم، إن وُجد. */
export function contractHealthReason(c: ContractDoc | null | undefined): string | null {
  if (!c) return null;
  for (const k of [
    'plan_validation_error',
    'contract_visits_error',
    'contract_activation_error',
  ] as const) {
    const v = c[k];
    if (typeof v === 'string' && v.trim() !== '') return v.trim();
  }
  return null;
}

/** هل يُعرَضُ زرُّ الاعتماد؟ — الاعتمادُ لِما لم يُدفَع بعد. */
export function contractApproveAllowed(c: ContractDoc | null | undefined): boolean {
  const status = c?.status ?? 'pending';
  return status === 'pending' && c?.is_paid !== true;
}

/** سببُ حجبِ الزرِّ، أو `null` حين لا يَكونُ موضعُه أصلاً. */
export function contractApproveBlockedReason(
  c: ContractDoc | null | undefined,
): string | null {
  const status = c?.status ?? 'pending';
  if (status !== 'pending') return null;
  if (c?.is_paid === true) {
    return 'مدفوع سلفاً — الاعتماد خطوة قبل الدفع. اعتماده الآن يطالب ' +
      'العميلة بالدفع مرة أخرى ويُخرجه من إعادة المحاولة التلقائية.';
  }
  return null;
}
