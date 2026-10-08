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

// ── حالةُ الطلبِ ───────────────────────────────────────────────────────────
//
// **هذه اللوحةُ كانت تَرسمُ `'deleted'` «تم الحذف نهائياً» بعلامةٍ خضراءَ**
// مع `deleted_fully_processed`، وشاشةُ التطبيقِ تَقولُ «جاري المسح…»
// بالبرتقاليّ. و`'deleted'` يَعني «سُجِّلَ والخادمُ يَعملُ عليه»: لو ماتَ
// الحاوي بين `getAuth().deleteUser` وتحديثِ الحالة بقيَ المستندُ عليها إلى
// الأبد واللوحةُ تَقولُ إنّ الحذفَ تمَّ. وهذا سطحُ امتثالِ آبل.
//
// والأزرارُ كانت محصورةً بـ`status === 'pending'` **ولا كاتبَ لها في
// المستودع** (المساراتُ الأربعةُ تَكتبُ `'deleted'` مباشرةً)، فعدّادُ
// «معلّق» صفرٌ بنيويّاً وكلُّ إجراءٍ إداريٍّ غيرُ قابلِ الوصول — ومنه
// الفشلُ الذي يَقولُ عنه السطحُ نفسُه «يتطلب مراجعة».

export type DeletionRequestState =
    'inProgress' | 'completed' | 'failed' | 'rejected' | 'unknown';

/// حالةُ الطلبِ من حقلِ `status` الخامّ.
export function deletionRequestState(status?: unknown): DeletionRequestState {
    switch (String(status ?? '').trim()) {
        case 'deleted': return 'inProgress';
        case 'deleted_fully_processed': return 'completed';
        case 'failed_deletion': return 'failed';
        case 'rejected': return 'rejected';
        default: return 'unknown';
    }
}

/// تسميةُ الحالةِ للأدمن — نصُّ شاشةِ التطبيقِ حرفاً بحرف.
export function deletionStateLabel(s: DeletionRequestState): string {
    switch (s) {
        case 'inProgress': return 'جاري الحذف…';
        case 'completed': return 'تم الحذف نهائياً';
        case 'failed': return 'فشل الحذف — يتطلب مراجعة';
        case 'rejected': return 'مرفوض (طلب قديم)';
        case 'unknown': return 'حالة غير معروفة — راجِعْ المستند';
    }
}

/// مُهلةُ عدِّ `'deleted'` عالقاً (ساعةٌ — انظر تعليلَ الدارت).
export const DELETION_STUCK_GRACE_MS = 60 * 60 * 1000;

/// أتُعرَضُ إعادةُ المحاولة؟ `unknown` لا — لا نَعرفُ ما هو، وكتابةُ
/// `'deleted'` فوقَه حذفٌ لا رجعةَ فيه بناءً على جهل.
export function deletionRetryAllowed(
    state: DeletionRequestState, requestedAtMs: number | null, nowMs: number,
): boolean {
    if (state === 'failed') return true;
    if (state !== 'inProgress') return false;
    if (requestedAtMs === null) return false;
    return nowMs - requestedAtMs >= DELETION_STUCK_GRACE_MS;
}

/// سببُ الفشلِ كما كتبَه الخادمُ، أو `null`. **كان بلا قارئٍ في أيِّ سطح.**
export function deletionFailureReason(d?: { error?: unknown } | null): string | null {
    const s = String(d?.error ?? '').trim();
    return s === '' ? null : s;
}
