import { describe, it, expect } from 'vitest';
import { endOfLocalDay } from './couponExpiry';

// انتهاءُ الكوبونِ من اللوحة — الجانبُ الكاتب.
//
// اللوحةُ كانت تَكتب `expiry: newExpiry` — نصَّ `<input type="date">` خاماً —
// بينما محرّرُ Flutter يَكتب `Timestamp`. وفحصُ الخادمِ كان
// `typeof c.expiry.toMillis === "function"`، فالنصُّ لا يَملكه و**الفحصُ
// يُتخطّى كلَّه**: كلُّ كوبونٍ أُنشئ من اللوحةِ كان بلا انتهاءٍ خادميّاً.
// والعميلُ (Dart) يَفحصُ النوعَين — فكانت الواجهةُ أصرمَ من الخادم.

describe('endOfLocalDay', () => {
  it('آخرُ لحظةٍ من اليومِ لا أوّلُها — منتصفُ الليل يُميت الكوبونَ صبحَ يومِه',
    () => {
      const d = endOfLocalDay('2026-12-31');
      expect(d.getFullYear()).toBe(2026);
      expect(d.getMonth()).toBe(11);
      expect(d.getDate()).toBe(31);
      expect(d.getHours()).toBe(23);
      expect(d.getMinutes()).toBe(59);
      expect(d.getSeconds()).toBe(59);
      expect(d.getMilliseconds()).toBe(999);
    });

  it('يُبنى من المكوّناتِ لا من new Date(نصّ) — تلك تُفسَّر UTC فتُزيح', () => {
    // `new Date("2026-12-31")` منتصفُ ليلِ UTC = 03:00 بالرياضِ **بدايةَ** اليوم.
    const utcMidnight = new Date('2026-12-31');
    const ours = endOfLocalDay('2026-12-31');
    expect(ours.getTime()).toBeGreaterThan(utcMidnight.getTime());
    // واليومُ المحلّيُّ هو المكتوب، أيّاً كانت منطقةُ المتصفّح.
    expect(ours.getDate()).toBe(31);
  });

  it('كلُّ أيّامِ سنةٍ كاملة: اليومُ المحلّيُّ هو المكتوب، والساعةُ 23:59:59.999',
    () => {
      for (let m = 1; m <= 12; m++) {
        const last = new Date(2026, m, 0).getDate();
        for (let day = 1; day <= last; day++) {
          const ymd = `2026-${String(m).padStart(2, '0')}-` +
            `${String(day).padStart(2, '0')}`;
          const d = endOfLocalDay(ymd);
          expect(d.getMonth(), ymd).toBe(m - 1);
          expect(d.getDate(), ymd).toBe(day);
          expect(d.getHours(), ymd).toBe(23);
        }
      }
    });

  it('نصٌّ فارغٌ أو فاسدٌ = Invalid Date (لا 1970 مُلفَّقة)', () => {
    for (const bad of ['', 'غير تاريخ', '2026-13', 'x-y-z', '0000-00-00']) {
      expect(Number.isNaN(endOfLocalDay(bad).getTime()), bad).toBe(true);
    }
  });
});

describe('Marketing.tsx — عقدُ الكتابة', () => {
  const files = import.meta.glob('../pages/Marketing.tsx', {
    query: '?raw', import: 'default', eager: true,
  }) as Record<string, string>;
  const src = Object.values(files)[0];

  it('يَكتب Timestamp لا نصّاً — العطلُ الحيُّ بعينه', () => {
    expect(src).toContain('expiry: Timestamp.fromDate(endOfLocalDay(newExpiry))');
    expect(src).not.toMatch(/expiry:\s*newExpiry\s*,/);
    expect(src).toContain("from 'firebase/firestore'");
  });

  it('لا يُعلن endOfLocalDay محلّيّاً (التصديرُ من ملفِّ مكوّنٍ يَكسر fast-refresh)',
    () => {
      expect(src).not.toContain('export function endOfLocalDay');
      expect(src).toContain("from '../utils/couponExpiry'");
    });

  it('يَكتب show_in_offers ويَعرضُ مُبدِّلَه — غيابُه = لا، فكوبونُ اللوحةِ ' +
     'لم يكن يظهرُ في التطبيق أبداً', () => {
    expect(src).toContain('show_in_offers: newShowInOffers');
    expect(src).toContain('useState(true)');
    expect(src).toContain('aria-label="الظهور في قسم العروض"');
  });

  it('يَكتب description ويَعرضُ حقلَه — بطاقةُ العرضِ تُصيّره', () => {
    expect(src).toContain('description: newDescription.trim()');
    expect(src).toContain('aria-label="وصف الكوبون"');
  });

  it('مجموعةُ الحقولِ المكتوبةِ هي عينُها في المحرّرَين', () => {
    // المقارنةُ على المجموعةِ كلِّها (كما في amounts.test.js): حقلٌ تاسعٌ
    // يَسقطُ هنا فيُراجَع بوعي بدل أن يَفترقَ المحرّران بصمتٍ سنةً كاملة.
    const block = src.slice(src.indexOf("addDoc(collection(db, 'promo_codes')"));
    const fields = block.slice(0, block.indexOf('});'));
    const written = [...fields.matchAll(/^\s+([a-zA-Z_]+):/gm)]
      .map((m) => m[1]).sort();
    expect(written).toEqual([
      'code', 'createdAt', 'description', 'expiry', 'maxUses',
      'restricted_zones', 'show_in_offers', 'status', 'type', 'uses', 'value',
    ].sort());
  });
});
