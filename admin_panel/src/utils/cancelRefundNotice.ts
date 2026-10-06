// مرآةُ `lib/utils/cancel_refund_notice.dart` — «ماذا يَحدثُ لمالِ العميلةِ
// إن أُلغيَ الطلب؟»
//
// **العطلُ المُصلَح (2026-10-05):** حوارُ تأكيدِ الإلغاءِ هنا كان سطراً
// واحداً — «هل أنت متأكد من إلغاء الطلب #X؟» — ولا كلمةَ عن المبلغ، بينما
// النتيجةُ الخادميّةُ **ثلاثٌ** مختلفةٌ اختلافاً جوهريّاً، وأخطرُها أنّ
// طلباً مدفوعاً بالبطاقةِ يُودَعُ مبلغُه **في محفظةِ زيارة لا إلى البطاقة**
// (`refund_engine.creditCancelledRefund`)، **ولا مسارَ سحبٍ نقديٍّ للمحفظةِ
// في المستودعِ كلِّه** — فالرصيدُ يُنفَقُ داخلَ التطبيقِ وحدَه.
//
// والقاعدةُ كانت مُنفَّذةً في سطحَين من ثلاثة (حوارُ العميلةِ في
// `orders_list_screen`، وحوارُ تطبيقِ الإدارةِ في
// `admin_order_details_screen`) — «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحٍ واحد»
// بشكلٍ آخر: السطحُ الثالثُ يَكتبُ الكتابةَ نفسَها بلا الجملة.
//
// **والصياغةُ تَتبعُ الجمهورَ وقدرةَ السطحِ معاً**، وهذا فرقٌ عن الدارت
// يُقالُ صريحاً: نصُّ الدارتِ الإداريُّ يُحيلُ إلى «بطاقةِ عمليّاتِ ميسر
// أدناه»، وهي **ليست في هذه اللوحة** — فاستردادُ البطاقةِ من تطبيقِ
// الإدارة، أمّا التقسيطُ (تمارا/تابي) فله زرُّه في هذا الصفِّ نفسِه. أمّا
// **القرارُ** (النوعُ والمقدار) فواحدٌ حرفاً بحرف، وجدولُ الحالاتِ مشترَكٌ.

export type CancelRefundKind = 'nothingPaid' | 'subscriptionVisit' | 'walletCredit';

export interface CancelRefundNotice {
  kind: CancelRefundKind;
  /** `null` حين لا يُعرَفُ المقدارُ — فلا يُذكَرُ رقمٌ مُلفَّق. */
  amount: number | null;
}

/** القرارُ نقيٌّ — يُختبَرُ بلا Firebase، ومطابقٌ لجدولِ الدارت. */
export function cancelRefundNotice(o: {
  isPaid: boolean;
  paymentMethod?: string | null;
  amount?: number | null;
}): CancelRefundNotice {
  if (!o.isPaid) return {kind: 'nothingPaid', amount: null};
  if (o.paymentMethod === 'subscription') {
    return {kind: 'subscriptionVisit', amount: null};
  }
  // الخادمُ يَشترطُ `amount > 0` لِيُودِع، فصفرٌ أو غيابٌ يَعني أنّ الإيداعَ
  // لا يَجري — فلا نَعِدُ برقمٍ، والجملةُ شرطيّة.
  const a = typeof o.amount === 'number' && Number.isFinite(o.amount) && o.amount > 0
    ? o.amount
    : null;
  return {kind: 'walletCredit', amount: a};
}

/**
 * نصُّ الإدارةِ — المضمونُ المالِيُّ كما في `cancelRefundAdminText` الدارتيّة،
 * والإحالةُ تَتبعُ قدرةَ هذا السطح.
 *
 * @param bnplRefundHere هل زرُّ استردادِ التقسيطِ متاحٌ لهذا الطلبِ هنا.
 */
export function cancelRefundAdminText(
  notice: CancelRefundNotice,
  opts?: {bnplRefundHere?: boolean},
): string {
  switch (notice.kind) {
    case 'nothingPaid':
      return '';
    case 'subscriptionVisit':
      return 'زيارةُ باقةٍ مدفوعةٍ مسبقاً: لا مبلغَ يُعاد، والزيارةُ تبقى في ' +
        'رصيد الباقة.';
    case 'walletCredit': {
      const sum = notice.amount === null
        ? 'المبلغُ المدفوع'
        : `${notice.amount.toFixed(2)} ر.س`;
      const head = `الطلب مدفوع: سيُودَع ${sum} في محفظة العميلة تلقائياً — ` +
        'لا استرداد إلى البطاقة.';
      return opts?.bnplRefundHere
        ? `${head} لاسترداد التقسيط إلى العميلة استخدم زر «استرداد» في هذا الصف قبل الإلغاء.`
        : `${head} استرداد البطاقة يتم من بطاقة عمليات ميسر في تطبيق الإدارة.`;
    }
  }
}
