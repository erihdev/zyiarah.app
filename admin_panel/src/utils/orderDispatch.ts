// مرآةُ قرارِ «لا سائقَ لطلبٍ غيرِ مدفوع» — الأصلُ
// `lib/utils/order_lifecycle.dart` (`orderPaidForDispatch` +
// `kUnpaidDispatchRefusal`)، والحارسُ الحقيقيُّ خادميٌّ في
// `functions/index.js` (`approveAndAssignOrder` يَرفضُ بالنصِّ نفسِه، قبلَ
// المعاملةِ وذرّياً داخلَها).
//
// **لمَ وُجدت:** القاعدةُ كانت مُنفَّذةً في أربعةِ مساراتٍ خادميّةٍ
// (`onOrderWritten` لا يُسنِدُ إلّا على انقلابِ `is_paid`، وكتلتا
// `sweepUnassignedPaidOrders` تتخطّيانِ `is_paid !== true`،
// و`capacity.countBookings` تتخطّاه، و`cancelStaleUnpaidOrders` تُلغيه)
// وغائبةً عن `approveAndAssignOrder` وحدَه — وهذه الصفحةُ أحدُ سطحَيه: زرُّ
// «تعيين سائق» كان يَظهرُ لكلِّ `pending` بلا أيِّ نظرٍ إلى الدفع، و`pending`
// بلا دفعٍ هي الحالةُ الطبيعيّةُ **قبلَ** الدفع.
//
// وإسنادُ غيرِ المدفوعِ ثلاثُ نتائج: يَخرجُ من مكنسةِ الإلغاءِ إلى الأبد
// (تَقرأُ `pending` وحدَها)، ويَشغلُ السائقَ في `CONFLICT_STATUSES` بلا أن
// يَستهلكَ سعةً فتُباعُ الساعةُ مرّةً أخرى لعميلةٍ تَدفعُ ثمّ تَعلقُ حتى
// الاستردادِ الآلي، ويُرسَلُ السائقُ وتَصِلُها دفعةُ «فريقنا في الطريق إليكِ».

import { ksaTodayDate } from './ksaInstant.ts';

/// هل يَجوزُ إسنادُ سائقٍ لهذا الطلبِ من حيثُ الدفع؟
///
/// القراءةُ `=== true` بقصد: الحقلُ الغائبُ أو التالفُ يُقرأُ **غيرَ مدفوع**،
/// وهو الاتّجاهُ المحافظ، وهو حرفيّاً ما تَقرؤه المساراتُ الخادميّةُ الأربعة.
export function orderPaidForDispatch(isPaid: unknown): boolean {
  return isPaid === true;
}

/// سببُ الرفضِ — مطابقٌ حرفيّاً للدارتِ وللخادم: صياغتانِ لقرارٍ واحدٍ هي ما
/// يُنتجُ هذا النوعَ من العطل، وكلا الجمهورَين هو الأدمن.
export const UNPAID_DISPATCH_REFUSAL =
  'لا يمكن إسناد سائق لطلب غير مدفوع — انتظر تأكيد الدفع';

// ——— «لا موعدَ في الماضي» ———
//
// مرآةُ `serviceDateAllowed` + `kPastServiceDateRefusal` في
// `lib/utils/order_lifecycle.dart`، وجدولُ حالاتِهما مشترَكٌ يَقرؤه
// `test/past_service_date_test.dart`. والحارسُ الحقيقيُّ خادميٌّ: نداءا
// `approveAndAssignOrder` و`rescheduleAssignedOrder` يَرفضانِ بالنصِّ نفسِه.
//
// **لمَ وُجدت:** أربعةُ مواضعَ تَكتبُ موعدَ الخدمةِ وكانت الأربعةُ تَقبلُ أيَّ
// تاريخٍ (الخادمُ يَفحصُ `isNaN` وحدَه، و`firestore.rules` صفرُ ذكرٍ
// لـ`service_date`)، وحقلا `datetime-local` في هذه الصفحةِ بلا `min` —
// **والصفحةُ الشقيقةُ تَحدُّ موعدَ البثِّ** بـ`min={minScheduleValue()}` في
// `Notifications.tsx`، فالقاعدةُ مُنفَّذةٌ في هذا السطحِ وغائبةٌ عن موعدِ
// الخدمةِ وحدَه.
//
// وموعدٌ ماضٍ يَخرُجُ من مكنسةِ الطلبِ المدفوعِ بلا سائق (‎−١٣س) ومن
// الاستردادِ الآليِّ (‎−٢٤س..−١س) ومن التذكيرِ (الآن..+٢٤س): مالٌ مقبوضٌ، ولا
// خدمةَ، ولا استردادَ، ولا تنبيه.

/// هل يَجوزُ هذا الموعدُ من حيثُ الماضي؟ [chosenWall] نصُّ `datetime-local`
/// (ساعةُ حائطٍ ساذجة) أو `Date` من ذلك النصّ.
///
/// الحدُّ **بدايةُ يومِ الرياضِ** لا «ليس قبلَ الآن»: دقّةُ المُنتقي يومٌ،
/// وساعةٌ مضت من اليومِ نفسِه موعدٌ مشروعٌ وداخلَ نافذةِ الـ١٣ ساعةً فقابلٌ
/// للاستعادة. و`nowMs` للفحصِ وحدَه.
export function serviceDateAllowed(chosenWall: string | Date, nowMs?: number): boolean {
  const s = chosenWall instanceof Date
    ? `${String(chosenWall.getFullYear()).padStart(4, '0')}-` +
      `${String(chosenWall.getMonth() + 1).padStart(2, '0')}-` +
      `${String(chosenWall.getDate()).padStart(2, '0')}`
    : String(chosenWall).slice(0, 10);
  // مقارنةُ نصٍّ لا لحظة: `YYYY-MM-DD` مُعجميّاً = زمنيّاً، فلا تَدخلُ منطقةُ
  // المتصفّحِ الحسابَ — وهو عينُ ما يَفعلُه `min` في الحقلِ نفسِه.
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  return s >= ksaTodayDate(nowMs);
}

/// سببُ الرفضِ — مطابقٌ حرفيّاً للدارتِ وللخادم.
export const PAST_SERVICE_DATE_REFUSAL =
  'لا يمكن ضبط موعد في الماضي — اختر اليوم أو تاريخاً بعده';
