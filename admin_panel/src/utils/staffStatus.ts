// «هل حسابُ هذا الموظّفِ صالحٌ للعمل؟» — قاعدةٌ واحدةٌ تَقرأُ كلَّ علَمٍ
// يُعطِّلُه فعلاً، مرآةً لِما يُنفِّذُه الخادمُ والتطبيق.
//
// **العطل (2026-10-05):** جدولُ المشرفينَ في `Admins.tsx` كان يَرسمُ عمودَ
// الحالةِ من `admin.status !== 'inactive'` — و**لا شيءَ في المستودعِ كلِّه
// يَكتبُ `status: 'inactive'` على مستندِ مستخدم** (الكاتبُ الوحيدُ لتلك
// القيمةِ هو محرِّرُ الكوبونات، على مجموعةٍ أخرى). فالعمودُ كان «نشط» بعلامةٍ
// خضراءَ **أبداً**، في كلِّ مسارِ تعطيلٍ موجود:
//
//  * `is_active == false` على `users` — ما يَكتبُه مفتاحُ
//    `admin_managers_screen` (دفعةً على `admins` و`users`)، وما تَقرؤه
//    `firestore.rules` في `staffEnabled()` فتَرفضُ كلَّ مُعيِّناتِ الإدارةِ،
//    وما يَقرؤه `getUserRole` فيُعيدُ `null` ⇒ شاشةُ «الدورُ غيرُ متاح».
//  * `status == 'banned'` — تَكتبُه **هذه اللوحةُ نفسُها** من صفحةِ
//    المستخدمين (قائمتُها بلا مُرشِّحِ دورٍ، فصفوفُ الموظّفينَ فيها)،
//    ويَقرؤه `user_provider` فيُسجّلُ خروجَه فوراً.
//  * `is_blocked == true` — حظرٌ قديمٌ للمدير العامِّ/الكونسول، يَقرؤه
//    `user_provider` كذلك.
//
// فاللوحةُ كانت تُناقِضُ نفسَها: تَحظُرُ حساباً من صفحةٍ ثمّ تَقولُ عنه
// «نشط» في صفحةٍ أخرى — وهي قصّةُ `driverActivation.ts` بعينِها (شارةٌ تَقرأُ
// حقلاً والكاتبُ يَكتبُ غيرَه)، على المجموعةِ التي لم تَنَلْ ذلك الإصلاح.
//
// والحالةُ **ثلاثيّةٌ لا ثنائيّة**، لأنّ الفرقَ قرارٌ لا زينة: «موقوف» يَرفعُه
// مفتاحُ تطبيقِ الإدارة، و«محظور» لا يَرفعُه إلّا المديرُ العامُّ
// (`firestore.rules` تَحصُرُ `status`/`is_blocked` به) — فدمجُهما يُغري
// بمحاولةِ رفعٍ تَرفضُها القواعد.

export type StaffState = 'active' | 'suspended' | 'banned';

/** ما يَقرؤه الخادمُ والتطبيقُ — القائمةُ هنا للتوثيقِ ولشدِّ الحارس. */
export const STAFF_DISABLE_FIELDS = ['is_active', 'status', 'is_blocked'] as const;

export interface StaffActivityDoc {
  is_active?: boolean;
  is_blocked?: boolean;
  status?: string;
}

/**
 * الحظرُ يَغلِبُ الوقفَ: هو الأقوى أثراً (خروجٌ قسريٌّ) والأضيقُ رفعاً
 * (المديرُ العامُّ وحدَه)، فإظهارُه «موقوفاً» يُغري بمفتاحٍ لا يَرفعُه.
 *
 * وغيابُ `is_active` يَعني **مُفعَّلاً**، كما في `staffAccountDisabled`
 * و`staffEnabled()`: مستنداتُ الإنتاجِ القائمةُ لا تَحملُ الحقلَ، فاعتبارُ
 * غيابِه وقفاً كان سيُظهِرُ كلَّ موظّفٍ موقوفاً.
 */
export function staffState(u: StaffActivityDoc | null | undefined): StaffState {
  if (!u) return 'active';
  if (u.is_blocked === true || u.status === 'banned') return 'banned';
  if (u.is_active === false) return 'suspended';
  return 'active';
}

/** للمواضعِ التي تَسألُ سؤالاً ثنائيّاً (ترشيحٌ أو عَدّ). */
export function staffIsActive(u: StaffActivityDoc | null | undefined): boolean {
  return staffState(u) === 'active';
}
