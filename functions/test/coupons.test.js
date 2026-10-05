"use strict";

// أهليّةُ الكوبونِ وقيمتُه — تشغيل: node test/coupons.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// `_computeTrustedDiscount` وُضع ليُجيب «كم يستحقُّ هذا الكوبون؟» من مستندِ
// `promo_codes` لا من `discount_amount` الذي يَكتبه العميل. وكان يُجيب
// **المقدار** ويُغفل **الأهليّة**: يَفحصُ `status` و`expiry` فقط، ويُغفل
// ثلاثةً يَفحصُها العميلُ كلَّها (`order_service.validateCoupon`):
//
//   `target_user_id` ..... كوبونُ إحالةٍ موجَّهٌ لعميلةٍ بعينها، وكودُه حتميّ
//                          (`REF`+ستّةُ محارفَ من المعرّف+`10`) ويُرسَل نصّاً
//                          في إشعار. فعميلةٌ أخرى تَصرفُه والخادمُ يَقبل.
//   `restricted_zones` ... كوبونُ منطقةٍ يَعملُ في كلِّ منطقة.
//   `uses`/`maxUses` ..... بلا سقف — وتعليقُ `countCouponUseOnOrderCreate` كان
//                          يقول «والمنعُ النهائيُّ جزءٌ من التسعيرِ الخادميّ»،
//                          وعداً بمنعٍ لم يكن في التسعيرِ الخادميّ.
//
// ═══ و`expiry` بنوعَين: المحرّران لا يَكتبان الشيءَ نفسَه ═══
//
// محرّرُ Flutter يَكتب `Timestamp`، ولوحةُ الويبِ كانت تَكتبُ نصَّ الحقلِ خاماً
// (`"2026-12-31"`). وفحصُ الخادمِ كان `typeof c.expiry.toMillis === "function"`
// — فالنصُّ لا يَملكه و**الفحصُ يُتخطّى كلَّه**: كلُّ كوبونٍ أُنشئ من اللوحةِ
// كان بلا انتهاءٍ خادميّاً، والعميلُ يَفحصُ النوعَين فكانت الواجهةُ أصرمَ من
// الخادم. اللوحةُ أُصلحت، والوحدةُ تَقرأُ النوعَين لأنّ وثائقَ النصِّ قائمةٌ.
//
// ═══ ولمَ الرفضُ وحدَه لا يَكفي ═══
//
// الرفضُ يَرفعُ «المتوقَّع»، و`verifyMoyasarPayment` لا يَسِمُ ولا يُنبّهُ إلّا
// عند `ratio < 0.5`. فكوبونُ 10% غيرُ مؤهَّلٍ يُنتج `ratio = 0.9`: لا وسمَ ولا
// تنبيهَ ولا أثر — وهي بالضبط نسبةُ كوبونِ الإحالة. لذا تُصنَّف الأسباب:
// `ESCALATED_PROBLEMS` ما لا تَبلغُه عميلةٌ صادقة، وما سواه يُسَمُ بلا تنبيه
// لأنّ سباقاً بين التطبيقِ والدفعِ يَبلغُه حسنُ النيّة.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const c = require("../coupons");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  try {
    fn(); console.log("  ok -", name); passed++;
  } catch (e) {
    console.error("  NOT OK -", name, "\n   ", e.message);
    process.exitCode = 1;
  }
}

const idx = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
const stripComments = (src) => src.split("\n")
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
const idxNoComments = stripComments(idx);
const NOW = Date.UTC(2026, 9, 5, 12, 0, 0);
const ok = {code: "WELCOME", type: "percentage", value: 10,
  status: "active", uses: 0, maxUses: 0};
const ctx = {uid: "u1", zoneName: "فيفا", nowMs: NOW};

// ══════════════════════ (أ) الأهليّة ══════════════════════

t("(أ١) مؤهَّلٌ = null، ولا وثيقةَ = not_found", () => {
  assert.strictEqual(c.couponProblem(ok, ctx), null);
  for (const nil of [null, undefined]) {
    assert.strictEqual(c.couponProblem(nil, ctx), "not_found");
  }
});

t("(أ٢) الثلاثةُ المُغفَلة — وهي علّةُ وجودِ الوحدة", () => {
  assert.strictEqual(
      c.couponProblem({...ok, target_user_id: "u2"}, ctx), "other_user");
  assert.strictEqual(
      c.couponProblem({...ok, restricted_zones: ["جازان"]}, ctx), "other_zone");
  assert.strictEqual(
      c.couponProblem({...ok, maxUses: 1, uses: 1}, ctx), "exhausted");
  // وكلٌّ منها يَسقطُ عند مطابقته
  assert.strictEqual(c.couponProblem({...ok, target_user_id: "u1"}, ctx), null);
  assert.strictEqual(
      c.couponProblem({...ok, restricted_zones: ["فيفا", "جازان"]}, ctx), null);
  assert.strictEqual(c.couponProblem({...ok, maxUses: 2, uses: 1}, ctx), null);
});

t("(أ٣) كوبونُ منطقةٍ وطلبٌ بلا منطقةٍ = other_zone لا مرورٌ صامت", () => {
  for (const z of [null, undefined, ""]) {
    assert.strictEqual(
        c.couponProblem({...ok, restricted_zones: ["فيفا"]},
            {...ctx, zoneName: z}), "other_zone", String(z));
  }
  // وقائمةٌ فارغةٌ = بلا قيد (كما يَكتبها المحرّران)
  assert.strictEqual(c.couponProblem({...ok, restricted_zones: []}, ctx), null);
});

t("(أ٤) target فارغٌ أو غيرُ نصٍّ = بلا توجيه (وثائقُ قديمة)", () => {
  for (const tgt of ["", null, undefined, 0, false]) {
    assert.strictEqual(c.couponProblem({...ok, target_user_id: tgt}, ctx), null,
        String(tgt));
  }
});

t("(أ٥) status: الغيابُ يُقبَل، وأيُّ قيمةٍ غيرِ active تُرفَض", () => {
  assert.strictEqual(c.couponProblem({...ok, status: undefined}, ctx), null);
  for (const st of ["expired", "disabled", "ACTIVE", "paused"]) {
    assert.strictEqual(c.couponProblem({...ok, status: st}, ctx), "inactive", st);
  }
});

t("(أ٦) ترتيبُ الأسبابِ ثابت: inactive قبل expired قبل exhausted", () => {
  const all = {...ok, status: "expired", expiry: "2020-01-01",
    maxUses: 1, uses: 9, target_user_id: "u2", restricted_zones: ["جازان"]};
  assert.strictEqual(c.couponProblem(all, ctx), "inactive");
  assert.strictEqual(c.couponProblem({...all, status: "active"}, ctx), "expired");
  assert.strictEqual(
      c.couponProblem({...all, status: "active", expiry: null}, ctx),
      "exhausted");
  assert.strictEqual(
      c.couponProblem({...all, status: "active", expiry: null, maxUses: 0}, ctx),
      "other_user");
});

// ══════════════════════ (ب) الانتهاء بنوعَيه ══════════════════════

t("(ب١) Timestamp ونصُّ ISO يُفهَمان كلاهما — العطلُ الحيُّ بعينه", () => {
  const past = Date.UTC(2026, 0, 1);
  const future = Date.UTC(2027, 0, 1);
  // Timestamp (محرّرُ Flutter)
  assert.strictEqual(
      c.couponProblem({...ok, expiry: {toMillis: () => past}}, ctx), "expired");
  assert.strictEqual(
      c.couponProblem({...ok, expiry: {toMillis: () => future}}, ctx), null);
  // نصٌّ خامّ (لوحةُ الويبِ قبل الإصلاح — وثائقٌ قائمةٌ في الإنتاج)
  assert.strictEqual(
      c.couponProblem({...ok, expiry: "2026-01-01"}, ctx), "expired");
  assert.strictEqual(c.couponProblem({...ok, expiry: "2027-01-01"}, ctx), null);
  assert.strictEqual(
      c.couponProblem({...ok, expiry: "2026-01-01T00:00:00.000Z"}, ctx),
      "expired");
  // Date وعددٌ أيضاً
  assert.strictEqual(
      c.couponProblem({...ok, expiry: new Date(past)}, ctx), "expired");
  assert.strictEqual(c.couponProblem({...ok, expiry: past}, ctx), "expired");
});

t("(ب٢) غيابُ الانتهاءِ أو قيمةٌ لا تُفكّ = بلا انتهاء", () => {
  for (const e of [null, undefined, "", "ليس تاريخاً", {}, NaN,
    {toMillis: () => NaN}]) {
    assert.strictEqual(c.couponExpiryMs({expiry: e}), null, String(e));
    assert.strictEqual(c.couponProblem({...ok, expiry: e}, ctx), null,
        String(e));
  }
});

t("(ب٣) الحدُّ: انتهاءٌ يساوي الآنَ ليس منتهياً، وقبلَه بميلي واحدةٍ منتهٍ", () => {
  assert.strictEqual(
      c.couponProblem({...ok, expiry: {toMillis: () => NOW}}, ctx), null);
  assert.strictEqual(
      c.couponProblem({...ok, expiry: {toMillis: () => NOW - 1}}, ctx),
      "expired");
});

// ══════════════════════ (ج) القيمة ══════════════════════

t("(ج١) الحسابُ منقولٌ حرفيّاً: نسبةٌ على المشحونِ المُذرَّى، أو ثابت", () => {
  for (const gross of [100, 250.5, 1000]) {
    for (const surge of [1, 1.2, 1.5]) {
      for (const v of [0, 5, 10, 25, 100]) {
        assert.strictEqual(
            c.couponDiscount({type: "percentage", value: v}, {chargedGross: gross, surge}),
            gross * surge * (v / 100), `${gross}/${surge}/${v}`);
      }
    }
  }
  assert.strictEqual(
      c.couponDiscount({type: "fixed", value: 40}, {chargedGross: 999, surge: 2}),
      40, "الثابتُ لا يُذرّى ولا يُنسَّب");
});

t("(ج٢) max_discount سقفٌ، وقيمةٌ فاسدةٌ لا تُسقطُ السقف", () => {
  assert.strictEqual(c.couponDiscount(
      {type: "percentage", value: 50, max_discount: 30},
      {chargedGross: 100, surge: 1}), 30);
  assert.strictEqual(c.couponDiscount(
      {type: "percentage", value: 10, max_discount: 30},
      {chargedGross: 100, surge: 1}), 10);
  // `0 || d` ⇒ d: سقفُ صفرٍ يُقرأ غياباً — وهذا ما كان، ويُحفَظ كما هو.
  assert.strictEqual(c.couponDiscount(
      {type: "percentage", value: 10, max_discount: 0},
      {chargedGross: 100, surge: 1}), 10);
  assert.strictEqual(c.couponDiscount({value: NaN}, {chargedGross: 100}), 0);
});

t("(ج٣) الموثوقُ = الأصغر، وصفرُ العميلِ ليس قراراً", () => {
  assert.strictEqual(c.trustedDiscount(5, 12), 5);
  assert.strictEqual(c.trustedDiscount(99, 12), 12);
  assert.strictEqual(c.trustedDiscount(0, 12), 12);
  assert.strictEqual(c.trustedDiscount(undefined, 12), 12);
  assert.strictEqual(c.trustedDiscount(-5, 12), 12);
  assert.strictEqual(c.trustedDiscount(5, -1), 0);
});

t("(ج٤) ESCALATED_PROBLEMS ما لا تَبلغُه عميلةٌ صادقةٌ وحدَه", () => {
  assert.deepStrictEqual([...c.ESCALATED_PROBLEMS].sort(),
      ["other_user", "other_zone"]);
  // سباقٌ بين التطبيقِ والدفعِ يَبلغُ هذه الثلاثةَ بحسنِ نيّة — فلا تنبيه.
  for (const quiet of ["exhausted", "expired", "inactive", "not_found"]) {
    assert.ok(!c.ESCALATED_PROBLEMS.has(quiet), quiet);
  }
});

// ══════════════════════ (د) حارسُ index.js ══════════════════════

t("(د١) الأهليّةُ تمرُّ بالوحدةِ ولم تُعَد إنلاين", () => {
  assert.ok(idx.includes("require(\"./coupons\")"), "الوحدةُ غيرُ مستوردة");
  assert.ok(idxNoComments.includes("coupons.couponProblem("),
      "_computeTrustedDiscount لا يَسألُ الأهليّة");
  assert.ok(idxNoComments.includes("coupons.couponDiscount(") &&
    idxNoComments.includes("coupons.trustedDiscount("),
  "القيمةُ لم تَمرّ بالوحدة");
  // الصيغةُ القديمةُ لم تَبقَ: فحصُ toMillis الذي كان يُتخطّى للنصّ
  assert.ok(!idxNoComments.includes("c.expiry.toMillis"),
      "فحصُ الانتهاءِ القديمُ ما زال في index.js — وهو أعمى للنصّ");
  assert.ok(!/c\.status\s*&&\s*c\.status\s*!==\s*"active"/.test(idxNoComments),
      "فحصُ الحالةِ أُعيد إنلاين");
});

t("(د٢) الرفضُ يُسَم ويُنبَّه — وإلّا فالإنفاذُ تجميليٌّ عند 10%", () => {
  const i = idxNoComments.indexOf("async function _computeTrustedDiscount");
  assert.ok(i > 0, "الدالّةُ غائبة");
  const body = idxNoComments.substring(i,
      idxNoComments.indexOf("\nfunction ", i + 10));
  assert.ok(body.includes("coupon_rejected_reason"),
      "سببُ الرفضِ لا يُكتب على الطلب — رفضُ 10% يُنتج ratio=0.9 فلا يَبلغُ " +
      "عتبةَ الوسمِ (0.5) ويَذهبُ إلى اللاشيء");
  assert.ok(body.includes("coupons.ESCALATED_PROBLEMS.has("),
      "التنبيهُ لا يُصنَّف بالوحدة");
  assert.ok(body.includes("queuePush(\"ADMIN_BROADCAST\""),
      "لا تنبيهَ إداريّاً لسببٍ لا تَبلغُه عميلةٌ صادقة");
  assert.ok(/\["super_admin", "orders_manager", "accountant_admin"\]/
      .test(body), "التنبيهُ بلا أدوارٍ مستهدَفة");
});

t("(د٣) وعدُ countCouponUseOnOrderCreate صار صادقاً", () => {
  // كان: «والمنعُ النهائيُّ جزءٌ من التسعيرِ الخادميّ (طور التشديد Phase 2)»
  // بلا منعٍ في التسعيرِ الخادميّ.
  assert.ok(!idx.includes("طور التشديد Phase 2"),
      "الوعدُ القديمُ ما زال مكتوباً");
  assert.ok(idx.includes("coupons.couponProblem"),
      "ولا منعَ فعليّاً يُستند إليه");
});

t("(د٤) الوحدةُ نقيّةٌ: لا Firestore ولا db", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "coupons.js"), "utf8");
  for (const bad of ["require(\"firebase", "getFirestore", "getApp(",
    "initializeApp", "(db,"]) {
    assert.ok(!stripComments(src).includes(bad), `coupons.js تلمس ${bad}`);
  }
});

console.log(`\ncoupons tests: ${passed} passed`);
