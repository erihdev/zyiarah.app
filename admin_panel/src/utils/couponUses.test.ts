import { describe, it, expect } from 'vitest';
import {
    couponMaxUses, couponUses, couponIsUnlimited, couponIsExhausted,
    couponMaxUsesLabel, couponUsesProgress,
} from './couponUses';

// جدولُ الحالاتِ **مشترَكٌ**: `test/coupon_uses_test.dart` يَقرأُ هذه الكتلةَ
// ويُقارِنُها `jsonDecode`اً، فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
// الصفّ: [uses, maxUses, unlimited, exhausted, progress(null = لا شريط)]
// ⟦CASES⟧
const CASES: [unknown, unknown, boolean, boolean, number | null][] = [
    [0, 0, true, false, null],
    [5, 0, true, false, null],
    [0, null, true, false, null],
    [3, undefined, true, false, null],
    [7, 'abc', true, false, null],
    [2, -5, true, false, null],
    [0, 20, false, false, 0],
    [5, 20, false, false, 0.25],
    [20, 20, false, true, 1],
    [25, 20, false, true, 1],
    [0, 1, false, false, 0],
    [1, 1, false, true, 1],
    ['3', '12', false, false, 0.25],
    [0, 10000, false, false, 0],
];
// ⟦/CASES⟧

describe('couponUses', () => {
    it('(أ) الجدولُ المشترَك', () => {
        for (const [uses, max, unlimited, exhausted, progress] of CASES) {
            const l = `uses=${JSON.stringify(uses)} max=${JSON.stringify(max)}`;
            expect(couponIsUnlimited(max), `unlimited ${l}`).toBe(unlimited);
            expect(couponIsExhausted(uses, max), `exhausted ${l}`).toBe(exhausted);
            expect(couponUsesProgress(uses, max), `progress ${l}`).toBe(progress);
        }
    });

    it('(ب) «∞» للمفتوحِ ورقمٌ للمحدود — ولا عُرفَ «> 9999»', () => {
        expect(couponMaxUsesLabel(0)).toBe('∞');
        expect(couponMaxUsesLabel(null)).toBe('∞');
        expect(couponMaxUsesLabel(20)).toBe('20');
        // سقفٌ كبيرٌ **سقفٌ** لا «بلا حدّ»: الخادمُ يُنفِّذُه
        expect(couponMaxUsesLabel(10000)).toBe('10000');
        expect(couponIsUnlimited(10000)).toBe(false);
    });

    it('(ج) التسامحُ نفسُ تسامحِ الخادمِ في القراءة', () => {
        expect(couponMaxUses('12')).toBe(12);
        expect(couponMaxUses('')).toBe(0);
        expect(couponUses(undefined)).toBe(0);
        expect(couponUses(-3)).toBe(0);
    });
});
