import { describe, it, expect } from 'vitest';
import {
    deletionRowIdentity, deletionStrandedBalance, deletionRequestState,
    deletionStateLabel, deletionRetryAllowed, deletionFailureReason,
    DELETION_STUCK_GRACE_MS,
} from './deletionLogRow.ts';

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

// ── حالةُ الطلبِ: جدولٌ مشترَكٌ ثانٍ ─────────────────────────────────────
// [status الخامّ، الحالة، التسمية] — يَقرؤه فحصُ الدارت ويُقارِنُه.
// وَ`'pending'` فيه عمداً: كان افتراضَ السطحَين وهو **لا كاتبَ له**.
// DELETION_STATE_CASES_START
const STATE_CASES: [unknown, string, string][] = [
    ['deleted', 'inProgress', 'جاري الحذف…'],
    ['deleted_fully_processed', 'completed', 'تم الحذف نهائياً'],
    ['failed_deletion', 'failed', 'فشل الحذف — يتطلب مراجعة'],
    ['rejected', 'rejected', 'مرفوض (طلب قديم)'],
    ['pending', 'unknown', 'حالة غير معروفة — راجِعْ المستند'],
    [null, 'unknown', 'حالة غير معروفة — راجِعْ المستند'],
    ['', 'unknown', 'حالة غير معروفة — راجِعْ المستند'],
    ['  deleted  ', 'inProgress', 'جاري الحذف…'],
    ['Deleted', 'unknown', 'حالة غير معروفة — راجِعْ المستند'],
    [7, 'unknown', 'حالة غير معروفة — راجِعْ المستند']
];
// DELETION_STATE_CASES_END

describe('حالةُ طلبِ الحذفِ وإعادةُ المحاولة', () => {
    it('جدولُ الحالاتِ والتسميات', () => {
        for (const [raw, state, label] of STATE_CASES) {
            expect(deletionRequestState(raw)).toBe(state);
            expect(deletionStateLabel(deletionRequestState(raw))).toBe(label);
        }
    });

    it('إعادةُ المحاولة: الفشلُ دائماً، والعالقُ بعدَ المُهلة، ولا شيءَ غيرُهما', () => {
        const now = 1_000_000_000_000;
        const old = now - DELETION_STUCK_GRACE_MS - 1;
        const fresh = now - 1000;
        expect(deletionRetryAllowed('failed', null, now)).toBe(true);
        expect(deletionRetryAllowed('failed', fresh, now)).toBe(true);
        expect(deletionRetryAllowed('inProgress', old, now)).toBe(true);
        expect(deletionRetryAllowed('inProgress', fresh, now)).toBe(false);
        expect(deletionRetryAllowed('inProgress', null, now)).toBe(false);
        expect(deletionRetryAllowed('completed', old, now)).toBe(false);
        expect(deletionRetryAllowed('rejected', old, now)).toBe(false);
        // الجهلُ لا يُعاد تشغيلُه: الحذفُ لا رجعةَ فيه.
        expect(deletionRetryAllowed('unknown', old, now)).toBe(false);
    });

    it('سببُ الفشلِ يُقرَأُ ويُقلَّم، والفراغُ لا شيء', () => {
        expect(deletionFailureReason({ error: 'auth/internal-error' }))
            .toBe('auth/internal-error');
        expect(deletionFailureReason({ error: '  x  ' })).toBe('x');
        expect(deletionFailureReason({ error: '' })).toBeNull();
        expect(deletionFailureReason({})).toBeNull();
        expect(deletionFailureReason(null)).toBeNull();
    });
});
