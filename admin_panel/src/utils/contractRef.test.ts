import { describe, expect, it } from 'vitest';
import { contractRef, contractRefMatches } from './contractRef.ts';

// **جدولُ الحالاتِ واحدٌ بين اللغتَين، والنسخةُ المرجعيّةُ هنا**:
// `test/contract_ref_test.dart` يَقرأُ هذه الكتلةَ ويُقارِنُها `jsonDecode`اً.
// والاتّجاهُ هكذا بقرارٍ مسجَّل: `node:fs` بلا أنواعٍ تحتَ `tsconfig.app.json`
// فـ`npm run build` يَسقطُ بـTS2591 بينما `tsc --noEmit` و`vitest` و`eslint`
// كلُّها تَمُرّ — والملفُّ الدارتيُّ خارجَ جَذرِ Vite فلا تَبلغُه
// `import.meta.glob`. و`File()` في دارت تَقرأُ أيَّ مسار.
// CONTRACT_REF_CASES_START
const CASES: [unknown, string, string][] = [
    ["CTR-1234567", "aBcDeFgHiJkLmNoPqRsT", "CTR-1234567"],
    [null, "aBcDeFgHiJkLmNoPqRsT", "ABCDEFGH"],
    ["", "aBcDeFgHiJkLmNoPqRsT", "ABCDEFGH"],
    ["   ", "abc", "ABC"],
    ["  CTR-9  ", "xyz", "CTR-9"],
    [null, "short", "SHORT"],
    [null, "", ""],
    [7, "abcdefghij", "ABCDEFGH"]
];
// CONTRACT_REF_CASES_END

describe('contractRef — مرآةُ lib/utils/contract_ref.dart', () => {
    it('جدولُ الحالاتِ المشترَكُ لم يَنحلّ', () => {
        expect(CASES.length).toBeGreaterThanOrEqual(8);
    });

    it.each(CASES)('contractRef(%o, %s) = %s', (stored, docId, want) => {
        expect(contractRef(stored, docId)).toBe(want);
    });

    it('والمُطابَقةُ: الرقمُ المعروضُ أو المعرّفُ كاملاً', () => {
        const stored = 'CTR-1234567';
        const id = 'aBcDeFgHiJkLmNoPqRsT';
        // الرقمُ المطبوعُ على العقد — وهو ما كان البحثُ يَعمى عنه.
        expect(contractRefMatches(stored, id, 'CTR-1234567')).toBe(true);
        expect(contractRefMatches(stored, id, 'ctr-123')).toBe(true);
        // والمعرّفُ كاملاً — فالروابطُ والسجلّاتُ القديمةُ تَحملُه.
        expect(contractRefMatches(stored, id, 'kLmNo')).toBe(true);
        expect(contractRefMatches(stored, id, 'لا شيء')).toBe(false);
        expect(contractRefMatches(stored, id, '   ')).toBe(true);
        expect(contractRefMatches(null, id, 'abcdefgh')).toBe(true);
    });
});
