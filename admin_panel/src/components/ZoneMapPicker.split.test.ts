import { describe, it, expect } from 'vitest';
import settingsSrc from '../pages/Settings.tsx?raw';
import pickerSrc from './ZoneMapPicker.tsx?raw';
import geoSrc from '../utils/circleGeoJSON.ts?raw';

// حارس دائم: **محرّك الخرائط في قطعةٍ واحدة، تُجلب عند فتح نموذج «إضافة محافظة» وحده.**
//
// `mapbox-gl` أثقلُ تبعيات اللوحة بفارقٍ كبير. بعد تقسيم المسارات صارت في قطعة
// Settings — وهو تحسّنٌ حقيقي (كان كلُّ أدمن ينزّلها قبل أيّ شاشة) لكنه ترك
// الثقبَ الأصغر: **فتحُ الإعدادات على أيّ تبويب** — الدفع، التحديث الإجباري،
// السقف اليومي — يجلب محرّك الخرائط كاملاً، ولو لم يُفتح تبويب التغطية قطّ.
//
// القياس الفعليّ (`npm run build`):
//
//   قبل:  Settings.js        1,917.68 kB  (530.74 kB مضغوطاً)
//         Settings.css          48.82 kB  (  5.85 kB)
//
//   بعد:  Settings.js           75.72 kB  ( 20.16 kB مضغوطاً)   ← فتحُ الإعدادات
//         ZoneMapPicker.js   1,842.81 kB  (511.16 kB)          ← نموذج الإضافة وحده
//         ZoneMapPicker.css     48.82 kB  (  5.85 kB)
//
// أي أنّ فتحَ الإعدادات هبط من ٥٣٠ كيلوبايت مضغوطةً إلى ٢٠ — وCSS الخرائط
// انتقلت معها. (وهبطت الحِزمة الرئيسية ٣ كيلوبايت مضغوطةً عرَضاً.)
//
// **والانحدار صامت تماماً**، كما في حارس المسارات: استيرادٌ واحد لـ`mapbox-gl`
// في أيّ ملفٍّ تصله Settings يُعيد ١٨٤٢ كيلوبايت إلى قطعتها، ولا يسقط فحصٌ آخر
// ولا يتغيّر شيء في الواجهة. يُرى في حجم البناء وحده، وأحدٌ لا يقرؤه.
//
// ملاحظةٌ على `utils/mapboxArabic.ts`: هي تستورد mapboxgl **على مستوى الوحدة
// وتُسجّل إضافة RTL كأثرٍ جانبي**. فلو بقي استيرادها في Settings لبقيت التبعية
// في قطعتها، ولو أُزيل استيراد `mapbox-gl` المباشر. فحصُ «من يستوردها» ليس
// تزيُّداً: هو النصف الثاني من الفصل.

/** يُجرّد التعليقات قبل الفحص. الشيفرةُ تشرح الفصلَ بذكر `mapbox-gl` و
 *  `mapboxArabic` بالاسم، فالفحص الخامّ يسقط على شرحِ نفسه (درسٌ مُكرَّر في هذا
 *  المستودع). ولا نقطع السطر عند أوّل `//`: فـ`https://` تحمل `//`. */
const codeOf = (src: string) => src
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter(l => !l.trimStart().startsWith('//') && !l.trimStart().startsWith('*'))
    .map(l => l.replace(/([^:])\/\/.*$/, '$1'))
    .join('\n');

// كل ملفّات المصدر تحت src/ نصّاً — عبر `import.meta.glob` لا `node:fs`:
// الأخيرة بلا أنماط في tsconfig.app.json (سقط عليها حارسٌ سابق)، وglob يكتبها
// `vite/client`. المسارات تعود نسبيّةً عن هذا الملفّ.
const RAW = import.meta.glob('../**/*.{ts,tsx}', {
    query: '?raw', import: 'default', eager: true,
}) as Record<string, string>;

/** مسارات المصدر (بلا ملفّات الفحص)، منسوبةً إلى src/. مفاتيحُ glob نسبيّةٌ
 *  عن هذا الملفّ: الأخُ يعود `./X` والبعيد `../a/b` — فنُسوّي الشكلين. */
const norm = (k: string) => k.startsWith('./')
    ? 'src/components/' + k.slice(2)
    : 'src/' + k.replace(/^\.\.\//, '');

const srcFiles = () => Object.keys(RAW)
    .filter(f => !/\.test\.tsx?$/.test(f))
    .map(norm)
    .sort();

const read = (f: string) => {
    const key = Object.keys(RAW).find(k => norm(k) === f);
    if (!key) throw new Error(`لم يُوجَد المصدر: ${f}`);
    return RAW[key];
};

const PICKER = 'src/components/ZoneMapPicker.tsx';
const ARABIC = 'src/utils/mapboxArabic.ts';

describe('قطعة محرّك الخرائط', () => {
    it('لا ملفّ غير المنتقي ووحدةِ التعريب يستورد mapbox-gl', () => {
        const importers = srcFiles().filter(f =>
            /from\s+'mapbox-gl'|import\s+'mapbox-gl/.test(codeOf(read(f))));
        expect(
            importers.sort(),
            'استيرادُ mapbox-gl من ملفٍّ آخر يسحب ١٨٤٢ كيلوبايت إلى قطعته:\n' +
            importers.map(f => `  - ${f}`).join('\n'),
        ).toEqual([PICKER, ARABIC].sort());
    });

    it('وحدةُ التعريب لا يستوردها إلا المنتقي (تستورد mapboxgl وتُسجّل أثراً جانبياً)', () => {
        const importers = srcFiles().filter(f =>
            f !== ARABIC && /mapboxArabic/.test(codeOf(read(f))));
        expect(importers, 'استيرادُها يُبقي mapbox-gl في قطعة المستورِد').toEqual([PICKER]);
    });

    it('Settings تؤجّل المنتقي بـlazy ولا تلمس الخرائط', () => {
        const code = codeOf(settingsSrc);
        expect(/const ZoneMapPicker = lazy\(\(\) => import\('\.\.\/components\/ZoneMapPicker\.tsx'\)\)/
            .test(code), 'المنتقي يجب أن يكون lazy في Settings').toBe(true);
        expect(/^import ZoneMapPicker from/m.test(code),
            'استيرادٌ ثابت يتجاوز التأجيل').toBe(false);
        expect(/mapbox/i.test(code),
            'Settings تذكر mapbox في شيفرتها — يجب أن تبقى صمّاء عن الخرائط').toBe(false);
        // والتجريدُ لم يُفرِغ الفحص: الاسم ما زال في النصّ الخامّ (في الشرح).
        expect(/mapbox/i.test(settingsSrc),
            'لا شرحَ يذكر mapbox — فالتجريد صار بلا موضوع ولا يثبت أن الفحص يرى الشيفرة',
        ).toBe(true);
    });

    it('**بوّابةُ التنزيل**: المنتقي يُركَّب داخل showAddForm لا مع الصفحة', () => {
        // هذا هو جوهرُ الفصل. `lazy` وحده لا يكفي: مكوّنٌ مؤجَّل يُركَّب مع
        // الصفحة يُجلب فوراً، فتعود التكلفة كما كانت بلا أن يسقط فحصٌ أعلاه.
        const code = codeOf(settingsSrc);
        const gate = code.indexOf('{showAddForm && (');
        const use = code.indexOf('<ZoneMapPicker');
        expect(gate, 'لم تُوجَد بوّابة showAddForm').toBeGreaterThan(-1);
        expect(use, 'لم يُوجَد استعمالُ المنتقي').toBeGreaterThan(-1);
        expect(use, 'المنتقي خارج بوّابة showAddForm — فيُجلب محرّك الخرائط مع ' +
            'الصفحة كما كان، والفصل بلا أثر').toBeGreaterThan(gate);
        // الحدُّ مُحيطٌ فعلاً، لا مجرّد موجودٍ في الملفّ: آخرُ `<Suspense` قبل
        // الاستعمال يجب أن يأتي بعد آخر `</Suspense>` — وإلّا فهو حدُّ شيءٍ آخر.
        const before = code.slice(0, use);
        expect(before.lastIndexOf('<Suspense'),
            'بلا حدّ Suspense مُحيط يرمي React أثناء جلب القطعة',
        ).toBeGreaterThan(before.lastIndexOf('</Suspense>'));
    });

    it('المنتقي أصمّ عن السياق — يُبلّغ بردود نداء', () => {
        const code = codeOf(pickerSrc);
        for (const dep of ['notificationContext', 'services/firebase', 'firebase/firestore']) {
            expect(code.includes(dep),
                `المنتقي يستورد ${dep} — يفقد قابلية الاختبار بلا مزوّدات`).toBe(false);
        }
        for (const cb of ['onPick', 'onReject']) {
            expect(code.includes(cb), `${cb} مفقود`).toBe(true);
        }
    });

    it('حسابُ الدائرة خارج قطعة الخرائط (هندسةٌ خالصة)', () => {
        expect(/mapbox/i.test(codeOf(geoSrc)),
            'حسابُ الدائرة لا يحتاج mapbox — إبقاؤه حرّاً يتيح اختبارَه وحده').toBe(false);
        expect(codeOf(settingsSrc).includes('circleGeoJSON'),
            'Settings لم تعد تحسب الدائرة').toBe(false);
    });
});
