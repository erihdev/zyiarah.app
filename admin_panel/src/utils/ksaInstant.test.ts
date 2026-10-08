import { describe, it, expect } from 'vitest';
import { ksaInstantOf, KSA_UTC_OFFSET_MS } from './ksaInstant';

// جدولُ الحالاتِ **نسخةٌ مطابقةٌ** لما بين العلامتَين في
// `test/ksa_instant_test.dart`، وفحصُ الدارتِ يَقرأُ هذا الملفَّ ويُقابِلُهما
// — فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقط.
// KSA_INSTANT_CASES_START
const CASES: [number[], string][] = [
    [[2026, 10, 9, 14, 0], "2026-10-09T11:00:00.000Z"],
    [[2026, 10, 9, 0, 0], "2026-10-08T21:00:00.000Z"],
    [[2026, 10, 9, 2, 59], "2026-10-08T23:59:00.000Z"],
    [[2026, 10, 9, 3, 0], "2026-10-09T00:00:00.000Z"],
    [[2026, 10, 9, 23, 30], "2026-10-09T20:30:00.000Z"],
    [[2026, 1, 1, 1, 15], "2025-12-31T22:15:00.000Z"],
    [[2026, 12, 31, 23, 0], "2026-12-31T20:00:00.000Z"],
    [[2026, 6, 15, 12, 45], "2026-06-15T09:45:00.000Z"],
];
// KSA_INSTANT_CASES_END

describe('ksaInstantOf', () => {
    it('يُطابقُ الجدولَ المشترَكَ، ومستقلٌّ عن منطقةِ المِحَكّ', () => {
        expect(CASES.length).toBeGreaterThanOrEqual(6);
        for (const [w, want] of CASES) {
            // المكوّناتُ هي ما يُقرَأ، فـ`new Date(y, m-1, d, h, min)` محلّيّةٌ
            // ومكوّناتُها هي ما مُرِّر — فالنتيجةُ واحدةٌ في أيِّ منطقة.
            const got = ksaInstantOf(new Date(w[0], w[1] - 1, w[2], w[3], w[4]));
            expect(got.toISOString()).toBe(want);
        }
    });

    it('التمثيلانِ يَتّفقان: أزِحْ +03 فتَعُدْ ساعةُ الحائط', () => {
        for (let h = 0; h < 24; h++) {
            const w = new Date(2026, 9, 9, h, 0);
            const back = new Date(ksaInstantOf(w).getTime() + KSA_UTC_OFFSET_MS);
            expect(back.getUTCHours()).toBe(h);
            expect(back.getUTCDate()).toBe(9);
        }
    });

    it('الإزاحةُ ثلاثُ ساعاتٍ — لا توقيتَ صيفيَّ في السعوديّة', () => {
        expect(KSA_UTC_OFFSET_MS).toBe(3 * 60 * 60 * 1000);
        // كانونُ الثاني وتمّوزُ سواءٌ: الإزاحةُ لا تَتبعُ الموسم.
        expect(ksaInstantOf(new Date(2026, 0, 15, 10, 0)).toISOString())
            .toBe('2026-01-15T07:00:00.000Z');
        expect(ksaInstantOf(new Date(2026, 6, 15, 10, 0)).toISOString())
            .toBe('2026-07-15T07:00:00.000Z');
    });
});
