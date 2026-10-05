"use strict";

// **مالكُ المستندِ المدفوعِ هو المُنادي** — تشغيل: node test/callable_ownership.test.js
//
// ═══ لماذا ═══
//
// `onCall` يُنادى من أيِّ جهازٍ بأيِّ وسائط: معرّفُ الطلبِ يَأتي من
// `request.data`، فلا شيءَ يَربطُه بالمُنادي إلّا سطرٌ في الشفرة. والسؤالُ كان
// مكتوباً بثلاثةِ أشكالٍ في أربعةِ مساراتٍ ماليّة — و**مفقوداً في الرابع**:
//
//   • `payWithWallet`         → `client_id !== uid`
//   • `payContractWithWallet` → `c.userId !== uid` (أشدُّ: الغيابُ يَرفض)
//   • `verifyMoyasarPayment`  → `client_id || userId`
//   • `createTamaraCheckout`  → **لا شيء**
//
// وتعليقُ قراءةِ الرابعِ يَقول «Fetch the true price + info from Firestore
// (prevent client tampering)» — فهو يَمنعُ تلاعبَ **المبلغِ** لا الملكيّة،
// وقارئٌ يَراه يَحسبُ البابَ مُغلَقاً. فأيُّ مسجَّلٍ يَملكُ معرّفَ طلبٍ —
// **سائقٌ يَرى طلباتَه المُسنَدة** مثلاً — كان يُنشئُ جلسةَ تمارا على طلبِ
// عميلةٍ أخرى: صفحةُ الدفعِ تَعرضُ المبلغَ واسمَ الخدمة، و**بريدُ العميلةِ**
// يُرسَلُ إلى تمارا كـ`consumer.email`؛ و`order_reference_id` معرّفُ الطلبِ
// نفسُه، فدفعُه يَقلبُ **طلبَ غيرِه** مدفوعاً (`_tamaraFlipPaid` بلا فحصِ
// مبلغٍ إطلاقاً). ولا فحصَ `is_paid` كذلك: جلسةٌ ثانيةٌ على طلبٍ مدفوعٍ هي
// خصمٌ مكرَّرٌ واستردادُه يدويّ.
//
// وهي قاعدةٌ مُنفَّذةٌ في **ثلاثةٍ من أربعة** — نفسُ شكلِ `isAssignableDriver`
// (مُنفَّذةٌ في اثنَين من أربعةٍ، وافتراقُ النسختَين شحنَ حادثةً). فالفحصُ
// يُقارِنُ **المجموعةَ كاملةً** بقائمةٍ مُعلَنةٍ لكلٍّ سببُها، فخامسٌ
// يُراجَعُ بدلَ أن يُنشَرَ بلا فحصٍ للملكيّة.
const assert = require("assert");
const fs = require("fs");
const path = require("path");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  fn();
  passed++;
  console.log(`  ok - ${name}`);
}

const raw = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
// يُجرَّدُ من أسطرِ التعليقِ: الشفرةُ تَشرحُ القاعدةَ بتسميةِ حقولِها، فمسحُ
// الخامِّ يُسقطُ الحارسَ على توثيقِه هو (تِسعُ مرّاتٍ في هذه الجلسة). وكلُّ
// فحصٍ يَسحبُ يُقابِلُه فحصٌ يُثبِتُ بقاءَ النصِّ في الخامّ.
const code = raw
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("//") &&
      !l.trimStart().startsWith("*") && !l.trimStart().startsWith("/*"))
    .join("\n");

/** حدودُ الصادرات، لاقتطاعِ جسمِ كلِّ `onCall`. */
const starts = [...code.matchAll(/^exports\.\w+ = /gm)].map((m) => m.index);
/**
 * @param {string} name اسمُ الدالّةِ المُصدَّرة
 * @return {string} جسمُها حتى الصادرِ التالي
 */
function body(name) {
  const i = code.indexOf(`exports.${name} = `);
  assert.ok(i > -1, `exports.${name} اختفى`);
  const next = starts.find((p) => p > i);
  return code.slice(i, next === undefined ? code.length : next);
}

// ─────────────────────────────────────────────────────────────────────────
// المساراتُ الماليّةُ التي يُنادِيها **العميلُ** (لا `_assertAdmin`) وتَقرأُ
// مستنداً بمعرّفٍ من `request.data`. لكلٍّ سببُ إدراجِه.
// **مُعيِّناتُ الصلاحيّةِ الإداريّةِ تُشتَقُّ ولا تُكتَبُ بيدٍ.** كان الفحصُ
// يَعرفُ تهجئةً واحدةً (`_assertAdmin`)، فحين أُضيف `_assertSuperAdmin`
// (لعمليّةٍ تَحصرُها القواعدُ على `isSuperAdmin()`) دخلَ نداءٌ **إداريٌّ**
// في مجموعةِ «المسارات العميليّة» — أي أنّ الحارسَ كان يَعمى عن تهجئةٍ
// ثانيةٍ بدلَ أن يَفشلَ عالياً. فالقائمةُ مُشتَقّةٌ من المصدرِ، ومُقابَلةٌ
// بمجموعةٍ مثبّتةٍ كي يُراجَعَ مُعيِّنٌ ثالثٌ بدلَ أن يُوسِّعَ النطاقَ بصمت.
const ADMIN_ASSERTIONS = [...code.matchAll(
    /^async function (_assert\w*Admin)\(/gm)].map((m) => m[1]).sort();
t("(أ٠) مُعيِّناتُ الصلاحيّةِ هي المعروفةُ وحدَها", () => {
  assert.deepStrictEqual(ADMIN_ASSERTIONS,
      ["_assertAdmin", "_assertSuperAdmin"],
      "مُعيِّنُ صلاحيّةٍ جديدٌ — أضِفْه بوعيٍ أو انظر لِمَ أُضيف");
});

const CLIENT_MONEY_CALLABLES = {
  createTamaraCheckout: "جلسةُ تقسيطٍ على طلبٍ بمعرّفٍ من العميل",
  payWithWallet: "خصمٌ من المحفظةِ لطلبٍ بمعرّفٍ من العميل",
  payContractWithWallet: "خصمٌ من المحفظةِ لعقدٍ بمعرّفٍ من العميل",
  verifyMoyasarPayment: "قلبُ is_paid لطلبٍ بمعرّفٍ من العميل",
};

t("(أ) المجموعةُ كاملةً: كلُّ مسارٍ ماليٍّ عميليٍّ يَفحصُ الملكيّة", () => {
  // الاشتقاقُ من المصدرِ لا من قائمةٍ يدويّة: `onCall` بلا `_assertAdmin`
  // يَقرأُ معرّفاً من `request.data` ⇒ داخلٌ في النطاق.
  const found = new Set();
  for (const m of code.matchAll(/^exports\.(\w+) = onCall/gm)) {
    const name = m[1];
    const b = body(name);
    if (ADMIN_ASSERTIONS.some((a) => b.includes(a)) ||
        b.includes("adminRoles.includes")) continue;
    if (!/request\.data[^\n]*\b\w*[Ii]d\b/.test(b) &&
        !/\{[^}]*\b\w*[Ii]d\b[^}]*\}\s*=\s*request\.data/.test(b)) continue;
    // يَقرأُ مستنداً بذلك المعرّف؟
    if (!/\.doc\(\s*\w*[Ii]d\s*\)/.test(b)) continue;
    found.add(name);
  }
  assert.deepStrictEqual([...found].sort(),
      Object.keys(CLIENT_MONEY_CALLABLES).sort(),
      "مجموعةُ المساراتِ الماليّةِ العميليّةِ تغيّرت — راجِعْ الجديدَ قبل نشرِه");

  for (const name of found) {
    const b = body(name);
    const hasRule = b.includes("_assertDocOwner(") ||
      /\.get\("client_id"\)\s*!==\s*uid/.test(b) ||
      /\.userId\s*!==\s*uid/.test(b);
    assert.ok(hasRule,
        `${name} لا يَفحصُ الملكيّة (${CLIENT_MONEY_CALLABLES[name]})`);
  }
});

t("(ب) والقاعدةُ تَعيشُ مرّةً — ولا نسخةَ إنلاين من سلسلةِ المالك", () => {
  assert.ok(code.includes("function _assertDocOwner("),
      "الدالّةُ اختفت — فالسؤالُ عادَ مكتوباً بأشكالٍ");
  // النسخةُ التي كانت في `verifyMoyasarPayment` بعينِها ممنوعةٌ الآن.
  assert.ok(!/const owner = orderDoc\.data\(\)\.client_id/.test(code),
      "النسخةُ الإنلاين عادت إلى verifyMoyasarPayment");
  // ولا مقارنةَ ملكيّةٍ مبنيّةً بيدٍ خارجَ الدالّةِ وخارجَ الاستثناءَين.
  const outside = code
      .replace(body("payWithWallet"), "")
      .replace(body("payContractWithWallet"), "")
      .replace(/function _assertDocOwner\([\s\S]*?\n\}/, "");
  // النمطُ يَجبُ أن يُلاحِظَ أيَّ صياغةٍ للسلسلة — `d.client_id || d.userId`
  // و`snap.data().client_id || snap.data().userId` سواء. (أوّلُ صياغةٍ طلبت
  // `\w+\.userId` فلم تَرَ `orderDoc.data().userId`: اختبارُ القضمِ أسقطَ
  // فحصاً آخرَ فظهرَ الضعفُ، والنمطُ الآن لا يَشترطُ شكلَ المُستقبِل.)
  assert.ok(!/client_id\s*\|\|[\s\S]{0,60}userId[\s\S]{0,160}permission-denied/
      .test(outside), "نسخةٌ رابعةٌ من سلسلةِ المالكِ ظهرت");
});

t("(ج) والمسارانِ يُنادِيانِها فعلاً — لا تَسكنُ بلا قارئ", () => {
  for (const name of ["createTamaraCheckout", "verifyMoyasarPayment"]) {
    assert.ok(body(name).includes("_assertDocOwner("),
        `${name} لا يُنادي القاعدة`);
  }
});

t("(د) وتمارا تَرفضُ طلباً مدفوعاً سلفاً — خصمٌ مكرَّرٌ استردادُه يدويّ", () => {
  const b = body("createTamaraCheckout");
  assert.ok(/is_paid === true/.test(b), "لا فحصَ is_paid في مسارِ تمارا");
  // والترتيبُ: الملكيّةُ ثمّ المدفوعُ ثمّ النداءُ الخارجيُّ — فلا بياناتٍ
  // تُرسَلُ إلى تمارا قبل أن يَثبُتَ الحقّ.
  const own = b.indexOf("_assertDocOwner(");
  const paid = b.indexOf("is_paid === true");
  const out = b.indexOf("tamara.checkout(");
  assert.ok(own > -1 && paid > -1 && out > -1);
  assert.ok(own < out && paid < out,
      "النداءُ الخارجيُّ يَسبقُ فحصَ الحقّ — فبريدُ العميلةِ يُرسَلُ أوّلاً");
});

t("(هـ) والاستثناءُ الأشدُّ يَبقى أشدَّ، وسببُه مكتوب", () => {
  // `payContractWithWallet` يَرفضُ غيابَ `userId` (لا يَتسامحُ كالشقيق)،
  // لأنّ العقودَ لا تُنشَأُ خادميّاً بلا مالك. قرارٌ لا سهو.
  assert.ok(/c\.userId !== uid/.test(body("payContractWithWallet")),
      "العقدُ صارَ متسامحاً مع غيابِ المالك — وهو لا يُنشَأُ بلا مالكٍ أصلاً");
  assert.ok(raw.includes("payContractWithWallet"));
});

t("(و) المضادّة: شرحُ القاعدةِ ما زال في الخامّ", () => {
  // الفحوصُ أعلاه تَقرأُ المُجرَّد، فلو أفرطَ التجريدُ لَما وجدَ شيئاً.
  assert.ok(raw.includes("prevent client tampering"),
      "التعليقُ الذي أوهمَ بإغلاقِ البابِ اختفى — وهو شاهدُ العطل");
  assert.ok(raw.length > code.length, "التجريدُ لم يُزِلْ شيئاً — النمطُ معطوب");
});

console.log(`\ncallable_ownership tests: ${passed} passed`);
