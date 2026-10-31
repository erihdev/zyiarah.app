// رحلاتُ نقلِ العاملاتِ عبر «مواصلات» — مرآةُ `lib/utils/transport_ride.dart`.
//
// الخادمُ (`functions/transport.js`) يَكتبُ على الطلبِ خريطةَ `transport`
// بساقَين `outbound` و`return`. هذه الوحدةُ قراءةٌ صِرفةٌ بمفرداتٍ عربيّةٍ،
// وتُقابَلُ بالمرآةِ الدارتيّةِ في `transportRide.test.ts` فلا تَنحرِف.

export const TRANSPORT_LIVE_STATES = [
  'requesting', 'requested', 'accepted', 'driving', 'arrived',
] as const;
export const TRANSPORT_FINAL_STATES = ['completed', 'cancelled', 'failed'] as const;

export interface TransportLegView {
  leg: 'outbound' | 'return';
  state: string;
  driverName: string | null;
  driverPhone: string | null;
  driverPlate: string | null;
  etaMinutes: number | null;
  error: string | null;
}

function nonEmpty(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.trim();
  return s ? s : null;
}

/** يَقرأُ ساقاً من مستندِ الطلب؛ `null` إن لم تُطلَب بعد. */
export function transportLegOf(
  order: Record<string, unknown> | null | undefined,
  leg: 'outbound' | 'return',
): TransportLegView | null {
  const t = order?.transport;
  if (!t || typeof t !== 'object') return null;
  const raw = (t as Record<string, unknown>)[leg];
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const state = nonEmpty(r.state);
  if (!state) return null;
  const d = r.driver && typeof r.driver === 'object' ? (r.driver as Record<string, unknown>) : null;
  const eta = typeof r.eta_minutes === 'number' ? r.eta_minutes : null;
  return {
    leg,
    state,
    driverName: d ? nonEmpty(d.name) : null,
    driverPhone: d ? nonEmpty(d.phone) : null,
    driverPlate: d ? nonEmpty(d.plate) : null,
    etaMinutes: eta,
    error: nonEmpty(r.error),
  };
}

/** التسميةُ العربيّةُ — لا حرفَ لاتينيّاً خامّاً في واجهةٍ عربيّة. */
export function transportStateLabel(state: string): string {
  switch (state) {
    case 'requesting': return 'جارٍ الطلب';
    case 'requested': return 'بانتظار سائق';
    case 'accepted': return 'سائق مؤكّد';
    case 'driving': return 'السائق في الطريق';
    case 'arrived': return 'السائق وصل';
    case 'completed': return 'اكتملت';
    case 'cancelled': return 'أُلغيت';
    case 'failed': return 'تعذّر الطلب';
    default: return 'غير معروفة';
  }
}

/** صنفُ لونِ الشارةِ (Tailwind) بحسبِ الحالة. */
export function transportStateClass(state: string): string {
  switch (state) {
    case 'requesting':
    case 'requested':
      return 'bg-amber-50 text-amber-700 border-amber-200';
    case 'accepted':
    case 'driving':
    case 'arrived':
      return 'bg-blue-50 text-blue-700 border-blue-200';
    case 'completed':
      return 'bg-emerald-50 text-emerald-700 border-emerald-200';
    case 'failed':
      return 'bg-red-50 text-red-700 border-red-200';
    default:
      return 'bg-slate-50 text-slate-600 border-slate-200';
  }
}

/**
 * الساقُ التي تَعني الإدارةَ الآن في قائمةِ الطلبات: الذهابُ ما لم يَكتملِ
 * الطلبُ، ثمّ العودة. `null` إن لم تُطلَب أيٌّ منهما.
 */
export function currentTransportLeg(
  order: Record<string, unknown> | null | undefined,
): TransportLegView | null {
  const status = order?.status;
  if (status === 'completed') {
    return transportLegOf(order, 'return') ?? transportLegOf(order, 'outbound');
  }
  return transportLegOf(order, 'outbound');
}
