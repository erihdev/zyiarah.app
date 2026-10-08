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
    // `payReferralBonus` يَقرأُ وجودَ مستندِ الإحالةِ **خارجَ** المعامَلة.
    get: async () => snapOf(p),
    collection: (c) => ({doc: (id) => mkRef(`${p}/${c}/${id}`)}),
  });
  const snapOf = (p) => {
    const d = store.get(p);
    return {exists: d !== undefined, data: () => d, get: (f) => (d || {})[f]};
  };
  /**
   * استعلامٌ مُصغَّرٌ بمساواةٍ واحدةٍ أو أكثر — لِمَسارِ الإحالةِ الاحتياطيّ
   * (مستنداتٌ قديمةٌ بمعرّفٍ عشوائيّ).
   * @param {string} c المجموعة
   * @param {Array} conds الشروط
   * @return {object} استعلام
   */
  const mkQuery = (c, conds) => ({
    where: (f, _op, v) => mkQuery(c, [...conds, [f, v]]),
    limit: () => mkQuery(c, conds),
    get: async () => {
      const docs = [];
      for (const [path, d] of store) {
        if (!path.startsWith(`${c}/`) || path.split("/").length !== 2) continue;
        if (conds.every(([f, v]) => d[f] === v)) {
          docs.push({id: path.split("/").pop(), ref: mkRef(path),
            data: () => d, get: (f) => d[f]});
        }
      }
      return {empty: docs.length === 0, docs, size: docs.length};
    },
  });
  return {
    _store: store, _ref: mkRef,
    collection: (c) => ({
      doc: (id) => mkRef(`${c}/${id}`),
      where: (f, op, v) => mkQuery(c, [[f, v]]),
    }),
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

// ── رصيدُ زياراتِ الاشتراك ────────────────────────────────────────────────
tAsync("(د١) الإكمال: الزيارةُ تُخصَمُ من العميلةِ ومن العقد، والعلمُ يُمحى",
    async () => {
      const db = fakeDb({
        "orders/o9": {
          code: "S9", status: "completed", contract_id: "k1",
          visit_accounting_pending: true,
        },
      });
      const r = await rewards.settleVisitAccounting(db, {
        orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
        status: "completed", code: "S9",
      }, async () => null);
      assert.strictEqual(r.settled, true);
      assert.strictEqual(r.delta, -1);
      assert.deepStrictEqual(db._store.get("users/c1").visits_remaining,
          FieldValue.increment(-1));
      assert.deepStrictEqual(db._store.get("contracts/k1").visits_remaining,
          FieldValue.increment(-1),
          "عدّادُ العقدِ لم يُخصَم — بطاقةُ الباقةِ تَعرضُ رصيداً خاطئاً");
      const o = db._store.get("orders/o9");
      assert.strictEqual(o.visit_counted, true);
      assert.deepStrictEqual(o.visit_accounting_pending, FieldValue.delete());
    });

tAsync("(د٢) الإلغاء: تُردُّ زيارةٌ **استُهلكت** فقط", async () => {
  const db = fakeDb({
    "orders/o9": {code: "S9", status: "cancelled", visit_counted: true},
  });
  const r = await rewards.settleVisitAccounting(db, {
    orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
    status: "cancelled", code: "S9",
  }, async () => null);
  assert.strictEqual(r.delta, 1);
  assert.deepStrictEqual(db._store.get("users/c1").visits_remaining,
      FieldValue.increment(1));
  assert.strictEqual(db._store.get("orders/o9").visit_counted, false);
});

tAsync("(د٣) وإلغاءُ ما لم يُستهلَك لا يَخلقُ زيارةً مجّانيّة", async () => {
  const db = fakeDb({
    "orders/o9": {
      code: "S9", status: "cancelled", visit_accounting_pending: true,
    },
  });
  const r = await rewards.settleVisitAccounting(db, {
    orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
    status: "cancelled", code: "S9",
  }, async () => null);
  assert.strictEqual(r.skipped, "never_counted");
  assert.strictEqual(db._store.get("users/c1"), undefined,
      "رُدَّت زيارةٌ لم تُستهلَك — دفعةٌ مدفوعةٌ سلفاً تُصبحُ مجّانيّة");
  assert.deepStrictEqual(db._store.get("orders/o9").visit_accounting_pending,
      FieldValue.delete(), "علمٌ يَبقى فتَقرؤه المكنسةُ للأبد");
});

tAsync("(د٤) والخصمُ مرّتَين ممتنع — `visit_counted` طازجٌ داخلَ المعامَلة",
    async () => {
      const db = fakeDb({
        "orders/o9": {code: "S9", status: "completed", visit_counted: true},
      });
      const r = await rewards.settleVisitAccounting(db, {
        orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
        status: "completed", code: "S9",
      }, async () => null);
      assert.strictEqual(r.skipped, "already_counted");
      assert.strictEqual(db._store.get("users/c1"), undefined);
    });

tAsync("(د٥) حالةٌ تَحرّكت بعد الفشل ⇒ لا تسويةَ، والعلمُ يُمحى", async () => {
  // المكنسةُ تُمرّرُ الحالةَ **الراهنة**: طلبٌ فشلَ خصمُه ثم أُعيد إلى
  // `in_progress` لا يُسوّى، ولا يَبقى في مجموعةِ المكنسةِ للأبد.
  const db = fakeDb({
    "orders/o9": {
      code: "S9", status: "in_progress", visit_accounting_pending: true,
    },
  });
  const r = await rewards.settleVisitAccounting(db, {
    orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
    status: "in_progress", code: "S9",
  }, async () => null);
  assert.strictEqual(r.skipped, "not_terminal");
  assert.deepStrictEqual(db._store.get("orders/o9").visit_accounting_pending,
      FieldValue.delete());
});

tAsync("(د٦) الفشل: العلمُ والسببُ، ويُصعَّدُ مرّةً لا مرّتَين", async () => {
  const db = fakeDb({"orders/o9": {code: "S9", status: "completed"}});
  db.runTransaction = async () => {
    throw new Error("deadline exceeded");
  };
  const pushes = [];
  const r = await rewards.settleVisitAccounting(db, {
    orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
    status: "completed", code: "S9",
  }, async (...a) => pushes.push(a));
  assert.strictEqual(r.settled, false);
  assert.strictEqual(r.failed, "deadline exceeded");
  const o = db._store.get("orders/o9");
  assert.strictEqual(o.visit_accounting_pending, true,
      "بلا العلمِ لا تَراه المكنسةُ أبداً — وهو العطلُ بعينِه");
  assert.strictEqual(o.visit_accounting_failed_reason, "deadline exceeded");
  assert.strictEqual(o.visit_accounting_alerted, true);
  assert.strictEqual(pushes.length, 1);
  assert.strictEqual(pushes[0][0], "ADMIN_BROADCAST");
  assert.deepStrictEqual(pushes[0][5], ["super_admin", "accountant_admin"]);

  // ومحاولةٌ ثانيةٌ فاشلةٌ لا تُصعِّدُ مرّةً أخرى
  const again = await rewards.settleVisitAccounting(db, {
    orderRef: db._ref("orders/o9"), orderId: "o9", clientId: "c1",
    status: "completed", code: "S9", alreadyAlerted: true,
  }, async (...a) => pushes.push(a));
  assert.strictEqual(again.failed, "deadline exceeded");
  assert.strictEqual(pushes.length, 1, "تصعيدٌ مكرَّرٌ لكلِّ دورةِ مكنسة");
});

// ── مكافأةُ الإحالة ──────────────────────────────────────────────────────
tAsync("(هـ١) الصرف: ٥٠ للمُحيل، سجلٌّ، كوبونٌ للمُحالة، والحالةُ تَنقلب",
    async () => {
      const db = fakeDb({
        "orders/o7": {code: "R7", client_id: "ref1"},
        "referrals/ref1": {status: "pending", referrer_id: "boss"},
      });
      const pushes = [];
      const r = await rewards.payReferralBonus(db, {
        refereeUid: "ref1", orderId: "o7",
        orderRef: db._ref("orders/o7"), code: "R7",
      }, async (...a) => pushes.push(a));
      assert.strictEqual(r.paid, true);
      assert.deepStrictEqual(db._store.get("wallets/boss").balance,
          FieldValue.increment(50));
      const tx = db._store.get("wallets/boss/transactions/refbonus_ref1");
      assert.strictEqual(tx.amount, 50);
      assert.strictEqual(tx.type, "referral_reward");
      assert.strictEqual(db._store.get("referrals/ref1").status, "rewarded");
      assert.strictEqual(db._store.get("orders/o7").referral_processed, true);
      // وكوبونُ المُحالةِ بالمخطّطِ الذي يَقرؤه التطبيقُ فعلاً
      const cp = db._store.get("promo_codes/REFREF110");
      assert.ok(cp, "لم يُكتَبْ كوبونُ الإحالة");
      assert.strictEqual(cp.type, "percentage");
      assert.strictEqual(cp.value, 10);
      assert.strictEqual(cp.maxUses, 1);
      assert.strictEqual(cp.status, "active");
      assert.strictEqual(cp.target_user_id, "ref1");
      assert.strictEqual(pushes.length, 2, "دفعتانِ: للمُحيلِ وللمُحالة");
    });

tAsync("(هـ٢) صُرِفت سلفاً ⇒ لا صرفَ ثانٍ، والعلمُ يُنظَّف", async () => {
  const db = fakeDb({
    "orders/o7": {code: "R7", client_id: "ref1", referral_payout_pending: true},
    "referrals/ref1": {status: "rewarded", referrer_id: "boss"},
  });
  const pushes = [];
  const r = await rewards.payReferralBonus(db, {
    refereeUid: "ref1", orderId: "o7",
    orderRef: db._ref("orders/o7"), code: "R7",
  }, async () => pushes.push(1));
  assert.strictEqual(r.paid, false);
  assert.strictEqual(r.skipped, "nothing_to_pay");
  assert.strictEqual(db._store.get("wallets/boss"), undefined,
      "صُرِفت المكافأةُ مرّتَين");
  assert.strictEqual(pushes.length, 0);
  assert.deepStrictEqual(db._store.get("orders/o7").referral_payout_pending,
      FieldValue.delete(), "علمٌ يَبقى فتَقرؤه المكنسةُ للأبد");
});

tAsync("(هـ٣) ولا مستندَ إحالةٍ أصلاً ⇒ تخطٍّ نظيفٌ لا فشل", async () => {
  const db = fakeDb({
    "orders/o7": {code: "R7", client_id: "ref1", referral_payout_pending: true},
  });
  const r = await rewards.payReferralBonus(db, {
    refereeUid: "ref1", orderId: "o7",
    orderRef: db._ref("orders/o7"), code: "R7",
  }, async () => null);
  assert.strictEqual(r.skipped, "no_referral");
  assert.deepStrictEqual(db._store.get("orders/o7").referral_payout_pending,
      FieldValue.delete());
});

tAsync("(هـ٤) الفشل: العلمُ والسببُ، وتصعيدٌ واحدٌ يَضمُّ التسويق",
    async () => {
      const db = fakeDb({
        "orders/o7": {code: "R7", client_id: "ref1"},
        "referrals/ref1": {status: "pending", referrer_id: "boss"},
      });
      db.runTransaction = async () => {
        throw new Error("aborted");
      };
      const pushes = [];
      const r = await rewards.payReferralBonus(db, {
        refereeUid: "ref1", orderId: "o7",
        orderRef: db._ref("orders/o7"), code: "R7",
      }, async (...a) => pushes.push(a));
      assert.strictEqual(r.failed, "aborted");
      const o = db._store.get("orders/o7");
      assert.strictEqual(o.referral_payout_pending, true,
          "بلا العلمِ لا تَراه المكنسةُ — ٥٠ ر.س تَضيعُ بلا أثر");
      assert.strictEqual(o.referral_payout_failed_reason, "aborted");
      assert.strictEqual(o.referral_payout_alerted, true);
      assert.strictEqual(pushes.length, 1);
      assert.strictEqual(pushes[0][0], "ADMIN_BROADCAST");
      assert.deepStrictEqual(pushes[0][5],
          ["super_admin", "accountant_admin", "marketing_admin"]);

      const again = await rewards.payReferralBonus(db, {
        refereeUid: "ref1", orderId: "o7",
        orderRef: db._ref("orders/o7"), code: "R7", alreadyAlerted: true,
      }, async (...a) => pushes.push(a));
      assert.strictEqual(again.failed, "aborted");
      assert.strictEqual(pushes.length, 1, "تصعيدٌ مكرَّرٌ كلَّ دورةِ مكنسة");
    });

tAsync("(هـ٥) والمسارُ الاحتياطيُّ: مستندُ إحالةٍ بمعرّفٍ عشوائيٍّ قديم",
    async () => {
      const db = fakeDb({
        "orders/o7": {code: "R7", client_id: "ref1"},
        "referrals/xyz99": {
          status: "pending", referrer_id: "boss", referee_id: "ref1",
        },
      });
      const r = await rewards.payReferralBonus(db, {
        refereeUid: "ref1", orderId: "o7",
        orderRef: db._ref("orders/o7"), code: "R7",
      }, async () => null);
      assert.strictEqual(r.paid, true, "المستندُ القديمُ لم يُعثَرْ عليه");
      assert.strictEqual(db._store.get("referrals/xyz99").status, "rewarded");
      // والمعرّفُ الحتميُّ للسجلِّ يَتبعُ **معرّفَ مستندِ الإحالة** لا uid
      assert.ok(db._store.get("wallets/boss/transactions/refbonus_xyz99"));
    });

// ── تجميعُ تقييمِ السائق ──────────────────────────────────────────────────
tAsync("(و١) أوّلُ تقييمٍ يُؤسّسُ المتوسّطَ من الصفرِ لا من بذرِ ٥٫٠",
    async () => {
      const db = fakeDb({
        "orders/o5": {code: "T5", rating: 4},
        // البذرُ عند التوفير: rating 5 **بلا** عدّاد.
        "drivers/d1": {rating: 5, name: "x"},
      });
      const r = await rewards.aggregateRating(db, {
        orderRef: db._ref("orders/o5"), orderId: "o5", driverId: "d1",
        rating: 4, code: "T5",
      }, async () => null);
      assert.strictEqual(r.aggregated, true);
      const d = db._store.get("drivers/d1");
      assert.strictEqual(d.rating_count, 1);
      assert.strictEqual(d.rating_avg, 4, "بذرُ ٥٫٠ دخلَ المتوسّط");
      assert.strictEqual(d.rating, 4);
      assert.strictEqual(db._store.get("orders/o5").rating_aggregated, true);
    });

tAsync("(و١ب) وبذرٌ **غيرُ رقميٍّ** لا يُفسِدُ أوّلَ متوسّط", async () => {
  // اختبارُ قضمٍ لم يَقضم كشفَ أنّ شرطَ `count > 0` ليس حسابيّاً: `avg * 0`
  // صفرٌ أيّاً كان `avg`. فما يَحرُسُه حقّاً هو **البذرُ التالف**:
  // `Number("ممتاز")` هو `NaN`، و`NaN * 0` هو `NaN`، فالمتوسّطُ كلُّه
  // يَصيرُ `NaN` (وFirestore لا تَقبلُه فتَسقطُ الكتابة).
  const db = fakeDb({
    "orders/o5": {code: "T5", rating: 4},
    "drivers/d1": {rating: "ممتاز"},
  });
  const r = await rewards.aggregateRating(db, {
    orderRef: db._ref("orders/o5"), orderId: "o5", driverId: "d1",
    rating: 4, code: "T5",
  }, async () => null);
  assert.strictEqual(r.aggregated, true);
  const d = db._store.get("drivers/d1");
  assert.strictEqual(d.rating_avg, 4,
      `المتوسّطُ ${d.rating_avg} — بذرٌ تالفٌ تسرّبَ إلى الحساب`);
  assert.strictEqual(d.rating_count, 1);
});

tAsync("(و٢) والمتوسّطُ التزايديُّ صحيح", async () => {
  const db = fakeDb({
    "orders/o6": {code: "T6", rating: 3},
    "drivers/d1": {rating_count: 3, rating_avg: 5},
  });
  await rewards.aggregateRating(db, {
    orderRef: db._ref("orders/o6"), orderId: "o6", driverId: "d1",
    rating: 3, code: "T6",
  }, async () => null);
  const d = db._store.get("drivers/d1");
  assert.strictEqual(d.rating_count, 4);
  assert.strictEqual(d.rating_avg, 4.5, "(5*3 + 3) / 4 = 4.5");
});

tAsync("(و٣) **والإعادةُ آمنة**: المانعُ علَمٌ على المستندِ لا شرطُ حدث",
    async () => {
      // كان المانعُ `before.rating != null` — حدثيّاً، فالدالّةُ لم تَكن
      // قابلةً للإعادةِ من مكنسةٍ أصلاً (تَحتسبُ التقييمَ مرّتَين).
      const db = fakeDb({
        "orders/o5": {code: "T5", rating: 4, rating_aggregated: true,
          rating_agg_pending: true},
        "drivers/d1": {rating_count: 1, rating_avg: 4},
      });
      const r = await rewards.aggregateRating(db, {
        orderRef: db._ref("orders/o5"), orderId: "o5", driverId: "d1",
        rating: 4, code: "T5",
      }, async () => null);
      assert.strictEqual(r.skipped, "already_aggregated");
      assert.strictEqual(db._store.get("drivers/d1").rating_count, 1,
          "احتُسِبَ التقييمُ مرّتَين");
      assert.deepStrictEqual(db._store.get("orders/o5").rating_agg_pending,
          FieldValue.delete());
    });

tAsync("(و٤) وتقييمٌ خارجَ المدى أو سائقٌ محذوفٌ ⇒ تخطٍّ لا فشل", async () => {
  const bad = fakeDb({"orders/o5": {rating: 9}});
  assert.strictEqual(
      (await rewards.aggregateRating(bad, {
        orderRef: bad._ref("orders/o5"), orderId: "o5", driverId: "d1",
        rating: 9,
      }, async () => null)).skipped, "invalid_rating");
  const gone = fakeDb({"orders/o5": {rating: 4, rating_agg_pending: true}});
  const r = await rewards.aggregateRating(gone, {
    orderRef: gone._ref("orders/o5"), orderId: "o5", driverId: "ghost",
    rating: 4,
  }, async () => null);
  assert.strictEqual(r.skipped, "no_driver");
  assert.deepStrictEqual(gone._store.get("orders/o5").rating_agg_pending,
      FieldValue.delete(), "علمٌ يَبقى على سائقٍ لا يَعودُ أبداً");
});

tAsync("(و٥) الفشل: العلمُ والسببُ، وتصعيدٌ واحد", async () => {
  const db = fakeDb({
    "orders/o5": {code: "T5", rating: 4}, "drivers/d1": {rating_count: 0},
  });
  db.runTransaction = async () => {
    throw new Error("contention");
  };
  const pushes = [];
  const r = await rewards.aggregateRating(db, {
    orderRef: db._ref("orders/o5"), orderId: "o5", driverId: "d1",
    rating: 4, code: "T5",
  }, async (...a) => pushes.push(a));
  assert.strictEqual(r.failed, "contention");
  const o = db._store.get("orders/o5");
  assert.strictEqual(o.rating_agg_pending, true);
  assert.strictEqual(o.rating_agg_failed_reason, "contention");
  assert.strictEqual(pushes.length, 1);
  assert.deepStrictEqual(pushes[0][5], ["super_admin", "orders_manager"]);
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

t("(ج١) index.js لا يَحملُ المعامَلاتِ إنلاين، والنداءاتُ تَمرُّ بالوحدة", () => {
  assert.ok(!/transactions"\)\s*\.doc\(`qatrat_\$\{orderId\}`\)/.test(idx),
      "بناءُ معامَلةِ قطرات عادَ إلى index.js");
  assert.ok(!idx.includes("[coupon] use-count failed for order"),
      "`catch` عدِّ الكوبونِ الصامتُ عادَ");
  assert.ok(!idx.includes("[rewards] qatrat txn failed"),
      "`catch` قطراتِ الصامتُ عادَ");
  // الموضعُ الثالث (2026-10-05): تسويةُ رصيدِ زياراتِ الاشتراك.
  assert.ok(!idx.includes("[linked] visit accounting failed for"),
      "`catch` تسويةِ الزياراتِ الصامتُ عادَ — خصمٌ فاشلٌ يَترُكُ زيارةً " +
    "مدفوعةً للعميلةِ بعد استهلاكِها، وردٌّ فاشلٌ يُفقدُها واحدةً تَستحقُّها");
  assert.ok(!/t\.set\(userRef, \{\s*visits_remaining: FieldValue/.test(idx),
      "بناءُ معامَلةِ الزياراتِ عادَ إلى index.js");
  // والنداءاتُ الثلاثةُ قائمة
  // والموضعُ الرابع (2026-10-05): مكافأةُ الإحالة — ٥٠ ر.س وكوبون.
  assert.ok(!idx.includes("[referral] payout txn failed for"),
      "`catch` مكافأةِ الإحالةِ الصامتُ عادَ — ٥٠ ر.س للمُحيلِ وكوبونُ " +
    "المُحالةِ يَضيعانِ بلا تنبيهٍ ولا محاولةٍ ثانية");
  assert.ok(!idx.includes("async function processReferralRewardServer"),
      "الدالّةُ عادَت إلى index.js");
  // والموضعُ الخامس: تجميعُ تقييمِ السائق — متوسّطٌ تزايديٌّ يَضيعُ بلا إعادة.
  assert.ok(!idx.includes("aggregateDriverRating: ${event.params.orderId}"),
      "`catch` تجميعِ التقييمِ الصامتُ عادَ");
  assert.ok(!/tx\.update\(ref, \{\s*rating_count:/.test(idx),
      "حسابُ المتوسّطِ عادَ إنلاين إلى index.js");
  for (const call of [
    "rewards.grantQatratPoints(db, {",
    "rewards.countCouponUse(db, {",
    "rewards.settleVisitAccounting(db, {",
    "rewards.payReferralBonus(db, {",
    "rewards.aggregateRating(db, {",
  ]) {
    assert.ok(idx.includes(call), `النداءُ غائب: ${call}`);
  }
  // والمضادّة: الأسماءُ ما زالت في الخامِّ (التعليقُ الشارحُ للنقل).
  assert.ok(idxRaw.includes("grantQatratPoints"));
  assert.ok(idxRaw.includes("qatrat txn failed"),
      "اختفى اقتباسُ السطرِ القديمِ من التوثيق — راجِعْ ما جرّده الفحص");
  assert.ok(idxRaw.includes("visits_remaining"),
      "الحقلُ اختفى من index.js كلِّه — راجِعْ المكنسةَ والنقل");
});

t("(ج٢) والمكنسةُ تَستعلمُ **العلمَ** لا الحالة — وهو جوهرُ العلاج", () => {
  // لو استُعلِمَت الحالةُ لازدحمت النافذةُ بما نُجِح، فلا يَبلغُها الفاشل.
  // ومجموعةُ الأعلامِ **مُشتَقّةٌ من الوحدةِ نفسِها**، فعلَمٌ رابعٌ بلا
  // مكنسةٍ يَسقطُ الفحصَ بدلَ أن يَمرّ.
  const names = Object.keys(rewards.PENDING_FLAGS);
  assert.ok(names.length >= 3,
      `أعلامُ الوحدةِ ${names.length} — انهارَ التعدادُ فالفحصُ فارغ`);
  for (const k of names) {
    assert.ok(
        idx.includes(`.where(rewards.PENDING_FLAGS.${k}, "==", true)`),
        `استعلامُ المكنسةِ لـ${k} ليس على علمِ الفشل (أو غائب)`);
  }
  // ولكلِّ علَمٍ سطرُ سجلٍّ **في كتلتِه**. قائمةُ الأسطرِ المكتوبةُ كانت
  // تَتخلّفُ عن العلمِ الخامسِ بصمت؛ وعَدُّ الأسطرِ في الملفِّ كلِّه
  // يَتجاوزُ النطاقَ (مكنسةُ `refund_engine` لها سطرُها أيضاً) — فالرابطُ
  // هو كتلةُ العلمِ نفسُها.
  for (const k of names) {
    const at = idx.indexOf(`.where(rewards.PENDING_FLAGS.${k}, "==", true)`);
    const blk = idx.slice(at, at + 1400);
    assert.ok(/opsHealthSweep: [a-z-]+ retried=/.test(blk),
        `كتلةُ ${k} بلا سطرِ سجلّ — فشلٌ صامتٌ في المكنسةِ نفسِها`);
    assert.ok(/alreadyAlerted:/.test(blk),
        `كتلةُ ${k} لا تُمرّرُ alreadyAlerted — تصعيدٌ مكرَّرٌ كلَّ دورة`);
  }
});

t("(ج٣) والنجاحُ يَمحو العلمَ — موضعانِ لكلِّ علمٍ لا أقلّ", () => {
  // علمٌ لا يُمحى يَجعلُ المكنسةَ تَقرأُ المنجَزَ للأبد (نفسُ عطلِ النافذة).
  const mod = codeOf(modRaw);
  for (const k of Object.keys(rewards.PENDING_FLAGS)) {
    const flag = `PENDING_FLAGS.${k}`;
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
  
// ═══════════════════════════════════════════════════════════════════════
// **لا جوائزَ لطلبٍ لم يُدفَع** — الفرعانِ على قاعدةٍ واحدة.
//
// الشرطُ كان في فرعِ الإلغاءِ وحدَه (`after.is_paid === true`) وغائباً عن فرعِ
// الإكمالِ — في `onOrderRewards` نفسِها، على بُعدِ عشرين سطراً. وكان **حيّاً**:
// `moyasarRefundPayment` يَكتبُ `is_paid: false` ولا يَمَسُّ `status`، فطلبٌ
// `scheduled` استُردَّ مالُه يَبقى في لوحةِ السائقِ فيُكمِلُه، فتُمنَحُ
// القطراتُ ومكافأةُ الإحالةِ لمالٍ أُعيد.
// ═══════════════════════════════════════════════════════════════════════
/**
 * @param {string} src المصدرُ
 * @param {string} name اسمُ الصادر
 * @return {string} جسمُه حتى الصادرِ التالي
 */
function _exportBody(src, name) {
  const i = src.indexOf(`exports.${name}`);
  assert.ok(i > -1, `exports.${name} اختفى`);
  const j = src.indexOf("\nexports.", i + 10);
  return src.slice(i, j < 0 ? src.length : j);
}

t("(ن) فرعُ الإكمالِ مشروطٌ بالدفعِ، وقبلَ أيِّ منحٍ", () => {
  const b = _exportBody(idx, "onOrderRewards");
  const gate = b.indexOf("completed && after.is_paid !== true");
  assert.ok(gate > -1, "فرعُ الإكمالِ بلا شرطِ دفع — القطراتُ والإحالةُ " +
    "تُمنَحانِ لطلبٍ أُعيد مالُه");
  const qat = b.indexOf("grantQatratPoints(");
  const ref = b.indexOf("payReferralBonus(");
  assert.ok(qat > -1 && ref > -1);
  assert.ok(gate < qat && gate < ref,
      "الشرطُ بعدَ المنحِ لا يَمنعُ شيئاً — الترتيبُ هو الإصلاح");
});

t("(س) والفرعانِ على القاعدةِ نفسِها — لا واحدٌ منهما", () => {
  const b = _exportBody(idx, "onOrderRewards");
  const n = (b.match(/after\.is_paid\s*!==\s*true|after\.is_paid === true/g) || [])
      .length;
  assert.strictEqual(n, 2,
      `شرطُ الدفعِ يَرِدُ ${n} مرّةً في onOrderRewards — المقصودُ فرعانِ ` +
      `(الإكمالُ والإلغاء)؛ زيادةٌ أو نقصٌ يُراجَع`);
  assert.ok(/after\.is_paid === true &&/.test(b),
      "شرطُ فرعِ الإلغاءِ زالَ — وهو السابقةُ التي يَقيسُ عليها الإكمال");
  // المضادّةُ: الصيغةُ ما زالت في الخامِّ (الفحوصُ تَقرأُ المُجرَّد).
  assert.ok(idxRaw.includes("after.is_paid !== true"));
});

t("(ع) وشواهدُ التعليلِ الثلاثةُ قائمة", () => {
  // (١) الاستردادُ يَكتبُ `is_paid: false` ولا يَمَسُّ `status`.
  const rf = _exportBody(idx, "moyasarRefundPayment");
  assert.ok(/is_paid:\s*false/.test(rf),
      "الاستردادُ لم يَعُد يَكتبُ is_paid: false — يُراجَعُ التعليل");
  assert.ok(!/\bstatus:\s*"cancelled"/.test(rf),
      "الاستردادُ صارَ يُلغي الطلبَ — فالمَسلكُ تغيّرَ ويُراجَعُ التعليلُ " +
      "لا يُسكَت (الشرطُ يَبقى صحيحاً على كلِّ حال)");
  // (٢) و`scheduled` في قائمةِ السائقِ النشطة، فالطلبُ يَبقى على هاتفِه.
  const lc = fs.readFileSync(
      path.join(__dirname, "..", "..", "lib", "utils", "order_lifecycle.dart"),
      "utf8");
  assert.ok(/kActiveAssignedStatuses = \{[^}]*'scheduled'/.test(lc),
      "scheduled خرجَ من حالاتِ السائقِ النشطة — يُراجَعُ التعليل");
  // (٣) وإكمالُ السائقِ يَكتبُ المُميِّزَ الخادميَّ، وهو ما يُطلِقُ الجوائز.
  const os = fs.readFileSync(
      path.join(__dirname, "..", "..", "lib", "services", "order_service.dart"),
      "utf8");
  assert.ok(/'rewards_handled_by': 'server'/.test(os),
      "المُميِّزُ الخادميُّ لم يَعُد يُكتَبُ عند الإكمال — يُراجَعُ التعليل");
});

console.log(`\nrewards tests: ${passed} passed`);
})();
