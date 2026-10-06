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

/**
 * يعدّ الطلبات التي تستهلك سائقاً في كل يوم/ساعة.
 * - تُستبعد الملغاة والمرفوضة وغير المدفوعة (is_paid !== true) والبلا booking_date.
 * - الطلب يشغل سائقاً طوال مدته: يُعدّ في كل ساعة من booking_time_slot إلى
 *   + مدّته من `slots.orderHours` (افتراضياً 4 عند الغياب/الصفر/التلف).
 * - `zoneDailyCounts`: طلبات المنطقة المسمّاة وحدها (zone_name === zoneName) —
 *   البسط الذي يُقاس على سقف المنطقة الخاص، بينما dailyCounts تعدّ الجميع
 *   لأن السائقين بلا مناطق (البسط والمقام من العالم نفسه).
 * @param {Array<object>} orders بيانات وثائق الطلبات
 * @param {{zoneName?: string|null}} opts
 * @return {{dailyCounts: object, slotCounts: object, zoneDailyCounts: object}}
 */
function countBookings(orders, {zoneName = null} = {}) {
  const dailyCounts = {};
  const slotCounts = {};
  const zoneDailyCounts = {};
  for (const d of orders || []) {
    if (!d) continue;
    if (d.status === "cancelled" || d.status === "rejected") continue;
    if (d.is_paid !== true) continue;
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
      if (!isNaN(startH)) {
        for (let h = startH; h < startH + hrs; h++) {
          const key = `${bDate}_${String(h).padStart(2, "0")}:00`;
          slotCounts[key] = (slotCounts[key] || 0) + 1;
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

module.exports = {countBookings, zoneDailyCap};
