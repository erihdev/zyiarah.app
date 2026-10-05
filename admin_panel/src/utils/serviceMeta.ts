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

/// تحويلٌ **صارم** مطابقٌ لـ`_num` في Dart (`double.tryParse ?? 0`): نصٌّ غيرُ
/// رقميٍّ يصير صفراً. و`num` أعلى هذا الملفِّ أكثرُ تسامحاً (`parseFloat`،
/// فـ`'4px'` تصير 4) — فرقٌ لا يَبلغُه شيءٌ يَكتبُه المشروعُ، ويُبقى كما هو
/// كي يَبقى نقلُ هذه الدالّةِ من `Orders.tsx` محفوظَ السلوكِ حرفيّاً.
const nStrict = (v: unknown): number => Number(v) || 0;

/// ملخّصُ تفصيلِ الخدمةِ بسطرٍ واحد — **مرآةُ** `zyiarahServiceMetaSummary` في
/// lib/widgets/service_meta_view.dart (مصدر الحقيقة). كانت هذه الدالة ترجع null
/// لكل نوع عدا home_package، فيُسنِد الأدمن من الويب سائقاً وهو لا يرى عدد
/// المكيفات ولا مقاسات الكنب ولا — الأخطر — عدد عاملات المناسبة وساعاتها،
/// وهي جوهر الحجز نفسه.
///
/// ملاحظة: لا نستعمل o.worker_count / o.hours_contracted بديلاً؛ يحملهما **كل**
/// طلب بقيم افتراضية (1 عاملة / 4 ساعات) فيطبعان بيانات كاذبة على غير محلّها.
export const metaSummary = (meta: unknown): string | null => {
    const m = meta as Record<string, unknown>;
    if (!meta || typeof meta !== 'object') return null;
    const parts: string[] = [];

    switch (m.kind) {
        // السيارات والمكيفات بنية بنود واحدة (label/count) — نفس الملخّص.
        case 'ac_service':
        case 'car_interior': {
            if (!Array.isArray(m.lines)) return null;
            for (const l of m.lines) {
                const c = nStrict(l?.count);
                if (c > 0) parts.push(`${l?.label ?? '-'} ×${c}`);
            }
            break;
        }
        case 'sofa_rug_sqm': {
            if (!Array.isArray(m.pieces)) return null;
            // تجميع حسب النوع: العدد والمقدار المسعَّر (م² للسجاد، م.ط للكنب).
            const count: Record<string, number> = {};
            const measure: Record<string, number> = {};
            const unit: Record<string, string> = {};
            for (const p of m.pieces) {
                const label = `${p?.label ?? '-'}`.split(' ')[0]; // «كنب 1» → «كنب»
                count[label] = (count[label] ?? 0) + 1;
                // الطلبات القديمة (بلا billed_measure/uses_area) كانت كلها بالمساحة.
                measure[label] = (measure[label] ?? 0) + nStrict(p?.billed_measure ?? p?.area_sqm);
                unit[label] = p?.uses_area === false ? 'م.ط' : 'م²';
            }
            for (const label of Object.keys(count)) {
                parts.push(`${label} ×${count[label]} (${measure[label].toFixed(2)} ${unit[label]})`);
            }
            break;
        }
        case 'store_products': {
            if (!Array.isArray(m.items)) return null;
            for (const it of m.items) {
                const q = nStrict(it?.quantity);
                if (q > 0) parts.push(`${it?.name ?? '-'} ×${q}`);
            }
            break;
        }
        case 'home_package': {
            // نظيرُ Dart: `label is! String || label.isEmpty` — والنصُّ الفارغُ
            // كاذبٌ في JS فالشرطانِ سواء.
            if (typeof m.homeLabel !== 'string' || !m.homeLabel) return null;
            const crews = nStrict(m.crewCount);
            if (crews <= 0) return null;
            parts.push(m.homeLabel);
            parts.push(crews === 1 ? 'كادر واحد' : crews === 2 ? 'كادران' : `${crews} كوادر`);
            const dur = nStrict(m.durationHours);
            if (dur > 0) parts.push(`${dur}س`);
            // تنبيه مبكّر: الطلب يحمل مواد يجب أن يجلبها السائق.
            if (Array.isArray(m.materials) && m.materials.length > 0) {
                parts.push(`+ ${m.materials.length} مادة`);
            }
            break;
        }
        case 'event_workers': {
            const w = nStrict(m.workers);
            const h = nStrict(m.event_hours);
            if (w <= 0 || h <= 0) return null;
            parts.push(w === 1 ? 'عاملة واحدة' : w === 2 ? 'عاملتان' : `${w} عاملات`);
            parts.push(h === 2 ? 'ساعتان' : `${h} ساعات`);
            break;
        }
        default:
            return null;
    }
    return parts.length ? parts.join(' • ') : null;
};
