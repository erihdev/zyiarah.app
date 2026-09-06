"use strict";
// إزالة إحداثيات الرياض الملفّقة من زيارات العقود + الفحص الهندسي للمنطقة —
// تشغيل: node test/zone_geo_and_visit_location.test.js (ضمن npm test).
//
// بنمط event_worker_contract_validation.test.js: نقرأ نص index.js ونقتطع أجسام
// الدوال الداخلية (غير exports.) بعدّ الأقواس ونبنيها دوالّ حقيقية عبر
// AsyncFunction/Function مع تمرير الاعتماديات الحرّة (admin/queuePush/...) كوهميات —
// تحقّق سلوكي فعلي دون محاكي Firestore ودون تهيئة index.js الثقيلة.
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

/**
 * يقتطع جسم دالة من index.js بعدّ الأقواس ابتداءً من توقيعها.
 * @param {string} sig بداية التوقيع (مثل "async function foo(").
 * @return {string} نص جسم الدالة (بين القوسين المعقوفين).
 */
function extractBody(sig) {
  const start = src.indexOf(sig);
  assert.ok(start >= 0, `${sig} غير موجودة في index.js`);
  const braceStart = src.indexOf("{", start);
  let depth = 0;
  let end = braceStart;
  for (; end < src.length; end++) {
    if (src[end] === "{") depth++;
    else if (src[end] === "}") {
      depth--;
      if (depth === 0) break;
    }
  }
  assert.ok(depth === 0, `أقواس غير متوازنة عند اقتطاع ${sig}`);
  return src.slice(braceStart + 1, end);
}

const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;

// الدوال قيد الاختبار (الاعتماديات الحرّة تُمرَّر معاملات إضافية):
const haversineM = new Function("lat1", "lng1", "lat2", "lng2",
    extractBody("function _haversineM("));
const flagZoneGeoMismatch = new AsyncFunction(
    "orderRef", "orderId", "od", "zoneData", "_haversineM", "queuePush",
    extractBody("async function _flagZoneGeoMismatch("));
const generateContractVisits = new AsyncFunction(
    "db", "contractRef", "c",
    "admin", "queuePush", "_findFreeDriverForSlot", "_assignDriverScheduled",
    extractBody("async function _generateContractVisits("));

// admin وهمي بالحدّ الأدنى الذي يلمسه جسم المولّد (بلا GeoPoint — أُزيل الملفّق).
const fakeAdmin = {
  firestore: {
    Timestamp: {fromDate: (d) => ({__ms: d.getTime()})},
    FieldValue: {serverTimestamp: () => "__server_ts__"},
  },
};

/**
 * db وهمي للمولّد: يسجّل كل orders.doc(id).set(payload) في saved.
 * @param {object} saved {معرّف_الطلب: payload}
 * @return {object} db وهمي.
 */
function fakeDb(saved) {
  return {
    collection(name) {
      assert.strictEqual(name, "orders", "المولّد يكتب في orders فقط");
      return {doc: (id) => ({id, set: async (p) => {
        saved[id] = p;
      }})};
    },
  };
}

/**
 * مسجّل queuePush وهمي.
 * @param {Array} calls مصفوفة تُملأ بـ{toUid, title, type, data}.
 * @return {Function} دالة async بنفس توقيع queuePush.
 */
function pushRecorder(calls) {
  return async (toUid, title, body, type, data, targetRoles) => {
    calls.push({toUid, title, body, type, data, targetRoles});
  };
}

const noDriver = async () => null;
const noAssign = async () => ({assigned: false});

let passed = 0;
/**
 * مُشغّل اختبار مصغّر بنمط pricing.test.js.
 * @param {string} name اسم الاختبار.
 * @param {Function} f جسم الاختبار.
 */
async function t(name, f) {
  await f();
  passed++;
  console.log("  ok -", name);
}

// نقاط مرجعية: الرياض ↔ جازان ≈ 970 كم — قصة العيب الأصلي نفسها.
const RIYADH = {latitude: 24.7136, longitude: 46.6753};
const JAZAN = {latitude: 16.8892, longitude: 42.5511};

(async () => {
  await t("(0) لا أثر لإحداثيات الرياض الملفّقة (24.7136) في index.js", async () => {
    assert.ok(!src.includes("24.7136"), "بقيت إحداثيات الرياض الملفّقة");
    // والمولّدان يختمان location_inherited (المسار الرئيسي نصيّاً — السلوكي أدناه).
    assert.ok(/location_inherited/.test(src));
  });

  await t("(a) عقد بلا موقع: زيارات بلا حقل location + location_inherited=true + " +
      "تنبيه إداري واحد للعقد كله", async () => {
    const saved = {};
    const pushes = [];
    const r = await generateContractVisits(fakeDb(saved), {id: "C1"}, {
      planVisits: 2, userId: "u1", userName: "عميلة", zone_name: "جازان",
      hours: 4, planName: "باقة أسبوعية",
      scheduled_visits: [
        {date: "2026-09-01", slot: "10:00"}, {date: "2026-09-08", slot: "12:00"},
      ],
    }, fakeAdmin, pushRecorder(pushes), noDriver, noAssign);
    assert.strictEqual(r.generated, 2);
    for (const id of ["sub_C1_1", "sub_C1_2"]) {
      assert.ok(saved[id], `لم يُكتب ${id}`);
      assert.ok(!("location" in saved[id]),
          "يجب ألّا يوجد حقل location إطلاقاً عند غياب موقع العقد");
      assert.strictEqual(saved[id].location_inherited, true);
    }
    const admin_ = pushes.filter((p) => p.toUid === "ADMIN_BROADCAST");
    assert.strictEqual(admin_.length, 1, "تنبيه إداري واحد لكل عقد لا لكل زيارة");
    assert.strictEqual(admin_[0].type, "admin_contract_no_location");
  });

  await t("(b) عقد بموقع مُلتقَط (location_captured=true): الموقع يُكتب و" +
      "location_inherited=false وبلا تنبيه", async () => {
    const saved = {};
    const pushes = [];
    await generateContractVisits(fakeDb(saved), {id: "C2"}, {
      planVisits: 1, userId: "u1", location: JAZAN, location_captured: true,
      scheduled_visits: [{date: "2026-09-01", slot: "10:00"}],
    }, fakeAdmin, pushRecorder(pushes), noDriver, noAssign);
    assert.deepStrictEqual(saved["sub_C2_1"].location, JAZAN);
    assert.strictEqual(saved["sub_C2_1"].location_inherited, false);
    assert.strictEqual(
        pushes.filter((p) => p.toUid === "ADMIN_BROADCAST").length, 0);
  });

  await t("(b2) عقد قديم بموقع لكن بلا location_captured: الموقع يُكتب لكن " +
      "location_inherited=true (قد يكون مركز منطقة لا عنواناً)", async () => {
    const saved = {};
    const pushes = [];
    await generateContractVisits(fakeDb(saved), {id: "C3"}, {
      planVisits: 1, userId: "u1", location: JAZAN,
      scheduled_visits: [{date: "2026-09-01", slot: "10:00"}],
    }, fakeAdmin, pushRecorder(pushes), noDriver, noAssign);
    assert.deepStrictEqual(saved["sub_C3_1"].location, JAZAN);
    assert.strictEqual(saved["sub_C3_1"].location_inherited, true);
    assert.strictEqual(
        pushes.filter((p) => p.toUid === "ADMIN_BROADCAST").length, 0);
  });

  await t("(c) هافرساين: صفر لنفس النقطة، درجة طول واحدة عند خط الاستواء " +
      "≈ 111.195 كم، والرياض↔جازان ≈ 970 كم", async () => {
    assert.strictEqual(haversineM(16.9, 42.5, 16.9, 42.5), 0);
    const oneDeg = haversineM(0, 0, 0, 1);
    assert.ok(Math.abs(oneDeg - 111195) < 120,
        `درجة الاستواء = ${oneDeg} خارج ±120م من 111195`);
    // تناظر
    assert.ok(Math.abs(haversineM(0, 0, 1, 0) - haversineM(1, 0, 0, 0)) < 1e-6);
    const rj = haversineM(RIYADH.latitude, RIYADH.longitude,
        JAZAN.latitude, JAZAN.longitude);
    assert.ok(rj > 950000 && rj < 990000, `الرياض↔جازان = ${rj}م خارج [950,990] كم`);
  });

  await t("(d) موقع خارج نصف القطر بفارق صارخ: وسم zone_geo_mismatch + مسافة + " +
      "تنبيه إداري واحد", async () => {
    const updates = [];
    const pushes = [];
    const orderRef = {update: async (u) => {
      updates.push(u);
    }};
    const od = {location: RIYADH, zone_name: "جازان", code: "555"};
    const zone = {centerLoc: JAZAN, radiusKm: 15};
    const dist = await flagZoneGeoMismatch(
        orderRef, "o1", od, zone, haversineM, pushRecorder(pushes));
    assert.ok(typeof dist === "number" && dist > 950000 && dist < 990000,
        `المسافة المُعادة ${dist} غير معقولة`);
    assert.strictEqual(updates.length, 1);
    assert.strictEqual(updates[0].zone_geo_mismatch, true);
    assert.strictEqual(updates[0].zone_geo_distance_m, dist);
    assert.strictEqual(pushes.length, 1);
    assert.strictEqual(pushes[0].toUid, "ADMIN_BROADCAST");
  });

  await t("(d2) داخل نصف القطر أو ضمن هامش الـ20%: لا وسم ولا تنبيه", async () => {
    const updates = [];
    const pushes = [];
    const orderRef = {update: async (u) => {
      updates.push(u);
    }};
    const zone = {centerLoc: JAZAN, radiusKm: 15};
    // ~9 كم من المركز (داخل 15 كم)
    let r = await flagZoneGeoMismatch(orderRef, "o2",
        {location: {latitude: 16.95, longitude: 42.60}, zone_name: "جازان"},
        zone, haversineM, pushRecorder(pushes));
    assert.strictEqual(r, null);
    // ~16 كم (فوق 15 لكن دون حدّ 15×1.2=18 كم — هامش الأطراف)
    r = await flagZoneGeoMismatch(orderRef, "o3",
        {location: {latitude: JAZAN.latitude + 0.1439, longitude: JAZAN.longitude},
          zone_name: "جازان"},
        zone, haversineM, pushRecorder(pushes));
    assert.strictEqual(r, null);
    assert.strictEqual(updates.length, 0);
    assert.strictEqual(pushes.length, 0);
  });

  await t("(d3) بيانات ناقصة أو وسم سابق: تجاهُل آمن بلا رمي", async () => {
    const pushes = [];
    const orderRef = {update: async () => {}};
    const zone = {centerLoc: JAZAN, radiusKm: 15};
    // بلا موقع على الطلب
    assert.strictEqual(await flagZoneGeoMismatch(orderRef, "o4",
        {zone_name: "جازان"}, zone, haversineM, pushRecorder(pushes)), null);
    // منطقة بلا مركز/نصف قطر
    assert.strictEqual(await flagZoneGeoMismatch(orderRef, "o5",
        {location: RIYADH}, {name: "جازان"}, haversineM,
        pushRecorder(pushes)), null);
    // مُعلَّم سلفاً (dedup): بعيد لكن zone_geo_mismatch=true — لا تكرار تنبيه
    assert.strictEqual(await flagZoneGeoMismatch(orderRef, "o6",
        {location: RIYADH, zone_geo_mismatch: true}, zone, haversineM,
        pushRecorder(pushes)), null);
    assert.strictEqual(pushes.length, 0);
  });

  console.log(`\nzone_geo_and_visit_location: ${passed} passed`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
