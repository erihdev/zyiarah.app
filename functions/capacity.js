"use strict";

// عدّ الحجوزات لحساب الإتاحة — دوال نقيّة بلا تبعيات (node test/capacity.test.js).
// كانت الحلقة داخل getHourlyAvailability في index.js؛ نُقلت هنا كما هي كي تُختبر،
// وأُضيف إليها عدّ المنطقة (سقف يومي اختياري لكل منطقة — قرار المالك 2026-09-16).

/**
 * يعدّ الطلبات التي تستهلك سائقاً في كل يوم/ساعة.
 * - تُستبعد الملغاة والمرفوضة وغير المدفوعة (is_paid !== true) والبلا booking_date.
 * - الطلب يشغل سائقاً طوال مدته: يُعدّ في كل ساعة من booking_time_slot إلى
 *   + hours_contracted (افتراضياً 4).
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
      const hrs = Number(d.hours_contracted || 4);
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
