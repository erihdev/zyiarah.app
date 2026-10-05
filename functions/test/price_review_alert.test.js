"use strict";

// وسمُ مراجعةِ السعرِ: قارئٌ، وتصريفٌ، وتنبيهٌ لا يُدّعى قبلَ إرسالِه.
// تشغيل: node test/price_review_alert.test.js
//
// ═══ ما يحرسه ═══
//
// تحقّقُ السعرِ الخادميُّ سياستُه **Tier A: وسمٌ وتنبيهٌ لا رفض** — قرارٌ
// مقصودٌ ومُعلَّلٌ (الرفضُ يَحجبُ دفعةَ عميلةٍ حقيقيّةٍ إن أخطأنا في الضريبةِ
// أو التقريب). فمُخرَجُ الفحصِ كلُّه أعلامٌ على المستندِ ودفعةٌ إداريّة.
//
// **١) الوسمُ لم يكن له قارئٌ في أيِّ واجهة.** صفرُ ورودٍ لـ`price_mismatch`
// ولا لأخواتِها في `lib/` وصفرٌ في `admin_panel/src/`: فالإدارةُ تَتلقّى
// دفعةً بخمسةِ أكوادٍ ثمّ تَفتحُ الطلبَ فتَراه عاديّاً تماماً — لا مبلغاً
// متوقَّعاً، ولا نسبةً، ولا سبيلَ إلى «راجعتُه واعتمدتُه».
//
// **٢) ونافذةُ المكنسةِ لا تُصرَّف.** استعلامُها كان
// `where("price_mismatch","==",true).limit(200)` ولا شيءَ يَمحو العلم: فكلُّ
// طلبٍ وُسِمَ يَبقى في مجموعةِ الاستعلامِ للأبد — وهو عطلُ «نافذةٌ تَمتلئُ
// بما لا يُزيلُه أحد» ثالثةً في هذه الجلسة بعد نافذةِ البثِّ المجدولِ
// ونافذةِ «مدفوعٌ وعالق».
//
// **٣) والتنبيهُ كان يُدّعى قبلَ إرسالِه.** مسارُ Tier A يَكتبُ
// `ops_alerted_mismatch: true` ثمّ يُرسلُ دفعةً مُبتلَعةً بـ`.catch(() => {})`:
// ففشلُ الإرسالِ يَترُكُ على المستندِ «نبّهنا عنه» وهو لم يُنبَّه،
// و`alertBatch` تُسقِطُ كلَّ مستندٍ العلمُ فيه `true` — فيُدفَنُ الوسمُ
// للأبد. وهو عكسُ ما تَنصُّ عليه `alertBatch` نفسُها: «الوسمُ **بعد** نجاحِ
// الإشعارِ فقط». ومع هذا الترتيبِ المعطوبِ كان توسيعُ المسحِ إلى
// `store_orders` **عقيماً** — العلمُ المضبوطُ سلفاً يُسكِتُه عن كلِّ مستند.
//
// **٤) و«تعذّر التحقّق» لم تكن له مكنسةٌ إطلاقاً**: ثلاثةُ مواضعَ تَسِمُ
// `price_unverifiable` ودفعةٌ واحدةٌ مُبتلَعةٌ هي كلُّ ما هناك.
const assert = require("assert");
const fs = require("fs");
const path = require("path");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ok - ${name}`);
}

const root = path.join(__dirname, "..", "..");
const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
// يُجرَّدُ من أسطرِ التعليقِ كاملةً: الشفرةُ تَشرحُ القرارَ باقتباسِ الشكلِ
// القديمِ نصّاً، فلولا التجريدُ سَقطَ الفحصُ على توثيقِه (التاسعةُ في الجلسة).
const code = src
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("//"))
    .join("\n");

test("(أ) كلُّ وسمٍ لـprice_mismatch يَكتبُ علمَ التنبيهِ معه — ثلاثةٌ لا أكثر", () => {
  const marks = (code.match(/price_mismatch: true/g) || []).length;
  assert.strictEqual(marks, 3,
      `مواضعُ الوسمِ ${marks} لا ٣ — موضعٌ جديدٌ يَلزمُه علمُ تنبيهٍ أيضاً`);
  const flags = (code.match(/ops_alerted_mismatch: (alertedM|alertedS|false)/g) || []).length;
  assert.strictEqual(flags, 3,
      "موضعُ وسمٍ بلا علمِ تنبيهٍ ⇒ مستندٌ لا تَراه المكنسةُ (الحقلُ الغائبُ " +
      "لا يُطابقُ == false) ولا تَصلُه دفعةٌ إن فشلت الأولى");
});

test("(ب) ولا يُدّعى التنبيهُ بـtrue حرفيّةٍ في أيِّ موضعِ وسم", () => {
  assert.ok(!code.includes("ops_alerted_mismatch: true"),
      "عادَ الادّعاءُ قبلَ الإرسال — ودفعةٌ مُبتلَعةٌ تَفشلُ فيُدفَنُ الوسم");
  assert.ok(!code.includes("ops_alerted_unverifiable: true"),
      "ونفسُ الشيءِ لفئةِ «تعذّر التحقّق»");
});

test("(ج) الدفعةُ تُرسَلُ **قبلَ** كتابةِ علمِها — في المواضعِ الخمسةِ كلِّها", () => {
  for (const v of ["alertedM", "alertedS", "alertedU1", "alertedU2", "alertedU3"]) {
    const sent = code.indexOf(`const ${v} = await queuePush(`);
    assert.ok(sent > -1, `${v} اختفى — راجِعْ موضعَ الوسمِ المقابل`);
    const written = code.indexOf(`: ${v},`);
    assert.ok(written > sent,
        `${v} يُكتَبُ قبلَ إرسالِ دفعتِه — وهو العطلُ بعينِه`);
    // وقيمتُها نتيجةُ الإرسالِ لا ثابت.
    const tail = code.slice(sent, written);
    assert.ok(tail.includes(".then(() => true).catch(() => false)"),
        `${v} لا يَحملُ نتيجةَ الإرسال`);
  }
});

test("(د) و«تعذّر التحقّق» ثلاثةُ مواضعَ كلُّها تَكتبُ علمَها", () => {
  const marks = (code.match(/price_unverifiable: true/g) || []).length;
  assert.strictEqual(marks, 3, `مواضعُ «تعذّر التحقّق» ${marks} لا ٣`);
  const flags = (code.match(/ops_alerted_unverifiable: alertedU[123]/g) || []).length;
  assert.strictEqual(flags, 3, "موضعٌ بلا علمِ تنبيهٍ ⇒ لا مكنسةَ تَراه");
});

test("(هـ) والمدفوعُ يُحفَظُ في مواضعِ الوسمِ الثلاثة (بطاقةُ المراجعةِ تَعرضُه)", () => {
  const paid = (code.match(/price_paid: (amount|paid)/g) || []).length;
  assert.strictEqual(paid, 3,
      "بلا price_paid تَحسبُ البطاقةُ المدفوعَ عكسيّاً من النسبة");
});

test("(و) استعلامُ المكنسةِ مساواتانِ، للمجموعتَين، وبـtry لكلِّ مجموعة", () => {
  const i = code.indexOf("for (const coll of [\"orders\", \"store_orders\"])");
  assert.ok(i > -1,
      "حلقةُ المجموعتَين اختفت — و`store_orders` يُوسَمُ بنفسِ الحقول");
  const body = code.slice(i, i + 2600);
  // `try` داخلَ الحلقةِ قبلَ الاستعلامِ — سقوطُ الأولى كان يَقطعُ الثانية
  // (نفسُ درسِ حلقةِ إعادةِ الطابورَين).
  assert.ok(body.indexOf("try {") < body.indexOf(".where(\"price_mismatch\""),
      "try خارجَ الحلقةِ ⇒ سقوطُ المجموعةِ الأولى يَقطعُ الثانية");
  assert.ok(/\.where\("price_mismatch", "==", true\)\s*\.where\("ops_alerted_mismatch", "==", false\)/
      .test(body), "نافذةُ الوسمِ بلا «لم يُنبَّه بعد» تَمتلئُ بما لا يُزيلُه أحد");
  assert.ok(/\.where\("price_unverifiable", "==", true\)\s*\.where\("ops_alerted_unverifiable", "==", false\)/
      .test(body), "فئةُ «تعذّر التحقّق» بلا مكنسةٍ هي الحالةُ الأصليّة");
  // مساواتانِ بلا مدًى لا تَلزمُهما فهرسٌ مركَّب — فلا يُضاف.
  const idx = fs.readFileSync(path.join(root, "firestore.indexes.json"), "utf8");
  assert.ok(!idx.includes("price_mismatch") && !idx.includes("price_unverifiable"),
      "فهرسٌ مركَّبٌ لمساواتَين زائدٌ (دمجُ zigzag) — وكلفةُ كتابةٍ بلا مقابل");
});

test("(ز) وجمهورُ المكنسةِ يَضمُّ المحاسبةَ كدفعاتِها الفوريّة", () => {
  const i = code.indexOf("for (const coll of [\"orders\", \"store_orders\"])");
  const body = code.slice(i, i + 2600);
  const n = (body.match(/\["super_admin", "orders_manager", "accountant_admin"\]/g) || []).length;
  assert.strictEqual(n, 2,
      "الفئتانِ معاً: المحاسبةُ في جمهورِ الدفعةِ الفوريّةِ فكانت المكنسةُ " +
      "وحدَها تُخرِجُها لنفسِ الواقعة");
  assert.ok(code.includes("audience = [\"super_admin\", \"orders_manager\"]"),
      "ويَبقى الافتراضُ كما كان لبقيّةِ الفئات");
});

test("(ح) الوسمُ له قارئٌ الآن — في السطحَين معاً", () => {
  // نصفُ الإصلاحِ وحدَه يَترُكُ الطلبَ عاديَّ المنظرِ لمن يَعملُ من السطحِ
  // الآخر، وهو شكلُ «حقلُ قرارٍ يَعرفُه محرّرٌ واحد» الذي تَكرّرَ أربعاً.
  const dartUtil = fs.readFileSync(
      path.join(root, "lib", "utils", "price_review.dart"), "utf8");
  const tsUtil = fs.readFileSync(
      path.join(root, "admin_panel", "src", "utils", "priceReview.ts"), "utf8");
  for (const f of ["price_mismatch", "price_unverifiable", "price_paid",
    "price_expected_net", "price_shadow_ratio", "coupon_rejected_reason"]) {
    assert.ok(dartUtil.includes(f), `${f} لا يَقرأُه تطبيقُ الإدارة`);
    assert.ok(tsUtil.includes(f), `${f} لا تَقرأُه اللوحة`);
  }
  // والاعتمادُ يُبطِلُ علمَي الاستعلامِ — وهو التصريف.
  for (const u of [dartUtil, tsUtil]) {
    assert.ok(u.includes("'price_mismatch'") || u.includes("\"price_mismatch\"") ||
      u.includes("price_mismatch,"), "علمُ الاستعلامِ غيرُ مذكورٍ في حِمْلِ الاعتماد");
  }
});

test("(ط) المضادّة: القرارُ ما زال موثَّقاً في الخامّ", () => {
  // لو غابَ فالتجريدُ حَجبَ أكثرَ من التعليقاتِ ولم يَبقَ للفحصِ ما يَجده.
  assert.ok(src.includes("ops_alerted_mismatch: true"),
      "اختفى اقتباسُ الادّعاءِ القديمِ من التوثيق — راجِعْ ما جرّدَه الفحص");
  assert.ok(code.length < src.length, "التجريدُ لم يُزِل شيئاً — نمطٌ معطوب");
});

console.log(`\nprice_review_alert tests: ${passed} passed`);
