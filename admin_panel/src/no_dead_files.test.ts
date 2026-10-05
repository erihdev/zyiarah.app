import { describe, it, expect } from 'vitest';

// **ملفٌّ لا يَستورِدُه أحدٌ لا يُحذِّرُ منه TypeScript** — تماماً كما لا يُحذّرُ
// Dart، وهو ما استدعى `test/no_dead_files_test.dart` في جانبِ التطبيق. هذا
// نظيرُه في اللوحة.
//
// ما وَجدَه أوّلُ تشغيلٍ له: `src/types/index.ts` — **103 أسطرٍ لا يَستورِدُها
// شيء**، وليست زائدةً فحسب بل **خريطةٌ خاطئةٌ لنموذجِ البيانات**، بقايا هيكلٍ
// عامٍّ لتطبيقِ نقلٍ لا علاقةَ له بزيارة:
//
//   • `Order` فيه `pickupLocation`/`dropoffLocation`/`driverId` و
//     `paymentMethod: 'cash' | 'card' | 'wallet'` — و**الدفعُ عند التسليمِ
//     أُزيل من الجذورِ بقرارِ المالك** (يَحرسُه `no_cod_test` في `lib/`).
//   • `OrderStatus` يَكتبُ `in-progress` بشَرطة، والقيمةُ الحقيقيّةُ
//     `in_progress` بشُرطةٍ سفليّة — ومعها تَغيبُ كلُّ الحالاتِ القائمة
//     (`awaiting_payment`, `under_review`, `scheduled`, `on_the_way`,
//     `delivering`, `delivered`).
//   • `Ticket.status: 'open' | 'in-progress' | 'closed'` — والمكتوبُ فعلاً
//     `open`/`replied`/`resolved`.
//   • `Driver.status: 'online' | 'offline' | 'busy' | 'suspended'` — والقائمُ
//     `available`/`en_route`/`in_service`، والأهليّةُ `is_active` + الدور.
//   • `AdminUser.role: 'Super Admin' | 'Accountant' | …` — والأدوارُ
//     `super_admin`/`orders_manager`/`accountant_admin`/`marketing_admin`.
//   • `Coupon` فيه `maxUsage`/`expiryDate` — والحقولُ `maxUses`/`expiry`.
//
// والفخُّ أنّ الواجهاتَ **متّسقةٌ مع نفسِها**، فمن يَبني صفحةً جديدةً عليها
// يَكتبُ أسماءَ حقولٍ وحالاتٍ خاطئةً و`tsc` راضٍ — ولا يَظهرُ الخللُ إلّا
// أمامَ مستندٍ حقيقيّ. الملفُّ محذوف، وكلُّ صفحةٍ تُصرّحُ بشكلِها محليّاً كما
// كانت تَفعلُ أصلاً (`Support.tsx` يُعرّفُ `Ticket` خاصّاً به).
//
// التعدادُ بـ`import.meta.glob` لا `node:fs`: الثاني بلا أنماطٍ تحت
// `tsconfig.app.json` وقد أسقطَ حارسَين هنا من قبل.

const RAW = import.meta.glob('./**/*.{ts,tsx}', { query: '?raw', import: 'default', eager: true }) as Record<string, string>;

// نقطةُ الدخولِ (يُحمّلها `index.html`) والاختباراتُ (يُشغّلها Vitest بالاسم).
const ENTRY = new Set(['./main.tsx']);
const isTest = (p: string) => /\.test\.tsx?$/.test(p);

describe('لا ملفَّ ميّتاً في اللوحة', () => {
  it('كلُّ ملفٍّ مُستورَدٌ من ملفٍّ آخرَ — أو نقطةُ دخولٍ/اختبار', () => {
    const dead: string[] = [];
    for (const path of Object.keys(RAW)) {
      if (ENTRY.has(path) || isTest(path)) continue;
      const stem = path.replace(/^.*\//, '').replace(/\.tsx?$/, '');
      const referenced = Object.entries(RAW).some(([other, src]) =>
        other !== path &&
        new RegExp(`['"][^'"]*/${stem}(\\.tsx?)?['"]|['"]\\./${stem}(\\.tsx?)?['"]`).test(src),
      );
      if (!referenced) dead.push(path);
    }
    expect(dead).toEqual([]);
  });

  it('والحارسُ يَقرأ ملفّاتٍ فعلاً (وإلّا فهو أجوف)', () => {
    expect(Object.keys(RAW).length).toBeGreaterThan(20);
    expect(RAW['./main.tsx']).toBeTruthy();
  });

  it('خريطةُ البياناتِ المهجورةُ لم تَعُد موجودة', () => {
    expect(RAW['./types/index.ts']).toBeUndefined();
    // ولا عادت القيمُ الخاطئةُ التي كانت فيها إلى أيِّ ملفٍّ آخر.
    for (const [path, src] of Object.entries(RAW)) {
      if (isTest(path)) continue;
      expect(src, `${path}: in-progress بشَرطة — القيمةُ in_progress`)
        .not.toContain("'in-progress'");
    }
  });
});
