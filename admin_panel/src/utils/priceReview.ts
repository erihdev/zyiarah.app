// مرآةُ `lib/utils/price_review.dart` — قراءةُ وسمِ مراجعةِ السعرِ واعتمادُه.
//
// تحقّقُ السعرِ الخادميُّ سياستُه «وسمٌ وتنبيهٌ لا رفض»، فمُخرَجُه أعلامٌ على
// المستندِ ودفعةٌ إداريّةٌ بأكوادِ الطلبات — **ولم يكن لها قارئٌ في أيِّ
// واجهة**: صفرُ ورودٍ في `lib/` وصفرُ ورودٍ في `admin_panel/src/`. فالإدارةُ
// تَفتحُ الطلبَ المُبلَّغَ عنه فتَراه طلباً عاديّاً تماماً، ولا سبيلَ إلى
// القولِ «راجعتُه واعتمدتُه» — فنافذةُ `opsHealthSweep` لا تُصرَّفُ أبداً.
//
// وهذه نصفُ الإصلاح: الإدارةُ تَعملُ من سطحَين (تطبيقُ الأدمن واللوحة)،
// فقارئٌ في أحدِهما وحدَه يَترُكُ الطلبَ عاديَّ المنظرِ لمن يَعملُ من الآخر —
// وهو شكلُ «حقلُ قرارٍ يَعرفُه محرّرٌ واحد» الذي تَكرّرَ في هذا المستودعِ
// أربعَ مرّاتٍ من قبل.
//
// **ودقّةٌ تَخصُّ الرقمَ المعروض:** مسارُ ميسر يَكتبُ `price_expected` قبلَ
// الخصمِ الموثوقِ و`price_expected_net` بعدَه، والمقارنةُ التي أنتجت الوسمَ
// كانت على الصافي. فعرضُ الأوّلِ وحدَه يُضخّمُ الفارقَ بقيمةِ الكوبون،
// فتَستردُّ الإدارةُ فرقاً لا تَملكُه.

export type PriceReviewKind = 'none' | 'underpaid' | 'unverifiable';

/** الحقلانِ اللذانِ تَستعلمُهما المكنسة — وإبطالُهما هو تصريفُ النافذة. */
export const PRICE_REVIEW_QUERY_FLAGS: string[] = [
  'price_mismatch',
  'price_unverifiable',
];

/** حقولُ الشاهد: تَبقى بعد الاعتماد. */
export const PRICE_REVIEW_EVIDENCE_FIELDS: string[] = [
  'price_paid',
  'price_expected',
  'price_expected_net',
  'price_shadow_ratio',
  'coupon_rejected_reason',
];

/** أسبابُ رفضِ الكوبونِ كما يُعيدُها `functions/coupons.js`. */
export const COUPON_REJECT_REASONS: Record<string, string> = {
  not_found: 'كود الكوبون غير موجود',
  inactive: 'الكوبون معطَّل',
  expired: 'الكوبون منتهي الصلاحية',
  exhausted: 'الكوبون استُنفد عدد استخداماته',
  other_user: 'كوبون مخصَّص لعميلة أخرى',
  other_zone: 'الكوبون لا يشمل منطقة الطلب',
};

export interface PriceReview {
  kind: PriceReviewKind;
  paid: number | null;
  expected: number | null;
  ratio: number | null;
  couponRejectedReason: string | null;
  reviewedAtPresent: boolean;
  /** خصمٌ بلغَ السعرَ كاملاً مع دفعٍ موجب — لا نسبةَ له. */
  suspiciousZero: boolean;
  /** الفارقُ القابلُ للاسترداد، أو `null` متى تعذّر حسابُه. */
  shortfall: number | null;
  /** يَشملُ المُعتمَدَ سابقاً: وإلّا اختفى القرارُ وصاحبُه لحظةَ اتّخاذِه. */
  needsCard: boolean;
  /** وسمٌ قائمٌ يَنتظرُ قراراً. */
  actionable: boolean;
}

const num = (v: unknown): number | null => {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
};

export function priceReviewOf(order: Record<string, unknown>): PriceReview {
  const mismatch = order.price_mismatch === true;
  const unverifiable = order.price_unverifiable === true;
  const rawReason = order.coupon_rejected_reason;
  const couponRejectedReason =
    typeof rawReason === 'string' && rawReason.trim() !== '' ? rawReason.trim() : null;

  const kind: PriceReviewKind = mismatch
    ? 'underpaid'
    : unverifiable
      ? 'unverifiable'
      : 'none';

  const paid = num(order.price_paid);
  // الصافي أوّلاً — انظر رأسَ الملف.
  const expected = num(order.price_expected_net) ?? num(order.price_expected);
  const reviewedAtPresent =
    order.price_reviewed_at !== null && order.price_reviewed_at !== undefined;

  const suspiciousZero =
    kind === 'underpaid' && expected === 0 && (paid ?? 0) > 0;
  const shortfall =
    paid !== null && expected !== null && expected > 0 && expected - paid > 0
      ? expected - paid
      : null;

  return {
    kind,
    paid,
    expected,
    ratio: num(order.price_shadow_ratio),
    couponRejectedReason,
    reviewedAtPresent,
    suspiciousZero,
    shortfall,
    needsCard: kind !== 'none' || couponRejectedReason !== null || reviewedAtPresent,
    actionable: kind !== 'none',
  };
}

/**
 * حِمْلُ «اعتماد المبلغ»: يُبطِلُ علمَي الاستعلامِ ويُوقّعُ القرار.
 * الطابعُ الزمنيُّ يُضيفُه موضعُ النداءِ (`serverTimestamp()`) كي يَبقى هذا
 * الملفُّ نقيّاً بلا Firebase.
 */
export function priceReviewApprovalPayload(by: string): Record<string, unknown> {
  const payload: Record<string, unknown> = {};
  for (const f of PRICE_REVIEW_QUERY_FLAGS) payload[f] = false;
  payload.price_review_decision = 'approved';
  payload.price_reviewed_by = by;
  return payload;
}

/** سطرٌ واحدٌ يَصلحُ للشارةِ في جدولٍ. */
export function priceReviewLine(r: PriceReview): string {
  if (r.kind === 'underpaid') {
    if (r.suspiciousZero) return 'الخصم بلغ السعر كاملاً ومع ذلك دُفع مبلغ';
    return r.paid !== null && r.expected !== null
      ? `دُفع ${r.paid.toFixed(2)} مقابل ${r.expected.toFixed(2)} ر.س`
      : 'المبلغ أدنى من المتوقَّع';
  }
  if (r.kind === 'unverifiable') return 'تعذّر التحقّق من السعر خادميّاً';
  return 'اعتمدته مراجعة سابقة';
}
