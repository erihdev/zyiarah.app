// حارس المرآة: القاعدةُ نفسُها التي في `lib/utils/crew_price_check.dart`.
// الأصلُ Dart، وTypeScript لا ينكسر حين يتغيّر — فلكلِّ جهةٍ اختبارُها، وهذه
// الحالاتُ هي حالاتُ `test/crew_price_inversion_test.dart` نفسُها حرفاً بحرف.
import { describe, expect, it } from 'vitest';
import { crewPriceInversions, crewPriceInversionLabel } from './crewPriceCheck';

describe('انقلابُ سعر الكوادر', () => {
  it('تصاعدٌ سليم ⇒ لا انقلاب', () => {
    expect(crewPriceInversions({ 1: 301, 2: 515, 3: 700, 4: 900 })).toEqual([]);
  });

  it('تساوٍ ليس انقلاباً', () => {
    expect(crewPriceInversions({ 1: 300, 2: 300 })).toEqual([]);
  });

  it('الحالةُ الحقيقيّة: 347 لكادرٍ و320 لكادرَين', () => {
    const invs = crewPriceInversions({ 1: 347, 2: 320 });
    expect(invs).toEqual([{ crews: 2, price: 320, lowerCrews: 1, lowerPrice: 347 }]);
  });

  it('يُقارَن بأعلى سعرٍ أدنى كوادرَ لا بالسابق وحده', () => {
    const invs = crewPriceInversions({ 1: 100, 2: 500, 3: 300 });
    expect(invs).toEqual([{ crews: 3, price: 300, lowerCrews: 2, lowerPrice: 500 }]);
  });

  it('تقريرٌ واحدٌ لكلِّ خيارٍ مخالفٍ لا لكلِّ زوج', () => {
    const invs = crewPriceInversions({ 1: 500, 2: 100, 3: 200, 4: 300 });
    expect(invs.map(i => i.crews)).toEqual([2, 3, 4]);
    expect(invs.every(i => i.lowerCrews === 1 && i.lowerPrice === 500)).toBe(true);
  });

  it('المعطَّل والصفر خارج المقارنة', () => {
    expect(crewPriceInversions({ 1: 300, 2: 0 })).toEqual([]);
    expect(crewPriceInversions({ 1: 300, 2: -5 })).toEqual([]);
    const invs = crewPriceInversions({ 1: 300, 2: 0, 3: 250 });
    expect(invs).toEqual([{ crews: 3, price: 250, lowerCrews: 1, lowerPrice: 300 }]);
  });

  it('قيمةٌ غيرُ منتهية لا تُقارَن', () => {
    expect(crewPriceInversions({ 1: 300, 2: NaN })).toEqual([]);
    expect(crewPriceInversions({ 1: 300, 2: Infinity })).toEqual([]);
  });

  it('خيارٌ واحدٌ أو لا شيء ⇒ لا انقلاب', () => {
    expect(crewPriceInversions({})).toEqual([]);
    expect(crewPriceInversions({ 3: 400 })).toEqual([]);
  });

  it('ثغراتُ الترقيم لا تُربك الترتيب', () => {
    expect(crewPriceInversions({ 1: 400, 4: 350 }))
      .toEqual([{ crews: 4, price: 350, lowerCrews: 1, lowerPrice: 400 }]);
  });

  it('مفاتيحُ المحرِّر نصوصٌ لا أرقام (شكلُ النموذج الفعليّ)', () => {
    // `pkg.crews` في `Settings.tsx` مفاتيحُه '1'..'4' نصّيّة — لو لم تُحوَّل
    // لصار الترتيبُ معجميّاً ولانقلب معنى «أقلُّ كوادر».
    expect(crewPriceInversions({ '1': 347, '2': 320 }))
      .toEqual([{ crews: 2, price: 320, lowerCrews: 1, lowerPrice: 347 }]);
    expect(crewPriceInversions({ '10': 100, '2': 500 }))
      .toEqual([{ crews: 10, price: 100, lowerCrews: 2, lowerPrice: 500 }]);
  });

  it('خاصّيّة: أيُّ ترتيبٍ تصاعديٍّ لا يُنتج انقلاباً', () => {
    for (let a = 10; a <= 900; a += 70) {
      for (let b = a; b <= 1000; b += 90) {
        expect(crewPriceInversions({ 1: a, 2: b })).toEqual([]);
      }
    }
  });

  it('خاصّيّة: كلُّ نزولٍ يُنتج انقلاباً واحداً بفارقٍ صحيح', () => {
    for (let a = 100; a <= 900; a += 50) {
      for (let b = 1; b < a; b += 37) {
        const invs = crewPriceInversions({ 1: a, 2: b });
        expect(invs.length).toBe(1);
        expect(invs[0].lowerPrice - invs[0].price).toBe(a - b);
      }
    }
  });
});

describe('نصُّ التنبيه', () => {
  it('يُسمّي الخيارَين ويذكر السعرَين', () => {
    const s = crewPriceInversionLabel({ crews: 2, price: 320, lowerCrews: 1, lowerPrice: 347 });
    expect(s).toContain('كادران');
    expect(s).toContain('كادر واحد');
    expect(s).toContain('320.00');
    expect(s).toContain('347.00');
  });

  it('صياغةُ الثلاثة والأربعة جمعٌ لا مفرد', () => {
    const s = crewPriceInversionLabel({ crews: 3, price: 10, lowerCrews: 1, lowerPrice: 20 });
    expect(s).toContain('3 كوادر');
  });
});
