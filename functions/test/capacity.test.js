"use strict";
// عدّ الإتاحة + سقف المنطقة اليومي — تشغيل: node test/capacity.test.js (ضمن npm test).
const assert = require("assert");
const {countBookings, zoneDailyCap} = require("../capacity");

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log("  ok -", name);
}

const paid = (over) => ({status: "scheduled", is_paid: true, booking_date: "2026-09-20",
  booking_time_slot: "09:00", hours_contracted: 4, zone_name: "الداير", ...over});

t("counts paid, non-cancelled orders per day and per occupied hour", () => {
  const r = countBookings([paid(), paid({booking_time_slot: "10:00", hours_contracted: 2})]);
  assert.strictEqual(r.dailyCounts["2026-09-20"], 2);
  assert.strictEqual(r.slotCounts["2026-09-20_09:00"], 1);
  assert.strictEqual(r.slotCounts["2026-09-20_10:00"], 2, "both occupy 10:00");
  assert.strictEqual(r.slotCounts["2026-09-20_11:00"], 2);
  assert.strictEqual(r.slotCounts["2026-09-20_12:00"], 1, "the 2-hour one ended");
  assert.strictEqual(r.slotCounts["2026-09-20_13:00"], undefined);
});

t("skips cancelled, rejected, unpaid, and orders without booking_date", () => {
  const r = countBookings([
    paid({status: "cancelled"}), paid({status: "rejected"}), paid({is_paid: false}),
    paid({booking_date: undefined}), null, paid({is_paid: "true"}),
  ]);
  assert.deepStrictEqual(r.dailyCounts, {});
  assert.deepStrictEqual(r.slotCounts, {});
});

t("default duration is 4 hours; a bad slot counts the day but no hours", () => {
  const r = countBookings([paid({hours_contracted: undefined}), paid({booking_time_slot: "x"})]);
  assert.strictEqual(r.dailyCounts["2026-09-20"], 2);
  assert.strictEqual(r.slotCounts["2026-09-20_12:00"], 1);
  assert.strictEqual(r.slotCounts["2026-09-20_13:00"], undefined);
});

// ═══ المدّةُ التالفةُ كانت تُصفّرُ عدَّ الساعات ═══
//
// كان العدُّ يكتب `Number(d.hours_contracted || 4)`: نصٌّ تالفٌ (أو سالبٌ)
// يُعطي `NaN`/قيمةً سالبة، فشرطُ الحلقة `h < startH + hrs` **كاذبٌ من أوّلِ
// دورة** — فالطلبُ يُعَدُّ في يومِه ولا يَشغلُ أيَّ ساعة، فتُقرأُ ساعاتُ
// سائقٍ مشغولٍ فارغةً. الآن من `slots.orderHours` فتسقطُ على ٤.
t("مدّةٌ تالفةٌ أو سالبةٌ تُحسَب ٤ ساعات — لا صفرَ ساعات", () => {
  for (const bad of ["abc", "4 ساعات", -2, NaN, null, true, {}]) {
    const r = countBookings([paid({hours_contracted: bad})]);
    assert.strictEqual(r.dailyCounts["2026-09-20"], 1, `يومُ ${bad}`);
    for (const h of ["09:00", "10:00", "11:00", "12:00"]) {
      assert.strictEqual(r.slotCounts[`2026-09-20_${h}`], 1,
          `الساعة ${h} عند مدّةٍ ${JSON.stringify(bad)} — صفرُ ساعاتٍ يُقرأ «السائق حرّ»`);
    }
    assert.strictEqual(r.slotCounts["2026-09-20_13:00"], undefined,
        "ولا تزيد على الافتراضي");
  }
});

t("مدّةٌ رقميّةٌ نصّاً أو كسريّةٌ تبقى كما كانت", () => {
  const str = countBookings([paid({hours_contracted: "2"})]);
  assert.strictEqual(str.slotCounts["2026-09-20_10:00"], 1);
  assert.strictEqual(str.slotCounts["2026-09-20_11:00"], undefined, "نصٌّ رقميّ = عدده");
  // كسريّة: تُغطّى بالتقريب لأعلى (الاتجاهُ المحافظ) كما كانت تماماً.
  const frac = countBookings([paid({hours_contracted: 2.5})]);
  assert.strictEqual(frac.slotCounts["2026-09-20_11:00"], 1);
  assert.strictEqual(frac.slotCounts["2026-09-20_12:00"], undefined);
});

t("zoneDailyCounts counts only the named zone; dailyCounts still counts everyone", () => {
  const r = countBookings([paid(), paid({zone_name: "فيفاء"}), paid({zone_name: undefined})],
      {zoneName: "الداير"});
  assert.strictEqual(r.dailyCounts["2026-09-20"], 3);
  assert.strictEqual(r.zoneDailyCounts["2026-09-20"], 1);
  const none = countBookings([paid()]);
  assert.deepStrictEqual(none.zoneDailyCounts, {}, "no zone requested → empty");
});

t("zoneDailyCap: positive integer or null", () => {
  assert.strictEqual(zoneDailyCap({max_orders_per_day: 3}), 3);
  assert.strictEqual(zoneDailyCap({max_orders_per_day: "2"}), 2);
  assert.strictEqual(zoneDailyCap({max_orders_per_day: 2.9}), 2);
  assert.strictEqual(zoneDailyCap({max_orders_per_day: 0}), null);
  assert.strictEqual(zoneDailyCap({max_orders_per_day: -1}), null);
  assert.strictEqual(zoneDailyCap({}), null);
  assert.strictEqual(zoneDailyCap(undefined), null);
  assert.strictEqual(zoneDailyCap({max_orders_per_day: "abc"}), null);
});

console.log(`\ncapacity tests: ${passed} passed`);
