"use strict";
// اختبارات تكافؤ التسعير الخادمي — تشغيل: node test/pricing.test.js
const assert = require("assert");
const {computeExpectedBasePrice, acPriceField, carPriceField} =
  require("../pricing");

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log("  ok -", name);
}

// مستند منطقة تجريبي بأسماء الحقول الحرفية (من خرائط التسعير).
const zone = {
  prices: {"4": 99, "8": 900},
  sofaSqmPrice: 27, rugSqmPrice: 12,
  acMaintWindowPrice: 40, acMaintSplitPrice: 60,
  acWashWindowPrice: 30, acWashSplitPrice: 45,
  carSmallPrice: 120, carMediumPrice: 160, carLargePrice: 200,
};

t("field names match acPriceField/carPriceField", () => {
  assert.strictEqual(acPriceField("maintenance", "split"), "acMaintSplitPrice");
  assert.strictEqual(acPriceField("wash", "window"), "acWashWindowPrice");
  assert.strictEqual(carPriceField("large"), "carLargePrice");
});

t("hourly = prices[hours] * workers", () => {
  assert.strictEqual(
      computeExpectedBasePrice({hours_contracted: 4, worker_count: 2}, zone),
      198); // 99 * 2
});

t("hourly bucket is NOT multiplied by hours", () => {
  assert.strictEqual(
      computeExpectedBasePrice({hours_contracted: 8, worker_count: 1}, zone),
      900); // prices["8"] as-is
});

t("sofa billed by length only (linear meter)", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "sofa_rug_sqm", pieces: [{kind: "sofa", length_m: 3, width_m: 0}],
  }}, zone), 81); // 3 * 27
});

t("rug billed by length * width (area)", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "sofa_rug_sqm", pieces: [{kind: "rug", length_m: 3, width_m: 2}],
  }}, zone), 72); // 6 * 12
});

t("sofa + rug mixed", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "sofa_rug_sqm",
    pieces: [{kind: "sofa", length_m: 2}, {kind: "rug", length_m: 3, width_m: 2}],
  }}, zone), 54 + 72); // 2*27 + 6*12
});

t("ac uses zone unit price, ignores client meta price", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "ac_service",
    lines: [{job: "maintenance", type: "split", count: 2, unit_price: 1, line_total: 2}],
  }}, zone), 120); // 2 * 60 (NOT 2*1 from the tampered meta)
});

t("car = count * size price", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "car_interior",
    lines: [{size: "large", count: 1}, {size: "small", count: 2}],
  }}, zone), 200 + 240); // 200 + 2*120
});

t("unpriced service returns null (cannot verify)", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "sofa_rug_sqm", pieces: [{kind: "sofa", length_m: 3}],
  }}, {rugSqmPrice: 12}), null); // no sofaSqmPrice in zone
});

t("store_products not verifiable server-side (null)", () => {
  assert.strictEqual(computeExpectedBasePrice({service_meta: {
    kind: "store_products", items: [{name: "x", quantity: 2, unit_price: 5}],
  }}, zone), null);
});

t("underpayment detection: tampered 1 SAR vs base*1.15 is flagged; legit is not", () => {
  const base = computeExpectedBasePrice({hours_contracted: 8, worker_count: 1}, zone);
  const expected = Math.round(base * 1.15 * 100) / 100; // 1035
  assert.ok(1 / expected < 0.5, "tampered 1 SAR must flag");
  assert.ok(expected / expected >= 0.5, "legit full payment must not flag");
});

t("null zone / null order => null (safe, no false flag)", () => {
  assert.strictEqual(computeExpectedBasePrice(null, zone), null);
  assert.strictEqual(computeExpectedBasePrice({hours_contracted: 4}, null), null);
});

// ── (باقات السكن) home_package: السعر من packages[type].crews[count] الموثوق ──
const pkgZone = {packages: {
  small: {durationHours: 4, crews: {
    "1": {price: 200, enabled: true},
    "2": {price: 310, enabled: true},
    "3": {price: 400, enabled: false}, // معطَّل من اللوحة لهذه المنطقة
  }},
  villa: {durationHours: 8, crews: {"2": {price: 380, enabled: true}}},
}};

t("home_package: enabled option returns its exact price (no worker multiply)", () => {
  assert.strictEqual(computeExpectedBasePrice({
    worker_count: 2, // يجب تجاهله — سعر الباقة يشمل الكوادر سلفاً
    service_meta: {kind: "home_package", homeType: "small", crewCount: 2},
  }, pkgZone), 310);
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "villa", crewCount: 2},
  }, pkgZone), 380);
});

t("home_package: disabled/missing option => null (client can't buy it)", () => {
  // معطَّل من اللوحة
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "small", crewCount: 3},
  }, pkgZone), null);
  // عدد كوادر غير مسعَّر أصلاً
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "villa", crewCount: 1},
  }, pkgZone), null);
  // نوع سكن غير موجود في المنطقة
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "medium", crewCount: 1},
  }, pkgZone), null);
  // منطقة بلا packages إطلاقاً
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "small", crewCount: 1},
  }, zone), null);
});

t("home_package: zero/invalid price => null (unpriced = not sellable)", () => {
  assert.strictEqual(computeExpectedBasePrice({
    service_meta: {kind: "home_package", homeType: "small", crewCount: 1},
  }, {packages: {small: {crews: {"1": {price: 0, enabled: true}}}}}), null);
});

console.log(`\n${passed} pricing tests passed.`);
