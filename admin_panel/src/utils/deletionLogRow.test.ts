import { describe, it, expect } from 'vitest';
import { deletionRowIdentity, deletionStrandedBalance } from './deletionLogRow.ts';

// ── جدولُ الحالاتِ المشترَكُ بين اللغتَين ───────────────────────────────
// يَقرؤه `test/account_deletion_log_test.dart` ويُقارِنُه `jsonDecode`اً،
// فحالةٌ تُضافُ لجهةٍ دون الأخرى تَسقُط.
// DELETION_ROW_CASES_START
const CASES: [Record<string, unknown> | null, string, number | null][] = [
    [{ email: 'a@b.com', name: 'نورة', phone: '0500000000' }, 'a@b.com', null],
    [{ name: 'نورة', phone: '0500000000' }, 'نورة', null],
    [{ phone: '0500000000' }, '0500000000', null],
    [{}, 'حساب مجهول', null],
    [null, 'حساب مجهول', null],
    [{ email: '   ' }, 'حساب مجهول', null],
    [{ email: null, name: 'نورة' }, 'نورة', null],
    [{ email: 'a@b.com', wallet_balance_at_deletion: 172.5 }, 'a@b.com', 172.5],
    [{ wallet_balance_at_deletion: 0 }, 'حساب مجهول', null],
    [{ wallet_balance_at_deletion: -5 }, 'حساب مجهول', null],
    [{ wallet_balance_at_deletion: '172.5' }, 'حساب مجهول', 172.5],
    [{ wallet_balance_at_deletion: 'abc' }, 'حساب مجهول', null],
    [{ wallet_balance_at_deletion: true }, 'حساب مجهول', null]
];
// DELETION_ROW_CASES_END

describe('سجلُّ حذفِ الحساب — الهويّةُ والدَّين', () => {
    it('جدولُ الحالات', () => {
        for (const [d, identity, balance] of CASES) {
            expect(deletionRowIdentity(d)).toBe(identity);
            expect(deletionStrandedBalance(d)).toBe(balance);
        }
    });

    it('الصفرُ ليس دَيناً، وغيابُ الحقلِ ليس صفراً', () => {
        expect(deletionStrandedBalance({ wallet_balance_at_deletion: 0 })).toBeNull();
        expect(deletionStrandedBalance({})).toBeNull();
        expect(deletionStrandedBalance({ wallet_balance_at_deletion: 0.01 })).toBe(0.01);
    });
});
