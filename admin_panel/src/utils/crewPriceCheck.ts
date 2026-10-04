// **مرآةُ** `lib/utils/crew_price_check.dart` — القاعدةُ نفسها، محرِّرانِ لها.
//
// انقلابُ سعرِ الكوادر: خيارٌ بكوادرَ **أكثر** بسعرٍ **أدنى** من خيارٍ أقلَّ
// منه كوادر، في نوعِ السكن نفسِه وفي المنطقة نفسِها.
//
// وُجد في بيانات الإنتاج (2026-10-04، «فيفا» / «فيلا أو دور»): كادرٌ واحد
// 347 ر.س وكادران 320 ر.س — فالعميلةُ ترى الخيارَين جنباً إلى جنب وتأخذ
// كادرَين بأقلَّ من كادر. ولا شيءَ في المحرِّرَين كان يقول شيئاً.
//
// **تنبيهٌ لا منع**: سعرٌ ترويجيٌّ مقصودٌ قرارٌ تجاريّ. ولا شيءَ في TypeScript
// ينكسر حين يتغيّر الأصلُ في Dart — لذلك لكلِّ جهةٍ اختبارُها.

export type CrewPriceInversion = {
  /** الخيارُ المخالف (الأكثرُ كوادرَ والأدنى سعراً). */
  crews: number;
  price: number;
  /** الخيارُ الأقلُّ كوادرَ الذي يتجاوزه سعراً (الأعلى سعراً بين من هم أدنى). */
  lowerCrews: number;
  lowerPrice: number;
};

/**
 * مواضعُ الانقلاب في نوعِ سكنٍ واحد.
 *
 * `prices` خياراتُ الكوادر **المفعّلة والمسعّرة** وحدَها: مفتاحٌ معطَّل أو سعرٌ
 * ≤ 0 لا يُعرض للعميل أصلاً («المعطَّل أو الصفر لا يظهر للعميل») فليس
 * انقلاباً. وغيرُ المنتهي (NaN/∞) يُستبعد: لا يُقارَن ما لا يُقاس.
 *
 * يُقارن كلُّ خيارٍ بأعلى سعرٍ بين الخيارات الأقلِّ منه كوادر — تقريرٌ واحدٌ
 * لكلِّ خيارٍ مخالف، لا لكلِّ زوج.
 */
export function crewPriceInversions(
  prices: Record<number | string, number>,
): CrewPriceInversion[] {
  const live = new Map<number, number>();
  for (const [k, v] of Object.entries(prices)) {
    const n = Number(k);
    if (!Number.isInteger(n)) continue;
    if (Number.isFinite(v) && v > 0) live.set(n, v);
  }
  const keys = [...live.keys()].sort((a, b) => a - b);
  const out: CrewPriceInversion[] = [];
  for (let i = 1; i < keys.length; i++) {
    let worstCrews = keys[0];
    let worstPrice = live.get(keys[0]) as number;
    for (let j = 1; j < i; j++) {
      const p = live.get(keys[j]) as number;
      if (p > worstPrice) { worstPrice = p; worstCrews = keys[j]; }
    }
    const price = live.get(keys[i]) as number;
    if (price < worstPrice) {
      out.push({ crews: keys[i], price, lowerCrews: worstCrews, lowerPrice: worstPrice });
    }
  }
  return out;
}

const CREW = (n: number): string =>
  n === 1 ? 'كادر واحد' : n === 2 ? 'كادران' : `${n} كوادر`;

/** نصُّ التنبيه — الصياغةُ نفسُها التي تُسمّي الخيارَ للعميلة. */
export function crewPriceInversionLabel(inv: CrewPriceInversion): string {
  return `${CREW(inv.crews)} بسعر ${inv.price.toFixed(2)} ر.س — أقلُّ من ` +
    `${CREW(inv.lowerCrews)} (${inv.lowerPrice.toFixed(2)} ر.س). ` +
    `العميلةُ ترى الخيارَين معاً.`;
}
