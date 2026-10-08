// **مرآةُ `lib/utils/deletion_log_row.dart`** — سجلُّ حذفِ الحساب.
//
// القرارُ واحدٌ والصياغةُ تَتبعُ السطح. والسببُ أنّ هذه اللوحةَ كانت
// تَعرِضُ `name` فوقَ `phone`: `name` لا يَكتبُه كاتبٌ قطّ، و`phone`
// يَكتبُه مسارُ العميلةِ من `user?.phoneNumber` — والمصادقةُ **بالبريدِ
// وحدَه** فهو `null` دائماً. فكلُّ صفٍّ في سجلِّ امتثالِ آبل كان يُقرأُ
// «— / —»، و`email` **مكتوبٌ** ولا تَقرؤه اللوحةُ إطلاقاً.
//
// وحقلُ الدَّينِ `wallet_balance_at_deletion` — يَكتبُه الخادمُ «كي يبقى
// الدَّينُ مكتوباً في مكانٍ يَقرؤه البشرُ» — كان مكتوباً في موضعٍ
// **ومقروءاً في صفر**.
//
// جدولُ الحالاتِ مشترَكٌ مع فحصِ الدارت (بين العلامتَين في
// `test/account_deletion_log_test.dart`).

export interface DeletionRowFields {
    email?: unknown;
    name?: unknown;
    phone?: unknown;
    wallet_balance_at_deletion?: unknown;
}

/// الهويّةُ المعروضة: البريدُ ثمّ الاسمُ ثمّ الجوّال، وإلّا فلا ادّعاء.
export function deletionRowIdentity(d?: DeletionRowFields | null): string {
    for (const k of ['email', 'name', 'phone'] as const) {
        const s = String(d?.[k] ?? '').trim();
        if (s) return s;
    }
    return 'حساب مجهول';
}

/// الرصيدُ المحجوز، أو `null` فلا دَين. **لا رقمَ قبل أن نعرفه:** صفرٌ
/// ليس دَيناً، وغيابُ الحقلِ ليس صفراً.
export function deletionStrandedBalance(d?: DeletionRowFields | null): number | null {
    const raw = d?.wallet_balance_at_deletion;
    if (raw === null || raw === undefined) return null;
    const v = typeof raw === 'number' ? raw : Number(String(raw));
    if (!Number.isFinite(v) || v <= 0) return null;
    return v;
}
