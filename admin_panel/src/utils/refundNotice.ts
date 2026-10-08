// مرآةُ قرارِ «ماذا يَحدثُ للخدمةِ إن استردَدتُ المال؟» — الأصلُ
// `lib/utils/refund_notice.dart`.
//
// **لمَ وُجدت:** حوارُ تأكيدِ استردادِ التقسيطِ في هذه الصفحةِ كان سطراً
// واحداً («لا يمكن التراجع»)، وكذلك حوارا تطبيقِ الإدارة — ثلاثةُ أسطحٍ لا
// يَقولُ أيٌّ منها ما يَحدثُ للخدمة. وهو نفسُ الشكلِ الذي استُبدِلَ في
// الاتّجاهِ المعاكس (`cancelRefundNotice`): حوارُ الإلغاءِ صارَ يَقولُ إلى
// أين يَذهبُ المال.
//
// ومسارا التقسيطِ الخادميّانِ يَكتبانِ `payment_status: "refunded"` و
// `is_paid: false` و`refunded: true` — **ولا يَمَسّانِ `status`**. فطلبٌ
// مفتوحٌ يَحملُ سائقاً يَبقى على هاتفِه فيَذهبُ الفريقُ وينفّذُ الخدمةَ بلا
// مقابل، وبطاقةُ العميلةِ تَبقى «مجدول» بزرِّ تتبّعٍ بينما وصلَتها دفعةُ «تم
// استرداد مبلغك 💳».
import { orderIsOpen } from './orderActivity.ts';

/// عمليّةُ البوّابةِ التي تُعيدُ المالَ أو تُحرّرُه. `capture` ليست هنا بقصد.
export type RefundOp = 'refund' | 'voidAuth';

/// أثرُ العمليّةِ على الخدمة.
export type RefundServiceImpact =
  | 'crewStillAssigned'
  | 'openWithoutCrew'
  | 'serviceEnded';

/// «مفتوح» هو `orderIsOpen` بعينِه: المنتهي مجموعةٌ قصيرةٌ ثابتةٌ وما عداه
/// مفتوح — فحالةٌ تُضافُ غداً لا تَسقطُ من التحذير.
export function refundServiceImpact(
    status: string | null | undefined,
    hasDriver: boolean,
): RefundServiceImpact {
  if (!orderIsOpen(status)) return 'serviceEnded';
  return hasDriver ? 'crewStillAssigned' : 'openWithoutCrew';
}

/// السطرُ المُلحَقُ بسؤالِ التأكيد — فارغٌ حين لا شيءَ يُقال. والصياغةُ
/// مطابقةٌ حرفاً بحرفٍ للدارت: الجمهورُ الأدمنُ في الثلاثة، واختلافُ النصِّ
/// بين سطحَين لقرارٍ واحدٍ هو ما يُنتجُ هذا النوعَ من العطل.
export function refundNoticeText(
    op: RefundOp,
    impact: RefundServiceImpact,
    partial: boolean,
): string {
  const verb = op === 'voidAuth' ? 'إلغاءُ التفويض' : 'استردادُ المبلغ';
  const lines: string[] = [];
  if (impact === 'crewStillAssigned') {
    lines.push(`${verb} لا يُلغي الطلب: يبقى بحالته وسائقُه مُسنَداً، ` +
      'فيذهب الفريق إلى العميلة. ألغِ الطلب أيضاً إن كانت الخدمة ' +
      'لن تُنفَّذ.');
  } else if (impact === 'openWithoutCrew') {
    lines.push(`${verb} لا يُلغي الطلب: يبقى مفتوحاً بلا سائق ولن يُسنَد له ` +
      'فريق بعدها (الإسناد يشترط الدفع). ألغِه أيضاً كي لا يبقى ' +
      'معلّقاً.');
  }
  if (partial) {
    lines.push('الاسترداد الجزئي يَسِم الطلب غير مدفوع بالكامل، فيخرج من ' +
      'عدّ السعة والتذكيرات والجوائز.');
  }
  return lines.join(' ');
}
