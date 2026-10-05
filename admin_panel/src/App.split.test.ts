import { describe, it, expect } from 'vitest';
import appSrc from './App.tsx?raw';
import { PAGE_ROLES, canAccess } from './config/access.ts';

// حارس دائم: **تقسيم الحِزمة على المسارات لا يعود ملفاً واحداً.**
//
// كانت الصفحات السبعَ عشرة كلها مستورَدةً ثابتاً في App.tsx، فيُبنى ملفٌ واحد:
//
//   قبل:  index.js  3,025 kB   (841 kB مضغوطاً)   ← ينزّله كل أدمن قبل أول شاشة
//   بعد:  index.js    906 kB   (273 kB مضغوطاً)   + قطعة لكل صفحة
//
// وأثقل تبعية (mapbox-gl) يستوردها **ملفٌ واحد**: Settings. فصارت في قطعتها
// (1,918 kB) تُجلب حين تُفتح الإعدادات وحدها — ومحاسبٌ أو مسؤول تسويق لا يملك
// /settings أصلاً، فلا ينزّل محرّك الخرائط قط.
//
// **والانحدار صامت تماماً:** تحويلُ `lazy(() => import(...))` إلى استيرادٍ
// ثابتٍ واحد يُعيد تلك الصفحة — وكل ما تستورده — إلى الحِزمة الرئيسية، ولا
// يسقط أي فحصٍ آخر ولا يتغيّر شيء في الواجهة. يُرى في حجم البناء وحده، وأحدٌ
// لا يقرؤه. فهذا الحارس هو القارئ.

/** الصفحتان الثابتتان بقصد: الهبوط بعد الدخول، وأول ما يُرى قبله. */
const EAGER = ['Dashboard', 'Login'];

/** كل صفحة في المسارات — تُشتقّ من خريطة الأدوار كي لا تُنسى صفحةٌ جديدة. */
const ROUTE_PAGES = [
    'Settings', 'Orders', 'ScheduleBoard', 'Drivers', 'Users', 'Accountants',
    'Marketing', 'Notifications', 'Support', 'Admins', 'AccountDeletion',
    'Contracts', 'StoreProducts', 'StoreOrders', 'Payroll',
];

describe('تقسيم الحِزمة على المسارات', () => {
    it('كل صفحة مسار مؤجَّلة بـlazy', () => {
        const missing = ROUTE_PAGES.filter(
            p => !new RegExp(`const ${p} = lazy\\(\\(\\) => import\\('\\./pages/${p}\\.tsx'\\)\\)`).test(appSrc));
        expect(
            missing,
            'صفحات عادت إلى الاستيراد الثابت — فعادت شفرتها إلى الحِزمة الرئيسية ' +
            'التي ينزّلها كل أدمن:\n' + missing.map(m => `  - ${m}`).join('\n'),
        ).toEqual([]);
    });

    it('لا صفحة مسار مستورَدة ثابتاً', () => {
        // `import Orders from './pages/Orders.tsx'` يتجاوز التأجيل بلا أن يسقط
        // الفحص أعلاه إن بقي سطر lazy أيضاً (استيرادان لنفس الصفحة).
        const statics = ROUTE_PAGES.filter(
            p => new RegExp(`^import ${p} from '\\./pages/`, 'm').test(appSrc));
        expect(statics, `استيراد ثابت يتجاوز التأجيل:\n${statics.join('\n')}`).toEqual([]);
    });

    it('Dashboard وLogin ثابتتان بقصد — تأجيلهما يزيد زمن أول رسم', () => {
        for (const p of EAGER) {
            expect(
                new RegExp(`^import ${p} from '\\./pages/${p}\\.tsx'`, 'm').test(appSrc),
                `${p} يجب أن تبقى استيراداً ثابتاً`,
            ).toBe(true);
        }
    });

    it('حدّ Suspense لكل مسار لا حدّ واحد حول Routes', () => {
        // حدٌّ واحد حول <Routes> يُفرِغ الإطار (الشريط الجانبي والترويسة) أثناء
        // جلب القطعة، فيرى الأدمن شاشةً بيضاء عند كل تنقّل. وبالحدّ داخل
        // `guard` يبقى الإطار ويدور المؤشّر في منطقة المحتوى.
        expect(appSrc).toMatch(/<Suspense fallback={<PageSpinner \/>}>{element}<\/Suspense>/);
        expect(appSrc).toContain('function PageSpinner()');
    });

    it('بوّابة الأدوار بوّابةُ تنزيلٍ أيضاً: الممنوع لا تُجلب قطعته', () => {
        // `guard` تُعيد <Navigate> بدل العنصر المؤجَّل حين يُمنع الدور، فالعنصر
        // لا يُصيَّر ولا تُجلب قطعته. هذا يعتمد على **ترتيب** التعبير الشرطي،
        // فنثبّته: الشرط أوّلاً، ثم Suspense، ثم Navigate.
        expect(appSrc).toMatch(
            /canAccess\(role, path\)\s*\?\s*<Suspense[\s\S]*?:\s*<Navigate to="\/" replace \/>/);
    });

    it('mapbox محصور في Settings — وهي ممنوعة عن دورين، فلا ينزّلانها', () => {
        // أثقل تبعية في اللوحة. حصرُها شرطُ بقاء الحِزمة الرئيسية صغيرة، وقيمتها
        // تتضاعف بأن دورين لا يملكان /settings أصلاً.
        expect(canAccess('accountant_admin', '/settings')).toBe(false);
        expect(canAccess('marketing_admin', '/settings')).toBe(false);
        expect(canAccess('super_admin', '/settings')).toBe(true);
        // وكل صفحةٍ في الخريطة لها سطر مسار في App — كي لا تُضاف صفحةٌ جديدة
        // بلا تأجيل فتعود الحِزمة تنتفخ بصمت.
        const paths = Object.keys(PAGE_ROLES).filter(p => p !== '/');
        const unrouted = paths.filter(p => !appSrc.includes(`path="${p.slice(1)}"`));
        expect(unrouted, `مسار في خريطة الأدوار بلا سطر في App:\n${unrouted.join('\n')}`).toEqual([]);
    });

    // ─────────── والاتجاهُ المقابل: مسارٌ بلا بوّابة ───────────
    //
    // الفحصُ أعلاه يَمشي من الخريطةِ إلى `App`، فيَكشفُ صفحةً في الخريطةِ بلا
    // سطرِ مسار. والاتجاهُ الآخرُ كان مفتوحاً، **وهو الاتجاهُ الذي يَسرّب**:
    // `<Route path="x" element={<X />} />` بلا `guard` يَصلُه **كلُّ أدمنٍ
    // مسجَّلٍ** أيَّ دورٍ كان، ولا شيءَ في الواجهةِ يَتغيّرُ للسوبر ولا فحصٌ
    // يَسقط — نفسُ صمتِ «استيرادٌ ثابتٌ بدلَ lazy» الذي كُتب هذا الملفُّ له.
    // (وصفحةٌ بلا سطرٍ في الخريطةِ تُغلَقُ على الأدوارِ الفرعيّةِ لأنّ
    // `canAccess` تَسقطُ مُغلَقةً — عطلٌ في الاتجاهِ الآمن، ويُكشَفُ هنا كذلك.)
    describe('وكلُّ مسارٍ في App له بوّابةٌ وسطرٌ في الخريطة', () => {
        // كلُّ `<Route path="x" element={…}/>` — والفهرسُ (Dashboard) وLogin
        // خارجَ النمطِ أصلاً لأنّهما بلا `path="…"`.
        const routes = [...appSrc.matchAll(
            /<Route\s+path="([a-z-]+)"\s+element=\{([^\n]*)/g)]
            .map(m => ({path: '/' + m[1], element: m[2]}));

        it('وجدَ المساراتَ فعلاً — وإلّا فالفحصُ أجوف', () => {
            expect(routes.length).toBeGreaterThanOrEqual(15);
        });

        it('لا مسارَ بلا `guard` — وهو الاتجاهُ الذي يَسرّب', () => {
            const unguarded = routes
                .filter(r => !r.element.includes(`guard('${r.path}'`))
                .map(r => `${r.path} ⇒ ${r.element.trim().slice(0, 60)}`);
            expect(unguarded,
                `مسارٌ بلا بوّابةِ دور — يَصلُه كلُّ أدمن:\n${unguarded.join('\n')}`)
                .toEqual([]);
        });

        it('ولا مسارَ خارجَ خريطةِ الأدوار', () => {
            const unmapped = routes
                .map(r => r.path)
                .filter(p => !(p in PAGE_ROLES));
            expect(unmapped,
                `مسارٌ بلا سطرٍ في الخريطة — مُغلَقٌ على الأدوارِ الفرعيّة:\n${unmapped.join('\n')}`)
                .toEqual([]);
        });
    });
});
