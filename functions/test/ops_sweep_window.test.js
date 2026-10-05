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

test("(ز) نافذةُ المحافظِ السالبةِ بلا قصٍّ — المجموعتانِ تُقرآنِ كاملتَين", () => {
  // العطلُ كان `where("balance","<",0).limit(200)` ثم ترشيحُ العلمِ في الكود:
  // القصُّ قبلَ الترشيح. ومدًى يُرتَّبُ ضمناً بحقلِه تصاعديّاً، فالأكثرُ سَلباً
  // يَسُدُّ النافذةَ ومحفظةٌ جديدةٌ بسالبٍ صغيرٍ لا تُقرأُ أصلاً.
  assert.ok(code.includes(
      "const negQ = db.collection(\"wallets\").where(\"balance\", \"<\", 0);"),
  "استعلامُ المحافظِ السالبةِ تغيّر — راجِعْ أنّه ما زال بلا قصّ");
  assert.ok(!/where\("balance", "<", 0\)[\s\S]{0,60}\.limit\(/.test(code),
      "عادَ `limit` إلى استعلامِ السالب — فالموسومُ يَسُدُّ النافذةَ مرّةً أخرى");
  assert.ok(code.includes("const [negSnap, flagSnap] = await Promise.all("),
      "المجموعتانِ (السالبُ الآن، والموسومُ سابقاً) تُقرآنِ معاً");
});

test("(ح) ويَحرُسُهما عَدٌّ خادميٌّ أوّلاً، فالانفجارُ لا يُعدَّدُ", () => {
  assert.ok(code.includes("negQ.count().get()") &&
    code.includes("flagQ.count().get()"),
  "العَدُّ بـcount(): قراءةٌ واحدةٌ لكلٍّ، ومدًى/مساواةٌ أحاديّةٌ بلا فهرسٍ مركَّب");
  assert.ok(/const NEG_WALLET_SCAN_MAX = \d+;/.test(code),
      "حدُّ المسحِ ثابتٌ مُسمّى، لا رقمٌ مبثوثٌ في الاستعلام");
  const i = code.indexOf("negCount > NEG_WALLET_SCAN_MAX");
  assert.ok(i > -1, "فرعُ تجاوزِ الحدِّ اختفى");
  const branch = code.slice(i, i + 900);
  assert.ok(branch.includes("queuePush(\"ADMIN_BROADCAST\""),
      "تجاوزُ الحدِّ خبرٌ بذاته — يُنبَّهُ عنه بالعددِ وحدَه");
  assert.ok(!/\.limit\(/.test(branch),
      "لا قصَّ في فرعِ الانفجار: إمّا العددُ وحدَه أو القراءةُ كاملة");
});

test("(ط) والعلمُ يُمحى عند التعافي — وإلّا فالحادثةُ الثانيةُ تُبتلَع", () => {
  // العلمُ كان يَعني «أخبرناكَ مرّةً، يوماً ما»: محفظةٌ عادَت موجَبةً ثم سَلبت
  // مرّةً أخرى لا يُنبَّهُ عنها إطلاقاً. وهذا الفرعُ هو القريبُ الوقوع.
  assert.ok(code.includes("ops_negative_alerted: FieldValue.delete()"),
      "لا محوَ للعلمِ عند التعافي — فالسلبُ الثاني صامتٌ أبداً");
  const i = code.indexOf("for (const doc of flagSnap.docs)");
  assert.ok(i > -1, "حلقةُ التصريفِ اختفت");
  const loop = code.slice(i, i + 420);
  assert.ok(loop.includes("Number(doc.data().balance ?? 0) >= 0"),
      "التصريفُ مشروطٌ بالتعافي؛ و`??` لا `||` على المال، والنصُّ غيرُ الرقميِّ " +
    "لا يُمحى (NaN >= 0 كاذب) وهو التصرّفُ المحافظ");
});

test("(ي) ومواضعُ العلمِ أربعةٌ بعينِها، والعميلُ ليس كاتباً", () => {
  // العلمُ خادميٌّ بالبناء: `wallets` مُغلقةٌ على العميلِ في القواعد، فلو
  // انفتحت صارَ ضبطُه سلفاً إسكاتاً للتنبيهِ الوحيدِ على خللِ مال.
  const sites = (code.match(/ops_negative_alerted/g) || []).length;
  assert.strictEqual(sites, 4,
      `مواضعُ العلمِ في الشفرةِ = ${sites} (المتوقَّع ٤: الاستعلام، الترشيح، ` +
    "الوسم، المحو) — موضعٌ خامسٌ يُراجَعُ بدلَ أن يَمرّ");
  const rules = fs.readFileSync(
      path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
  const i = rules.indexOf("match /wallets/{walletId}");
  assert.ok(i > -1, "قاعدةُ المحافظِ اختفت");
  assert.ok(rules.slice(i, i + 260).includes("allow write: if false"),
      "المحافظُ ما زالت مُغلقةً على العميل — وهو ما يَجعلُ العلمَ موثوقاً");
});

test("(ك) ولا فهرسَ مركَّبٌ لـwallets: الاستعلامانِ أحاديّا الحقل", () => {
  const idx = JSON.parse(fs.readFileSync(
      path.join(__dirname, "..", "..", "firestore.indexes.json"), "utf8"));
  const w = (idx.indexes || []).filter((x) => x.collectionGroup === "wallets");
  assert.strictEqual(w.length, 0,
      "أُضيف فهرسٌ مركَّبٌ لـwallets — الاستعلامانِ لا يَلزمُهما واحدٌ " +
    "(مدًى على حقلٍ واحدٍ، ومساواةٌ على حقلٍ واحد)، والفهرسُ بلا استعلامٍ " +
    "كلفةُ كتابةٍ بلا مقابل");
  assert.deepStrictEqual(idx.fieldOverrides || [], [],
      "استثناءُ فهرسةٍ أحاديّةٍ يُبطِلُ أحدَ الاستعلامَين بصمت");
});

test("(ل) وعدُّ مهامِّ السائقِ الحيّةِ رقمٌ حقيقيٌّ لا مقصوفٌ بـlimit", () => {
  // الحارسُ يَسألُ «> 0» فحسب، لكنّ الرسالةَ تَطبعُ العدد: `limit(5)` لكلِّ
  // مجموعةٍ كان يَسقُفُه عند عشرة، فيُعيدُ الأدمنُ إسنادَ عشرٍ ويَظنُّ أنّه
  // أفرغَ السائق.
  const i = code.indexOf("const activeCounts = await Promise.all(");
  assert.ok(i > -1, "عدُّ المهامِّ الحيّةِ قبلَ حذفِ السائقِ اختفى");
  const blk = code.slice(i, i + 560);
  assert.ok(blk.includes(".count().get().then((a) => a.data().count)"),
      "العَدُّ خادميٌّ: مساواةٌ + in بلا مدًى ⇒ لا فهرسَ مركَّب، وقراءةٌ واحدة");
  assert.ok(!blk.includes(".limit("),
      "عادَ القصُّ — فالرقمُ المطبوعُ للأدمنِ ليس الرقمَ الحقيقيّ");
  assert.ok(code.includes("لديه ${activeCount} طلب نشط"),
      "الرسالةُ ما زالت تَطبعُ العدد — وهو ما يَجعلُ دقّتَه شرطاً");
});

test("(م) المضادّة: الشكلانِ القديمانِ ما زالا موثَّقَين في الخامّ", () => {
  // لو غابا فالتجريدُ حَجبَ أكثرَ من التعليقاتِ ولم يَبقَ للفحصِ ما يَجده.
  assert.ok(src.includes("`where(\"balance\",\"<\",0).limit(200)`"),
      "اختفى اقتباسُ نافذةِ السالبِ القديمةِ من التوثيق");
  assert.ok(src.includes("أخبرناكَ مرّةً، يوماً ما"),
      "اختفى وصفُ معنى العلمِ القديمِ من التوثيق");
  assert.ok(src.includes("`limit(5)` لكلِّ مجموعةٍ يَسقُفُه عند عشرة"),
      "اختفى اقتباسُ سقفِ العدِّ القديمِ من التوثيق");
});


// ─────────────────────────────────────────────────────────────────────────────
// (ن) نافذةُ استردادِ الإلغاءِ لا تَحتفظُ بما لا دَينَ فيه
//
// المُرشِّحاتُ السريعةُ كانت تَتخطّى بـ`continue` وتُبقي `needs_refund: true`،
// فالمستندُ يَبقى في نافذةِ الـ200 **إلى الأبد**. وأخطرُها زيارةُ الباقة:
// تُولَّدُ `is_paid: true` و`amount: 0`، وإلغاءُ العميلةِ لها يَكتبُ
// `needs_refund = is_paid` أي `true`، و`onOrderRewards` يَستثني الاشتراكَ فلا
// يُودِعُ شيئاً — فكلُّ زيارةِ باقةٍ مُلغاةٍ تَشغلُ خانةً دائماً، وعدّادُها
// عددُ الإلغاءاتِ في عمرِ التطبيق. وهو العطلُ الذي أُغلق في المحرّكِ نفسِه
// ثمّ أُعيد من هذا الموضع.
test("(ن١) ما لا دَينَ فيه يُطفأُ علمُه لا يُتخطّى", () => {
  const at = code.indexOf("cancelled-refund retried=");
  assert.ok(at > -1, "سطرُ سجلِّ المكنسةِ اختفى");
  const blk = code.slice(Math.max(0, at - 2600), at);
  assert.ok(/needs_refund: false/.test(blk),
      "المكنسةُ لا تُطفئُ العلمَ — فالمستندُ يَبقى في النافذةِ أبداً");
  // الخمسةُ تُطفَأُ في فرعٍ واحدٍ لا تُتخطّى كلٌّ وحدَه.
  for (const term of [
    "d.refund_credited === true",
    "d.payment_status === \"refunded\"",
    "d.auto_refund_processed === true",
    "d.payment_method === \"subscription\"",
  ]) {
    assert.ok(blk.includes(term), `المُرشِّحُ ${term} اختفى`);
    assert.ok(!new RegExp(term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
        "\\) continue;").test(blk),
    `${term} ما زال يَتخطّى بلا إطفاء`);
  }
});

test("(ن٢) زيارةُ الباقةِ هي السببُ، وما زالت تُولَّدُ كذلك", () => {
  // لو تغيّرَ توليدُ الزيارةِ (مثلاً `is_paid: false`) فالتعليلُ يُراجَعُ لا
  // يُسكَت: النافذةُ قد لا تَزدحمُ أصلاً.
  const at = code.indexOf("payment_method: \"subscription\"");
  assert.ok(at > -1);
  const blk = code.slice(Math.max(0, at - 400), at + 200);
  assert.ok(/amount: 0/.test(blk), "زيارةُ الباقةِ لم تَعُد بمبلغٍ صفر");
  assert.ok(/is_paid: true/.test(blk), "زيارةُ الباقةِ لم تَعُد مدفوعة");
  assert.ok(/status: "pending"/.test(blk),
      "لو لم تُولَّد pending فزرُّ الإلغاءِ لا يَظهرُ ويَسقطُ التعليل");
});

test("(ن٣) وغيابُ المالكِ وحدَه يُبقي العلمَ — ويُعَدّ", () => {
  const at = code.indexOf("cancelled-refund retried=");
  const blk = code.slice(Math.max(0, at - 2600), at + 300);
  assert.ok(/if \(!d\.client_id\) \{ unknown\+\+; continue; \}/.test(blk),
      "غيابُ المالكِ يَجبُ أن يُعَدَّ لا أن يُتخطّى بصمت");
  assert.ok(/released=\$\{released\}/.test(blk) &&
      /unknown=\$\{unknown\}/.test(blk),
  "العدّادانِ لا يُطبَعان — فالتراكمُ يَبقى غيرَ مرئيّ");
});
console.log(`\nops_sweep_window tests: ${passed} passed`);
