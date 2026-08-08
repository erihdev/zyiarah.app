// تفصيل `service_meta` — **مرآة** لـ lib/widgets/service_meta_view.dart.
// أي انحراف هنا يعني أن الإدارة على الويب ترى غير ما يراه السائق والتطبيق.

export interface MetaRow { label: string; detail: string; total: string }

/// حقول Firestore قد تصل نصّاً — التحويل المباشر كان يُسقط شاشات في هذا المشروع.
const num = (v: unknown): number => {
    if (typeof v === 'number') return v;
    if (v === null || v === undefined) return 0;
    const n = parseFloat(String(v));
    return isNaN(n) ? 0 : n;
};

/// رقم مختصر: بلا كسور إن كان صحيحاً (نظير _t في التطبيق).
const t = (v: number): string => (v === Math.round(v) ? v.toFixed(0) : String(v));

const sar = (v: unknown): string => `${num(v).toFixed(2)} ر.س`;

const asList = (v: unknown): Record<string, unknown>[] =>
    Array.isArray(v) ? (v.filter(x => x && typeof x === 'object') as Record<string, unknown>[]) : [];

/// العنوان المختصر أعلى الجدول (نظير _headline).
export function metaHeadline(meta: unknown): string {
    const m = (meta ?? {}) as Record<string, unknown>;
    switch (m.kind) {
        case 'sofa_rug_sqm': return `${asList(m.pieces).length} قطعة`;
        case 'ac_service': return `${num(m.total_units).toFixed(0)} مكيف`;
        case 'car_interior': return `${num(m.total_cars).toFixed(0)} سيارة`;
        case 'store_products': return `${num(m.total_qty).toFixed(0)} منتج`;
        case 'home_package': {
            const h = Math.round(num(m.durationHours));
            if (h <= 0) return '';
            const label = h === 1 ? 'ساعة واحدة' : h === 2 ? 'ساعتان' : h <= 10 ? `${h} ساعات` : `${h} ساعة`;
            return `مدة الجدولة ${label}`;
        }
        default: return '';
    }
}

function materialRows(m: Record<string, unknown>): MetaRow[] {
    // مواد التنظيف المشتراة داخل الطلب — **يجب** أن تراها الإدارة، وإلا تعذّر
    // التحقق من مبلغ الفاتورة إن اعترضت العميلة.
    return asList(m.materials).map(it => {
        const q = Math.round(num(it.quantity));
        const price = num(it.price);
        return {
            label: `🧴 ${it.name ?? '-'}`,
            detail: `${q} × ${t(price)}`,
            total: `${(q * price).toFixed(2)} ر.س`,
        };
    });
}

/// صفوف الجدول الكامل لكل نوع (نظير الـ switch في ZyiarahServiceMetaView).
export function metaRows(meta: unknown): MetaRow[] {
    if (!meta || typeof meta !== 'object') return [];
    const m = meta as Record<string, unknown>;

    switch (m.kind) {
        case 'sofa_rug_sqm':
            return asList(m.pieces).map(p => {
                const l = num(p.length_m);
                const w = num(p.width_m);
                const a = num(p.area_sqm);
                const rate = num(p.price_per_unit ?? p.price_per_sqm);
                // الطلبات القديمة (بلا uses_area) كانت كلها بالمساحة.
                const usesArea = p.uses_area !== false && w > 0;
                return {
                    label: `${p.label ?? '-'}`,
                    detail: usesArea
                        ? `${t(l)}م × ${t(w)}م = ${a.toFixed(2)} م² × ${t(rate)}`
                        : `${t(l)} م.ط × ${t(rate)}`,
                    total: sar(p.line_total),
                };
            });

        // السيارات والمكيفات بنية بنود واحدة (label/count/unit_price).
        case 'ac_service':
        case 'car_interior':
            return asList(m.lines).map(l => ({
                label: `${l.label ?? '-'}`,
                detail: `${Math.round(num(l.count))} × ${t(num(l.unit_price))} ر.س`,
                total: sar(l.line_total),
            }));

        case 'store_products':
            return asList(m.items).map(it => ({
                label: `${it.name ?? '-'}`,
                detail: `${Math.round(num(it.quantity))} × ${t(num(it.unit_price))} ر.س`,
                total: sar(it.line_total),
            }));

        case 'home_package': {
            const label = m.homeLabel;
            const crews = Math.round(num(m.crewCount));
            if (typeof label !== 'string' || !label || crews <= 0) return [];
            const crewsLabel = crews === 1 ? 'كادر واحد' : crews === 2 ? 'كادران' : `${crews} كوادر`;
            return [
                { label: 'نوع السكن', detail: '', total: label },
                { label: 'عدد الكوادر', detail: '', total: crewsLabel },
                ...materialRows(m),
            ];
        }

        case 'event_workers': {
            const w = Math.round(num(m.workers));
            const h = Math.round(num(m.event_hours));
            if (w <= 0 || h <= 0) return [];
            return [
                {
                    label: 'عدد العاملات', detail: '',
                    total: w === 1 ? 'عاملة واحدة' : w === 2 ? 'عاملتان' : w <= 10 ? `${w} عاملات` : `${w} عاملة`,
                },
                {
                    label: 'مدة المناسبة', detail: '',
                    total: h === 2 ? 'ساعتان' : h >= 3 && h <= 10 ? `${h} ساعات` : `${h} ساعة`,
                },
            ];
        }

        default:
            return [];
    }
}
