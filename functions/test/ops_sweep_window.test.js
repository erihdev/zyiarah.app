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

/**
 * جسمُ دالّةٍ بحدِّه الحقيقيّ — لا بعدِّ أحرف.
 *
 * شرائحُ هذا الملفِّ كانت تَتجاوزُ دوالَّها: `cancelStaleUnpaidOrders` ٥٢٤
 * حرفاً، و`unassignJobsOnDriverDisable` ١٤١١، و`_unassignPayload` ٣٠٣ — أي
 * أنّ الفحصَ يَقرأُ شفرةَ دالّةٍ أخرى ويَحكمُ بها. ولم يَبِتْ ذلك عطلاً
 * بعدُ (قِيسَ: لا مصطلحَ مَحروساً في المُتجاوَز)، لكنّه فخُّ الحدِّ نفسُه
 * الذي عضَّ هنا مرّاتٍ — `indexOf(']);')` في حارسِ COD، و`indexOf('}')` في
 * حارسِ المخزَن، وشريحةُ ١٦٠٠ حرفٍ في حارسِ تحقّقِ السعر.
 * @param {string} src المصدر
 * @param {string} anchor مِرساةُ الدالّة
 * @return {string} الجسم
 */
function fnBody(src, anchor) {
  const i = src.indexOf(anchor);
  assert.ok(i > -1, `المِرساةُ «${anchor}» اختفت`);
  const ends = [
    src.indexOf("\nexports.", i + 10),
    src.indexOf("\nasync function ", i + 10),
    src.indexOf("\nfunction ", i + 10),
  ].filter((x) => x > 0);
  const j = ends.length ? Math.min(...ends) : src.length;
  assert.ok(j - i > 300, `اقتطاعُ «${anchor}» انهار`);
  return src.slice(i, j);
}

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
  const body = fnBody(code, "exports.cancelStaleUnpaidOrders");
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
// ═══ (١٤) مهمّةٌ فشلَ فكُّ إسنادِها عن سائقٍ معطَّل ═══
//
// `unassignJobsOnDriverDisable` كان يَبتلعُ فشلَ التحديثِ لكلِّ مستندٍ
// (`.catch` يَطبعُ) **ويَعُدُّه ناجحاً** — فالتنبيهُ يَقولُ «أُعيدت لقائمة
// الإسناد» عن مهمّةٍ ما زالت مُسنَدةً لمن لا يَعمل، والمُشغّلُ بلا `retry`.
test("(١٤) العدُّ على النجاحِ وحدَه، والفشلُ يَكتبُ علَمَه", () => {
  const seg = fnBody(src, "exports.unassignJobsOnDriverDisable");
  assert.ok(!/\}\)\.catch\(\(e\) =>\s*\n?\s*console\.error\(`unassignJobsOnDriverDisable/
      .test(seg), "الفشلُ ما زال مُبتلَعاً بـ.catch على التحديث");
  assert.ok(/try \{[\s\S]{0,160}?update\(_unassignPayload\([\s\S]{0,40}?\);\s*\n\s*n\+\+;/
      .test(seg), "العدُّ ليس داخلَ مسارِ النجاح");
  assert.ok(seg.includes("unassign_pending: true"),
      "الفشلُ لا يَكتبُ علَمَه — فلا تَراه المكنسة");
  assert.ok(seg.includes("failed++"), "الفشلُ غيرُ معدود");
  assert.ok(/failed > 0/.test(seg),
      "التنبيهُ لا يُفرِّقُ المُعادَ من المتعذّر — وهي الدعوى المَحروسة");
});

test("(١٥) والمكنسةُ تَستعلمُ العلَمَ لا الحالة، وتُعيدُ نفسَ الحِمْل", () => {
  const i = src.indexOf("exports.opsHealthSweep");
  const sweep = src.slice(i);
  assert.ok(sweep.includes(".where(\"unassign_pending\", \"==\", true)"),
      "لا مكنسةَ على العلَم");
  // الحالةُ (`assigned`) هي حالةُ كلِّ مهمّةٍ قائمةٍ — استعلامُها يَغرق.
  assert.ok(!/unassign[\s\S]{0,400}?where\("status", "in", \["scheduled"/.test(sweep),
      "المكنسةُ تَستعلمُ الحالةَ فتَغرقُ فيها");
  // **والحِمْلُ موضعٌ واحدٌ بمُنادِيَين.** كتبتُه أوّلاً مرّتَين — في
  // المُشغّلِ وفي المكنسةِ — وهو عينُ «قرارٌ مكتوبٌ مرّتَين يَنحرِف»
  // الذي يُصحّحُه هذا المستودعُ مرّةً بعد مرّة: نسخةٌ تَفقدُ حقلاً تُنتجُ
  // مهمّةً «مُستردَّةً» بحقولِ سائقٍ باقيةٍ فلا تُسنَدُ لأحد. فالفحصُ
  // يَشدُّ التعريفَ الواحدَ والمُنادِيَين، لا تشابهَ النصَّين.
  assert.strictEqual(
      (src.match(/function _unassignPayload\(/g) || []).length, 1,
      "تعريفُ الحِمْلِ ليس موضعاً واحداً");
  assert.ok(sweep.includes("_unassignPayload(\"driver_disabled\")"),
      "المكنسةُ لا تُعيدُ نفسَ الحِمْل");
  assert.strictEqual(
      (src.match(/_unassignPayload\("driver_disabled"\)/g) || []).length, 2,
      "المُنادِيانِ ليسا اثنَين — فنسخةٌ إنلاين عادت");
  // والحِمْلُ نفسُه يَمحو العلَمَين، وإلّا بَقيَ المستندُ في المجموعةِ أبداً.
  const def = fnBody(src, "function _unassignPayload(");
  for (const f of ["unassign_pending", "unassign_driver_id"]) {
    assert.ok(new RegExp(f + ": FieldValue\\.delete\\(\\)").test(def),
        `النجاحُ لا يَمحو ${f} — فالمستندُ يَبقى في مجموعةِ المكنسةِ للأبد`);
  }
});

// ═══ (١٦) رمزُ دفعٍ موسومٌ بدورٍ قديم ═══
//
// توجيهُ تنبيهاتِ الإدارةِ يَستعلمُ `fcm_tokens.role`، و`syncRoleToPushToken`
// يُصحّحُها بـ`.catch(() => {})` — ففشلٌ عابرٌ يُعيدُ العطلَ الذي كُتبت له.
// والفحصُ **بنيويٌّ**: يُقابِلُ الرمزَ بـ`users` فلا علَمَ يُلفَّق.
test("(١٦) فحصُ انحرافِ دورِ الرمزِ بنيويٌّ ويُقابِلُ users", () => {
  const i = src.indexOf("exports.opsHealthSweep");
  const sweep = src.slice(i);
  assert.ok(sweep.includes("db.collection(\"fcm_tokens\")"),
      "لا فحصَ لانحرافِ الرمز");
  assert.ok(/where\("role", "in", STAFF_TOKEN_ROLES\)/.test(sweep),
      "الجمهورُ ليس رموزَ الموظّفينَ وحدَها");
  assert.ok(/collection\("users"\)\.doc\(doc\.id\)/.test(sweep),
      "لا مُقابلةَ بـusers — فالفحصُ يُصدّقُ الرمزَ نفسَه");
  // **والمُقارنةُ تَحكُمُ الكتابةَ، لا تَحضُرُ فحسب.** أوّلُ صياغةٍ أثبتَت
  // حضورَ `users` و`role_synced_at` وحدَهما، فمرَّ اختبارُ قضمٍ جعلَ الشرطَ
  // `if (false)` **أخضرَ**: درسُ «الاسمُ ليس القدرة» واقعاً عليَّ مرّةً أخرى.
  assert.ok(/if \(_tokenRoleDrifted\(doc\.data\(\), u\)\) \{[\s\S]{0,200}?_tokenRolePayload\(u\)/
      .test(sweep),
  "الكتابةُ ليست مشروطةً بالمُقارنةِ — فتصحيحٌ يَجري دائماً أو لا يَجري أبداً");
  assert.ok(sweep.includes("role_synced_at") ||
      sweep.includes("_tokenRolePayload(u)"), "لا تصحيحَ يُكتَب");
  // ومستخدمٌ زال ورمزُه باقٍ: هو العطلُ المسجَّلُ بعينِه.
  assert.ok(/if \(!u\) \{[\s\S]{0,200}?doc\.ref\.delete\(\)/.test(sweep),
      "رمزُ مستخدمٍ محذوفٍ لا يُحذَف");
});

test("(١٧) ولا فهرسَ مركَّباً أُضيفَ لأيٍّ منهما", () => {
  const idx = JSON.parse(fs.readFileSync(
      path.join(__dirname, "../../firestore.indexes.json"), "utf8"));
  for (const coll of ["fcm_tokens"]) {
    const hit = (idx.indexes || []).filter((x) => x.collectionGroup === coll);
    assert.strictEqual(hit.length, 0,
        `${coll} صارَ له فهرسٌ مركَّب — مساواةٌ/in على حقلٍ واحدٍ لا تَلزمُها`);
  }
  // و`unassign_pending` مساواةٌ واحدةٌ على `orders` — لا فهرسَ لها وحدَها.
  const orderIdx = (idx.indexes || []).filter((x) =>
    x.collectionGroup === "orders" &&
      x.fields.length === 1 && x.fields[0].fieldPath === "unassign_pending");
  assert.strictEqual(orderIdx.length, 0, "فهرسٌ أحاديٌّ لا لزومَ له");
});


// ════════════════════════════════════════════════════════════════════════
// (١٨–٢١) **نافذتانِ كانتا تَسيلانِ بما تَتخطّاه الحلقة.**
//
// العائلةُ أُغلقت أربعَ مرّاتٍ (البثُّ المجدول، «مدفوعٌ وعالق»، المحافظُ
// السالبة، استردادُ الإلغاء)، ومسحٌ لكلِّ `limit()` في `opsHealthSweep`
// (خمسةَ عشَرَ) أعطى اثنتَين بالتوقيعِ نفسِه: مستندٌ تَتخطّاه الحلقةُ
// بـ`continue` **يَبقى مطابقاً للاستعلامِ إلى الأبد**.
// ════════════════════════════════════════════════════════════════════════

test("(١٨) العقودُ العالقةُ تُقرأُ كاملةً بحدِّ مسحٍ لا بنافذةِ limit", () => {
  // **على المُجرَّدِ من التعليقات**: شرحُ القرارِ يَذكرُ «نافذةَ limit»
  // و«المئة» نصّاً، فلولا التجريدُ سقطَ الفحصُ على توثيقِه.
  const i = code.indexOf("exports.opsHealthSweep");
  const sweep = code.slice(i);
  const j = sweep.indexOf("db.collection(\"contracts\")");
  assert.ok(j > 0, "زالَ إنقاذُ العقودِ من المكنسة");
  const blk = sweep.slice(j, j + 1400);
  assert.ok(!/\.limit\(\d+\)/.test(blk.slice(0, 300)),
      "عادت نافذةُ limit — والمُتخطّى (plan_validation_failed) لا يَخرُجُ " +
      "منها أبداً فيَدفعُ عقداً مدفوعاً عالقاً خارجَها");
  assert.ok(blk.includes(".count().get()"), "لا عَدَّ خادميّاً قبلَ القراءة");
  assert.ok(blk.includes("STUCK_CONTRACT_SCAN_MAX"),
      "لا حدَّ مسحٍ — فقراءةُ الجمهورِ كاملةً بلا سقف");
  // وتجاوزُ الحدِّ **يُنبّه** ولا يُعدِّدُ — سابقةُ المحافظِ السالبة.
  assert.ok(/kCount > STUCK_CONTRACT_SCAN_MAX[\s\S]{0,300}?queuePush\(/.test(blk),
      "تجاوزُ الحدِّ لا يُنبّه — فالانفجارُ يَمُرُّ صامتاً");
  // ومضادّةٌ: الشكلُ الممنوعُ ما زال مُقتبَساً في الشرحِ الخامّ.
  assert.ok(src.includes("نافذةُ الـ100"),
      "زالَ شرحُ العطلِ — فلا يَعرفُ القارئُ لِمَ لا limit هنا");
});

test("(١٩) والحدُّ مُعرَّفٌ مرّةً بجوارِ سابقتِه", () => {
  const m = code.match(/const STUCK_CONTRACT_SCAN_MAX = (\d+);/);
  assert.ok(m, "الحدُّ ليس ثابتاً مُسمّىً");
  assert.ok(Number(m[1]) > 0 && Number(m[1]) <= 1000, "حدُّ مسحٍ خارجَ المعقول");
  assert.strictEqual(
      (code.match(/const STUCK_CONTRACT_SCAN_MAX\b/g) || []).length, 1,
      "تعريفانِ للحدّ");
  assert.ok(code.includes("const NEG_WALLET_SCAN_MAX"),
      "زالت السابقةُ التي يَقتدي بها — فالقرارُ يُراجَع");
});

test("(٢٠) وإعادةُ إحياءِ الطابورِ نافذتُها متدحرجةٌ — الحدُّ الأدنى في الاستعلام", () => {
  const i = code.indexOf("exports.opsHealthSweep");
  const sweep = code.slice(i);
  const j = sweep.indexOf("for (const col of [\"notification_queue\"");
  assert.ok(j > 0, "زالَ إحياءُ الطابورِ من المكنسة");
  const blk = sweep.slice(j, j + 1600);
  // المدَيانِ معاً على `createdAt`: بلا الأدنى يُطابِقُ الاستعلامُ كلَّ
  // مستندٍ غيرِ مُعالَجٍ على الإطلاق، و`asc` يُقدّمُ الأقدمَ — فتُقرأُ مئةٌ
  // عتيقةٌ وتُتخطّى كلُّها ولا يُرى حديثٌ عالقٌ واحد.
  assert.ok(/\.where\("createdAt", "<=",/.test(blk), "زالَ الحدُّ الأعلى");
  assert.ok(/\.where\("createdAt", ">=",/.test(blk),
      "لا حدَّ أدنى في الاستعلام — فالنافذةُ تَسيلُ بالعتيقِ المُتخطّى");
  // ولم يَعُد العمرُ يُفحَصُ في الحلقةِ وحدَها (وإلّا فالعتيقُ ما زال يُقرَأ).
  assert.ok(!/ageMs >/.test(blk),
      "فحصُ العمرِ ما زال في الحلقةِ — فالاستعلامُ يَقرأُ العتيقَ ثمّ يُلقيه");
  // والترتيبُ الذي يَجعلُ السيلَ قاتلاً ما زال كما هو (فهو جزءُ التعليل).
  assert.ok(/orderBy\("createdAt", "asc"\)/.test(blk),
      "تغيّرَ الترتيبُ — فتعليلُ «الأقدمُ يُقدَّم» يُراجَع");
});

test("(٢١) وشاهدا التعليل: الفهرسُ يَخدمُ المدَيَين، والفشلُ الدائمُ يُقيم", () => {
  // مدَيانِ على حقلٍ واحدٍ يَخدمُهما الفهرسُ القائمُ — لا فهرسَ جديد.
  const idx = JSON.parse(fs.readFileSync(
      path.join(__dirname, "../../firestore.indexes.json"), "utf8"));
  for (const coll of ["notification_queue", "notification_triggers"]) {
    const hit = (idx.indexes || []).filter((x) => x.collectionGroup === coll &&
        x.fields.some((f) => f.fieldPath === "processed") &&
        x.fields.some((f) => f.fieldPath === "createdAt"));
    assert.strictEqual(hit.length, 1,
        `${coll} بلا فهرسِ (processed, createdAt) — المدَيانِ يَلزمُهما`);
  }
  // وسببُ السيلِ قائمٌ: فرعُ الفشلِ يَترُكُ `processed: false` ثمّ يَستسلم.
  assert.ok(/processed: false,[\s\S]{0,200}?error: error\.message/.test(code),
      "فرعُ الفشلِ لم يَعُد يَترُكُ processed:false — فالتعليلُ يُراجَع");
  assert.ok(code.includes("giveUp: true"),
      "زالَ الاستسلامُ بعد ثلاثِ محاولاتٍ — فالتعليلُ يُراجَع");
});


// ═══ حذفُ حسابٍ عالقٌ في «جاري الحذف» (2026-10-08) ═══
//
// `processAccountDeletion` يَكتبُ `'deleted'` ثمّ يَحذفُ المصادقةَ والمستندَ
// والرموزَ ثمّ **يُحدّثُ الحالةَ**. موتُ الحاويِ بين الحذفِ والتحديثِ يُجمّدُ
// الطلبَ على `'deleted'` إلى الأبد، وزرُّ إعادةِ المحاولةِ يَلزمُه مَن
// يَفتحُ الشاشة — و`opsHealthSweep` لم يَكن يَمَسُّ المجموعةَ إطلاقاً.
test("(٢٢) مكنسةُ الحذفِ العالقِ: مساواةٌ واحدةٌ والعمرُ في الشفرة", () => {
  // **المِرساةُ داخلَ المكنسةِ لا في الملفّ**: أوّلُ ورودٍ لـ
  // `collection("account_deletions")` في `index.js` هو تحديثُ
  // `processAccountDeletion` نفسِه — فخُّ «أوّلِ ورودٍ» عضَّ في أوّلِ تشغيل.
  const sweep = fnBody(code, "exports.opsHealthSweep");
  const i = sweep.indexOf("collection(\"account_deletions\")");
  assert.ok(i > 0, "المكنسةُ لا تَمَسُّ account_deletions");
  const seg = sweep.slice(i, i + 700);
  assert.ok(seg.includes(".where(\"status\", \"==\", \"deleted\")"),
      "الاستعلامُ ليس على الحالةِ العابرة");
  // **ولا مدًى في الاستعلام**: مساواةٌ وحدَها ⇒ لا فهرسَ مركَّب. وهو قرارٌ
  // لا سهو: `'deleted'` حالةٌ عابرةٌ لا متراكمة، فالنافذةُ لا تَمتلئ.
  assert.ok(!/\.where\("requested_at"/.test(seg),
      "عادَ المدى إلى الاستعلامِ — فهرسٌ مركَّبٌ يَلزمُه، واتجاهُ القائمِ "
      + "يُسقِطُ الأقدمَ عند السقف");
  assert.ok(/requested_at[\s\S]{0,200}?toMillis/.test(seg),
      "العمرُ لا يُرشَّحُ في الشفرة — فكلُّ حذفٍ جارٍ يُنبَّهُ عنه");
});

test("(٢٣) والعلَمُ والجمهورُ والمُهلةُ: واحدٌ، المدير العامُّ، ساعة", () => {
  const sweep = fnBody(code, "exports.opsHealthSweep");
  const i = sweep.indexOf("collection(\"account_deletions\")");
  assert.ok(i > 0, "المكنسةُ لا تَمَسُّ account_deletions");
  const seg = sweep.slice(i, i + 1400);
  assert.ok(seg.includes("\"deletion_stuck_alerted\""),
      "بلا علَمٍ ⇒ تنبيهٌ كلَّ دورةِ مكنسة");
  // القاعدةُ تَحصُرُ قراءةَ `account_deletions` بالمدير العامّ، فتنبيهُ غيرِه
  // يُرسِلُه إلى صفحةٍ لا يَفتحُها.
  assert.ok(/\["super_admin"\]\)/.test(seg),
      "جمهورُ التنبيهِ ليس المدير العامَّ وحدَه");
  const rules = fs.readFileSync(
      path.join(__dirname, "../../firestore.rules"), "utf8");
  assert.ok(rules.includes("allow read, update, delete: if isSuperAdmin();"),
      "تغيّرت قاعدةُ قراءةِ account_deletions — يُراجَعُ جمهورُ التنبيه");
  // والمُهلةُ عينُ `kDeletionStuckGrace` في العميل: تنبيهٌ عن صفٍّ لا يَحملُ
  // زرَّ إعادةٍ بعدُ هو إرسالُ الأدمنِ إلى شاشةٍ بلا إجراء.
  const dart = fs.readFileSync(path.join(__dirname,
      "../../lib/utils/deletion_log_row.dart"), "utf8");
  assert.ok(dart.includes("kDeletionStuckGrace = Duration(hours: 1)"),
      "مُهلةُ العميلِ لم تَعُد ساعةً — تُراجَعُ مُهلةُ المكنسة");
  // **بالتعبيرِ كاملاً لا بالاحتواء**: اختبارُ قضمٍ جعلَها
  // `2 * 60 * 60 * 1000` فمرَّ **أخضرَ** — فالنصُّ يَحتوي الأوّلَ.
  assert.ok(seg.includes("toMillis() >= 60 * 60 * 1000"),
      "مُهلةُ المكنسةِ ليست ساعةً — فالطرفانِ افترقا");
});

test("(٢٤) ولا فهرسَ مركَّباً أُضيفَ للمجموعة", () => {
  const idx = JSON.parse(fs.readFileSync(
      path.join(__dirname, "../../firestore.indexes.json"), "utf8"));
  const hit = (idx.indexes || [])
      .filter((x) => x.collectionGroup === "account_deletions");
  // **الفهرسُ القائمُ يَبقى بلا استعلامٍ ومُعلَّقاً لحذفٍ بشريّ.** لم يُشكَّل
  // الاستعلامُ ليُبرّرَه: اتجاهُه `requested_at DESC` يُعطي الأحدثَ أوّلاً
  // فيُسقِطُ الأقدمَ — الأوجبَ قانونيّاً — عند السقف، وتصحيحُ اتّجاهِ فهرسٍ
  // منشورٍ تعديلٌ ومسارُ الفهارسِ بلا `--force`.
  assert.strictEqual(hit.length, 1,
      "تغيّرَ عددُ فهارسِ account_deletions — راجِعْ: أصارَ له استعلام؟");
});

test("(٢٥) وشاهدُ التعليل: الحالةُ تُكتَبُ أوّلاً وتُحدَّثُ آخِراً", () => {
  const a = code.indexOf("async function processAccountDeletion(");
  const b = code.indexOf("\nexports.onAccountDeletionRequested", a);
  assert.ok(a > 0 && b > a, "اقتطاعٌ فاشلٌ لجسمِ processAccountDeletion");
  const body = code.slice(a, b);
  const iAuth = body.indexOf("getAuth().deleteUser(");
  const iDone = body.indexOf("status: \"deleted_fully_processed\"");
  assert.ok(iAuth > 0 && iDone > iAuth,
      "تحديثُ الحالةِ لم يَعُد بعدَ حذفِ المصادقةِ — فنافذةُ العلوقِ تُراجَع");
});

console.log(`\nops_sweep_window tests: ${passed} passed`);
