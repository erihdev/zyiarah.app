/**
 * مرآةُ `lib/utils/order_activity.dart` — «ما الذي يَنتظرُ إجراءً إداريّاً؟».
 *
 * بطاقةُ لوحةِ المعلومات كانت «طلبات بانتظار الموافقة» من
 * `where('status','==','pending')` على `store_orders`، و**لا أحدَ يَكتبُ
 * `pending`** على طلبِ متجر: الدورةُ الحقيقيّةُ
 * `awaiting_payment ⇒ under_review ⇒ delivering ⇒ delivered`، وخطوةُ الموافقةِ
 * التي يُسمّيها العنوانُ أُلغيت بقرارِ المالك («لا موافقة قبل الدفع» —
 * `lib/services/store_service.dart`). فالرقمُ كان **صفراً أبداً**، بنيةً لا
 * عَرَضاً، بينما طلباتٌ مدفوعةٌ تَنتظرُ نقرةَ «جاري التوصيل».
 *
 * الحالتان هنا هما بالضبط ما تَعرضُ له شاشتا الإدارةِ زرّاً:
 * `under_review` ⇒ «جاري التوصيل»، و`delivering` ⇒ «تم التسليم».
 * `processing`/`shipped` إرثُ المسارِ القديمِ تُعامَلان نظيرتَيهما.
 *
 * المجموعتان **متطابقتان نصّاً** مع الملفِّ الدارتيّ، ويُثبّت ذلك
 * `test/order_activity_test.dart` بقراءةِ الملفَّين معاً — لا تعليقٌ وحده.
 */

/** حالاتٌ منتهية: خرج الطلبُ من العمل. */
export const TERMINAL_ORDER_STATUSES: readonly string[] = [
  'delivered',
  'completed',
  'cancelled',
  'rejected',
];

/** حالاتُ طلبِ المتجرِ التي تَنتظرُ نقرةً من الإدارة. */
export const STORE_NEEDS_ACTION_STATUSES: readonly string[] = [
  'under_review',
  'delivering',
  'processing',
  'shipped',
];

/** طلبٌ مفتوحٌ = حالتُه ليست منتهية. الغائبُ/الفارغُ مفتوح. */
export function orderIsOpen(status: unknown): boolean {
  const s = typeof status === 'string' ? status.trim() : '';
  return !TERMINAL_ORDER_STATUSES.includes(s);
}

/** طلبُ متجرٍ يَنتظرُ إجراءً إداريّاً. */
export function storeOrderNeedsAction(status: unknown): boolean {
  const s = typeof status === 'string' ? status.trim() : '';
  return STORE_NEEDS_ACTION_STATUSES.includes(s);
}
