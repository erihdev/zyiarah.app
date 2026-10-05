"use strict";

// نافذةُ `limit` لا تَمتلئُ بما لا يُزيلُه أحد — تشغيل: node test/ops_sweep_window.test.js
//
// ═══ ما يحرسه ═══
//
// الفحصُ الأوّلُ في `opsHealthSweep` يَسألُ عن حالةٍ متناقضة: مستندٌ موسومٌ
// `awaiting_payment` و`is_paid == true` — «مالٌ مقبوضٌ بلا مسارِ تشغيل». وكان
// الاستعلامُ مساواةً واحدةً على الحالةِ بـ`limit(500)`، و`is_paid` يُرشَّحُ في
// الكودِ **بعد** القصّ، وتعليقُه يَقول: «limit بلا orderBy مقبول: تشبّعُه
// يَتطلّبُ مئاتِ المستنداتِ العالقةِ معاً».
//
// **وهي موجودةٌ بالفعل، بالبناءِ لا بالعُطل:**
//
//   • `store_orders` يُنشَأُ **قبلَ** الدفعِ بـ`awaiting_payment`
//     (`store_service.createStoreOrder` — قرارُ المالك: لا موافقةَ قبل الدفع).
//   • `cancelStaleUnpaidOrders` يَمسحُ `orders` بحالةِ `pending` وحدَها، فلا
//     شيءَ يُلغي سلّةً متروكة.
//   • والبقاءُ **مقصود**: بطاقةُ الطلبِ في `orders_list_screen` تُظهرُ زرَّ
//     الدفعِ لـ`awaiting_payment` فالعميلةُ تَستأنف.
//
// فسلالُ العميلاتِ المتروكةُ تَتراكمُ بلا حدٍّ — ومعدّلُ تركِ السلّةِ في أيِّ
// متجرٍ هو الأغلبيّة. واستعلامٌ بمساواةٍ واحدةٍ يُرتَّبُ بـ`__name__`،
// ومعرّفاتُ `store_orders` من `.doc()` أي عشوائيّة: فحين تَتجاوزُ المتروكاتُ
// خمسَ مئةٍ يَسقطُ الطلبُ **المدفوعُ** العالقُ من النافذةِ بالاحتمالِ وحدَه —
// وهو كلُّ موضوعِ هذا الفحص. لا خطأ، لا سطرَ سجلّ، لا تنبيه.
//
// الإصلاحُ أن تَسألَ النافذةُ عن الحالةِ المتناقضةِ نفسِها: مساواتانِ معاً،
// فسلّةٌ متروكةٌ (`is_paid: false`) لا تَدخلُها أصلاً. ومساواتانِ بلا مدًى لا
// تَلزمُهما فهرسٌ مركَّب (دمجُ zigzag على الفهارسِ الأحاديّة) — وله سابقةٌ حيّةٌ
// في المستودع: استعلامُ `referrals` بمساواتَين وبلا فهرسٍ في
// `firestore.indexes.json`.
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

const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
// يُجرَّدُ من أسطرِ التعليقِ كاملةً: الشفرةُ تَشرحُ القرارَ بذكرِ الشكلِ
// القديمِ نصّاً، فلولا التجريدُ سَقطَ الفحصُ على توثيقِه.
const code = src
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("//"))
    .join("\n");

test("(أ) النافذةُ تَسألُ عن المساواتَين معاً لا عن الحالةِ وحدَها", () => {
  const i = code.indexOf(".where(\"status\", \"==\", \"awaiting_payment\")");
  assert.ok(i > -1, "استعلامُ الفحصِ الأوّلِ اختفى");
  const q = code.slice(i, code.indexOf(".get()", i));
  assert.ok(q.includes(".where(\"is_paid\", \"==\", true)"),
      "بلا هذه المساواةِ تَمتلئُ النافذةُ بالسلالِ المتروكةِ ويَسقطُ المدفوعُ العالق");
  assert.ok(q.includes(".limit(500)"), "حدُّ النافذةِ ما زال مقصوداً");
});

test("(ب) ولا تَرشيحَ لـis_paid في الكودِ بعد القصّ — النافذةُ هي الحارس", () => {
  // ترشيحٌ في الكودِ على لقطةٍ مقصوصةٍ هو العطلُ بعينِه: القصُّ سَبقَ الترشيح.
  assert.ok(!code.includes(".filter((doc) => doc.data().is_paid === true)"),
      "عادَ الترشيحُ إلى الكود — فالقصُّ يَسبقُه مرّةً أخرى");
});

test("(ج) والمهجورةُ تُعَدُّ بـcount() لا بقراءةِ خمسِ مئةِ مستند", () => {
  const i = code.indexOf(".where(\"status\", \"==\", \"awaiting_payment\")");
  const after = code.slice(i, i + 1600);
  assert.ok(/\.where\("status", "==", "awaiting_payment"\)\s*\.count\(\)/.test(after),
      "عدُّ المهجورةِ يَلزمُه count(): مساواةٌ واحدةٌ بلا فهرسٍ وبقراءةٍ واحدة");
  assert.ok(!code.includes("abandoned>24h"),
      "الرقمُ المقصوصُ بالنافذةِ عادَ — والنافذةُ لا تَرى غيرَ المدفوعِ الآن");
});

test("(د) سببُ التراكمِ ما زال قائماً: لا شيءَ يُلغي سلّةً متروكة", () => {
  // لو صارَ شيءٌ يُلغي `store_orders` المتروكةَ فالتعليلُ أعلاه يَحتاجُ مراجعةً
  // (لا إسكاتاً): التضييقُ يَبقى صحيحاً، لكنّ وصفَ السببِ يَصيرُ قديماً.
  const i = code.indexOf("exports.cancelStaleUnpaidOrders");
  assert.ok(i > -1, "مكنسةُ غير المدفوعِ اختفت");
  const body = code.slice(i, i + 1800);
  assert.ok(body.includes("db.collection(\"orders\")"),
      "المكنسةُ تَمسحُ orders");
  assert.ok(!body.includes("db.collection(\"store_orders\")"),
      "صارت تَمسحُ store_orders — راجِعْ تعليلَ التراكمِ أعلاه");
  assert.ok(body.includes(".where(\"status\", \"==\", \"pending\")"),
      "ومسحُها محصورٌ بـpending — وawaiting_payment ليست منها");
});

test("(هـ) و`store_orders` ما زال يُنشَأُ قبلَ الدفعِ (أصلُ التراكم)", () => {
  const svc = fs.readFileSync(
      path.join(__dirname, "..", "..", "lib", "services", "store_service.dart"),
      "utf8");
  assert.ok(svc.includes("'status': 'awaiting_payment'"),
      "لو صارَ يُنشَأُ بعد الدفعِ فلا متروكاتٍ أصلاً — راجِعْ التعليل");
  assert.ok(svc.includes("'is_paid': false"),
      "والعلمُ الذي تُضيّقُ به النافذةُ هو ما يُكتَبُ هنا");
});

test("(و) المضادّة: الشكلُ القديمُ ما زال موثَّقاً في الخامّ", () => {
  // لو غابَ فالتجريدُ حَجبَ أكثرَ من التعليقاتِ ولم يَبقَ للفحصِ ما يَجده.
  assert.ok(src.includes("تشبّعُه يَتطلّبُ مئاتِ المستنداتِ العالقةِ معاً"),
      "اختفى اقتباسُ الافتراضِ القديمِ من التوثيق — راجِعْ ما جرّدَه الفحص");
  assert.ok(code.length < src.length, "التجريدُ لم يُزِل شيئاً — نمطٌ معطوب");
});

console.log(`\nops_sweep_window tests: ${passed} passed`);
