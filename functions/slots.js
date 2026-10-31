/**
 * نافذةُ شَغل السائق ومسندُ التداخل (slots)
 * ────────────────────────────────────────────────────────────────────────
 * سؤالٌ واحد بصياغتين: **إلى متى يَشغل هذا الطلبُ سائقَه، وهل يتداخل مع فترةٍ
 * أخرى؟** كان مكتوباً بيدٍ في ٢٣ موضعاً: مدّةُ الطلب في **١٦**، ومسحُ التعارض
 * (نافذة −٢٤س + مجموعةُ الحالات النشطة + مقارنةُ التداخل) في **٧**.
 *
 * وحدةٌ **نقيّة**: لا Firestore ولا وسيط `db` — تستقبل بياناتِ مستندٍ مقروءةً
 * سلفاً وتُعيد حساباً. الاستعلامُ يبقى في `index.js`، والقرارُ هنا.
 *
 * ═══ لمَ وُحِّد، ولم يكن فيه انحراف ═══
 *
 * فحصتُ المواضع السبعة أوّلاً بحثاً عن تباعد — ولم أجده: النوافذ كلّها −٢٤س،
 * ومجموعاتُ الحالات متطابقةٌ **مجموعةً** (تختلف ترتيباً فقط، ولا أثر لذلك في
 * استعلام `in`)، ومقارنةُ التداخل بالصيغة نفسها في الخمسة. والافتراضُ ٤ ساعات
 * في السادسة عشرة كلّها. فالتوحيدُ **وقائيّ**، وهذا ما يجعله مفيداً: تغييرُ
 * الافتراضي — قرارُ منتَجٍ محتمل — يلزمه اليوم تعديلُ ١٦ موضعاً معاً، وهو شكلُ
 * قصّة الضريبة نفسها (٢٧ موضعاً، ٥٪ ← ١٥٪، وموضعٌ منسيّ يُنتج خطأً صامتاً).
 *
 * ═══ `||` هنا صحيح، بخلاف `amounts.js` ═══
 *
 * هناك `??` واجب: صفرٌ صريح قرارٌ (طلبٌ مجّاني) و`||` يتخطّاه فيُحمّل العميلَ
 * ما لا يلزمه. وهنا العكس: **صفرُ ساعاتٍ ليس قراراً بل حقلٌ غير مضبوط**، فردُّه
 * إلى الافتراضي هو الصحيح. فنُبقي `||` عن قصد لا عن سهو.
 *
 * ═══ وفرقٌ كامن أُصلح: موضعُ `Number()` ═══
 *
 * كانت المواضع تكتب `Number(x.hours_contracted || 4)` — والقوسُ مهمّ: نصٌّ غير
 * رقميّ يُعطي `NaN`، فـ`new Date(start + NaN)` تصير `Invalid Date`، ومقارنةُ
 * التداخل مع `Invalid Date` **false** دائماً — أي **«السائق حرّ»**. فحقلٌ تالف
 * يُنتج حجزاً مزدوجاً بصمت، وهو أسوأ اتجاهٍ ممكن للخطأ. وهنا `Number(x) || 4`:
 * النصُّ التالف يسقط على الافتراضي المحافظ. **كامنٌ لا حيّ** — لا موضع في
 * المستودع يكتب `hours_contracted` نصّاً غير رقميّ (يُكتب `Number(md.hours || 4)`
 * أو عدداً) — والإصلاح وقائيّ، والتمييزُ جزءٌ من الصدق.
 */

"use strict";

/** مدّةُ الطلب الافتراضية بالساعات حين يغيب الحقل أو يكون صفراً/تالفاً. */
const ORDER_HOURS_DEFAULT = 4;

/** رجوعُ نافذة مسح التعارض بالساعات — انظر `conflictWindowStart`. */
const CONFLICT_LOOKBACK_HOURS = 24;

const MS_PER_HOUR = 60 * 60 * 1000;

/**
 * الحالاتُ التي **تَشغل** سائقاً فعلاً، فتدخل مسحَ التعارض.
 * `pending` خارجَها بقصد: طلبٌ لم يُسنَد لا يَشغل أحداً.
 */
const CONFLICT_STATUSES = [
  "scheduled", "assigned", "accepted", "on_the_way", "in_progress",
];

/**
 * مدّةُ الطلب بالساعات.
 * @param {?object} data بياناتُ مستند الطلب.
 * @param {*} [override] مدّةٌ صريحة تتقدّم على الحقل (التوجيه المباشر).
 * @return {number} ساعاتٌ موجبة — الافتراضيّ عند الغياب/الصفر/التلف.
 */
function orderHours(data, override) {
  // `override || field` لا فحصُ undefined/null: يطابق السلسلة الأصلية
  // `durationHours || orderData.hours_contracted || 4` حرفاً بحرف — فمدّةُ
  // تجاوزٍ صفرية ليست قراراً بل غياباً، فتسقط على الحقل لا على الافتراضي.
  const raw = override || (data ? data.hours_contracted : undefined);
  // `Number(x) || DEFAULT` لا `Number(x || DEFAULT)`: انظر ترويسة الملفّ —
  // الثانيةُ تُعطي NaN لنصٍّ تالف، وNaN يُقرأ «السائق حرّ».
  //
  // والمنطقيُّ مستثنىً صراحةً: `Number(true)` هو **1** في JS، فحقلٌ تالفٌ
  // قيمتُه `true` كان يُقرأ «مهمّةُ ساعةٍ واحدة» — أي ثلاثُ ساعاتٍ من انشغالِ
  // السائقِ تُقرأ فراغاً، وهو الاتجاهُ الخاطئُ نفسُه بوجهٍ آخر. وُجد بفحصِ
  // `capacity.js` على القيمِ التالفة.
  const n = typeof raw === "boolean" ? NaN : Number(raw);
  return n > 0 ? n : ORDER_HOURS_DEFAULT;
}

/**
 * نهايةُ فترة الطلب.
 * @param {Date} start بدايةُ الفترة.
 * @param {?object} data بياناتُ الطلب (لمدّته).
 * @param {*} [override] مدّةٌ صريحة.
 * @return {Date} لحظةُ الانتهاء.
 */
function orderEnd(start, data, override) {
  return new Date(start.getTime() + orderHours(data, override) * MS_PER_HOUR);
}

/**
 * بدايةُ نافذة مسح التعارض.
 *
 * −٢٤س لا −٨س: مهمّةٌ طويلة (باقاتُ السكن حتى ١٢ ساعة) تبدأ قبل الفترة المطلوبة
 * بأكثر من ٨ ساعات كانت تفوت المسح، فيُحجَز السائقُ لمهمّتين متداخلتين. والمدى
 * لازمٌ لأنّ Firestore تُرشّح بـ`service_date` (البداية) لا بالنهاية.
 * @param {Date} slotStart بدايةُ الفترة المطلوبة.
 * @return {Date} حدُّ الاستعلام الأدنى.
 */
function conflictWindowStart(slotStart) {
  return new Date(slotStart.getTime() - CONFLICT_LOOKBACK_HOURS * MS_PER_HOUR);
}

/**
 * هل يتداخل طلبٌ قائم مع الفترة المطلوبة؟
 *
 * المسندُ `slotStart < orderEnd && orderStart < slotEnd` — تماسٌّ على الحدّ
 * (نهايةُ أحدهما = بدايةُ الآخر) **ليس** تداخلاً، وهو ما كانت المواضع الخمسة
 * تفعله جميعاً. وطلبٌ بلا `service_date` لا يتداخل (كلُّ موضعٍ كان يتخطّاه).
 * @param {?object} orderData بياناتُ الطلب القائم.
 * @param {Date} slotStart بدايةُ الفترة المطلوبة.
 * @param {Date} slotEnd نهايةُ الفترة المطلوبة.
 * @return {boolean} صحيحٌ عند التداخل.
 */
function overlapsSlot(orderData, slotStart, slotEnd) {
  if (!orderData || !orderData.service_date ||
      typeof orderData.service_date.toDate !== "function") return false;
  const oStart = orderData.service_date.toDate();
  if (isNaN(oStart.getTime())) return false;
  return slotStart < orderEnd(oStart, orderData) && oStart < slotEnd;
}

// ═══ كم عاملةً يَحجزُ الطلب، ومَن هنّ (قرارُ المالك 2026-10-31) ═══
//
// السعةُ عددُ العاملاتِ المتوفّرات، والطلبُ يَتحقّقُ بتوفّرِ عددِ العاملاتِ
// غيرِ المشغولات — والكادرُ عاملةٌ واحدة. فطلبٌ بكادرَين يَحجزُ عاملتَين،
// لا واحدةً كما كان: الإسنادُ كان يَكتبُ `driver_id` واحداً مهما اختارت
// العميلة، فيُعرَضُ يومٌ «متاحاً» بعاملةٍ واحدةٍ فارغةٍ لطلبٍ يَحتاجُ ثلاثاً.
//
// `driver_id` يَبقى العاملةَ الأولى (كلُّ ما يَقرؤه — الرؤيةُ، الإشعار،
// النقلُ، التقييم — لا يَتغيّر)، و`worker_ids` قائمةُ المحجوزاتِ كلِّهنّ
// وأوّلُها `driver_id`. والانشغالُ يُقرأُ من القائمة **و**`driver_id` معاً
// (`orderWorkerIds`)، لأنّ الطلباتِ القديمةَ والمُسنَدةَ يدويّاً لا تَحملُ القائمة.

/** حدٌّ أعلى معقولٌ للعدد — قيمةٌ فوقه تالفةٌ لا اختيار. */
const MAX_WORKERS_PER_ORDER = 20;

/**
 * عددُ العاملاتِ الذي يَحتاجُه الطلب: `service_meta.crewCount` (باقاتُ السكن)،
 * ثمّ `service_meta.workers` (عاملاتُ المناسبات)، ثمّ `worker_count` (الحجزُ
 * بالساعة). القيمةُ الفاسدةُ تُتخطّى إلى التالي، وغيابُ الكلِّ ⇒ ١.
 * @param {object|null|undefined} order
 * @return {number}
 */
function orderWorkersNeeded(order) {
  const o = order || {};
  const meta = o.service_meta || {};
  for (const v of [meta.crewCount, meta.workers, o.worker_count]) {
    const n = Number(v);
    if (v !== null && v !== undefined && Number.isInteger(n) &&
        n >= 1 && n <= MAX_WORKERS_PER_ORDER) return n;
  }
  return 1;
}

/**
 * معرّفاتُ العاملاتِ اللاتي يَشغلُهنّ الطلب: `driver_id` ثمّ `worker_ids`، بلا تكرار.
 * @param {object|null|undefined} order
 * @return {string[]}
 */
function orderWorkerIds(order) {
  const o = order || {};
  const ids = [];
  if (typeof o.driver_id === "string" && o.driver_id) ids.push(o.driver_id);
  if (Array.isArray(o.worker_ids)) {
    for (const id of o.worker_ids) {
      if (typeof id === "string" && id && !ids.includes(id)) ids.push(id);
    }
  }
  return ids;
}

module.exports = {
  ORDER_HOURS_DEFAULT,
  CONFLICT_LOOKBACK_HOURS,
  CONFLICT_STATUSES,
  MAX_WORKERS_PER_ORDER,
  orderHours,
  orderEnd,
  conflictWindowStart,
  overlapsSlot,
  orderWorkersNeeded,
  orderWorkerIds,
};
