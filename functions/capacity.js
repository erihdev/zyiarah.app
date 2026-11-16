"use strict";

// عدّ الحجوزات لحساب الإتاحة — بلا Firestore ولا وسيط `db` (node test/capacity.test.js).
// كانت الحلقة داخل getHourlyAvailability في index.js؛ نُقلت هنا كما هي كي تُختبر،
// وأُضيف إليها عدّ المنطقة (سقف يومي اختياري لكل منطقة — قرار المالك 2026-09-16).
//
// **ومدّةُ الطلبِ من `slots.js` لا من هنا.** كان هذا الملفُّ يكتبها بيده
// `Number(d.hours_contracted || 4)` — الموضعَ السابعَ عشَر لسلسلةٍ وُحِّدت في
// `slots.orderHours`، بالقوسِ الخاطئ الذي وُجد التوحيدُ لإصلاحه: نصٌّ تالفٌ
// (أو قيمةٌ سالبة) يُعطي `NaN`، و`h < startH + NaN` **كاذبٌ من أوّلِ دورة**،
// فالطلبُ يُعَدُّ في يومِه ولا يَشغلُ **أيَّ ساعة** — فتُقرأُ ساعاتُ سائقٍ
// مشغولٍ فارغةً، ويُعرَضُ على العميلةِ بدءٌ يَرفضُه المُسنِد بعد الدفع. وقد
// سبقَ لهذا الشكلِ أن شحنَ حادثةً: «يومٌ ظهرَ متاحاً، دُفِع، فلم يُوجَد سائقٌ
// مؤهَّل، فعلِقَ الطلبُ حتى الاسترداد الآلي». و`slots.js` **نقيّةٌ كذلك**،
// فالاعتمادُ عليها لا يَنقضُ قابليّةَ الاختبار بلا مُحاكٍ — وهو ما كانت
// عبارةُ «بلا تبعيات» تَحرُسُه حقّاً.
const slots = require("./slots");

// ── الحجزُ المؤقّت (2026-11-17، قرارُ المالك «منع الحجز المزدوج») ──────────
// البطاقةُ وSTC وتمارا تُنشئُ الطلبَ `pending` وغيرَ مدفوعٍ ثمّ تَفتحُ الدفع،
// والعدُّ كان يَتخطّى غيرَ المدفوعِ كلَّه — فعميلتانِ تَريانِ آخرَ خانةٍ حرّةً
// معاً وتَدفعانِ كلتاهما، ثمّ لا يَجدُ المُسنِدُ عاملةً للثانية فيَعلقُ طلبُها
// المدفوعُ حتى الاستردادِ الآليّ. فالطلبُ غيرُ المدفوعِ **الحديثُ** يَحجزُ خانتَه
// مدّةً قصيرةً تَكفي لإتمامِ الدفع، ثمّ يَسقطُ الحجزُ بنفسِه إن لم يُدفَع.
// المدّةُ أقصرُ من مهلةِ `cancelStaleUnpaidOrders` (٣٠ دقيقة) عمداً: الحجزُ
// يَنتهي قبلَ أن يُلغى الطلب، فلا خانةَ تُحبَسُ على طلبٍ ميّت.
const HOLD_MINUTES = 15;
const HOLD_MS = HOLD_MINUTES * 60 * 1000;
// انحرافُ ساعةٍ مقبولٌ بين خادمَين — طابعٌ «في المستقبل» بأكثرَ منه تالفٌ فلا يَحجز.
const HOLD_SKEW_MS = 2 * 60 * 1000;

/**
 * هل الطلبُ غيرُ المدفوعِ حجزٌ مؤقّتٌ حيّ؟ بلا `nowMs` لا حجزَ أصلاً (السلوكُ
 * القديم)، وطلبُ السائلةِ نفسِها لا يَحجزُ عليها (محاولةٌ سابقةٌ متروكةٌ لا
 * تَمنعُها من إعادةِ الحجز).
 * @param {object} d بيانات الطلب
 * @param {{nowMs?: number, excludeClientId?: string|null}} opts
 * @return {boolean}
 */
function isLiveHold(d, {nowMs, excludeClientId = null} = {}) {
  if (!Number.isFinite(nowMs) || nowMs <= 0) return false;
  if (!d || d.status !== "pending") return false;
  if (excludeClientId && d.client_id === excludeClientId) return false;
  const c = d.created_at;
  if (!c || typeof c.toMillis !== "function") return false;
  const age = nowMs - c.toMillis();
  return Number.isFinite(age) && age >= -HOLD_SKEW_MS && age < HOLD_MS;
}

/**
 * يعدّ الطلبات التي تستهلك سائقاً في كل يوم/ساعة.
 * - تُستبعد الملغاة والمرفوضة وغير المدفوعة (is_paid !== true) والبلا booking_date
 *   — إلّا غيرَ المدفوعِ الذي هو حجزٌ مؤقّتٌ حيّ (`isLiveHold`) متى مُرِّر `nowMs`.
 * - الطلب يشغل سائقاً طوال مدته: يُعدّ في كل ساعة من booking_time_slot إلى
 *   + مدّته من `slots.orderHours` (افتراضياً 4 عند الغياب/الصفر/التلف).
 * - `zoneDailyCounts`: طلبات المنطقة المسمّاة وحدها (zone_name === zoneName) —
 *   البسط الذي يُقاس على سقف المنطقة الخاص، بينما dailyCounts تعدّ الجميع
 *   لأن السائقين بلا مناطق (البسط والمقام من العالم نفسه).
 * @param {Array<object>} orders بيانات وثائق الطلبات
 * @param {{zoneName?: string|null, nowMs?: number, excludeClientId?: string|null}} opts
 * @return {{dailyCounts: object, slotCounts: object, zoneDailyCounts: object}}
 */
function countBookings(orders, {zoneName = null, nowMs, excludeClientId = null} = {}) {
  const dailyCounts = {};
  const slotCounts = {};
  const zoneDailyCounts = {};
  for (const d of orders || []) {
    if (!d) continue;
    if (d.status === "cancelled" || d.status === "rejected") continue;
    if (d.is_paid !== true && !isLiveHold(d, {nowMs, excludeClientId})) continue;
    const bDate = d.booking_date;
    if (!bDate) continue;
    dailyCounts[bDate] = (dailyCounts[bDate] || 0) + 1;
    if (zoneName && d.zone_name === zoneName) {
      zoneDailyCounts[bDate] = (zoneDailyCounts[bDate] || 0) + 1;
    }
    const ts = d.booking_time_slot;
    if (ts) {
      const startH = parseInt(String(ts).split(":")[0], 10);
      const hrs = slots.orderHours(d);
      // الساعةُ تُعَدُّ بالعاملاتِ لا بالطلبات (قرارُ المالك 2026-10-31): طلبٌ
      // بكادرَين يَشغلُ عاملتَين، والمقامُ `maxTeamsPerSlot` عددُ العاملات.
      // والسقفُ اليوميُّ (`dailyCounts`) يَبقى بالطلبات — هو حدُّ طلباتٍ لا عاملات.
      const workers = slots.orderWorkersNeeded(d);
      if (!isNaN(startH)) {
        for (let h = startH; h < startH + hrs; h++) {
          const key = `${bDate}_${String(h).padStart(2, "0")}:00`;
          slotCounts[key] = (slotCounts[key] || 0) + workers;
        }
      }
    }
  }
  return {dailyCounts, slotCounts, zoneDailyCounts};
}

/**
 * السقف اليومي الخاص بالمنطقة من مستندها: عدد صحيح موجب، أو null = لا سقف خاص
 * (0 أو غائب أو غير رقمي). يضيّق السقف العام فقط ولا يوسّعه أبداً.
 * @param {object|undefined} zoneData
 * @return {number|null}
 */
function zoneDailyCap(zoneData) {
  const n = Number(zoneData && zoneData.max_orders_per_day);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
}

module.exports = {countBookings, zoneDailyCap, isLiveHold, HOLD_MINUTES};
