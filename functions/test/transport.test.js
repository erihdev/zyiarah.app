"use strict";

// نقلُ العاملاتِ عبر مواصلات — تشغيل: node test/transport.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// (أ) القرارُ الصِّرف `decide`: متى تُطلَبُ رحلةُ ذهابٍ، ومتى عودةٍ، ومتى
//     تُلغى — جدولٌ على التغيُّرِ قبلَ/بعدَ، بلا Firestore.
// (ب) الحجزُ الذرّيُّ `claimLeg`: مُشغّلٌ يُعادُ إطلاقُه على كتابتِنا نفسِها
//     لا يَطلبُ الرحلةَ مرّتَين، و`replace` يَزيدُ الجيلَ ويُلغي السابقة.
// (ج) الفشلُ يُكتَبُ **ويُنبَّهُ عنه** — لا دفنَ صامتاً (قاعدةُ المستودع).
// (د) الويب هوك: حدثُ جيلٍ قديمٍ يُهمَل، وحدثٌ أدنى رتبةً لا يَرجِعُ بالحالة،
//     ورحلةٌ بمعرّفٍ آخرَ تُهمَل.
// (هـ) المكنسةُ: رحلةٌ لم تُقبَل والموعدُ قريبٌ ⇒ تنبيهٌ واحدٌ لا أكثر.
// (و) المصدر: الوحدةُ تَستقبلُ `db` ولا تَستوردُه؛ المدّةُ من `slots.js`؛
//     ولا عنوانَ لمواصلات ولا ترويسةَ مصادقةٍ خارجَ `mowasalat_api.js`.
// (ز) `mowasalat_api`: التوقيعُ يَفشلُ مُغلَقاً، والتحليلُ متسامح، ولا رميَ
//     على حالةِ HTTP، و404 عندَ الإلغاءِ يُقرَأُ «أُلغيت».
//
// العقدُ مع مواصلات **افتراضيٌّ** حتى تَصِلَ وثائقُهم؛ ما يُثبَّتُ هنا هو
// سلوكُنا نحن حيالَ أيِّ ردّ، لا شكلُ ردِّهم.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const transport = require("../transport");
const mowasalat = require("../mowasalat_api");

const ROOT = path.join(__dirname, "..");

let passed = 0;
const asyncTests = [];
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === "function") throw new Error("استعمل tAsync");
    console.log("  ok -", name);
    passed++;
  } catch (e) {
    console.error("  NOT OK -", name, "\n   ", e.message);
    process.exitCode = 1;
  }
}
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص (async)
 */
function tAsync(name, fn) {
  asyncTests.push([name, fn]);
}

// ══════════════ Firestore مزيّف (على نسق refund_engine.test.js) ══════════════
/**
 * @param {object} seed مستندات أوّلية {"orders/o1": {...}}
 * @return {object}
 */
function fakeDb(seed) {
  const store = new Map();
  // نسخٌ عميقٌ يُبقي كائناتِ الطوابعِ (ذاتَ toMillis) كما هي — JSON يُسقطُ الدوالّ.
  const clone = (v) => {
    if (!v || typeof v !== "object") return v;
    if (typeof v.toMillis === "function") return v;
    if (Array.isArray(v)) return v.map(clone);
    const o = {};
    for (const [k, x] of Object.entries(v)) if (x !== undefined) o[k] = clone(x);
    return o;
  };
  for (const [k, v] of Object.entries(seed || {})) store.set(k, clone(v));
  const writes = [];
  const setDotted = (obj, key, val) => {
    const ks = key.split(".");
    let cur = obj;
    for (let i = 0; i < ks.length - 1; i++) {
      if (!cur[ks[i]] || typeof cur[ks[i]] !== "object") cur[ks[i]] = {};
      cur = cur[ks[i]];
    }
    cur[ks[ks.length - 1]] = val;
  };
  const apply = (p, obj) => {
    if (!store.has(p)) store.set(p, {});
    const d = store.get(p);
    for (const [k, v] of Object.entries(obj)) setDotted(d, k, v);
  };
  const snapOf = (p) => {
    const d = store.get(p);
    return {exists: d !== undefined, id: p.split("/").pop(), data: () => d};
  };
  const mkRef = (p) => ({
    path: p, id: p.split("/").pop(),
    get: async () => snapOf(p),
    update: async (obj) => {
      writes.push({path: p, obj});
      apply(p, obj);
    },
  });
  const col = (c) => ({
    doc: (id) => mkRef(`${c}/${id}`),
    where: () => col(c),
    limit: () => col(c),
    get: async () => ({docs: [...store.keys()].filter((k) => k.startsWith(c + "/"))
        .map((k) => ({id: k.split("/").pop(), data: () => store.get(k)}))}),
  });
  return {
    _store: store, _writes: writes,
    collection: col,
    runTransaction: async (fn) => fn({
      get: async (ref) => snapOf(ref.path),
      update: (ref, obj) => {
        writes.push({path: ref.path, obj});
        apply(ref.path, obj);
      },
    }),
  };
}

/** @return {Function} طابورٌ مزيّفٌ يُسجّل */
function fakePush() {
  const calls = [];
  const fn = async (...a) => {
    calls.push(a);
  };
  fn.calls = calls;
  return fn;
}

/**
 * @param {object} cfg {create, cancel}
 * @return {object} مزوّدٌ مزيّف
 */
function fakeProvider(cfg) {
  const calls = [];
  return {
    name: "fake", cfg: {}, calls,
    api: {
      createRide: async (_c, req) => {
        calls.push(["create", req.reference]);
        if (cfg && cfg.createThrows) throw new Error("ECONNRESET");
        return (cfg && cfg.create) ||
          {ok: true, httpStatus: 201, rideId: "r_1", status: "requested", result: {}};
      },
      cancelRide: async (_c, id) => {
        calls.push(["cancel", id]);
        return (cfg && cfg.cancel) || {ok: true, httpStatus: 200, status: "cancelled", result: {}};
      },
      getRide: async () => ({ok: true, httpStatus: 200, status: null, result: {}}),
    },
  };
}

const NOW = new Date("2026-11-01T06:00:00Z"); // 09:00 الرياض
const ts = (ms) => ({toMillis: () => ms, toDate: () => new Date(ms)});
const TOMORROW = NOW.getTime() + 24 * 3600e3;
const CFG = {enabled: true, provider: "mowasalat", leadMinutes: 45, baseUrl: "https://x",
  hq: {lat: 17.15, lng: 42.62, label: "مقر زيارة"}};
const BASE = {
  code: "A-1", status: "scheduled", is_paid: true, client_id: "c1", client_name: "نورة",
  driver_id: "w1", driver_name: "فاطمة", driver_phone: "0501112222",
  location: {latitude: 17.2, longitude: 42.7}, service_date: ts(TOMORROW), hours_contracted: 4,
};
const deps = (p, q) => ({cfg: CFG, provider: p, queuePush: q, now: NOW});

// ═════════════════════════ (أ) القرار الصِّرف ═════════════════════════

t("(أ١) إسنادُ عاملةٍ لطلبٍ مدفوعٍ ذي موعدٍ ⇒ طلبُ ذهاب", () => {
  const before = {...BASE, driver_id: null, status: "pending"};
  assert.deepStrictEqual(transport.decide(before, BASE, NOW.getTime()),
      [{type: "request", leg: "outbound", replace: false}]);
});

t("(أ٢) غيرُ مدفوعٍ أو بلا موعدٍ أو موعدٌ مضى ⇒ لا شيء", () => {
  assert.deepStrictEqual(transport.decide({}, {...BASE, is_paid: false}, NOW.getTime()), []);
  assert.deepStrictEqual(transport.decide({}, {...BASE, service_date: null}, NOW.getTime()), []);
  assert.deepStrictEqual(transport.decide({}, {...BASE, service_date: ts(NOW.getTime() - 1)},
      NOW.getTime()), []);
});

t("(أ٣) كتابتُنا نحن (ذهابٌ حيٌّ موجود) لا تُعيدُ الطلب — لا رحلةَ مرّتَين", () => {
  const withOut = {...BASE, transport: {outbound: {state: "requested", gen: 1}}};
  assert.deepStrictEqual(transport.decide(withOut, withOut, NOW.getTime()), []);
});

t("(أ٤) تغيُّرُ الموعدِ أو العاملةِ على ذهابٍ حيٍّ ⇒ استبدال", () => {
  const withOut = {...BASE, transport: {outbound: {state: "accepted", gen: 1}}};
  assert.deepStrictEqual(transport.decide(withOut, {...withOut, service_date: ts(TOMORROW + 3600e3)},
      NOW.getTime()), [{type: "request", leg: "outbound", replace: true}]);
  assert.deepStrictEqual(transport.decide(withOut, {...withOut, driver_id: "w2"}, NOW.getTime()),
      [{type: "request", leg: "outbound", replace: true}]);
});

t("(أ٥) ذهابٌ فشل ثمّ تَغيّرَ الموعدُ ⇒ جيلٌ جديد؛ وبلا تغيُّرٍ ⇒ لا تكرارَ للفشل", () => {
  const failed = {...BASE, transport: {outbound: {state: "failed", gen: 1}}};
  assert.deepStrictEqual(transport.decide(failed, failed, NOW.getTime()), []);
  assert.deepStrictEqual(transport.decide(failed, {...failed, service_date: ts(TOMORROW + 1)},
      NOW.getTime()), [{type: "request", leg: "outbound", replace: false}]);
});

t("(أ٦) بعدَ التحرّك (on_the_way/in_progress) لا ذهابَ جديداً", () => {
  for (const st of ["on_the_way", "in_progress"]) {
    assert.deepStrictEqual(transport.decide(BASE, {...BASE, status: st}, NOW.getTime()), []);
  }
});

t("(أ٧) إنجازٌ ⇒ عودةٌ واحدة، ولا ثانيةَ إن وُجدت", () => {
  const done = {...BASE, status: "completed"};
  assert.deepStrictEqual(transport.decide({...BASE, status: "in_progress"}, done, NOW.getTime()),
      [{type: "request", leg: "return", replace: false}]);
  const withRet = {...done, transport: {return: {state: "requested", gen: 1}}};
  assert.deepStrictEqual(transport.decide({...BASE, status: "in_progress"}, withRet, NOW.getTime()), []);
  // إنجازٌ بلا عاملةٍ (خدمةٌ إداريّة) ⇒ لا عودة.
  assert.deepStrictEqual(transport.decide({...BASE, status: "in_progress", driver_id: null},
      {...done, driver_id: null}, NOW.getTime()), []);
});

t("(أ٨) إلغاءُ الطلبِ أو فكُّ الإسنادِ أو حذفُه ⇒ إلغاءُ الحيِّ فقط", () => {
  const live = {...BASE, transport: {outbound: {state: "accepted", gen: 2},
    return: {state: "cancelled", gen: 1}}};
  assert.deepStrictEqual(transport.decide(live, {...live, status: "cancelled"}, NOW.getTime()),
      [{type: "cancel", legs: ["outbound"]}]);
  assert.deepStrictEqual(transport.decide(live, {...live, driver_id: null, status: "pending"},
      NOW.getTime()), [{type: "cancel", legs: ["outbound"]}]);
  assert.deepStrictEqual(transport.decide(live, null, NOW.getTime()),
      [{type: "cancel", legs: ["outbound"]}]);
  // ولا شيءَ حيٌّ ⇒ لا نداءَ أصلاً.
  assert.deepStrictEqual(transport.decide(BASE, {...BASE, status: "cancelled"}, NOW.getTime()), []);
});

t("(أ٩) الإعداداتُ: غيابُ المستندِ أو enabled≠true ⇒ معطَّل، ومواصلات بلا مفتاحٍ ⇒ null لا محاكٍ", () => {
  assert.strictEqual(transport.normalizeConfig(null).enabled, false);
  assert.strictEqual(transport.normalizeConfig({enabled: "yes"}).enabled, false);
  const c = transport.normalizeConfig({enabled: true, hq_location: {latitude: 1, longitude: 2},
    lead_minutes: "30", api_base_url: "https://api.x"});
  assert.deepStrictEqual(c.hq, {lat: 1, lng: 2, label: "مقر المؤسسة"});
  assert.strictEqual(c.leadMinutes, 30);
  assert.strictEqual(transport.normalizeConfig({lead_minutes: -5}).leadMinutes,
      transport.DEFAULT_LEAD_MINUTES);
  assert.strictEqual(transport.selectProvider(c, {}), null);
  assert.strictEqual(transport.selectProvider(c, {apiKey: "k"}).name, "mowasalat");
  assert.strictEqual(transport.selectProvider({...c, provider: "simulator"}, {}).name, "simulator");
});

t("(أ١٠) طلبُ الرحلة: الذهابُ من المقرِّ قبلَ الموعدِ بمهلةٍ، والعودةُ من العميلةِ الآن، والراكبةُ هي العاملة", () => {
  const out = transport.buildRideRequest(BASE, CFG, "outbound", 3, "o1", NOW.getTime());
  assert.strictEqual(out.reference, "o1:outbound:3");
  assert.deepStrictEqual(out.pickup, CFG.hq);
  assert.strictEqual(out.dropoff.lat, 17.2);
  assert.strictEqual(out.pickupMs, TOMORROW - 45 * 60e3);
  assert.deepStrictEqual(out.passenger, {name: "فاطمة", phone: "0501112222"});
  const ret = transport.buildRideRequest(BASE, CFG, "return", 1, "o1", NOW.getTime());
  assert.strictEqual(ret.pickup.lat, 17.2);
  assert.deepStrictEqual(ret.dropoff, CFG.hq);
  assert.strictEqual(ret.pickupMs, NOW.getTime());
  assert.strictEqual(transport.buildRideRequest(BASE, {...CFG, hq: null}, "outbound", 1, "o1", 0), null);
  assert.strictEqual(transport.buildRideRequest({...BASE, location: null}, CFG, "outbound", 1, "o1", 0), null);
});

// ═════════════════════ (ب)(ج) المسارُ الكاملُ على db مزيّف ═════════════════════

tAsync("(ب١) الإسنادُ يَطلبُ الذهابَ مرّةً واحدةً ولو أُعيدَ إطلاقُ المُشغّل", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const p = fakeProvider();
  const q = fakePush();
  const before = {...BASE, driver_id: null, status: "pending"};
  const r1 = await transport.handleOrderChange(db, {orderId: "o1", before, after: BASE}, deps(p, q));
  assert.strictEqual(r1[0].outcome, "requested");
  const leg = db._store.get("orders/o1").transport.outbound;
  assert.strictEqual(leg.state, "requested");
  assert.strictEqual(leg.gen, 1);
  assert.strictEqual(leg.provider_ride_id, "r_1");
  assert.strictEqual(leg.reference, "o1:outbound:1");
  // إعادةُ الإطلاقِ على الوثيقةِ بعدَ كتابتِنا — بنفسِ قبلَ/بعدَ الإسناد كما قد يَصِلُ متأخّراً.
  const after2 = db._store.get("orders/o1");
  const r2 = await transport.handleOrderChange(db, {orderId: "o1", before, after: after2}, deps(p, q));
  assert.deepStrictEqual(r2, []);
  assert.deepStrictEqual(p.calls, [["create", "o1:outbound:1"]], "طُلبت الرحلةُ مرّتَين");
});

tAsync("(ب٢) حجزٌ متسابقٌ: claimLeg الثانيةُ على ساقٍ حيّةٍ تُعيدُ null", async () => {
  const db = fakeDb({"orders/o1": {...BASE, transport: {outbound: {state: "requesting", gen: 1}}}});
  assert.strictEqual(await transport.claimLeg(db, "o1", "outbound", false, "fake", NOW), null);
  const c = await transport.claimLeg(db, "o1", "outbound", true, "fake", NOW);
  assert.strictEqual(c.gen, 2);
});

tAsync("(ب٣) تغيُّرُ الموعدِ على ذهابٍ مقبولٍ ⇒ إلغاءُ القديمةِ عندَ المزوّدِ ثمّ جيلٌ ٢", async () => {
  const seeded = {...BASE, transport: {outbound: {state: "accepted", gen: 1, provider_ride_id: "r_old"}}};
  const db = fakeDb({"orders/o1": seeded});
  const p = fakeProvider({create: {ok: true, httpStatus: 201, rideId: "r_new", status: "requested", result: {}}});
  const q = fakePush();
  const after = {...seeded, service_date: ts(TOMORROW + 7200e3)};
  db._store.get("orders/o1").service_date = after.service_date;
  await transport.handleOrderChange(db, {orderId: "o1", before: seeded, after}, deps(p, q));
  assert.deepStrictEqual(p.calls, [["cancel", "r_old"], ["create", "o1:outbound:2"]]);
  const leg = db._store.get("orders/o1").transport.outbound;
  assert.strictEqual(leg.gen, 2);
  assert.strictEqual(leg.provider_ride_id, "r_new");
});

tAsync("(ج١) رفضُ المزوّدِ ⇒ failed مكتوبةٌ **وتنبيهٌ إداريٌّ** — لا دفنَ صامتاً", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const p = fakeProvider({create: {ok: false, httpStatus: 422, rideId: null, status: null,
    result: {message: "no coverage"}}});
  const q = fakePush();
  const r = await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE}, deps(p, q));
  assert.strictEqual(r[0].outcome, "failed");
  const leg = db._store.get("orders/o1").transport.outbound;
  assert.strictEqual(leg.state, "failed");
  assert.ok(leg.error.includes("422"));
  assert.strictEqual(q.calls.length, 1);
  assert.strictEqual(q.calls[0][0], "ADMIN_BROADCAST");
  assert.deepStrictEqual(q.calls[0][5], transport.ADMIN_ROLES);
  assert.ok(q.calls[0][2].includes("A-1"), "التنبيهُ لا يُسمّي الطلب");
});

tAsync("(ج٢) خطأُ شبكةٍ عندَ الإنشاء ⇒ failed لا استثناءً خارجاً من المُشغّل", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const p = fakeProvider({createThrows: true});
  const q = fakePush();
  const r = await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE}, deps(p, q));
  assert.strictEqual(r[0].outcome, "failed");
  assert.ok(db._store.get("orders/o1").transport.outbound.error.includes("ECONNRESET"));
  assert.strictEqual(q.calls.length, 1);
});

tAsync("(ج٣) بلا مقرٍّ في الإعدادات ⇒ failed بسببٍ مقروءٍ وتنبيه، ولا نداءَ للمزوّد", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const p = fakeProvider();
  const q = fakePush();
  await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE},
  {...deps(p, q), cfg: {...CFG, hq: null}});
  assert.strictEqual(db._store.get("orders/o1").transport.outbound.state, "failed");
  assert.ok(db._store.get("orders/o1").transport.outbound.error.includes("مقر"));
  assert.deepStrictEqual(p.calls, []);
  assert.strictEqual(q.calls.length, 1);
});

tAsync("(ج٤) معطَّلٌ أو بلا مزوّدٍ ⇒ لا كتابةَ على الطلبِ إطلاقاً", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const q = fakePush();
  const r = await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE},
  {cfg: {...CFG, enabled: false}, provider: fakeProvider(), queuePush: q, now: NOW});
  assert.strictEqual(r[0].outcome, "disabled");
  assert.deepStrictEqual(db._writes, []);
  const r2 = await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE},
  {cfg: CFG, provider: null, queuePush: q, now: NOW});
  assert.strictEqual(r2[0].outcome, "disabled");
  assert.deepStrictEqual(db._writes, []);
});

tAsync("(ج٥) الإنجازُ يَطلبُ العودةَ من بيتِ العميلةِ إلى المقرِّ الآن", async () => {
  const done = {...BASE, status: "completed", transport: {outbound: {state: "completed", gen: 1}}};
  const db = fakeDb({"orders/o1": done});
  const p = fakeProvider();
  const q = fakePush();
  await transport.handleOrderChange(db, {orderId: "o1", before: {...BASE, status: "in_progress"},
    after: done}, deps(p, q));
  assert.deepStrictEqual(p.calls, [["create", "o1:return:1"]]);
  assert.strictEqual(db._store.get("orders/o1").transport.return.state, "requested");
});

tAsync("(ج٦) إلغاءُ الطلبِ يُلغي الرحلةَ الحيّةَ عندَ المزوّدِ ويَكتبُ cancelled؛ وفشلُ الإبلاغِ يُنبَّهُ عنه", async () => {
  const live = {...BASE, transport: {outbound: {state: "accepted", gen: 1, provider_ride_id: "r_1"}}};
  const db = fakeDb({"orders/o1": {...live, status: "cancelled"}});
  const p = fakeProvider();
  const q = fakePush();
  await transport.handleOrderChange(db, {orderId: "o1", before: live,
    after: {...live, status: "cancelled"}}, deps(p, q));
  assert.deepStrictEqual(p.calls, [["cancel", "r_1"]]);
  assert.strictEqual(db._store.get("orders/o1").transport.outbound.state, "cancelled");
  assert.strictEqual(q.calls.length, 0);

  const db2 = fakeDb({"orders/o2": {...live, status: "cancelled"}});
  const p2 = fakeProvider({cancel: {ok: false, httpStatus: 500, status: null, result: {}}});
  const q2 = fakePush();
  await transport.handleOrderChange(db2, {orderId: "o2", before: live,
    after: {...live, status: "cancelled"}}, deps(p2, q2));
  assert.strictEqual(db2._store.get("orders/o2").transport.outbound.state, "cancelled");
  assert.strictEqual(q2.calls.length, 1);
});

tAsync("(ج٧) المحاكي يَقبلُ فوراً بسائقٍ وهميٍّ ولا يَلمسُ شبكة", async () => {
  const db = fakeDb({"orders/o1": BASE});
  const q = fakePush();
  const prov = transport.selectProvider({...CFG, provider: "simulator"}, {});
  await transport.handleOrderChange(db, {orderId: "o1",
    before: {...BASE, driver_id: null, status: "pending"}, after: BASE},
  {cfg: CFG, provider: prov, queuePush: q, now: NOW});
  const leg = db._store.get("orders/o1").transport.outbound;
  assert.strictEqual(leg.state, "accepted");
  assert.ok(leg.provider_ride_id.startsWith("sim_"));
  assert.strictEqual(leg.driver.name, "سائق تجريبي");
});

// ═════════════════════════════ (د) الويب هوك ═════════════════════════════

const seededLive = () => ({...BASE, transport: {outbound: {state: "requested", gen: 2,
  provider_ride_id: "r_1", reference: "o1:outbound:2"}}});

tAsync("(د١) حدثُ قبولٍ يَكتبُ الحالةَ والسائقَ ويُبلِّغُ العاملة", async () => {
  const db = fakeDb({"orders/o1": seededLive()});
  const q = fakePush();
  const r = await transport.applyRideEvent(db, {rideId: "r_1", reference: "o1:outbound:2",
    status: "accepted", driver: {name: "سالم", phone: "0509", plate: "أ ب ج 123"}, etaMinutes: 12},
  {queuePush: q, now: NOW});
  assert.strictEqual(r.applied, true);
  const leg = db._store.get("orders/o1").transport.outbound;
  assert.strictEqual(leg.state, "accepted");
  assert.strictEqual(leg.driver.name, "سالم");
  assert.strictEqual(leg.eta_minutes, 12);
  assert.strictEqual(q.calls.length, 1);
  assert.strictEqual(q.calls[0][0], "w1", "البلاغُ لحسابِ العاملةِ نفسِها");
});

tAsync("(د٢) جيلٌ قديمٌ، ورحلةٌ بمعرّفٍ آخر، ومرجعٌ معطوبٌ ⇒ تُهمَلُ بلا كتابة", async () => {
  const db = fakeDb({"orders/o1": seededLive()});
  const q = fakePush();
  for (const ev of [
    {rideId: "r_1", reference: "o1:outbound:1", status: "accepted"},
    {rideId: "r_other", reference: "o1:outbound:2", status: "accepted"},
    {rideId: "r_1", reference: "o1:outbound", status: "accepted"},
    {rideId: "r_1", reference: "o1:sideways:2", status: "accepted"},
    {rideId: "r_1", reference: "o1:outbound:2", status: null},
    {rideId: "r_1", reference: "nope:outbound:2", status: "accepted"},
  ]) {
    const r = await transport.applyRideEvent(db, ev, {queuePush: q, now: NOW});
    assert.strictEqual(r.applied, false, JSON.stringify(ev));
  }
  assert.deepStrictEqual(db._writes, []);
  assert.strictEqual(db._store.get("orders/o1").transport.outbound.state, "requested");
});

tAsync("(د٣) حدثٌ أدنى رتبةً لا يَرجِعُ بالحالة، والنهائيُّ لا يُكتَبُ فوقَه", async () => {
  const s = seededLive();
  s.transport.outbound.state = "arrived";
  const db = fakeDb({"orders/o1": s});
  const q = fakePush();
  const r = await transport.applyRideEvent(db, {rideId: "r_1", reference: "o1:outbound:2",
    status: "accepted"}, {queuePush: q, now: NOW});
  assert.deepStrictEqual(r, {applied: false, reason: "regress"});
  const r2 = await transport.applyRideEvent(db, {rideId: "r_1", reference: "o1:outbound:2",
    status: "completed"}, {queuePush: q, now: NOW});
  assert.strictEqual(r2.applied, true);
  const r3 = await transport.applyRideEvent(db, {rideId: "r_1", reference: "o1:outbound:2",
    status: "cancelled"}, {queuePush: q, now: NOW});
  assert.deepStrictEqual(r3, {applied: false, reason: "already_final"});
});

tAsync("(د٤) إلغاءٌ من جهةِ المزوّدِ ⇒ تنبيهٌ إداريٌّ", async () => {
  const db = fakeDb({"orders/o1": seededLive()});
  const q = fakePush();
  await transport.applyRideEvent(db, {rideId: "r_1", reference: "o1:outbound:2",
    status: "cancelled"}, {queuePush: q, now: NOW});
  assert.strictEqual(db._store.get("orders/o1").transport.outbound.state, "cancelled");
  assert.strictEqual(q.calls.length, 1);
  assert.strictEqual(q.calls[0][0], "ADMIN_BROADCAST");
});

// ═════════════════════════════ (هـ) المكنسة ═════════════════════════════

tAsync("(هـ١) ذهابٌ لم يُقبَل والموعدُ خلالَ ساعةٍ ⇒ تنبيهٌ واحدٌ؛ والبعيدُ والمقبولُ لا", async () => {
  const soon = NOW.getTime() + 40 * 60e3;
  const db = fakeDb({
    "orders/a": {...BASE, service_date: ts(soon),
      transport: {outbound: {state: "requested", gen: 1, pickup_at: ts(soon - 45 * 60e3)}}},
    "orders/b": {...BASE, service_date: ts(soon + 5 * 3600e3),
      transport: {outbound: {state: "requested", gen: 1, pickup_at: ts(soon + 4 * 3600e3)}}},
    "orders/c": {...BASE, service_date: ts(soon),
      transport: {outbound: {state: "accepted", gen: 1, pickup_at: ts(soon)}}},
  });
  const q = fakePush();
  const Timestamp = {fromDate: (d) => ts(d.getTime())};
  const n1 = await transport.sweepUnacceptedRides(db, {queuePush: q, now: NOW, Timestamp});
  assert.strictEqual(n1, 1);
  assert.strictEqual(q.calls[0][4].orderId, "a");
  const n2 = await transport.sweepUnacceptedRides(db, {queuePush: q, now: NOW, Timestamp});
  assert.strictEqual(n2, 0, "تنبيهٌ ثانٍ عن الرحلةِ نفسِها");
});

// ═════════════════════════════ (و) المصدر ═════════════════════════════

/**
 * @param {string} src
 * @return {string} بلا أسطرِ التعليق
 */
function codeOf(src) {
  return src.split("\n").filter((l) => !/^\s*(\/\/|\/?\*)/.test(l)).join("\n");
}

t("(و١) الوحدةُ تَستقبلُ db ولا تَستوردُه، ولا تَكتبُ المدّةَ بيدِها", () => {
  const raw = fs.readFileSync(path.join(ROOT, "transport.js"), "utf8");
  const src = codeOf(raw);
  for (const bad of ["getFirestore(", "getApp(", "initializeApp("]) {
    assert.ok(!src.includes(bad), `transport.js يستدعي ${bad})`);
  }
  assert.ok(src.includes("slots.orderHours("), "المدّةُ تُقرأُ من slots.js");
  assert.ok(!/hours_contracted\s*\|\|\s*4/.test(src), "مدّةٌ مكتوبةٌ بيد");
});

t("(و٢) لا عنوانَ لمواصلات ولا ترويسةَ مصادقةٍ خارجَ mowasalat_api.js", () => {
  const files = fs.readdirSync(ROOT).filter((f) => f.endsWith(".js") && f !== "mowasalat_api.js");
  for (const f of files) {
    const src = codeOf(fs.readFileSync(path.join(ROOT, f), "utf8"));
    assert.ok(!/\/v1\/rides/.test(src), `${f} يَكتبُ مسارَ مواصلات بيدِه`);
  }
  const api = codeOf(fs.readFileSync(path.join(ROOT, "mowasalat_api.js"), "utf8"));
  assert.ok(api.includes("\"Authorization\": `Bearer ${apiKey}`"), "الترويسةُ تُبنى في موضعٍ واحد");
  assert.ok((api.match(/Authorization/g) || []).length === 1, "الترويسةُ مكتوبةٌ أكثرَ من مرّة");
});

t("(و٣) الحقنُ وحدَه: handleOrderChange وapplyRideEvent تأخذانِ db أوّلاً", () => {
  const src = fs.readFileSync(path.join(ROOT, "transport.js"), "utf8");
  assert.ok(src.includes("async function handleOrderChange(db,"));
  assert.ok(src.includes("async function applyRideEvent(db,"));
  assert.ok(src.includes("async function sweepUnacceptedRides(db,"));
});

// ═════════════════════════ (ز) mowasalat_api ═════════════════════════

t("(ز١) التوقيعُ يَفشلُ مُغلَقاً: بلا سرٍّ أو بلا ترويسةٍ أو بطولٍ مختلفٍ ⇒ رفض", () => {
  const crypto = require("crypto");
  const body = Buffer.from("{\"a\":1}");
  const good = crypto.createHmac("sha256", "s").update(body).digest("hex");
  assert.strictEqual(mowasalat.verifySignature("s", body, good), true);
  assert.strictEqual(mowasalat.verifySignature("s", body, good.toUpperCase()), true);
  assert.strictEqual(mowasalat.verifySignature("", body, good), false);
  assert.strictEqual(mowasalat.verifySignature("s", body, undefined), false);
  assert.strictEqual(mowasalat.verifySignature("s", body, "abc"), false);
  const flipped = (good[0] === "0" ? "1" : "0") + good.slice(1);
  assert.strictEqual(mowasalat.verifySignature("s", body, flipped), false);
  assert.strictEqual(mowasalat.verifySignature("other", body, good), false);
});

t("(ز٢) خريطةُ الحالات: المعروفُ يُطبَّع، والمجهولُ null لا حالةً عشوائيّة", () => {
  assert.strictEqual(mowasalat.normalizeStatus("DRIVER_ASSIGNED"), "accepted");
  assert.strictEqual(mowasalat.normalizeStatus(" arrived "), "arrived");
  assert.strictEqual(mowasalat.normalizeStatus("teleported"), null);
  assert.strictEqual(mowasalat.normalizeStatus(undefined), null);
  const ev = mowasalat.parseWebhookEvent({event: "ride.updated",
    ride: {id: 77, reference: "o:outbound:1", status: "en_route", eta_minutes: "9",
      driver: {name: "س", phone: "05", vehicle_plate: "ق 1"}}});
  assert.deepStrictEqual(ev, {rideId: "77", reference: "o:outbound:1", status: "driving",
    driver: {name: "س", phone: "05", plate: "ق 1"}, etaMinutes: 9});
  assert.strictEqual(mowasalat.parseWebhookEvent(null).reference, null);
});

tAsync("(ز٣) لا رميَ على حالةِ HTTP، والتحليلُ متسامحٌ، و404 عندَ الإلغاءِ «أُلغيت»", async () => {
  const realFetch = global.fetch;
  const calls = [];
  try {
    global.fetch = async (url, opts) => {
      calls.push([url, opts]);
      if (url.endsWith("/cancel")) return {ok: false, status: 404, text: async () => "not json"};
      if (opts.method === "POST") return {ok: false, status: 503, text: async () => "<html>"};
      return {ok: true, status: 200, text: async () => JSON.stringify({status: "arrived"})};
    };
    const cfg = {baseUrl: "https://api.example/", apiKey: "K"};
    const c = await mowasalat.createRide(cfg, {reference: "r", pickup: {lat: 1, lng: 2, label: "a"},
      dropoff: {lat: 3, lng: 4, label: "b"}, pickupAt: "2026-01-01T00:00:00Z",
      passenger: {name: "n", phone: "p"}});
    assert.deepStrictEqual({ok: c.ok, httpStatus: c.httpStatus, rideId: c.rideId}, {ok: false, httpStatus: 503, rideId: null});
    assert.strictEqual(calls[0][0], "https://api.example/v1/rides", "شرطةُ النهايةِ تُزال");
    assert.strictEqual(calls[0][1].headers.Authorization, "Bearer K");
    const x = await mowasalat.cancelRide(cfg, "id 1");
    assert.deepStrictEqual({ok: x.ok, status: x.status}, {ok: true, status: "cancelled"});
    assert.ok(calls[1][0].includes("/v1/rides/id%201/cancel"));
    const g = await mowasalat.getRide(cfg, "z");
    assert.strictEqual(g.status, "arrived");
    global.fetch = async () => {
      throw new Error("down");
    };
    const g2 = await mowasalat.getRide(cfg, "z");
    assert.deepStrictEqual({ok: g2.ok, status: g2.status}, {ok: false, status: null},
        "getRide يَبتلعُ خطأَ الشبكةِ كـ«لا نعرف»");
    await assert.rejects(() => mowasalat.createRide(cfg, {pickup: {}, dropoff: {}, passenger: {}}),
        /down/, "createRide يُمرّرُ خطأَ الشبكةِ ليُكتَبَ failed عندَ المُنادي");
  } finally {
    global.fetch = realFetch;
  }
});

(async () => {
  for (const [name, fn] of asyncTests) {
    try {
      await fn();
      console.log("  ok -", name);
      passed++;
    } catch (e) {
      console.error("  NOT OK -", name, "\n   ", e.message);
      process.exitCode = 1;
    }
  }
  console.log(`\ntransport tests: ${passed} passed`);
})();
