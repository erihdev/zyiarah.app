import { AlertTriangle, HelpCircle, ShieldCheck } from 'lucide-react';
import { COUPON_REJECT_REASONS, priceReviewLine, type PriceReview } from '../utils/priceReview.ts';

// شارةُ وسمِ مراجعةِ السعرِ في صفِّ جدول — مشتركةٌ بين «الطلبات» و«مبيعات
// المتجر» لأنّ الخادمَ يَسِمُ المجموعتَين بنفسِ الحقول.
//
// الوسمُ كان بلا قارئٍ في أيِّ واجهة: الإدارةُ تَتلقّى دفعةً بأكوادِ الطلباتِ
// ثمّ تَفتحُ الطلبَ فتَراه عاديّاً تماماً. وهذه الشارةُ تَضعُ الرقمَ في
// الخليّةِ التي فيها المال.
export default function PriceReviewBadge({ r }: { r: PriceReview }) {
    if (!r.needsCard) return null;
    const pending = r.actionable;
    const reason = r.couponRejectedReason
        ? COUPON_REJECT_REASONS[r.couponRejectedReason] ?? r.couponRejectedReason
        : null;
    // العنوانُ (tooltip) يَحملُ التفصيلَ كاملاً: الصفُّ ضيّقٌ والرقمُ لازم.
    const title = [
        priceReviewLine(r),
        r.ratio !== null ? `النسبة ${(r.ratio * 100).toFixed(1)}%` : null,
        r.shortfall !== null ? `الفارق ${r.shortfall.toFixed(2)} ر.س` : null,
        reason ? `كوبون مرفوض: ${reason}` : null,
    ].filter(Boolean).join(' · ');

    const cls = pending
        ? (r.kind === 'underpaid'
            ? 'bg-rose-50 text-rose-700 border-rose-200'
            : 'bg-amber-50 text-amber-700 border-amber-200')
        : 'bg-emerald-50 text-emerald-700 border-emerald-200';
    const label = pending
        ? (r.kind === 'underpaid' ? 'مراجعة سعر' : 'تعذّر التحقّق')
        : 'سعر مُعتمد';
    const Icon = pending
        ? (r.kind === 'underpaid' ? AlertTriangle : HelpCircle)
        : ShieldCheck;

    return (
        <span
            title={title}
            className={`mt-1 inline-flex items-center gap-1 px-2 py-0.5 rounded-lg border text-[11px] font-bold ${cls}`}
        >
            <Icon size={12} />{label}
        </span>
    );
}
