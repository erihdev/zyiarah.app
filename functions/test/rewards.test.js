"use strict";

// مكافآتُ الطلبِ وعدُّ الكوبون — تشغيل: node test/rewards.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// موضعانِ كان `catch`هما سطرَ `console.error` وحدَه، في مُشغّلَين **بلا
// `retry`** لا يَعودانِ لمستندٍ فاته الحدث:
//
//   `[rewards] qatrat txn failed for …`   ⇒ العميلةُ أتمّت طلباً ولم تُضَف
//       نقاطُها (ريالٌ لكلِّ خمسين نقطة)، ولا دفعةَ تُخبرها، ولا تنبيه،
//       ولا محاولةً ثانية.
//   `[coupon] use-count failed for order …` ⇒ `uses` لم يُزَد، فكوبونٌ لمرّةٍ
//       واحدةٍ يَبقى قابلاً للإنفاق — و`coupons.couponProblem` يَبني
//       «exhausted» على ذلك العدّادِ بعينِه، فالمنعُ الخادميُّ يَسقطُ معه.
//
// وهي العائلةُ نفسُها التي أُغلقت في `refund_engine.creditCancelledRefund`
// و`autoResolveUnfulfilledPaidOrder`. **والعِلاجُ هنا أنظفُ**: الاستردادُ وجدَ
// علماً جاهزاً (`needs_refund`) تَستعلمُه المكنسة، وهذان لا — فالفشلُ يَكتبُ
// علمَه بنفسِه، والمكنسةُ تَستعلمُ **العلمَ لا الحالة**، فمجموعتُها لا تَحوي
// إلّا الفشل. ولو استُعلِمَت الحالةُ لازدحمت النافذةُ بما نُجِح، وهو العطلُ
// الذي وُجد مرّتَين في هذه الجلسة (نافذةُ البثِّ المجدول، ونافذةُ «مدفوعٌ
// وعالق»).
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {FieldValue} = require("firebase-admin/firestore");
const rewards = require("../rewards");

let passed = 0;
const asyncTests = [];
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  try {
    fn();
    console.log("  ok -", name);
    passed++;
  } catch (e) {
    console.error("  NOT OK -", name, "\n   ", e.message);
    process.exitCode = 1;
  }
}
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص غير المتزامن
 */
function tAsync(name, fn) {
  asyncTests.push([name, fn]);
}

/**
 * Firestore مزيّفٌ صغير — بلا مُحاكٍ وبلا شبكة (قاعدةُ refund_engine).
 * @param {object} seed مستنداتٌ ابتدائيّة
 * @return {object} ديسك مزيّف
 */
function fakeDb(seed) {
  const store = new Map(Object.entries(seed || {}));
  const touch = (p) => {
    if (!store.has(p)) store.set(p, {});
    return store.get(p);
  };
  const mkRef = (p) => ({
    path: p,
    id: p.split("/").pop(),
    update: async (obj) => Object.assign(touch(p), obj),
    collection: (c) => ({doc: (id) => mkRef(`${p}/${c}/${id}`)}),
  });
  const snapOf = (p) => {
    const d = store.get(p);
    return {exists: d !== undefined, data: () => d, get: (f) => (d || {})[f]};
  };
  return {
    _store: store, _ref: mkRef,
    collection: (c) => ({doc: (id) => mkRef(`${c}/${id}`)}),
    runTransaction: async (fn) => fn({
      get: async (ref) => snapOf(ref.path),
      update: (ref, obj) => Object.assign(touch(ref.path), obj),
      set: (ref, obj) => Object.assign(touch(ref.path), obj),
      create: (ref, obj) => store.set(ref.path, {...obj}),
    }),
  };
}

// ── قطرات ────────────────────────────────────────────────────────────────
tAsync("(أ١) النجاح: النقاطُ تُضاف، الطلبُ يُوسَم، والعميلةُ تُبلَّغ", async () => {
  const db = fakeDb({"orders/o1": {code: "A1", qatrat_pending: true}});
  const pushes = [];
  const r = await rewards.grantQatratPoints(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    points: 230, code: "A1",
  }, async (...a) => {
    pushes.push(a);
    return null;
  });
  assert.strictEqual(r.granted, true);
  assert.deepStrictEqual(db._store.get("wallets/c1").qatrat_points,
      FieldValue.increment(230));
  const tx = db._store.get("wallets/c1/transactions/qatrat_o1");
  assert.strictEqual(tx.points, 230);
  assert.strictEqual(tx.type, "qatrat_reward");
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.qatrat_granted, true);
  // **العلمُ يُمحى عند النجاح** — بلاهُ تَتضخّمُ مجموعةُ المكنسةِ بما نُجِح.
  assert.deepStrictEqual(o.qatrat_pending, FieldValue.delete());
  assert.strictEqual(pushes.length, 1);
  assert.strictEqual(pushes[0][0], "c1");
});

tAsync("(أ٢) مُنِحَ سلفاً ⇒ لا إضافةَ ولا دفعة، والعلمُ يُنظَّف", async () => {
  const db = fakeDb({
    "orders/o1": {code: "A1", qatrat_granted: true, qatrat_pending: true},
  });
  const pushes = [];
  const r = await rewards.grantQatratPoints(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    points: 230, code: "A1",
  }, async () => pushes.push(1));
  assert.strictEqual(r.granted, false);
  assert.strictEqual(r.skipped, "already_granted");
  assert.strictEqual(db._store.get("wallets/c1"), undefined,
      "أُضيفت نقاطٌ رغم المنحِ السابق");
  assert.strictEqual(pushes.length, 0, "دفعةٌ للعميلة بلا إضافة");
  assert.deepStrictEqual(db._store.get("orders/o1").qatrat_pending,
      FieldValue.delete(), "علمٌ يَبقى فتَقرؤه المكنسةُ للأبد");
});

tAsync("(أ٣) الفشل: العلمُ يُكتَب، والسببُ، ويُصعَّدُ مرّةً", async () => {
  const db = fakeDb({"orders/o1": {code: "A1"}});
  db.runTransaction = async () => {
    throw new Error("ABORTED: too much contention");
  };
  const pushes = [];
  const r = await rewards.grantQatratPoints(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    points: 230, code: "A1",
  }, async (...a) => {
    pushes.push(a);
    return null;
  });
  assert.strictEqual(r.granted, false);
  assert.ok(r.failed);
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.qatrat_pending, true, "بلا العلمِ لا تَجدُه المكنسة");
  assert.ok(o.qatrat_failed_reason);
  assert.strictEqual(o.qatrat_alerted, true);
  assert.strictEqual(pushes.length, 1, "لم يُصعَّد الفشل");
  assert.strictEqual(pushes[0][0], "ADMIN_BROADCAST");
  assert.deepStrictEqual(pushes[0][5], ["super_admin", "accountant_admin"]);
});

tAsync("(أ٤) ولا تصعيدَ ثانٍ — العلمُ يُكتَبُ والتنبيهُ لا يُكرَّر", async () => {
  const db = fakeDb({"orders/o1": {code: "A1"}});
  db.runTransaction = async () => {
    throw new Error("ABORTED");
  };
  const pushes = [];
  await rewards.grantQatratPoints(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    points: 230, code: "A1", alreadyAlerted: true,
  }, async () => pushes.push(1));
  assert.strictEqual(db._store.get("orders/o1").qatrat_pending, true);
  assert.strictEqual(pushes.length, 0, "تنبيهٌ مكرَّر");
});

// ── عدُّ الكوبون ──────────────────────────────────────────────────────────
tAsync("(ب١) النجاح: uses يُزاد، الطلبُ يُوسَم، والعلمُ يُمحى", async () => {
  const db = fakeDb({
    "orders/o1": {coupon_code: "WELCOME", coupon_count_pending: true},
    "promo_codes/p1": {uses: 3, maxUses: 10},
  });
  const r = await rewards.countCouponUse(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1",
    promoRef: db._ref("promo_codes/p1"), code: "WELCOME",
  }, async () => null);
  assert.strictEqual(r.counted, true);
  assert.deepStrictEqual(db._store.get("promo_codes/p1").uses,
      FieldValue.increment(1));
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.coupon_counted, true);
  assert.deepStrictEqual(o.coupon_count_pending, FieldValue.delete());
  assert.strictEqual(o.coupon_overlimit, undefined, "وُسِمَ تجاوزاً بلا تجاوز");
});

tAsync("(ب٢) تجاوزُ الحدِّ يُوسَمُ عند الاستهلاك (TOCTOU) ولا يَمنع", async () => {
  const db = fakeDb({
    "orders/o1": {coupon_code: "ONCE"},
    "promo_codes/p1": {uses: 1, maxUses: 1},
  });
  const r = await rewards.countCouponUse(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1",
    promoRef: db._ref("promo_codes/p1"), code: "ONCE",
  }, async () => null);
  assert.strictEqual(r.counted, true);
  assert.strictEqual(db._store.get("orders/o1").coupon_overlimit, true);
});

tAsync("(ب٣) عُدَّ سلفاً ⇒ لا زيادة، والعلمُ يُنظَّف", async () => {
  const db = fakeDb({
    "orders/o1": {coupon_counted: true, coupon_count_pending: true},
    "promo_codes/p1": {uses: 3},
  });
  const r = await rewards.countCouponUse(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1",
    promoRef: db._ref("promo_codes/p1"), code: "X",
  }, async () => null);
  assert.strictEqual(r.skipped, "already_counted");
  assert.strictEqual(db._store.get("promo_codes/p1").uses, 3, "زِيدَ مرّتَين");
  assert.deepStrictEqual(db._store.get("orders/o1").coupon_count_pending,
      FieldValue.delete());
});

tAsync("(ب٤) الفشل: العلمُ يُكتَب ويُصعَّدُ للتسويقِ مرّةً", async () => {
  const db = fakeDb({"orders/o1": {coupon_code: "X"}});
  db.runTransaction = async () => {
    throw new Error("DEADLINE_EXCEEDED");
  };
  const pushes = [];
  const r = await rewards.countCouponUse(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1",
    promoRef: db._ref("promo_codes/p1"), code: "X",
  }, async (...a) => {
    pushes.push(a);
    return null;
  });
  assert.strictEqual(r.counted, false);
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.coupon_count_pending, true);
  assert.ok(o.coupon_count_failed_reason);
  assert.strictEqual(pushes.length, 1);
  assert.deepStrictEqual(pushes[0][5], ["super_admin", "marketing_admin"]);
});

// ── حُرّاسُ المصدر ────────────────────────────────────────────────────────
const ROOT = path.join(__dirname, "..");
const idxRaw = fs.readFileSync(path.join(ROOT, "index.js"), "utf8");
const modRaw = fs.readFileSync(path.join(ROOT, "rewards.js"), "utf8");
/**
 * @param {string} src نصُّ ملفّ
 * @return {string} النصُّ بلا أسطرِ تعليق
 */
function codeOf(src) {
  return src
      .split("\n")
      .filter((l) => !/^\s*\/\//.test(l))
      .join("\n");
}
const idx = codeOf(idxRaw);

t("(ج١) index.js لا يَحملُ المعامَلتَين إنلاين، والنداءانِ يَمرّانِ بالوحدة", () => {
  assert.ok(!/transactions"\)\s*\.doc\(`qatrat_\$\{orderId\}`\)/.test(idx),
      "بناءُ معامَلةِ قطرات عادَ إلى index.js");
  assert.ok(!idx.includes("[coupon] use-count failed for order"),
      "`catch` عدِّ الكوبونِ الصامتُ عادَ");
  assert.ok(!idx.includes("[rewards] qatrat txn failed"),
      "`catch` قطراتِ الصامتُ عادَ");
  assert.ok(idx.includes("rewards.grantQatratPoints(db, {"));
  assert.ok(idx.includes("rewards.countCouponUse(db, {"));
  // والمضادّة: الاسمانِ ما زالا في الخامِّ (التعليقُ الشارحُ للنقل).
  assert.ok(idxRaw.includes("grantQatratPoints"));
  assert.ok(idxRaw.includes("qatrat txn failed"),
      "اختفى اقتباسُ السطرِ القديمِ من التوثيق — راجِعْ ما جرّده الفحص");
});

t("(ج٢) والمكنسةُ تَستعلمُ **العلمَ** لا الحالة — وهو جوهرُ العلاج", () => {
  // لو استُعلِمَت الحالةُ لازدحمت النافذةُ بما نُجِح، فلا يَبلغُها الفاشل.
  assert.ok(idx.includes(".where(rewards.PENDING_FLAGS.qatrat, \"==\", true)"),
      "استعلامُ قطرات ليس على علمِ الفشل");
  assert.ok(idx.includes(".where(rewards.PENDING_FLAGS.couponCount, \"==\", true)"),
      "استعلامُ عدِّ الكوبونِ ليس على علمِ الفشل");
  assert.ok(/qatrat retried=/.test(idx), "مكنسةُ قطرات غائبة");
  assert.ok(/coupon-count retried=/.test(idx), "مكنسةُ عدِّ الكوبونِ غائبة");
});

t("(ج٣) والنجاحُ يَمحو العلمَ — موضعانِ لكلِّ علمٍ لا أقلّ", () => {
  // علمٌ لا يُمحى يَجعلُ المكنسةَ تَقرأُ المنجَزَ للأبد (نفسُ عطلِ النافذة).
  const mod = codeOf(modRaw);
  for (const flag of ["PENDING_FLAGS.qatrat", "PENDING_FLAGS.couponCount"]) {
    const sites = mod.split(`[${flag}]: FieldValue.delete()`).length - 1;
    assert.ok(sites >= 2,
        `${flag}: مواضعُ المحوِ ${sites} — يَلزمُ المعامَلةُ والتنظيفُ معاً`);
  }
});

t("(ج٤) والوحدةُ لا تُنادي getFirestore — `db` وسيطٌ أوّل", () => {
  const mod = codeOf(modRaw);
  for (const bad of ["getFirestore(", "getApp(", "initializeApp("]) {
    assert.ok(!mod.includes(bad), `${bad} في وحدةٍ تَأخذُ db وسيطاً`);
  }
  assert.ok(modRaw.includes("getFirestore()"),
      "اختفى ذكرُ القاعدةِ من رأسِ الملفّ — راجِعْ ما جرّده الفحص");
  assert.ok(mod.length < modRaw.length, "التجريدُ لم يُزِل شيئاً — نمطٌ معطوب");
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
  console.log(`\nrewards tests: ${passed} passed`);
})();
