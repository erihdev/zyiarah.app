// **صفرُ `maxUses` يَعني «بلا حدّ» — مرآةُ `lib/utils/coupon_uses.dart`.**
//
// الخادمُ صريحٌ (`functions/coupons.js`): `if (maxUses > 0 && uses >= maxUses)`
// — فصفرٌ أو غيابٌ أو غيرُ رقميٍّ يَعني **لا سقفَ إطلاقاً**. وجدولُ هذه اللوحةِ
// كان عُرفُه أنّ «بلا حدّ» رقمٌ كبيرٌ (`maxUses > 9999 ? '∞'`)، فكوبونٌ لا سقفَ
// له يُطبَعُ `0` ويُحسَبُ `uses / 0` فيُرسَمُ شريطاً **ممتلئاً أحمرَ** مع
// استخدامٍ موجب — «نَفِد» عن كوبونٍ مفتوح. وذاك العُرفُ كذبةٌ من الجهةِ
// الأخرى كذلك: سقفُ 10000 يُرسَمُ «∞» والخادمُ يُنفِّذُه.
//
// وجدولُ الحالاتِ مشترَكٌ: الكتلةُ في `couponUses.test.ts` يَقرؤها
// `test/coupon_uses_test.dart` ويُقارِنُها.

/** العددُ كما يَقرؤه الخادمُ: غيرُ الرقميِّ والغيابُ والسالبُ = صفرٌ («بلا حدّ»). */
export function couponMaxUses(raw: unknown): number {
    const n = typeof raw === 'number' ? raw : Number(raw ?? '');
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.trunc(n);
}

/** العددُ المستهلَك — نفسُ التسامح. */
export function couponUses(raw: unknown): number {
    const n = typeof raw === 'number' ? raw : Number(raw ?? '');
    if (!Number.isFinite(n) || n <= 0) return 0;
    return Math.trunc(n);
}

/** بلا سقفٍ — مرآةُ `maxUses > 0 &&` في `couponProblem`. */
export function couponIsUnlimited(rawMaxUses: unknown): boolean {
    return couponMaxUses(rawMaxUses) === 0;
}

/** نَفِدَ — مرآةُ `uses >= maxUses` بعد شرطِ السقف. */
export function couponIsExhausted(rawUses: unknown, rawMaxUses: unknown): boolean {
    const max = couponMaxUses(rawMaxUses);
    return max > 0 && couponUses(rawUses) >= max;
}

/** نصُّ السقفِ في رأسِ الشريط: «∞» حين لا سقفَ، لا رقمٌ صفريّ. */
export function couponMaxUsesLabel(rawMaxUses: unknown): string {
    return couponIsUnlimited(rawMaxUses) ? '∞' : String(couponMaxUses(rawMaxUses));
}

/** تقدّمُ الشريطِ 0..1، أو `null` حين لا سقفَ — فلا شريطَ بدلَ دعوى. */
export function couponUsesProgress(rawUses: unknown, rawMaxUses: unknown): number | null {
    const max = couponMaxUses(rawMaxUses);
    if (max <= 0) return null;
    const r = couponUses(rawUses) / max;
    return r < 0 ? 0 : (r > 1 ? 1 : r);
}
