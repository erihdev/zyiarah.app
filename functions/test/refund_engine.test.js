"use strict";

// محرّك الاسترداد الآلي — تشغيل: node test/refund_engine.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// الشريحة الرابعة، وأوّل وحدةٍ **تلمس Firestore**. فالحارس ذو شقّين: السلوك
// (بـ`db` مزيّف — وهو ما يُثبت أنّ كسر عرف النقاء لم يكسر قابلية الاختبار)،
// والمصدر (ألّا يُعاد كتابةُ ما جُمِع).
//
// ─── (١) العلّة التي كشفها التفكيك: طلبٌ مدفوع يُدفَن صامتاً ───
//
// لـ`_autoResolveUnfulfilledPaidOrder` أربعةُ مساراتٍ فاشلة، كلٌّ منها يكتب
// `stranded_alerted: true` — **ولا واحد منها يُرسل تنبيهاً**. و`queuePush` لا
// يُنادى في الدالة كلها إلّا على مسارَي النجاح. ثم تقرأ المكنسة:
//
//     if (["gateway_error","wallet_error","no_amount","no_payment_id"]
//         .includes(r.reason)) continue;   // «المعالج ضبط stranded_alerted»
//
// فتتخطّى تنبيهها اعتماداً على تنبيهٍ لم يُرسَل قطّ. وحتى لو لم تتخطَّ، فالعلَم
// نفسه يرفعه **فرعُ الإنذار المبكّر** أعلاه («فات موعد البدء، والمحاولة
// مستمرة») قبل ذلك بساعات، والسطر التالي `if (d.stranded_alerted === true)
// continue;` فيتخطّى أيضاً. وعلَمُ المطالبة `auto_refund_processed` لا يُحَلّ،
// فلا مكنسةٌ لاحقة تُعيد المحاولة.
//
// المحصّلة: **المال محصَّل، والخدمة لم تُقدَّم، والاسترداد فشل، ولا أحد يُخبَر،
// ولا محاولة ثانية.** وهذا بالضبط ما بُني `stranded_alerted` لمنعه — وقد
// وثّقه حارسٌ قائم (`test/driver_audit_fixes_test.dart`: «طلب مدفوع فات موعده
// بلا سائق كان يختفي خادميّاً بلا تنبيه»)، فأعادت ميزةُ الاسترداد الآليّ (#18)
// فتحَ الثقب نفسه من مسارٍ آخر. والحارس القديم يمرّ: هو يفحص وجود **السلسلة**
// في المكنسة، لا أنّ تنبيهاً يُرسَل فعلاً.
//
// العلاج: المحرّك — وهو الذي يعرف أنّ الاسترداد فشل — يُصعّد بنفسه، بعلَمٍ
// **مستقلّ** (`auto_refund_alerted`) كي لا يكتمه الإنذار المبكّر، ويظلّ التنبيه
// واحداً لكلّ طلب. فصار تعليقُ المكنسة صادقاً.
//
// ─── (٢) القرار المكتوب مرّتين: مصالحة البوابة ثم void أم refund ───
//
//   _moyasarVoidOrRefund (مسار التلاعب)      — بصياغة الخروج المبكّر
//   _autoResolveUnfulfilledPaidOrder (#18)   — بصياغة gatewayOk/finalStatus/action
//
// نفس المنطق حرفيّاً: اسأل البوابة؛ إن ردّت سلفاً فانتهِ؛ وإلّا فإن كانت
// الدفعة مفوَّضةً غير مقبوضة فـ`void` وإلّا `refund` كامل. جُمِع في
// `reconcileAndSettle`، ويحرس هذا الملفّ ألّا يُكتب ثالثةً.
//
// ─── (٣) العرف الجديد: الوحدة تستقبل db ولا تستوردها ───
//
// كسر عرفِ «الوحدات النقية» (قرار المالك) لا يعني كسر قابلية الاختبار، وهي
// كانت سببَه. فالحدّ الذي يحلّ محلّ النقاء: **لا `getFirestore()` ولا
// `getApp()` داخل أيّ وحدة** — المرجع وسيطٌ دائماً. وإلّا صارت الوحدة لا
// تُختبر إلّا بمحاكي Firestore، وهو ما كان العرف يتجنّبه.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {FieldValue} = require("firebase-admin/firestore");
const engine = require("../refund_engine");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === "function") {
      throw new Error("فحصٌ غير متزامن مُرِّر إلى t() — استعمل tAsync");
    }
    console.log("  ok -", name);
    passed++;
  } catch (e) {
    console.error("  NOT OK -", name, "\n   ", e.message);
    process.exitCode = 1;
  }
}

const asyncTests = [];
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص (async)
 */
function tAsync(name, fn) {
  asyncTests.push([name, fn]);
}

// ══════════════════════════ Firestore مزيّف ══════════════════════════
// صغيرٌ بقدر ما يحتاجه المحرّك: runTransaction (get/update/set/create)،
// collection().doc()، و update() على المرجع. بلا محاكٍ وبلا شبكة.
/**
 * @param {object} seed مستندات أوّلية {"orders/o1": {...}}
 * @return {object} db مزيّف
 */
function fakeDb(seed) {
  const store = new Map(Object.entries(seed || {}));
  const writes = [];
  const touch = (p) => {
    if (!store.has(p)) store.set(p, {});
    return store.get(p);
  };
  const mkRef = (p) => ({
    path: p,
    id: p.split("/").pop(),
    update: async (obj) => {
      writes.push({op: "update", path: p, obj});
      Object.assign(touch(p), obj);
    },
    collection: (c) => ({doc: (id) => mkRef(`${p}/${c}/${id}`)}),
  });
  const snapOf = (p) => {
    const d = store.get(p);
    return {
      exists: d !== undefined, id: p.split("/").pop(),
      data: () => d, get: (f) => (d || {})[f],
    };
  };
  return {
    _store: store, _writes: writes, _ref: mkRef,
    collection: (c) => ({doc: (id) => mkRef(`${c}/${id}`)}),
    runTransaction: async (fn) => fn({
      get: async (ref) => snapOf(ref.path),
      update: (ref, obj) => {
        writes.push({op: "tx.update", path: ref.path, obj});
        Object.assign(touch(ref.path), obj);
      },
      set: (ref, obj) => {
        writes.push({op: "tx.set", path: ref.path, obj});
        Object.assign(touch(ref.path), obj);
      },
      create: (ref, obj) => {
        writes.push({op: "tx.create", path: ref.path, obj});
        store.set(ref.path, {...obj});
      },
    }),
  };
}

/**
 * @param {object} db ديسك مزيّف
 * @param {string} id معرّف الطلب
 * @return {object} لقطةُ طلبٍ شبيهة بـQueryDocumentSnapshot
 */
function orderDocOf(db, id) {
  const p = `orders/${id}`;
  return {id, ref: db._ref(p), data: () => db._store.get(p)};
}

/** @return {object} طابور إشعارات مزيّف يسجّل النداءات */
function fakePush() {
  const calls = [];
  const fn = async (...a) => {
    calls.push(a);
  };
  fn.calls = calls;
  return fn;
}

/**
 * @param {object} cfg نتائجُ البوابة المرجوّة
 * @return {object} عميل بوابةٍ مزيّف يسجّل النداءات
 */
function fakeGateway(cfg) {
  const calls = [];
  return {
    calls,
    getPayment: async (s, id) => {
      calls.push(["getPayment", id]);
      return cfg.get || {ok: false, httpStatus: 0, status: null, result: {}};
    },
    voidPayment: async (s, id) => {
      calls.push(["voidPayment", id]);
      return cfg.void || {ok: true, httpStatus: 200, status: "voided", result: {}};
    },
    refund: async (s, id, amt) => {
      calls.push(["refund", id, amt]);
      return cfg.refund || {ok: true, httpStatus: 200, status: "refunded", result: {}};
    },
  };
}

const PAID_CARD = {
  status: "pending", is_paid: true, payment_method: "creditcard",
  moyasar_payment_id: "pay_1", client_id: "c1", code: "A-100",
  total_amount: 230,
};

// ════════════════ (أ) reconcileAndSettle — القرار المجموع ════════════════

tAsync("(أ١) ردّت البوابة سلفاً → already، وبلا نداء void/refund", async () => {
  const g = fakeGateway({get: {ok: true, status: "refunded"}});
  const r = await engine.reconcileAndSettle("sk", "pay_1", g);
  assert.deepStrictEqual(r,
      {ok: true, already: true, action: "refunded", status: "refunded"});
  assert.deepStrictEqual(g.calls, [["getPayment", "pay_1"]],
      "لا يجوز ضربُ البوابة ثانيةً بعد أن ردّت");
});

tAsync("(أ٢) مفوَّضة غير مقبوضة (authorized/initiated) → void", async () => {
  for (const st of ["authorized", "initiated"]) {
    const g = fakeGateway({get: {ok: true, status: st}});
    const r = await engine.reconcileAndSettle("sk", "pay_1", g);
    assert.strictEqual(r.action, "voided", st);
    assert.ok(g.calls.some((c) => c[0] === "voidPayment"), st);
    assert.ok(!g.calls.some((c) => c[0] === "refund"), `${st}: لا refund`);
  }
});

tAsync("(أ٣) مقبوضة → refund **كامل** (amount=undefined)", async () => {
  const g = fakeGateway({get: {ok: true, status: "paid"}});
  const r = await engine.reconcileAndSettle("sk", "pay_1", g);
  assert.strictEqual(r.action, "refunded");
  assert.deepStrictEqual(g.calls[1], ["refund", "pay_1", undefined],
      "المبلغ يجب أن يبقى undefined = استردادٌ كامل لما قبضته البوابة");
});

tAsync("(أ٤) تعذّر سؤال البوابة → refund لا void (المسار المحافظ)", async () => {
  // getPayment تبلع أخطاء الشبكة بقصد: «تعذّر السؤال» = «لا أعرف». فالمحافظ
  // أن نحاول refund؛ فإن رفضته البوابة بقي المال مكانه وصار الأمر للمراجعة.
  const g = fakeGateway({get: {ok: false, status: null},
    refund: {ok: false, httpStatus: 400, status: null}});
  const r = await engine.reconcileAndSettle("sk", "pay_1", g);
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.action, "refunded");
  assert.ok(!g.calls.some((c) => c[0] === "voidPayment"),
      "لا يجوز إلغاء تفويضٍ لم نتحقّق أنه غير مقبوض");
});

// ════════════ (ب) العلّة: كلّ مسارٍ فاشل **يُصعّد** للإدارة ════════════

const FAIL_CASES = [
  ["no_payment_id", {...PAID_CARD, moyasar_payment_id: null}, {}],
  ["gateway_error", {...PAID_CARD},
    {get: {ok: true, status: "paid"}, refund: {ok: false, status: null}}],
  ["no_amount", {...PAID_CARD, payment_method: "wallet",
    total_amount: 0, amount: 0}, {}],
];

for (const [reason, data, gcfg] of FAIL_CASES) {
  tAsync(`(ب) ${reason} → تنبيهٌ إداريٌّ واحد + auto_refund_alerted`, async () => {
    const db = fakeDb({"orders/o1": {...data}});
    const push = fakePush();
    const r = await engine.autoResolveUnfulfilledPaidOrder(
        db, "sk", orderDocOf(db, "o1"), {queuePush: push, gateway: fakeGateway(gcfg)});
    assert.deepStrictEqual(r, {handled: false, reason}, "السبب المُعاد");
    const o = db._store.get("orders/o1");
    assert.strictEqual(o.auto_refund_failed, true);
    assert.strictEqual(o.auto_refund_alerted, true, "علَمُ التنبيه المستقلّ");
    assert.strictEqual(o.auto_refund_failed_reason, reason);
    const admin = push.calls.filter((c) => c[0] === "ADMIN_BROADCAST");
    assert.strictEqual(admin.length, 1,
        `**العلّة**: ${reason} كان يرفع العلَم بلا إرسال أيّ تنبيه`);
    assert.ok(admin[0][4] && admin[0][4].autoRefundFailed === true,
        "حِمل الإشعار يحمل علامةً يُفرَز بها");
    assert.ok(admin[0][4].reason === reason, "والسبب");
    assert.ok(String(admin[0][2]).includes("A-100"), "ورقم الطلب في النصّ");
    assert.ok(Array.isArray(admin[0][5]) &&
        admin[0][5].includes("accountant_admin"),
    "يصل المحاسب — المال محصَّل");
  });
}

tAsync("(ب) wallet_error → تصعيد (المعاملة ذرّية فلم يُمَسّ المال)", async () => {
  const db = fakeDb({"orders/o1":
    {...PAID_CARD, payment_method: "wallet"}});
  // نُفشل معاملةَ المحفظة وحدها (الثانية) بعد نجاح المطالبة (الأولى).
  let n = 0;
  const base = db.runTransaction;
  db.runTransaction = async (fn) => {
    n++;
    if (n === 2) throw new Error("boom");
    return base(fn);
  };
  const push = fakePush();
  const r = await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: push});
  assert.deepStrictEqual(r, {handled: false, reason: "wallet_error"});
  assert.strictEqual(
      push.calls.filter((c) => c[0] === "ADMIN_BROADCAST").length, 1,
      "**العلّة**: فشلُ المحفظة كان يُدفَن صامتاً");
});

tAsync("(ب) الإنذار المبكّر (stranded_alerted) **لا يكتم** التصعيد", async () => {
  // جوهر العلّة: العلَم مشتركٌ بمعنيين — «أنذرناك أنه متأخّر» و«تعذّر
  // استردادُه». وفرعُ الإنذار المبكّر يرفعه ساعاتٍ قبل مسار الاسترداد.
  const db = fakeDb({"orders/o1":
    {...PAID_CARD, moyasar_payment_id: null, stranded_alerted: true}});
  const push = fakePush();
  await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: push});
  assert.strictEqual(
      push.calls.filter((c) => c[0] === "ADMIN_BROADCAST").length, 1,
      "علَمُ الإنذار المبكّر كان يكتم تنبيهَ فشل الاسترداد");
});

tAsync("(ب) تشغيلٌ ثانٍ بعد التصعيد لا يُكرّر التنبيه", async () => {
  const db = fakeDb({"orders/o1": {...PAID_CARD, moyasar_payment_id: null,
    auto_refund_alerted: true}});
  const push = fakePush();
  await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: push});
  assert.strictEqual(push.calls.length, 0, "تنبيهٌ واحد لكلّ طلب");
});

tAsync("(ب) assigned_midway: لا تصعيد — يُحَلّ العلَم وتعود الحالة", async () => {
  const db = fakeDb({"orders/o1": {...PAID_CARD, payment_method: "wallet"}});
  let n = 0;
  const base = db.runTransaction;
  db.runTransaction = async (fn) => {
    n++;
    if (n === 2) {
      db._store.get("orders/o1").driver_id = "d9"; // أُسنِد لحظتها
    }
    return base(fn);
  };
  const push = fakePush();
  const r = await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: push});
  assert.deepStrictEqual(r, {handled: false, reason: "assigned_midway"});
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.auto_refund_processed, false, "المطالبة تُحَلّ");
  assert.strictEqual(o.payment_status, "paid", "لا يبقى refunding");
  assert.strictEqual(push.calls.length, 0, "الطلب سليم — لا تنبيه");
});

// ═════════════════ (ج) مسارات النجاح كما كانت ═════════════════

tAsync("(ج١) المحفظة: إيداعٌ + معاملةٌ موسومة + إلغاءٌ + إشعارا العميل/الإدارة",
    async () => {
      const db = fakeDb({"orders/o1": {...PAID_CARD, payment_method: "wallet"}});
      const push = fakePush();
      const r = await engine.autoResolveUnfulfilledPaidOrder(
          db, "sk", orderDocOf(db, "o1"), {queuePush: push});
      assert.deepStrictEqual(r, {handled: true, action: "wallet_refund"});
      const w = db._store.get("wallets/c1");
      assert.deepStrictEqual(w.balance, FieldValue.increment(230),
          "الإيداع بـincrement لا بكتابة رصيدٍ محسوب");
      const tx = db._store.get("wallets/c1/transactions/refund_o1");
      assert.ok(tx, "معرّف المعاملة مشتقٌّ من الطلب = حمايةٌ من الإيداع المزدوج");
      assert.strictEqual(tx.type, "refund");
      assert.strictEqual(tx.amount, 230);
      const o = db._store.get("orders/o1");
      assert.strictEqual(o.status, "cancelled");
      assert.strictEqual(o.cancel_reason, "unfulfilled_no_driver");
      assert.strictEqual(o.refund_credited, true);
      assert.strictEqual(o.is_paid, false);
      assert.strictEqual(o.rewards_handled_by, "server");
      assert.strictEqual(push.calls.length, 2, "العميل + الإدارة");
      assert.strictEqual(push.calls[0][0], "c1");
      assert.ok(String(push.calls[0][2]).includes("محفظتكِ"));
    });

tAsync("(ج٢) البطاقة المقبوضة: refund + إلغاء + refunded_at + مبلغٌ مسجَّل",
    async () => {
      const db = fakeDb({"orders/o1": {...PAID_CARD}});
      const push = fakePush();
      const g = fakeGateway({get: {ok: true, status: "paid"}});
      const r = await engine.autoResolveUnfulfilledPaidOrder(
          db, "sk", orderDocOf(db, "o1"), {queuePush: push, gateway: g});
      assert.deepStrictEqual(r, {handled: true, action: "refunded"});
      const o = db._store.get("orders/o1");
      assert.strictEqual(o.payment_status, "refunded");
      assert.strictEqual(o.refunded_amount, 230);
      assert.deepStrictEqual(o.refunded_at, FieldValue.serverTimestamp());
      assert.strictEqual(o.voided_at, undefined, "مقبوضة فلا voided_at");
      assert.ok(String(push.calls[0][2]).includes("بطاقتكِ"));
    });

tAsync("(ج٣) البطاقة المفوَّضة: void + voided_at + وسم «إلغاء تفويض»",
    async () => {
      const db = fakeDb({"orders/o1": {...PAID_CARD}});
      const push = fakePush();
      const g = fakeGateway({get: {ok: true, status: "authorized"}});
      const r = await engine.autoResolveUnfulfilledPaidOrder(
          db, "sk", orderDocOf(db, "o1"), {queuePush: push, gateway: g});
      assert.deepStrictEqual(r, {handled: true, action: "voided"});
      const o = db._store.get("orders/o1");
      assert.strictEqual(o.payment_status, "voided");
      assert.deepStrictEqual(o.voided_at, FieldValue.serverTimestamp());
      assert.strictEqual(o.refunded_at, undefined);
      const admin = push.calls.find((c) => c[0] === "ADMIN_BROADCAST");
      assert.ok(String(admin[2]).includes("إلغاء تفويض"));
    });

tAsync("(ج٤) الاشتراك وBNPL تُعاد للمكنسة بلا مطالبة ولا نداء بوابة",
    async () => {
      for (const [m, reason] of [["subscription", "subscription"],
        ["tamara", "bnpl"], ["tabby", "bnpl"]]) {
        const db = fakeDb({"orders/o1": {...PAID_CARD, payment_method: m}});
        const push = fakePush();
        const g = fakeGateway({});
        const r = await engine.autoResolveUnfulfilledPaidOrder(
            db, "sk", orderDocOf(db, "o1"), {queuePush: push, gateway: g});
        assert.deepStrictEqual(r, {handled: false, reason}, m);
        assert.strictEqual(db._store.get("orders/o1").auto_refund_processed,
            undefined, `${m}: لا مطالبة`);
        assert.strictEqual(g.calls.length, 0, `${m}: لا نداء بوابة`);
        assert.strictEqual(push.calls.length, 0,
            `${m}: التصعيد شأنُ المكنسة لا المحرّك`);
      }
    });

tAsync("(ج٥) المطالبة الذرّية تمنع استرداداً ثانياً", async () => {
  const db = fakeDb({"orders/o1": {...PAID_CARD}});
  const g = fakeGateway({get: {ok: true, status: "paid"}});
  const first = await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: fakePush(), gateway: g});
  assert.strictEqual(first.handled, true);
  const second = await engine.autoResolveUnfulfilledPaidOrder(
      db, "sk", orderDocOf(db, "o1"), {queuePush: fakePush(), gateway: g});
  assert.deepStrictEqual(second, {handled: false, reason: "claimed_or_ineligible"});
});

// ═══════════════ (د) voidOrRefundTampered (مسار التلاعب) ═══════════════

tAsync("(د١) مطالبة ثانية → already بلا نداء بوابة", async () => {
  const db = fakeDb({"orders/o1": {tamper_handled: true}});
  const g = fakeGateway({});
  const r = await engine.voidOrRefundTampered(
      db, "sk", "pay_1", db._ref("orders/o1"), {gateway: g});
  assert.deepStrictEqual(r, {done: true, action: "already"});
  assert.strictEqual(g.calls.length, 0);
});

tAsync("(د٢) مفوَّضة → void + tamper_blocked + refund_credited", async () => {
  const db = fakeDb({"orders/o1": {is_paid: true}});
  const g = fakeGateway({get: {ok: true, status: "authorized"}});
  const r = await engine.voidOrRefundTampered(
      db, "sk", "pay_1", db._ref("orders/o1"), {gateway: g});
  assert.deepStrictEqual(r, {done: true, action: "voided"});
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.payment_status, "voided");
  assert.strictEqual(o.is_paid, false);
  assert.strictEqual(o.tamper_blocked, true);
  assert.strictEqual(o.refund_credited, true);
  assert.deepStrictEqual(o.voided_at, FieldValue.serverTimestamp());
});

tAsync("(د٣) فشل البوابة → payment_review و**is_paid لا تُقلَب**", async () => {
  const db = fakeDb({"orders/o1": {is_paid: true}});
  const g = fakeGateway({get: {ok: true, status: "paid"},
    refund: {ok: false, status: null}});
  const r = await engine.voidOrRefundTampered(
      db, "sk", "pay_1", db._ref("orders/o1"), {gateway: g});
  assert.deepStrictEqual(r, {done: false, action: "gateway_error"});
  const o = db._store.get("orders/o1");
  assert.strictEqual(o.payment_status, "payment_review");
  assert.strictEqual(o.tamper_gateway_failed, true);
  assert.strictEqual(o.is_paid, true,
      "لم يُعَد المال → لا نقلب is_paid ولا نرمي؛ الطلب للمراجعة اليدوية");
});

tAsync("(د٤) ردّت البوابة سلفاً → تُصالَح الحالة بلا نداءٍ ثانٍ", async () => {
  const db = fakeDb({"orders/o1": {is_paid: true}});
  const g = fakeGateway({get: {ok: true, status: "refunded"}});
  const r = await engine.voidOrRefundTampered(
      db, "sk", "pay_1", db._ref("orders/o1"), {gateway: g});
  assert.deepStrictEqual(r, {done: true, action: "refunded"});
  assert.strictEqual(db._store.get("orders/o1").refund_credited, true);
  assert.strictEqual(g.calls.length, 1);
});

// ════════════════ (هـ) reopenFieldsIfSystemCancelled ════════════════

t("(هـ١) إلغاءٌ نظاميّ لعدم الدفع → إعادةُ فتحٍ بحذف حقول الإلغاء", () => {
  const f = engine.reopenFieldsIfSystemCancelled(
      {status: "cancelled", cancel_reason: "unpaid_expired"});
  assert.strictEqual(f.status, "pending");
  assert.strictEqual(f.reopened_after_late_payment, true);
  for (const k of ["cancel_reason", "cancelled_by", "cancelled_at"]) {
    assert.deepStrictEqual(f[k], FieldValue.delete(), k);
  }
});

t("(هـ٢) إلغاءٌ بشريّ أو طلبٌ قائم → لا إعادة فتح", () => {
  assert.deepStrictEqual(engine.reopenFieldsIfSystemCancelled(
      {status: "cancelled", cancel_reason: "client_request"}), {});
  assert.deepStrictEqual(engine.reopenFieldsIfSystemCancelled(
      {status: "pending"}), {});
  assert.deepStrictEqual(engine.reopenFieldsIfSystemCancelled(null), {});
});

// ══════════════════════ (و) حرّاس المصدر ══════════════════════

/**
 * يُجرّد التعليقات قبل الفحص — بلا قطعِ السطر عند أوّل `//` (فـ`https://`
 * تحمل `//` وقد محا ذلك حارسَ تمارا أوّل مرّة فصار بلا أثر): تُحذَف كتلُ
 * `/* *\/` وسطورُ التعليق الكاملة، ولا يُقتصّ تعليقٌ ذيليّ إلّا إن لم يسبقه `:`.
 * @param {string} src المصدر الخام.
 * @return {string} المصدر بلا تعليقات.
 */
function codeOf(src) {
  return src
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .filter((l) => !/^\s*\/\//.test(l))
      .map((l) => l.replace(/([^:])\/\/.*$/, "$1"))
      .join("\n");
}

const ROOT = path.join(__dirname, "..");
const idx = fs.readFileSync(path.join(ROOT, "index.js"), "utf8");
const mod = fs.readFileSync(path.join(ROOT, "refund_engine.js"), "utf8");

t("(و١) الأربعةُ المنقولة لم تَبقَ في index.js، والنداءات تمرّ بالوحدة", () => {
  for (const s of ["_moyasarVoidOrRefund", "_notifyAutoRefund",
    "_reopenFieldsIfSystemCancelled", "_autoResolveUnfulfilledPaidOrder"]) {
    assert.ok(!idx.includes(s), `${s} ما زال في index.js`);
  }
  assert.ok(idx.includes("require(\"./refund_engine\")"));
  assert.ok(idx.includes("refunds.voidOrRefundTampered(db, secret, paymentId, orderRef)"),
      "مسار التلاعب يجب أن يمرّ بالوحدة");
  assert.ok(idx.includes("refunds.autoResolveUnfulfilledPaidOrder("),
      "مسار تعذّر التنفيذ يجب أن يمرّ بالوحدة");
  assert.ok(/refunds\.autoResolveUnfulfilledPaidOrder\(\s*\n?\s*db, secret, doc, \{queuePush\}\)/
      .test(idx), "و`queuePush` يُحقَن — وبه يُصعّد المحرّك");
  assert.strictEqual(
      (idx.match(/refunds\.reopenFieldsIfSystemCancelled\(/g) || []).length, 4,
      "مواضعُ إعادة الفتح الأربعة (verify/webhook/reconcile/wallet) — كانت " +
      "ثلاثةً، والمحفظة الرابعةُ التي لا تُعيد الفتح: تعليقُ الدفاع كان في " +
      "index.js بلا كودِه، فيبقى الطلبُ ملغىً مدفوعاً بلا خدمة");
});

t("(و٢) قرارُ void-أم-refund لا يُكتب ثالثةً في index.js", () => {
  // الصياغتان المجموعتان كانتا تفحصان `live.status === "authorized" ||
  // "initiated"`. ولا تعليقَ في index.js يذكرهما، فالفحص على المصدر الخام
  // (بلا تجريد تعليقات — أصرمُ، ولا احتمالَ سلبيٍّ كاذب؛ خلافاً لحارس تمارا).
  for (const lit of ["\"authorized\"", "\"initiated\""]) {
    assert.ok(!idx.includes(lit),
        `حالةُ ${lit} عادت إلى index.js — القرار يُكتب مرّة واحدة في ` +
        "reconcileAndSettle، وإلّا انحرفت النسختان كما انحرفتا قبلاً");
  }
  // وفي الوحدة نفسها: موضعٌ واحد يقرّر.
  assert.strictEqual((mod.match(/voidPayment\(/g) || []).length, 1,
      "نداءُ void مرّةً واحدة داخل reconcileAndSettle");
});

t("(و٣) كلّ مسارٍ فاشل يمرّ على _failAndEscalate (لا تثبيتَ صامت)", () => {
  // هذا هو الحارسُ الذي يمنع العلّة من أن تنبت ثانيةً: كتابةُ
  // `auto_refund_failed: true` في موضعٍ واحد فقط — الموضع الذي يُنبّه.
  assert.strictEqual((mod.match(/auto_refund_failed: true/g) || []).length, 1,
      "تثبيتُ الفشل مكتوبٌ أكثر من مرّة — فرعٌ يُثبّت بلا تصعيد = دفنٌ صامت");
  assert.ok(mod.includes("escalateFailedAutoRefund(queuePush,"),
      "_failAndEscalate يجب أن يُصعّد فعلاً");
  assert.ok(!idx.includes("auto_refund_failed"),
      "index.js لا يكتب علَم الفشل — القرار كلّه في المحرّك");
});

t("(و٤) قائمةُ أسباب المكنسة == ESCALATED_REASONS حرفاً بحرف", () => {
  // الاقتران الحقيقي: المكنسة تتخطّى تنبيهها لهذه الأسباب **لأنّ** المحرّك
  // يُصعّدها. فسببٌ في قائمتها لا يُصعّده المحرّك = دفنٌ صامت من جديد، وسببٌ
  // يُصعّده وليس في قائمتها = تنبيهٌ مزدوج.
  const m = idx.match(/if \(\[([^\]]*)\]\s*\n?\s*\.includes\(r\.reason\)\) continue;/);
  assert.ok(m, "قائمةُ الأسباب في sweepUnassignedPaidOrders لم تُوجَد");
  const inSweep = m[1].split(",").map((s) => s.trim().replace(/^"|"$/g, ""))
      .filter(Boolean).sort();
  assert.deepStrictEqual(inSweep, [...engine.ESCALATED_REASONS].sort(),
      "قائمةُ المكنسة والأسبابُ المُصعَّدة انحرفتا");
});

t("(و٥) العرف الجديد: لا وحدةٍ تستورد Firestore — المرجعُ وسيط", () => {
  // الحدّ الذي يحلّ محلّ عرف النقاء. أيُّ `getFirestore()` داخل وحدةٍ يُعيدنا
  // إلى وحدةٍ لا تُختبر إلّا بمحاكي Firestore — وهو ما كان العرف يتجنّبه.
  //
  // هنا **يجب** تجريدُ التعليقات: الوحدة تشرح القاعدة بذكر الاسم المحظور،
  // فالفحص الخام يسقط على شرحِ نفسه (وقع ذلك أوّل مرّة). والتجريد يحفظ درسَ
  // حارس تمارا: لا نقطع السطر عند أوّل `//` وإلّا محا `https://` ما نبحث عنه.
  const MODULES = ["pricing.js", "capacity.js", "notify_prefs.js", "vat.js",
    "drivers.js", "amounts.js", "moyasar_api.js", "tamara_api.js",
    "refund_engine.js"];
  for (const f of MODULES) {
    const src = codeOf(fs.readFileSync(path.join(ROOT, f), "utf8"));
    for (const bad of ["getFirestore(", "getApp(", "initializeApp("]) {
      assert.ok(!src.includes(bad),
          `${f} يستدعي ${bad}) — الوحدة تستقبل db وسيطاً ولا تستوردها`);
    }
  }
  // والتجريد ليس شاملاً: الاسم ما زال موجوداً في النصّ الكامل (في الشرح)،
  // فلو جرّدنا أكثر من اللازم صار الحارس بلا موضوع.
  assert.ok(fs.readFileSync(path.join(ROOT, "refund_engine.js"), "utf8")
      .includes("getFirestore()"), "الوحدة تشرح القاعدة — وهذا ما يُجرَّد");
  // وفعلاً: المحرّك يأخذ db أوّل وسيط في دوالّه التي تلمس Firestore.
  assert.ok(mod.includes("async function voidOrRefundTampered(db,"));
  assert.ok(mod.includes("async function autoResolveUnfulfilledPaidOrder(db,"));
});

t("(و٦) index.js ما زال يُصدّر ٦٨ دالّة", () => {
  // كانت ٦٢ وصارت ٦٣ بإضافة `processServerNotificationQueue`: طابورُ الإشعاراتِ
  // الخادميُّ (`notification_queue`) انفصلَ عن طابورِ العميلِ لأنّ الثقةَ كانت
  // تُحسَب من `createdBy` — حقلٍ يَكتبه العميل. المُعالِجُ **واحدٌ مُشترَك**
  // بين التسجيلَين، فالزيادةُ تسجيلٌ لا نسخةُ منطق. (الحارسُ يُجبر على مراجعةِ
  // أيِّ تصديرٍ جديد — وقد أدّى ذلك هنا.)
  //
  // وصارت ٦٤ بإضافة `deleteStorageObject`: `storage.rules` **لا تَستطيعُ
  // قراءةَ Firestore** فلا تَعرفُ الدورَ، وكانت تَقول لكلِّ مسارِ صورٍ
  // `allow delete: if request.auth != null` — أيُّ عميلةٍ مسجَّلةٍ تَحذفُ
  // كلَّ بنرٍ وكلَّ صورةِ منتج. فصارَ الحذفُ خادميّاً بعد `_assertAdmin`،
  // كـ`deleteDriverAccount`. (مراجعةٌ مقصودةٌ لا إسكاتاً — وهو ما يَطلبُه
  // هذا الحارسُ بنصِّه.)
  //
  // وصارت ٦٥ بإضافة `validateCouponCode`: `promo_codes` كانت
  // `allow read: if isLoggedIn()` فكلُّ كودِ خصمٍ في المستودعِ مقروءٌ لكلِّ
  // عميلةٍ مسجَّلة — بما فيها ما وسَمَه الأدمنُ `show_in_offers: false` كي لا
  // يُكشَفَ كودُ قناةٍ خاصّة. والتحقّقُ انتقلَ خادميّاً فصارت القاعدةُ
  // تُضيَّقُ بلا كسرِ المسار. (مراجعةٌ مقصودةٌ، كأختَيها أعلاه.)
  //
  // وصارت ٦٧ بإضافةِ `deleteStaffAccount` و`syncRoleToPushToken`: حذفُ
  // موظّفٍ كان ثلاثةَ مساراتٍ ولا واحدٌ منها كاملاً — فحسابُ Auth يَبقى حيّاً
  // و`fcm_tokens/{id}` يَبقى موسوماً `role:'admin'`، فيَستقبلُ جهازُ المُقصى
  // كلَّ تنبيهٍ إداريٍّ إلى الأبد، ولا يُصحَّحُ أبداً لأنّ القواعدَ تُقارِنُ
  // الرمزَ بـ`users/{id}` وقد زال. والمُشغّلُ هو ما يُغني عن تذكّرِ كلِّ
  // مسارٍ (شاشةٌ ولوحةٌ وكونسولٌ وما يُكتَبُ غداً)، ويُصحّحُ كذلك نسخةَ
  // الدورِ البائتةَ بعد ترقيةٍ أو تنزيل. (مراجعةٌ مقصودةٌ، كأخواتِها أعلاه.)
  // وصارت ٦٨ بإضافةِ `ensureReferralCode`: توليدُ كودِ الإحالةِ كان على
  // الجهازِ، وفحصُ التصادمِ `users.where('referral_code','==',code)` —
  // وقاعدةُ `users` هي `isOwner(userId) || isAdmin()`، فاستعلامُ **قائمةٍ**
  // عليها لا يُثبِتُ أيَّهما ويُرفَض. والاستعلامُ بلا `try`، فالاستثناءُ
  // يَخرجُ من الدالّة: **كلُّ عميلةٍ لا تَملكُ كوداً بعدُ لا تَحصلُ على
  // واحدٍ أبداً**، وبرنامجُ الإحالةِ كلُّه يَبدأُ به. والفحصُ لازمٌ لأنّ
  // `applyReferralCode` يَحُلُّ المُحيلَ بالكودِ فالتصادمُ إسنادٌ خاطئٌ
  // لمكافأةٍ ماليّة — فمكانُه الخادمُ وحدَه. (مُثبَتٌ على المُحاكي في
  // `rules.roles`؛ ومراجعةٌ مقصودةٌ كأخواتِها أعلاه.)
  const n = (idx.match(/^exports\.\w+ = /gm) || []).length;
  assert.strictEqual(n, 68, `عدد الصادرات ${n} ≠ 68`);
});

// ── إعادةُ رصيدِ طلبٍ مُلغًى: مرّةً واحدةً، ومع قولِ الفشل ─────────────────
//
// كان المنطقُ إنلاين في `onOrderRewards` و`catch`ه سطرَ `console.error` وحدَه:
// فشلُ المعامَلةِ يَعني محفظةً لم تُودَع، ولا دفعةً للعميلة، ولا تنبيهاً
// للإدارة، ولا محاولةً ثانية — `onDocumentUpdated` بلا `retry` ولا يَعودُ
// لمستندٍ فاته الحدث. **مالُ العميلةِ يَبقى عندنا بلا أثرٍ خارجَ سطرِ سجلّ**،
// وهي الحفرةُ نفسُها التي أُغلقت في `autoResolveUnfulfilledPaidOrder` من مسارٍ
// آخر: إلغاءُ طلبٍ مدفوع.
tAsync("(ح١) النجاح: المحفظةُ تُودَع، الطلبُ يُوسَم، والعميلةُ تُبلَّغ", async () => {
  const db = fakeDb({"orders/o1": {code: "A1", amount: 230, client_id: "c1"}});
  const pushes = [];
  const r = await engine.creditCancelledRefund(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    amount: 230, code: "A1",
  }, async (...a) => {
    pushes.push(a);
    return null;
  });
  assert.strictEqual(r.credited, true);
  assert.deepStrictEqual(db._store.get("wallets/c1").balance,
      FieldValue.increment(230));
  assert.strictEqual(db._store.get("orders/o1").refund_credited, true);
  const tx = db._store.get("wallets/c1/transactions/refund_o1");
  assert.strictEqual(tx.amount, 230);
  assert.strictEqual(tx.type, "refund");
  assert.strictEqual(pushes.length, 1);
  assert.strictEqual(pushes[0][0], "c1");
});

tAsync("(ح٢) الحُرّاسُ الثلاثةُ تَمنعُ إيداعاً ثانياً — ولا دفعةَ عندها", async () => {
  for (const guard of [
    {refund_credited: true},
    {payment_status: "refunded"},
    {auto_refund_processed: true},
  ]) {
    const db = fakeDb({
      "orders/o1": {code: "A1", amount: 230, client_id: "c1", ...guard},
    });
    const pushes = [];
    const r = await engine.creditCancelledRefund(db, {
      orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
      amount: 230, code: "A1",
    }, async () => pushes.push(1));
    assert.strictEqual(r.credited, false, JSON.stringify(guard));
    assert.strictEqual(r.skipped, "already_settled", JSON.stringify(guard));
    assert.strictEqual(db._store.get("wallets/c1"), undefined,
        `أُودِعت المحفظةُ رغم ${JSON.stringify(guard)}`);
    assert.strictEqual(pushes.length, 0, "دفعةٌ للعميلة بلا إيداع");
  }
});

tAsync("(ح٣) الفشل: يُوسَم ويُصعَّد، و`needs_refund` يَبقى للمكنسة", async () => {
  const db = fakeDb({
    "orders/o1": {code: "A1", amount: 230, client_id: "c1", needs_refund: true},
  });
  db.runTransaction = async () => {
    throw new Error("ABORTED: too much contention");
  };
  const pushes = [];
  const r = await engine.creditCancelledRefund(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    amount: 230, code: "A1",
  }, async (...a) => {
    pushes.push(a);
    return null;
  });
  assert.strictEqual(r.credited, false);
  assert.ok(r.failed, "الفشلُ لم يُعَد");
  const d = db._store.get("orders/o1");
  assert.strictEqual(d.refund_credit_failed, true);
  assert.strictEqual(d.refund_credit_alerted, true);
  assert.ok(d.refund_credit_failed_reason, "السببُ لم يُثبَّت");
  // **`needs_refund` لا يُلمَس**: هو ما تَستعلمُه المكنسةُ لإعادةِ المحاولة.
  assert.strictEqual(d.needs_refund, true);
  assert.strictEqual(pushes.length, 1, "لم يُصعَّد الفشل");
  assert.strictEqual(pushes[0][0], "ADMIN_BROADCAST");
  assert.deepStrictEqual(pushes[0][5], ["super_admin", "accountant_admin"]);
});

tAsync("(ح٤) ولا يُصعَّدُ مرّتَين — `alreadyAlerted` يُسكِتُ الثانية", async () => {
  const db = fakeDb({"orders/o1": {code: "A1", amount: 230, client_id: "c1"}});
  db.runTransaction = async () => {
    throw new Error("ABORTED");
  };
  const pushes = [];
  const r = await engine.creditCancelledRefund(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    amount: 230, code: "A1", alreadyAlerted: true,
  }, async () => pushes.push(1));
  assert.strictEqual(r.credited, false);
  // الوسمُ يُكتَبُ كلَّ مرّةٍ (السببُ يُحدَّث)، والتنبيهُ مرّةً واحدة.
  assert.strictEqual(db._store.get("orders/o1").refund_credit_failed, true);
  assert.strictEqual(pushes.length, 0, "تنبيهٌ مكرَّرٌ للإدارة");
});

t("(ح٥) `index.js` لا يَحملُ الإيداعَ إنلاين بعد اليوم", () => {
  // يُجرَّدُ من التعليقِ أوّلاً: الشفرةُ تَشرحُ النقلَ بذكرِ اسمِ الدالّة.
  const code = codeOf(idx);
  // لولا هذا لعادت النسخةُ الإنلاين في الميزةِ القادمةِ ولا يَسقطُ شيء.
  assert.ok(!/transactions"\)\s*\.doc\(`refund_\$\{orderId\}`\)/.test(code),
      "بناءُ معامَلةِ الاسترداد عاد إلى index.js");
  assert.ok(code.includes("refunds.creditCancelledRefund(db, {"),
      "`onOrderRewards` لا يُنادي المحرّك");
  // والمكنسةُ تُنادي الدالّةَ نفسَها — التنبيهُ وحدَه لا يُعيدُ المال.
  assert.ok(/cancelled-refund retried=/.test(code),
      "مكنسةُ إعادةِ المحاولةِ غائبة");
  // **أُعيد توجيهُه وشُدِّد (2026-10-05):** كان يُثبّتُ مساواتَين، وصارت
  // ثلاثاً بإضافةِ `is_paid` — لأنّ `needs_refund` يَكتبُه **العميلُ** على
  // طلبِه عند الإلغاء (`hasOnly` في القواعد)، فكتابةٌ مباشرةٌ من الـSDK
  // تَضَعُ `true` على طلبٍ غيرِ مدفوعٍ فتَشغلُ خانةً من الـ200 بلا حقّ.
  assert.ok(/\.where\("status", "==", "cancelled"\)\s*\n\s*\.where\("needs_refund", "==", true\)\s*\n\s*\.where\("is_paid", "==", true\)/
      .test(code), "استعلامُ المكنسةِ ليس بثلاثِ مساواتٍ (الحالة/العلم/المدفوع)");
  // والمضادّة: الاسمُ ما زال في الخامّ (التعليقُ الشارحُ للنقل) — فلو غابَ
  // لكانَ التجريدُ حَجبَ أكثرَ من التعليقات.
  assert.ok(idx.includes("creditCancelledRefund"),
      "اختفى الاسمُ من الملفِّ كلِّه — راجِعْ ما جرّده الفحص");
});

t("(ح٦) وحُرّاسُ المكنسةِ هي حُرّاسُ المحرّكِ نفسُها — مجموعةً", () => {
  const code = codeOf(idx);
  const engineSrc = codeOf(mod);
  // حارسٌ في المكنسةِ لا يَعرفُه المحرّكُ = إيداعٌ يُتخطّى بصمت؛ والعكسُ
  // = قراءةٌ زائدةٌ كلَّ دورة. الطرفانِ يَتحرّكانِ معاً أو يَسقطُ الفحص.
  const sweep = code.slice(code.indexOf("cancelled-refund") - 2000,
      code.indexOf("cancelled-refund"));
  for (const f of ["refund_credited", "payment_status", "auto_refund_processed",
    "is_paid", "subscription"]) {
    assert.ok(sweep.includes(f), `حارسُ ${f} غائبٌ عن المكنسة`);
  }
  const eng = engineSrc
      .slice(engineSrc.indexOf("async function creditCancelledRefund"));
  for (const f of ["refund_credited", "payment_status", "auto_refund_processed"]) {
    assert.ok(eng.includes(f), `حارسُ ${f} غائبٌ عن المحرّك`);
  }
});

// ── النافذةُ تَنضَح: كلُّ مَخرَجٍ يُسقِطُ الدَّينَ يَمسحُ العلم ──────────
//
// العائلةُ الرابعةُ من «نافذةٌ تَمتلئُ بما لا يُزيلُه أحد» في هذه الجلسة
// (نافذةُ البثِّ المجدول، ونافذةُ «مدفوعٌ وعالق»، ثم هذه) — و**هذه كتبتُها
// أنا** في الشريحةِ السابقةِ بعد أن وثّقتُ الدرسَ بنفسِه في `rewards.js`:
// «الفشلُ يَكتبُ علمَه، والمكنسةُ تَستعلمُ العلمَ، فالمجموعةُ لا تَحوي إلّا
// الفشل». استعملتُ النمطَ الصحيحَ للعلمَين الجديدَين وأخطأتُه هنا، لأنّ
// `needs_refund` كان قائماً فبدا علماً جاهزاً — وهو **حالةُ دَينٍ** لا علمَ
// فشل: يَبقى `true` بعد نجاحِ الاستردادِ فيَشغلُ خانتَه إلى الأبد.
//
// وأختاها في الملفِّ نفسِه على بُعدِ سبعينَ سطراً (`reopenFieldsIfSystemCancelled`
// و`reconcileAndSettle`) تَكتبانِ `needs_refund: false` مع `refund_credited:
// true` معاً — فالعُرفُ كان موجوداً والدالّةُ الجديدةُ وحدَها خرجت عليه.
tAsync("(ح٧) النجاحُ يَمسحُ العلم — وإلّا بَقيَ في النافذةِ إلى الأبد", async () => {
  const db = fakeDb({
    "orders/o1": {code: "A1", amount: 230, client_id: "c1", needs_refund: true},
    "wallets/c1": {balance: 10},
  });
  const r = await engine.creditCancelledRefund(db, {
    orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
    amount: 230, code: "A1",
  }, async () => null);
  assert.strictEqual(r.credited, true);
  const d = db._store.get("orders/o1");
  assert.strictEqual(d.refund_credited, true);
  assert.strictEqual(d.needs_refund, false,
      "طلبٌ نُجِحَ استردادُه يَبقى في نافذةِ المكنسةِ ويُزحزحُ الفاشل");
});

tAsync("(ح٨) و«سُوِّيَ سلفاً» يَمسحُه كذلك — الدَّينُ غيرُ مستحقّ", async () => {
  for (const settled of [
    {refund_credited: true},
    {payment_status: "refunded"},
    {auto_refund_processed: true},
  ]) {
    const db = fakeDb({
      "orders/o1": Object.assign(
          {code: "A1", amount: 230, client_id: "c1", needs_refund: true},
          settled),
      "wallets/c1": {balance: 10},
    });
    const r = await engine.creditCancelledRefund(db, {
      orderRef: db._ref("orders/o1"), orderId: "o1", clientId: "c1",
      amount: 230, code: "A1",
    }, async () => null);
    assert.strictEqual(r.skipped, "already_settled");
    assert.strictEqual(db._store.get("orders/o1").needs_refund, false,
        `سُوِّيَ بـ${Object.keys(settled)[0]} والعلمُ باقٍ`);
    // ولا إيداعَ مزدوجاً بحالٍ.
    assert.strictEqual(db._store.get("wallets/c1").balance, 10);
  }
});

t("(ح٩) والعُرفُ عُرفُ الملفِّ لا استثناءً — مجموعةُ مواضعِ المسح", () => {
  const eng = codeOf(mod);
  // ثلاثةُ مسارٍ تُسقِطُ الدَّينَ: الشقيقتانِ القائمتانِ ومَخرَجا الدالّةِ
  // الجديدة (النجاحُ و«سُوِّيَ سلفاً»). والفشلُ **لا** يَمسح.
  const sites = (eng.match(/needs_refund: false/g) || []).length;
  assert.strictEqual(sites, 4,
      `مواضعُ مسحِ needs_refund ${sites} ≠ 4 — موضعٌ زائدٌ أو ناقص، راجِعْه`);
  const fn = eng.slice(eng.indexOf("async function creditCancelledRefund"));
  const fail = fn.slice(fn.indexOf("refund_credit_failed: true"));
  assert.ok(!fail.includes("needs_refund: false"),
      "فرعُ الفشلِ يَمسحُ العلمَ — فلا تُعيدُ المكنسةُ المحاولةَ أبداً");
  // والمضادّة: الشرحُ ما زال في الخامّ (الفحصُ يَقرأُ المُجرَّد).
  assert.ok(mod.includes("نافذةُ البثِّ المجدول") || mod.includes("تَنضَح"),
      "اختفى شرحُ القاعدةِ — فلا يَعرفُ القارئُ لِمَ تُمسَح");
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
  console.log(`\nrefund_engine tests: ${passed} passed`);
})();

// ── «refunding» مؤشّرٌ عابرٌ لا حالةٌ نهائيّة ────────────────────────────────
//
// كانت تُكتب في موضعَين و**لا يقرأها شيء** — لا شاشة ولا قاعدة ولا دالّة — ثمّ
// تبقى قائمةً في فرعَي فشلٍ من أربعة. والتعليقُ فوقها يسمّيها «مؤشّراً دائماً
// قابلاً للمصالحة»، والمصالحةُ غيرُ موجودة.
//
// والأثرُ ليس نظريّاً: `admin_order_details_screen` يقرأ
// `moyasar_status ?? payment_status`، فطلبٌ مدفوعٌ بالمحفظة (لا `moyasar_status`
// له) عالقٌ على "refunding" يُسقط شروطَ void/refund/capture **كلَّها**
// و`alreadyFinal` معاً — بطاقةُ عمليّاتٍ بلا زرٍّ وبلا سبب، في اللحظة التي
// صُعِّد فيها فشلُ الاسترداد إلى الأدمن.
//
// القاعدة: كلُّ مخرجٍ من `autoResolveUnfulfilledPaidOrder` يستبدلها —
// refunded/voided عند النجاح، **paid** حين لم يتحرّك شيء (معاملةُ المحفظة
// ذرّية: إمّا التزمت كلُّها أو لا شيء)، و**payment_review** حين لا نعرف
// (فشلُ البوابة) — وهي كلمةُ `voidOrRefundTampered` نفسِها للحالة عينِها،
// ويعرفها `index.js` فلا يُحيي الطلبَ تلقائياً.
{
  const src = require("fs").readFileSync(
      require("path").join(__dirname, "..", "refund_engine.js"), "utf8");
  // نحجب التعليقات: الوحدةُ تشرح القرارَ بذكر "refunding" في تعليقها، فالفحصُ
  // بلا حجبٍ يفشل على توثيقه هو — نفسُ درسِ حارسِ تمارا ونشرِ الدوالّ.
  const code = src.split("\n")
      .filter((l) => !l.trimStart().startsWith("//") &&
                     !l.trimStart().startsWith("*") &&
                     !l.trimStart().startsWith("/*"))
      .join("\n");

  t("(ز١) refunding تُكتب مرّتين فقط — ولا ثالثة", () => {
    const n = (code.match(/payment_status: "refunding"/g) || []).length;
    assert.strictEqual(n, 2, "موضعُ كتابةٍ ثالث لمؤشّرٍ لا يقرأه أحد");
  });

  t("(ز٢) ولا تُترك في أيّ فرعِ فشل", () => {
    // كلُّ نداءٍ لـ_failAndEscalate يمرّر extra فيه payment_status.
    const calls = code.match(/_failAndEscalate\([\s\S]{0,260}?\);/g) || [];
    assert.ok(calls.length >= 4, `وُجد ${calls.length} نداءً فقط`);
    for (const c of calls) {
      if (c.includes("function _failAndEscalate")) continue;
      assert.ok(/payment_status:/.test(c),
          `فرعُ فشلٍ بلا payment_status — يبقى على "refunding":\n${c}`);
    }
  });

  t("(ز٣) الحالتان المستعملتان paid وpayment_review لا غيرهما", () => {
    const states = new Set();
    for (const m of code.matchAll(/_failAndEscalate\([\s\S]{0,260}?payment_status: "([a-z_]+)"/g)) {
      states.add(m[1]);
    }
    assert.deepStrictEqual([...states].sort(), ["paid", "payment_review"]);
  });

  t("(ز٤) التعليقُ الذي يشرح القرار ما زال في النصّ الخامّ", () => {
    // لو أفرط الحجبُ لما بقي شيءٌ يُفحَص — نتأكّد أنّ ما حُجب كان تعليقاً حقّاً.
    assert.ok(src.includes("refunding"), "اختفت الكلمةُ من الملفّ كلِّه");
    assert.ok(src.includes("عابر"), "اختفى التعليقُ الذي يصفها بالعابرة");
  });
}

