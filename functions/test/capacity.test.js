"use strict";
// عدّ الإتاحة + سقف المنطقة اليومي — تشغيل: node test/capacity.test.js (ضمن npm test).
const assert = require("assert");
const {
  countBookings, zoneDailyCap, isLiveHold, HOLD_MINUTES, HOLD_MAX_WORKERS, HOLD_MAX_HOURS,
} = require("../capacity");

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

// ── الحجزُ المؤقّت ──
const NOW = Date.UTC(2026, 10, 17, 9, 0, 0);
const ts = (minsAgo) => ({toMillis: () => NOW - minsAgo * 60 * 1000});
const hold = (over) => paid({status: "pending", is_paid: false, client_id: "c1",
  created_at: ts(3), ...over});

t("حجزٌ مؤقّت: غيرُ مدفوعٍ حديثٌ يَشغلُ خانتَه ويومَه", () => {
  const r = countBookings([hold()], {nowMs: NOW});
  assert.strictEqual(r.dailyCounts["2026-09-20"], 1);
  assert.strictEqual(r.slotCounts["2026-09-20_09:00"], 1);
  assert.strictEqual(r.slotCounts["2026-09-20_12:00"], 1);
});

t("حجزٌ مؤقّت: يَسقطُ بعدَ المدّة، وعلى حدِّها بالضبط", () => {
  assert.deepStrictEqual(
      countBookings([hold({created_at: ts(HOLD_MINUTES)})], {nowMs: NOW}).dailyCounts, {});
  assert.deepStrictEqual(
      countBookings([hold({created_at: ts(HOLD_MINUTES + 20)})], {nowMs: NOW}).dailyCounts, {});
  assert.strictEqual(countBookings([hold({created_at: ts(HOLD_MINUTES - 1)})],
      {nowMs: NOW}).dailyCounts["2026-09-20"], 1);
});

t("حجزٌ مؤقّت: طلبُ السائلةِ نفسِها لا يَحجزُ عليها، وطلبُ غيرِها يَحجز", () => {
  const r = countBookings([hold(), hold({client_id: "c2"})],
      {nowMs: NOW, excludeClientId: "c1"});
  assert.strictEqual(r.dailyCounts["2026-09-20"], 1);
  assert.strictEqual(r.slotCounts["2026-09-20_09:00"], 1);
});

t("حجزٌ مؤقّت: بلا nowMs لا حجزَ (السلوكُ القديم)، وغيرُ pending لا يَحجز", () => {
  assert.deepStrictEqual(countBookings([hold()]).dailyCounts, {});
  for (const st of ["cancelled", "rejected", "scheduled", "under_review", undefined]) {
    assert.deepStrictEqual(
        countBookings([hold({status: st})], {nowMs: NOW}).dailyCounts, {}, String(st));
  }
});

t("حجزٌ مؤقّت: طابعٌ غائبٌ أو تالفٌ أو مستقبليٌّ لا يَحجز", () => {
  for (const c of [undefined, null, "2026-11-17", 5, {}, {toMillis: () => NaN},
    ts(-30)]) {
    assert.strictEqual(isLiveHold(hold({created_at: c}), {nowMs: NOW}), false);
  }
  assert.strictEqual(isLiveHold(hold({created_at: ts(-1)}), {nowMs: NOW}), true,
      "انحرافُ دقيقةٍ بين خادمَين مقبول");
  assert.strictEqual(isLiveHold(hold(), {nowMs: NaN}), false);
  assert.strictEqual(isLiveHold(null, {nowMs: NOW}), false);
});

t("حجزٌ مؤقّت: يُعَدُّ بالعاملاتِ كالمدفوع، والمدفوعُ لا يَتأثّرُ بالوقت", () => {
  const r = countBookings([hold({service_meta: {crewCount: 2}}),
    paid({created_at: ts(9999)})], {nowMs: NOW});
  assert.strictEqual(r.slotCounts["2026-09-20_09:00"], 3);
  assert.strictEqual(r.dailyCounts["2026-09-20"], 2);
});

t("الحجزُ أقصرُ من مهلةِ إلغاءِ غيرِ المدفوع، والخادمُ يُمرّرُ الوقتَ والسائلة", () => {
  const fs = require("fs");
  const path = require("path");
  const idx = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const m = idx.match(/exports\.cancelStaleUnpaidOrders[\s\S]*?Date\.now\(\) - (\d+) \* 60 \* 1000/);
  assert.ok(m, "مهلةُ مكنسةِ الإلغاءِ لم تُقرأ");
  assert.ok(HOLD_MINUTES < Number(m[1]),
      "الحجزُ يَجبُ أن يَنتهيَ قبلَ إلغاءِ الطلب");
  const i = idx.indexOf("exports.getHourlyAvailability");
  const body = idx.slice(i, idx.indexOf("\nexports.", i + 10));
  assert.ok(/countBookings\([\s\S]*?nowMs: Date\.now\(\),[\s\S]*?excludeClientId: request\.auth\.uid/.test(body),
      "getHourlyAvailability لا يُمرّرُ الحجزَ المؤقّت");
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

t("الساعةُ تُعَدُّ بالعاملات: طلبٌ بكادرَين يَشغلُ اثنتَين، واليومُ يَبقى بالطلبات", () => {
  const r = countBookings([
    paid({service_meta: {kind: "home_package", crewCount: 2}}),
    paid({booking_time_slot: "10:00", hours_contracted: 2, worker_count: 3}),
    paid({booking_time_slot: "10:00", hours_contracted: 1,
      service_meta: {kind: "event_workers", workers: 4}}),
  ]);
  assert.strictEqual(r.dailyCounts["2026-09-20"], 3, "السقفُ اليوميُّ حدُّ طلبات");
  assert.strictEqual(r.slotCounts["2026-09-20_09:00"], 2);
  assert.strictEqual(r.slotCounts["2026-09-20_10:00"], 2 + 3 + 4);
  assert.strictEqual(r.slotCounts["2026-09-20_11:00"], 2 + 3);
  assert.strictEqual(r.slotCounts["2026-09-20_12:00"], 2);
  const bad = countBookings([paid({service_meta: {crewCount: 0}})]);
  assert.strictEqual(bad.slotCounts["2026-09-20_09:00"], 1, "قيمةٌ تالفةٌ ⇒ عاملةٌ واحدة");
});

t("الحجزُ غيرُ المدفوعِ محدودٌ بأكبرِ ما يُباع، والمدفوعُ لا يُمَسّ", () => {
  const big = {booking_time_slot: "08:00", hours_contracted: 100000,
    service_meta: {kind: "home_package", crewCount: 20}};
  const h = countBookings([hold(big)], {nowMs: NOW}).slotCounts;
  assert.strictEqual(Object.keys(h).length, HOLD_MAX_HOURS, "المدّةُ مقصوصة");
  assert.strictEqual(h["2026-09-20_08:00"], HOLD_MAX_WORKERS, "العاملاتُ مقصوصات");
  assert.strictEqual(h["2026-09-20_19:00"], HOLD_MAX_WORKERS);
  assert.strictEqual(h["2026-09-20_20:00"], undefined);
  const p = countBookings([paid({booking_time_slot: "08:00", hours_contracted: 14,
    service_meta: {crewCount: 6}})]).slotCounts;
  assert.strictEqual(Object.keys(p).length, 14);
  assert.strictEqual(p["2026-09-20_08:00"], 6);
  const fs = require("fs");
  const path = require("path");
  const hp = fs.readFileSync(
      path.join(__dirname, "..", "..", "lib", "utils", "home_packages.dart"), "utf8");
  assert.ok(new RegExp(`const int kMaxCrews = ${HOLD_MAX_WORKERS};`).test(hp),
      "حدُّ العاملاتِ يَتبعُ kMaxCrews");
  assert.ok(hp.includes(`.clamp(1, ${HOLD_MAX_HOURS})`), "حدُّ المدّةِ يَتبعُ تثبيتَ الباقة");
});

console.log(`\ncapacity tests: ${passed} passed`);
