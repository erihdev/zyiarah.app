"use strict";

// أهلية السائق للإسناد — **قاعدة واحدة في موضع واحد** (قابلة للاختبار عبر
// `node test/drivers.test.js`، على نسق pricing.js و capacity.js).
//
// ═══ لماذا مُوحَّدت ═══
//
// القاعدة (H3) أن مستند `drivers/{id}` لا يُسنَد إليه طلب إلا إذا كان `id` حسابَ
// دخولٍ حقيقياً بدور سائق في `users/{id}`. سببها أن **معرّف مستند السائق قد لا
// يكون uid**: لوحة الويب كانت تُنشئ السائق بـ`addDoc` — مستند `drivers` بمعرّف
// عشوائي، بلا حساب Auth وبلا `users/{uid}` (انظر التعليق في
// `admin_panel/src/pages/Drivers.tsx`). أُصلح التوفير، **والمستندات القديمة
// باقية في القاعدة**.
//
// وإسناد طلبٍ لأحدها يُخفيه عن الجميع: تطبيق السائق وقواعد Firestore كلاهما
// يربط برؤية الطلب `request.auth.uid == resource.data.driver_id`
// (`firestore.rules:171`). فالطلب **مدفوع**، ويظهر للعميل «تم تعيين سائق»،
// ولا سائق يراه أبداً — لا رفضاً ولا تأخيراً، بل اختفاءً.
//
// والفئة الثانية: اللوحة تكتب `users/{uid}.role = staffType`، وقد يكون كادر
// تنظيف لا سائق توصيل. له حساب يعمل، لكنه ليس من يُسنَد إليه الطلب.
//
// ═══ وكانت القاعدة في موضعين من أربعة ═══
//
// تُفرَض في `_findFreeDriverForSlot` (المُسنِد الآلي) وفي `getHourlyAvailability`
// (عدّاد السعة — **يجب** أن يطابق المُسنِد: عدّادٌ يفوق ما يقبله المُسنِد كان
// يُظهر يوماً «متاحاً» فيدفع العميل ثم لا يجد المُسنِد سائقاً فيعلق الطلب حتى
// الاسترداد الآلي، وهذه حادثةٌ وقعت فعلاً وموثَّقة في تعليق العدّاد).
//
// ولا تُفرَض في `approveAndAssignOrder` ولا `rescheduleAssignedOrder` — وهما
// **المسارَان اللذان يستعملهما الأدمن بيده** للكنب والمكيفات والمتجر. فالمسار
// الآلي محصَّن والمسار اليدوي مكشوف. هذا ما يفعله التكرار: تُضاف القاعدة حيث
// ظهر العَرَض، ويُنسى الموضع الآخر الذي يحتاجها.
//
// فصارت هنا دالةً واحدة ينادونها الأربعة، و`test/drivers.test.js` يثبّت ذلك.

/** دور السائق في `users/{id}` — `staff_role` هو الدور الحقيقي ثم `role` احتياطاً. */
const DRIVER_ROLE = "driver";

/**
 * هل مستند `users/{id}` يحمل دور سائق؟
 *
 * `staff_role` هو الدور الفعلي (الكادر يحمل `role:'admin'` + `staff_role`)،
 * و`role` احتياطٌ للحسابات المُهيَّأة قديماً — نفس ترتيب `getUserRole()` في
 * القواعد وفي `_assertAdmin`.
 * @param {object|null|undefined} userData بيانات `users/{id}`، أو null إن لم يوجد
 * @return {boolean}
 */
function hasDriverRole(userData) {
  if (!userData) return false;
  return (userData.staff_role || userData.role) === DRIVER_ROLE;
}

/**
 * هل مستند `drivers/{id}` نشط؟
 *
 * الغياب يعني نشطاً (`!== false` لا `=== true`): المستندات القديمة بلا الحقل،
 * واعتبارها غير نشطة كان يُفرِغ الأسطول.
 * @param {object|null|undefined} driverData بيانات `drivers/{id}`
 * @return {boolean}
 */
// ═══ وعلَمانِ يُعطّلانِ، وهذا القارئُ كان يَعرفُ واحداً (2026-10-06) ═══
//
// حالةُ تعطيلِ السائقِ يَحملُها حقلانِ: `is_active` و`is_suspended` —
// تطبيقُ الإدارةِ كان يَكتبُ الأوّلَ ولوحةُ الويبِ الثاني، **فمستنداتُ
// الإنتاجِ تَحملُ هذا أو ذاك** (أُصلِحَ الكاتبانِ فصارا يَكتبانِ كليهما،
// والقديمُ باقٍ). و`unassignJobsOnDriverDisable` يَقرأُ **أيَّهما كفى**
// (`is_active === false || is_suspended === true`)، وهذا القارئُ كان
// `is_active` وحدَه.
//
// فسائقٌ حالتُه `{is_suspended: true, is_active: true}`:
//   ١. أُطلِقَ عند وَسمِه فأُلغيَ إسنادُ مهامِّه (عادت `pending`)؛
//   ٢. **وهو «قابلٌ للإسناد» عند هذا القارئ** — فمكنسةُ
//      `sweepUnassignedPaidOrders` (كلَّ خمسِ دقائق) أو `approveAndAssignOrder`
//      تُعيدُ العملَ إليه.
// أي أنّ إجراءَ المالكِ يُنقَضُ بصمت: اللوحةُ تَعرضُه «موقوفاً» ويَستمرُّ
// يَستقبلُ المهامّ. والقراءةُ هنا **تَضييقٌ بحتٌ** (تُعطّلُ أكثرَ ولا
// تُجيزُ أقلَّ)، و`is_suspended` لا يَكتبُه في المستودعِ كلِّه إلّا إجراءُ
// الإيقافِ الإداريُّ — فلا طريقَ لتعطيلٍ غيرِ مقصود.
function isActiveDriverDoc(driverData) {
  if (!driverData) return false;
  return driverData.is_active !== false && driverData.is_suspended !== true;
}

/**
 * **القاعدة**: هل يجوز إسناد طلب إلى هذا السائق؟ نشطٌ **و** حسابُ دخولٍ بدور سائق.
 *
 * لا تُدرِج الانشغال الزمني: السعة تعدّ المجموع والمُسنِد يستثني المشغول، وهما
 * سؤالان مختلفان عن هذا السؤال الواحد.
 * @param {object|null|undefined} driverData بيانات `drivers/{id}`
 * @param {object|null|undefined} userData بيانات `users/{id}` (null إن لم يوجد)
 * @return {boolean}
 */
function isAssignableDriver(driverData, userData) {
  return isActiveDriverDoc(driverData) && hasDriverRole(userData);
}

/**
 * سبب عدم الأهلية — رسالة عربية للأدمن، أو null إن كان مؤهَّلاً.
 *
 * تُفصِّل لأن المسار اليدوي يحتاج أن **يقول للأدمن ما العمل**، لا أن يرفض بصمت.
 * @param {object|null|undefined} driverData بيانات `drivers/{id}`
 * @param {object|null|undefined} userData بيانات `users/{id}` (null إن لم يوجد)
 * @return {string|null}
 */
function assignabilityProblem(driverData, userData) {
  if (!driverData) return "السائق غير موجود";
  if (!isActiveDriverDoc(driverData)) return "السائق غير نشط";
  if (!userData) {
    return "هذا السائق بلا حساب دخول — إسناد الطلب إليه يُخفيه عن الجميع " +
      "(لا أحد يراه ولا يمكن تتبّعه). أنشئ له حساباً من «إضافة سائق» أو اختر غيره.";
  }
  if (!hasDriverRole(userData)) {
    return "هذا الحساب ليس سائق توصيل — لا تظهر له الطلبات المُسنَدة. " +
      "اختر سائقاً، أو صحّح تصنيفه من شاشة الكادر.";
  }
  return null;
}

/**
 * يقسّم مصفوفة إلى قطع — لأن `getAll` نداءٌ واحد لكن حجم الطلب محدود.
 * @param {Array<*>} arr
 * @param {number} size
 * @return {Array<Array<*>>}
 */
function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < (arr || []).length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
}

/** حجم قطعة `getAll` — نداءٌ واحد لكل قطعة بدل نداءٍ لكل مستند. */
const GET_ALL_CHUNK = 300;

module.exports = {
  DRIVER_ROLE,
  GET_ALL_CHUNK,
  hasDriverRole,
  isActiveDriverDoc,
  isAssignableDriver,
  assignabilityProblem,
  chunk,
};
