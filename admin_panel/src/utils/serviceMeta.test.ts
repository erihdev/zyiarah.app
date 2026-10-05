import { describe, it, expect } from 'vitest';
import { metaHeadline, metaRows, metaSummary } from './serviceMeta.ts';

// تفصيل `service_meta` — **مرآة** لـ `lib/widgets/service_meta_view.dart`،
// وكانت بلا فحص واحد.
//
// ولماذا يستحقّ الفحص: هذا هو الجدول الذي **تتحقّق به الإدارة من مبلغ الفاتورة
// إن اعترضت العميلة** — كم قطعة، ما مقاسها، بأي سعر للمتر، وكم مادة تنظيف
// اشترتها داخل الطلب. فأي انحراف هنا يعني أن الإدارة على الويب ترى غير ما يراه
// السائق والتطبيق، في نزاعٍ على المال.
//
// **والنتيجة أن المرآة مطابقة.** قارنتُها بالأصل سطراً سطراً — جمعُ العاملات
// والكوادر والساعات، وظهورُ المواد، وسقوطُ `uses_area` للطلبات القديمة، كلّها
// متطابقة. فهذه الفحوص **تثبّت التطابق** لا تُصلح انحرافاً: الأصل في Dart لا
// يكسر شيئاً في TypeScript إن تغيّر، فبقي التطابق محفوظاً بالصدفة وحدها.
//
// وحدودُ الجمع هي ما يُفحَص هنا بعينه (1 و2 و3 و10 و11)، لأنها حيث تختلف
// الصياغة العربية وحيث ينحرف نقلٌ متعجّل: «عاملتان» لا «2 عاملات»، و«11 عاملة»
// لا «11 عاملات».

describe('metaHeadline — العنوان المختصر', () => {
    it('كل نوع يُعرِّف نفسه بوحدته', () => {
        expect(metaHeadline({ kind: 'sofa_rug_sqm', pieces: [{}, {}, {}] })).toBe('3 قطعة');
        expect(metaHeadline({ kind: 'ac_service', total_units: 2 })).toBe('2 مكيف');
        expect(metaHeadline({ kind: 'car_interior', total_cars: 1 })).toBe('1 سيارة');
        expect(metaHeadline({ kind: 'store_products', total_qty: 7 })).toBe('7 منتج');
    });

    it('باقة السكن: جمع الساعات على حدوده — نظير switch في Dart', () => {
        const h = (durationHours: unknown) => metaHeadline({ kind: 'home_package', durationHours });
        expect(h(1)).toBe('مدة الجدولة ساعة واحدة');
        expect(h(2)).toBe('مدة الجدولة ساعتان');
        expect(h(3)).toBe('مدة الجدولة 3 ساعات');
        expect(h(10)).toBe('مدة الجدولة 10 ساعات');
        expect(h(11)).toBe('مدة الجدولة 11 ساعة');
    });

    it('مدة غير موجبة ⇒ لا عنوان (لا «مدة الجدولة 0 ساعة»)', () => {
        for (const v of [0, -1, undefined, null, 'ليس رقماً']) {
            expect(metaHeadline({ kind: 'home_package', durationHours: v })).toBe('');
        }
    });

    it('نوع مجهول أو ميتا غائبة ⇒ فراغ لا انهيار', () => {
        for (const m of [undefined, null, {}, { kind: 'لا_يوجد' }, 'نصّ', 5]) {
            expect(metaHeadline(m)).toBe('');
        }
    });
});

describe('metaRows — الكنب والسجاد', () => {
    const piece = (over: Record<string, unknown> = {}) => ({
        kind: 'sofa_rug_sqm',
        pieces: [{ label: 'كنب', length_m: 2, width_m: 1.5, area_sqm: 3, price_per_unit: 20, line_total: 60, ...over }],
    });

    it('بالمساحة: طول × عرض = م² × السعر', () => {
        expect(metaRows(piece())[0]).toEqual({
            label: 'كنب', detail: '2م × 1.5م = 3.00 م² × 20', total: '60.00 ر.س',
        });
    });

    it('الطلبات القديمة بلا uses_area تُقرأ بالمساحة — سقوطٌ تراجعي', () => {
        // `uses_area` حقل جديد؛ الطلبات التي سبقَته كانت كلها بالمساحة. ولو
        // قُرئت طوليّاً لأظهرت الإدارة سعراً لا يطابق فاتورة العميلة.
        const rows = metaRows(piece());
        expect(rows[0].detail).toContain('م²');
    });

    it('uses_area:false ⇒ متر طولي (الكنب الطولي الجديد)', () => {
        expect(metaRows(piece({ uses_area: false }))[0].detail).toBe('2 م.ط × 20');
    });

    it('عرض صفر ⇒ طولي ولو كان uses_area صادقاً — لا «× 0م»', () => {
        expect(metaRows(piece({ uses_area: true, width_m: 0 }))[0].detail).toBe('2 م.ط × 20');
    });

    it('price_per_sqm القديم يُقرأ حين يغيب price_per_unit', () => {
        const m = piece();
        delete (m.pieces[0] as Record<string, unknown>).price_per_unit;
        (m.pieces[0] as Record<string, unknown>).price_per_sqm = 25;
        expect(metaRows(m)[0].detail).toContain('× 25');
    });

    it('الأرقام الصحيحة بلا كسور والكسرية كما هي (نظير _t)', () => {
        expect(metaRows(piece({ length_m: 3, width_m: 2, area_sqm: 6 }))[0].detail)
            .toBe('3م × 2م = 6.00 م² × 20');
        expect(metaRows(piece({ length_m: 2.5 }))[0].detail).toContain('2.5م');
    });

    it('pieces ليست مصفوفة ⇒ لا صفوف', () => {
        expect(metaRows({ kind: 'sofa_rug_sqm', pieces: 'x' })).toEqual([]);
        expect(metaRows({ kind: 'sofa_rug_sqm' })).toEqual([]);
    });
});

describe('metaRows — المكيفات والسيارات والمتجر', () => {
    it('المكيفات والسيارات بنية بنود واحدة', () => {
        for (const kind of ['ac_service', 'car_interior']) {
            expect(metaRows({ kind, lines: [{ label: 'صيانة شباك', count: 2, unit_price: 75, line_total: 150 }] }))
                .toEqual([{ label: 'صيانة شباك', detail: '2 × 75 ر.س', total: '150.00 ر.س' }]);
        }
    });

    it('منتجات المتجر: الكمية × سعر الوحدة', () => {
        expect(metaRows({ kind: 'store_products', items: [{ name: 'منظّف', quantity: 3, unit_price: 12.5, line_total: 37.5 }] }))
            .toEqual([{ label: 'منظّف', detail: '3 × 12.5 ر.س', total: '37.50 ر.س' }]);
    });

    it('الحقول النصّية تُحوَّل رقميّاً — Firestore قد يسلّمها نصّاً', () => {
        // «التحويل المباشر كان يُسقط شاشات في هذا المشروع» — تعليق المصدر.
        expect(metaRows({ kind: 'store_products', items: [{ name: 'س', quantity: '2', unit_price: '10', line_total: '20' }] }))
            .toEqual([{ label: 'س', detail: '2 × 10 ر.س', total: '20.00 ر.س' }]);
    });

    it('الاسم الغائب يصير شرطةً لا undefined', () => {
        expect(metaRows({ kind: 'store_products', items: [{ quantity: 1, unit_price: 1 }] })[0].label).toBe('-');
        expect(metaRows({ kind: 'ac_service', lines: [{ count: 1, unit_price: 1 }] })[0].label).toBe('-');
    });
});

describe('metaRows — باقة السكن ومواد التنظيف', () => {
    const pkg = (over: Record<string, unknown> = {}) =>
        ({ kind: 'home_package', homeLabel: 'شقة متوسطة', crewCount: 2, ...over });

    it('صفّان: نوع السكن وعدد الكوادر', () => {
        expect(metaRows(pkg())).toEqual([
            { label: 'نوع السكن', detail: '', total: 'شقة متوسطة' },
            { label: 'عدد الكوادر', detail: '', total: 'كادران' },
        ]);
    });

    it('جمع الكوادر على حدوده — نظير switch في Dart', () => {
        const c = (crewCount: number) => metaRows(pkg({ crewCount }))[1]?.total;
        expect(c(1)).toBe('كادر واحد');
        expect(c(2)).toBe('كادران');
        expect(c(3)).toBe('3 كوادر');
        expect(c(11)).toBe('11 كوادر');
    });

    it('بلا اسم سكن أو بكوادر غير موجبة ⇒ لا صفوف', () => {
        expect(metaRows(pkg({ homeLabel: '' }))).toEqual([]);
        expect(metaRows(pkg({ homeLabel: 42 }))).toEqual([]);
        expect(metaRows(pkg({ crewCount: 0 }))).toEqual([]);
    });

    it('**مواد التنظيف تظهر** — بدونها يتعذّر التحقق من مبلغ الفاتورة', () => {
        // العميلة تشتري مواد داخل الطلب فتدخل الفاتورة. فإن غابت عن جدول
        // الإدارة ظهر الإجمالي أكبر من مجموع السطور، ولا سبيل لتفسير الفرق.
        const rows = metaRows(pkg({ materials: [{ name: 'معطّر', quantity: 2, price: 15 }] }));
        expect(rows).toHaveLength(3);
        expect(rows[2]).toEqual({ label: '🧴 معطّر', detail: '2 × 15', total: '30.00 ر.س' });
    });

    it('إجمالي المادة = كمية × سعر محسوباً هنا لا مقروءاً', () => {
        // لا حقل line_total للمواد، فالجدول يحسبه — وهذا ما تُقارنه الإدارة.
        const rows = metaRows(pkg({ materials: [{ name: 'م', quantity: 3, price: 12.5 }] }));
        expect(rows[2].total).toBe('37.50 ر.س');
    });

    it('materials ليست مصفوفة ⇒ الصفّان الأساسيان يبقيان', () => {
        expect(metaRows(pkg({ materials: 'x' }))).toHaveLength(2);
    });
});

describe('metaRows — عاملات المناسبات', () => {
    const ev = (workers: unknown, event_hours: unknown) => ({ kind: 'event_workers', workers, event_hours });

    it('جمع العاملات على حدوده — «عاملتان» لا «2 عاملات»', () => {
        const w = (n: number) => metaRows(ev(n, 4))[0]?.total;
        expect(w(1)).toBe('عاملة واحدة');
        expect(w(2)).toBe('عاملتان');
        expect(w(3)).toBe('3 عاملات');
        expect(w(10)).toBe('10 عاملات');
        expect(w(11)).toBe('11 عاملة');
    });

    it('جمع ساعات المناسبة على حدوده', () => {
        const h = (n: number) => metaRows(ev(2, n))[1]?.total;
        expect(h(1)).toBe('1 ساعة');
        expect(h(2)).toBe('ساعتان');
        expect(h(3)).toBe('3 ساعات');
        expect(h(10)).toBe('10 ساعات');
        expect(h(11)).toBe('11 ساعة');
    });

    it('عدد أو مدة غير موجبة ⇒ لا صفوف', () => {
        expect(metaRows(ev(0, 4))).toEqual([]);
        expect(metaRows(ev(3, 0))).toEqual([]);
        expect(metaRows(ev(undefined, undefined))).toEqual([]);
    });
});

describe('metaRows — المدخلات الفاسدة لا تُسقط شاشة الإدارة', () => {
    it('ميتا غائبة أو بدائية ⇒ مصفوفة فارغة', () => {
        for (const m of [undefined, null, 'نصّ', 7, true]) expect(metaRows(m)).toEqual([]);
    });

    it('عناصر غير كائنات داخل القوائم تُستبعَد لا تُرمى', () => {
        expect(metaRows({ kind: 'store_products', items: [null, 'x', 5, { name: 'ص', quantity: 1, unit_price: 1 }] }))
            .toHaveLength(1);
    });

    it('نوع مجهول ⇒ فراغ', () => {
        expect(metaRows({ kind: 'نوع_جديد_لم_يُضَف' })).toEqual([]);
    });
});

// ═══════════════════════════════════════════════════════════════════════
// الملخّصُ بسطرٍ واحد — الجدولُ **المشترك** مع
// `test/service_meta_summary_test.dart`.
//
// `admin_meta_parity_test` كان يَفحصُ **بنيةً** (أنّ الأنواعَ الستّةَ مذكورةٌ
// في الجهتَين) ولم يُقارِنْ خَرْجَي الدالّتَين قطّ — فانحرفَتا في فرعٍ واحد:
// هذه الجهةُ تُلحقُ مدّةَ الباقةِ («4س») و«مصدرُ الحقيقة» في Dart لا يَحملها،
// فبطاقةُ السائقِ لا تَذكرُ طولَ المهمّةِ بينما صفُّ اللوحةِ يَذكره.
//
// الكتلةُ أدناه تُقارَنُ حرفاً بحرفٍ بنظيرتِها في Dart (الفحصُ هناك يَقرأُ هذا
// الملفّ) — فلا تُضافُ حالةٌ لجهةٍ دون الأخرى.
// ──── SUMMARY-CASES-BEGIN ────
const cases: { meta: unknown; want: string | null }[] =
[
  {"meta": {"kind": "ac_service", "lines": [{"label": "صيانة شباك", "count": 1}, {"label": "غسيل سبليت", "count": 2}]}, "want": "صيانة شباك ×1 • غسيل سبليت ×2"},
  {"meta": {"kind": "car_interior", "lines": [{"label": "سيدان", "count": 1}]}, "want": "سيدان ×1"},
  {"meta": {"kind": "ac_service", "lines": [{"label": "لا شيء", "count": 0}]}, "want": null},
  {"meta": {"kind": "ac_service"}, "want": null},
  {"meta": {"kind": "sofa_rug_sqm", "pieces": [{"label": "كنب 1", "billed_measure": 2.5, "uses_area": false}, {"label": "كنب 2", "billed_measure": 3, "uses_area": false}, {"label": "سجاد 1", "area_sqm": 6}]}, "want": "كنب ×2 (5.50 م.ط) • سجاد ×1 (6.00 م²)"},
  {"meta": {"kind": "store_products", "items": [{"name": "منظف", "quantity": 2}]}, "want": "منظف ×2"},
  {"meta": {"kind": "home_package", "homeLabel": "شقة متوسطة", "crewCount": 2, "durationHours": 4, "materials": [{}, {}]}, "want": "شقة متوسطة • كادران • 4س • + 2 مادة"},
  {"meta": {"kind": "home_package", "homeLabel": "فيلا", "crewCount": 1}, "want": "فيلا • كادر واحد"},
  {"meta": {"kind": "home_package", "homeLabel": "قصر", "crewCount": 3, "durationHours": 8}, "want": "قصر • 3 كوادر • 8س"},
  {"meta": {"kind": "home_package", "homeLabel": "", "crewCount": 2}, "want": null},
  {"meta": {"kind": "event_workers", "workers": 2, "event_hours": 2}, "want": "عاملتان • ساعتان"},
  {"meta": {"kind": "event_workers", "workers": 3, "event_hours": 5}, "want": "3 عاملات • 5 ساعات"},
  {"meta": {"kind": "event_workers", "workers": 1, "event_hours": 3}, "want": "عاملة واحدة • 3 ساعات"},
  {"meta": {"kind": "event_workers", "workers": 0, "event_hours": 5}, "want": null},
  {"meta": {"kind": "unknown_kind"}, "want": null},
  {"meta": {}, "want": null}
];
// ──── SUMMARY-CASES-END ────

describe('metaSummary — الجدولُ المشترك', () => {
    it('الجدولُ غيرُ فارغٍ ويُغطّي الأنواعَ الستّة', () => {
        expect(cases.length).toBeGreaterThanOrEqual(14);
        const kinds = new Set(
            cases.map(c => (c.meta as Record<string, unknown>)?.kind).filter(Boolean));
        for (const k of ['ac_service', 'car_interior', 'sofa_rug_sqm',
            'store_products', 'home_package', 'event_workers']) {
            expect(kinds.has(k)).toBe(true);
        }
    });

    cases.forEach((c, i) => {
        const kind = (c.meta as Record<string, unknown>)?.kind ?? '(بلا نوع)';
        it(`[${i}] ${String(kind)}`, () => {
            expect(metaSummary(c.meta)).toBe(c.want);
        });
    });

    it('ولا مُدخَلَ غيرَ كائنٍ يُسقطُ الدالّة', () => {
        expect(metaSummary(null)).toBeNull();
        expect(metaSummary(undefined)).toBeNull();
        expect(metaSummary('garbage')).toBeNull();
        expect(metaSummary(7)).toBeNull();
    });
});
