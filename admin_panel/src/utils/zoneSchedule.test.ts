import { describe, it, expect } from 'vitest';
// `?raw` من Vite يجلب الملف نصّاً — و`vite/client` يُعرّفه، بخلاف `node:fs`
// الذي لا أنواع له في `tsconfig.app.json` فيكسر `tsc -b` (وهو ما يشغّله
// فحص «بناء لوحة الإدارة» في CI، لا vitest).
import editorSrc from '../components/ZoneScheduleEditor.tsx?raw';
import {
    HOURS, formatHour12, withStart, withEnd, scheduleFromDoc, scheduleToDoc,
    type ZoneSchedule,
} from './zoneSchedule.ts';

// جدول فتح المحافظة — **عقدٌ بين ثلاث نسخ**، وهذا الملف يثبّت نصيب اللوحة منه:
//
//   admin_panel/src/utils/zoneSchedule.ts          يكتب (هذا الملف)
//   lib/screens/admin/admin_zone_schedule_editor   يكتب — المرآة في التطبيق
//   functions/index.js zoneDayScheduleForDate      **يقرأ ويحكم**
//
// والقارئ هو المرجع، وشرطه حرفيّاً:
//   Number.isInteger(s) && Number.isInteger(e) && e > s
// وإن لم يتحقّق أعاد `null` — أي **مغلق كلّ اليوم**.
//
// **العطل الذي وجده هذا الملف:** قائمتا الساعات في محرّر الويب مستقلّتان على
// 0..23 بلا أي قيد، فيحفظ الأدمن «مفتوح ١٠م → ٨ص»، فتقول اللوحة حُفظ، ويقرؤه
// الخادم مغلقاً: لا إتاحة، ولا حجز، ولا خطأ في أي مكان يُنبّه أحداً. ومحرّر
// Flutter يُقيّده منذ البداية — فكان الانحراف بين المرآتين، وهو ما يفعله
// التكرار دائماً.
//
// وشَدُّ القيد جاء من هذه الفحوص نفسها: نظير Flutter يُخلّف ثغرةً في طرف المدى
// (بداية 23 ⇒ نهاية `(24).clamp(1,23)` = 23 ⇒ متساويان ⇒ مغلق). فالفحص على
// **كل** الأزواج لا على أمثلةٍ مختارة، لأن الثغرة كانت في الطرف وحده.

/** شرط القارئ الخادمي، منقولاً حرفيّاً كي يُقاس عليه. */
const serverAcceptsRange = (s: unknown, e: unknown): boolean =>
    Number.isInteger(s) && Number.isInteger(e) && (e as number) > (s as number);

describe('قيد النطاق — ما يقبله الخادم', () => {
    it('كل زوج ساعات يمرّ على withStart يُنتج نطاقاً يقبله الخادم', () => {
        // 24×24 = 576 زوجاً. الثغرة كانت في زاويةٍ واحدة منها، فلا تكفي أمثلة.
        const bad: string[] = [];
        for (const s of HOURS) {
            for (const e of HOURS) {
                const r = withStart(s, e);
                if (!serverAcceptsRange(r.start, r.end)) bad.push(`withStart(${s},${e}) ⇒ ${r.start}..${r.end}`);
            }
        }
        expect(bad, `نطاقات يقرؤها الخادم «مغلق»:\n${bad.join('\n')}`).toEqual([]);
    });

    it('كل زوج ساعات يمرّ على withEnd يُنتج نطاقاً يقبله الخادم', () => {
        const bad: string[] = [];
        for (const s of HOURS) {
            for (const e of HOURS) {
                const r = withEnd(s, e);
                if (!serverAcceptsRange(r.start, r.end)) bad.push(`withEnd(${s},${e}) ⇒ ${r.start}..${r.end}`);
            }
        }
        expect(bad, `نطاقات يقرؤها الخادم «مغلق»:\n${bad.join('\n')}`).toEqual([]);
    });

    it('النطاق يبقى داخل 0..23 — لا ساعة 24 ولا سالبة', () => {
        for (const s of HOURS) {
            for (const e of HOURS) {
                for (const r of [withStart(s, e), withEnd(s, e)]) {
                    expect(r.start).toBeGreaterThanOrEqual(0);
                    expect(r.end).toBeLessThanOrEqual(23);
                }
            }
        }
    });

    it('النطاق السليم لا يُمَسّ — القيد يصحّح ولا يتدخّل', () => {
        expect(withStart(8, 22)).toEqual({ start: 8, end: 22 });
        expect(withEnd(8, 22)).toEqual({ start: 8, end: 22 });
    });

    it('تحريك البداية فوق النهاية يدفع النهاية (نظير Flutter)', () => {
        expect(withStart(20, 10)).toEqual({ start: 20, end: 21 });
        expect(withStart(10, 10)).toEqual({ start: 10, end: 11 });
    });

    it('تحريك النهاية تحت البداية يسحب البداية (نظير Flutter)', () => {
        expect(withEnd(20, 10)).toEqual({ start: 9, end: 10 });
        expect(withEnd(10, 10)).toEqual({ start: 9, end: 10 });
    });

    it('طرفا المدى — حيث كان نظير Flutter يُخلّف نطاقاً مغلقاً', () => {
        // بداية 23: لا تبقى ساعةٌ بعدها، فتُقَصّ إلى 22.
        expect(withStart(23, 23)).toEqual({ start: 22, end: 23 });
        expect(withStart(23, 5)).toEqual({ start: 22, end: 23 });
        // نهاية 0: لا تبقى ساعةٌ قبلها، فتُقَصّ إلى 1.
        expect(withEnd(0, 0)).toEqual({ start: 0, end: 1 });
        expect(withEnd(15, 0)).toEqual({ start: 0, end: 1 });
    });
});

describe('scheduleFromDoc — متسامح مع مستندات قديمة', () => {
    it('مستند فارغ/غائب ⇒ سبعة أيام بافتراضي 8..22 مغلقة', () => {
        for (const raw of [undefined, null, {}, 'نصّ', 42]) {
            const s = scheduleFromDoc(raw);
            expect(s.enabled).toBe(false);
            expect(Object.keys(s.weekly)).toHaveLength(7);
            for (let d = 0; d < 7; d++) {
                expect(s.weekly[String(d)]).toEqual({ open: false, start: 8, end: 22, closed: [] });
            }
            expect(s.blackouts).toEqual([]);
            expect(s.windows).toEqual([]);
        }
    });

    it('enabled وopen يلزمهما true بعينه — لا قيمة «شبه صادقة»', () => {
        // الخادم يفحص `enabled !== true` و`open === true`. فلو قبلنا 1 أو "true"
        // لعرضت اللوحة جدولاً «مُفعّلاً» يتجاهله الخادم كلّياً.
        expect(scheduleFromDoc({ enabled: 1 }).enabled).toBe(false);
        expect(scheduleFromDoc({ enabled: 'true' }).enabled).toBe(false);
        expect(scheduleFromDoc({ enabled: true }).enabled).toBe(true);
        expect(scheduleFromDoc({ weekly: { '0': { open: 1 } } }).weekly['0'].open).toBe(false);
        expect(scheduleFromDoc({ weekly: { '0': { open: true } } }).weekly['0'].open).toBe(true);
    });

    it('الساعات تُحوَّل رقميّاً — الحقل قد يصل نصّاً من مستند قديم', () => {
        const s = scheduleFromDoc({ weekly: { '3': { open: true, start: '9', end: '17' } } });
        expect(s.weekly['3'].start).toBe(9);
        expect(s.weekly['3'].end).toBe(17);
    });

    it('closed وblackouts وwindows: غير المصفوفة تُقرأ فراغاً لا تُسقط الشاشة', () => {
        const s = scheduleFromDoc({ blackouts: 'ليس مصفوفة', windows: 7, weekly: { '0': { closed: 'x' } } });
        expect(s.blackouts).toEqual([]);
        expect(s.windows).toEqual([]);
        expect(s.weekly['0'].closed).toEqual([]);
    });

    it('النافذة الناقصة تأخذ افتراضي 9..13 وتواريخ فارغة', () => {
        const s = scheduleFromDoc({ windows: [{}] });
        expect(s.windows[0]).toEqual({ from: '', to: '', start: 9, end: 13 });
    });
});

describe('scheduleToDoc — ما يُكتب فعلاً على Firestore', () => {
    const base = (over: Partial<ZoneSchedule> = {}): ZoneSchedule => ({
        enabled: true,
        weekly: Object.fromEntries(HOURS.slice(0, 7).map((_, d) =>
            [String(d), { open: false, start: 8, end: 22, closed: [] }])),
        blackouts: [],
        windows: [],
        ...over,
    });

    it('الساعات المقفلة تُقَصّ على النطاق وتُرتَّب', () => {
        // تضييق الدوام لا يُبقي «أشباح» ساعات مقفلة خارج حدوده — ولو بقيت،
        // عاملها الخادم ساعاتٍ ممتلئة في نطاقٍ لم تعد فيه.
        const s = base();
        s.weekly['0'] = { open: true, start: 10, end: 14, closed: [13, 9, 11, 14, 22, 10] };
        expect(scheduleToDoc(s).weekly['0'].closed).toEqual([10, 11, 13]);
    });

    it('النطاق نصف مفتوح: البداية داخل والنهاية خارج', () => {
        const s = base();
        s.weekly['1'] = { open: true, start: 8, end: 9, closed: [8, 9] };
        expect(scheduleToDoc(s).weekly['1'].closed).toEqual([8]);
    });

    it('النوافذ بلا تاريخين تُحذَف — الخادم يشترط from وto', () => {
        const s = base({
            windows: [
                { from: '2026-10-05', to: '2026-10-07', start: 9, end: 13 },
                { from: '', to: '2026-10-09', start: 9, end: 13 },
                { from: '2026-10-11', to: '', start: 9, end: 13 },
            ],
        });
        expect(scheduleToDoc(s).windows).toHaveLength(1);
        expect(scheduleToDoc(s).windows[0].from).toBe('2026-10-05');
    });

    it('كل يوم مفتوح في المخرَج يقبله القارئ الخادمي', () => {
        // الحارس الجوهري: اللوحة لا تكتب يوماً «مفتوحاً» يقرؤه الخادم مغلقاً.
        // (المحرّر يمرّ كل تعديل على withStart/withEnd، فالمخرَج سليم بالبناء.)
        const s = base({ enabled: true });
        for (let d = 0; d < 7; d++) {
            const r = withStart(d * 3, d * 3 + 1);
            s.weekly[String(d)] = { open: true, start: r.start, end: r.end, closed: [] };
        }
        const doc = scheduleToDoc(s);
        for (const [d, day] of Object.entries(doc.weekly)) {
            if (!day.open) continue;
            expect(serverAcceptsRange(day.start, day.end), `اليوم ${d}: ${day.start}..${day.end}`).toBe(true);
        }
    });

    it('الذهاب والعودة مستقرّ — الكتابة ثم القراءة لا تحرّك شيئاً', () => {
        const s = base({
            enabled: true,
            blackouts: ['2026-10-15'],
            windows: [{ from: '2026-10-05', to: '2026-10-07', start: 9, end: 13 }],
        });
        s.weekly['2'] = { open: true, start: 10, end: 14, closed: [11] };
        const once = scheduleToDoc(s);
        expect(scheduleToDoc(scheduleFromDoc(once))).toEqual(once);
    });
});

describe('formatHour12 — العرض 12 والتخزين 24', () => {
    it('منتصف الليل والظهر لا يصيران صفراً', () => {
        expect(formatHour12(0)).toBe('12 ص');
        expect(formatHour12(12)).toBe('12 م');
    });

    it('الصباح ص والمساء م', () => {
        expect(formatHour12(8)).toBe('8 ص');
        expect(formatHour12(11)).toBe('11 ص');
        expect(formatHour12(13)).toBe('1 م');
        expect(formatHour12(23)).toBe('11 م');
    });

    it('كل ساعة تُعرَض بلا تكرار داخل نصف اليوم', () => {
        // عرضٌ مكرّر داخل القائمة يجعل الأدمن يختار ساعةً غير التي يرى.
        const am = HOURS.filter(h => h < 12).map(formatHour12);
        const pm = HOURS.filter(h => h >= 12).map(formatHour12);
        expect(new Set(am).size).toBe(12);
        expect(new Set(pm).size).toBe(12);
    });
});

describe('المحرّر يمرّ كل تعديل ساعة على القيد', () => {
    // القيد الصحيح لا ينفع إن لم يُنادَ. ولو أُعيدت `start: Number(e.target.value)`
    // المباشرة، لبقيت كل الفحوص أعلاه خضراء والعطل عاد كما كان — فهذا الحارس على
    // **موضع النداء** لا على القاعدة. (نفس درس توحيد أهلية السائق: فحصُ القاعدة
    // وحدها يترك المسار المكشوف مكشوفاً.)
    const src = editorSrc;

    it('المحرّر يستورد withStart وwithEnd', () => {
        expect(src).toContain('withStart');
        expect(src).toContain('withEnd');
    });

    it('أربع قوائم ساعات — يومية ونافذة، بدايةً ونهايةً — كلها عبر القيد', () => {
        // أربع `<select>` للساعات: بداية/نهاية اليوم الأسبوعي، وبداية/نهاية
        // النافذة الاستثنائية. كلٌّ منها يجب أن تمرّ على دالّة القيد.
        expect(src.match(/withStart\(/g) ?? [], 'بدايتان: اليوم والنافذة').toHaveLength(2);
        expect(src.match(/withEnd\(/g) ?? [], 'نهايتان: اليوم والنافذة').toHaveLength(2);
    });

    it('لا إسناد مباشر لساعة من قيمة القائمة — يتجاوز القيد', () => {
        // الصيغة التي كانت: `{ start: Number(e.target.value) }` و
        // `s.windows[i].end = Number(e.target.value)`.
        const direct = [
            /\bstart:\s*Number\(e\.target\.value\)/,
            /\bend:\s*Number\(e\.target\.value\)/,
            /\.start\s*=\s*Number\(e\.target\.value\)/,
            /\.end\s*=\s*Number\(e\.target\.value\)/,
        ].filter(re => re.test(src)).map(String);
        expect(direct, `إسناد مباشر يتجاوز withStart/withEnd:\n${direct.join('\n')}`).toEqual([]);
    });
});
