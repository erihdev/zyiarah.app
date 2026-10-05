"use strict";

// ثقةُ طابورِ الإشعارات — تشغيل: node test/notification_trust.test.js (ضمن npm test).
//
// ═══ الثغرة ═══
//
// `processNotificationTriggers` كان يَحسبُ الثقةَ هكذا:
//
//     let senderIsTrusted = trigger.createdBy === "server";
//
// و`createdBy` **حقلٌ يَكتبه العميل**: قاعدةُ `notification_triggers` كانت
// `allow create: if isLoggedIn()` بلا أيِّ قيدٍ على الحقول. فأيُّ مستخدمٍ
// مسجَّلٍ يَكتب `createdBy: "server"` فيُعَدُّ موثوقاً ويَتخطّى الحارسَ كلَّه:
//
//   * إشعارُ Push **وسجلٌّ داخلَ التطبيق** بعنوانٍ ونصٍّ من اختيارِه إلى أيِّ
//     ضحيّةٍ، باسمِ «زيارة» — وهو التصيّدُ الذي كُتب الحارسُ لمنعِه حرفيّاً
//     (تعليقُه يقول ذلك).
//   * بثٌّ إداريٌّ مزيَّفٌ لكلِّ الموظّفين (`toUid: "ADMIN_BROADCAST"`).
//   * بريدٌ من نطاقِ المنشأةِ إلى **أيِّ عنوان**: `recipientEmail` يُقرأ من
//     المستند — أي مُرحِّلُ بريدٍ مفتوح. والمرفقاتُ تَمرُّ بالمسارِ نفسِه
//     (انظر `attachments.test.js`).
//
// ═══ الإصلاح: الثقةُ من المجموعةِ لا من حقل ═══
//
// لا تستطيع الدالّةُ التمييزَ بين كاتبٍ وكاتبٍ من محتوى المستند — الذي
// يُميّزُهما هو **مَن كتب**، ولا تَعرفُه إلّا القواعد. فالفصلُ بالمجموعة:
// `notification_queue` **بلا قاعدةِ مطابقةٍ في firestore.rules**، فالعميلُ
// ممنوعٌ منها بالافتراضِ المُغلَق وAdmin SDK يَتخطّى القواعد. فالكتابةُ فيها
// برهانُ أصلٍ خادميٍّ لا يُنتحَل، والثقةُ تُحسَب من `snap.ref.parent.id`.
//
// وهذا **لا يَنتظر نشرَ القواعد**: `firestore.rules` تُنشَر يدويّاً (قرارُ
// STAGE-C)، بينما `functions` تُنشَر آليّاً على `main` — فالشِّقُّ الحاملُ
// للوزنِ يَعمل فورَ الدمج. وقيدُ `createdBy == auth.uid` أُضيف للقواعدِ دفاعاً
// في العمق (يَمنعُ انتحالَ موظّف)، و`rules.notifications.test.js` يُثبّته
// بالمُحاكي.
//
// ═══ ونصفٌ ثانٍ كان **حيّاً** ═══
//
// `Contracts.tsx` كان يَكتبُ الـtrigger **بلا `createdBy` إطلاقاً**، فيُحسَب
// غيرَ موثوقٍ ويُرفَض (`refused_untrusted_sender`): اعتمادُ العقدِ من لوحةِ
// الويبِ لا يَصلُ العميلةَ منه شيء — وتعليقُ الكودِ هناك يقول إنّه أُضيف
// ليُخرجَ ذلك الاعتمادَ من الصمت.

const assert = require("assert");
const fs = require("fs");
const path = require("path");

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

const root = path.resolve(__dirname, "..", "..");
const read = (rel) => fs.readFileSync(path.join(root, rel), "utf8");
const strip = (src) => src.split("\n")
    .filter((l) => !/^\s*(\/\/|\*|\/\*|#)/.test(l)).join("\n");

const idx = read("functions/index.js");
const code = strip(idx);
const rules = read("firestore.rules");

t("(أ) الثقةُ من اسمِ المجموعة، ولا أثرَ لحقلِ createdBy في حسابِها", () => {
  assert.ok(code.includes(
      "let senderIsTrusted = snap.ref.parent.id === \"notification_queue\""),
  "الثقةُ لا تُحسَب من المجموعة");
  assert.ok(!code.includes("trigger.createdBy === \"server\""),
      "الثقةُ عادت إلى حقلٍ يَكتبه العميل — وهي الثغرةُ بعينها");
  // والمصطلحُ ما زال في الخامِّ (التوثيقُ يَشرحُ ما كان) فالتجريدُ لم يُفرِغ الفحص.
  assert.ok(idx.includes("createdBy === \"server\""),
      "التوثيقُ الذي يَحملُ السببَ حُذف — فالفحصُ بلا موضوع");
});

t("(ب) الدفعُ الخادميُّ كلُّه إلى الطابورِ الخادميّ", () => {
  const i = code.indexOf("async function queuePush(");
  assert.ok(i > 0, "queuePush غائبة");
  const body = code.substring(i, code.indexOf("\n}", i));
  assert.ok(body.includes("collection(\"notification_queue\")"),
      "queuePush ما زالت تَكتبُ الطابورَ القابلَ للكتابةِ من العميل");
  assert.ok(!body.includes("collection(\"notification_triggers\")"));
  // ولا كاتبَ خادميٌّ آخرَ لطابورِ العميل: المواضعُ الباقيةُ قراءةٌ/مكنسةٌ فقط.
  const adds = (code.match(/collection\("notification_triggers"\)\s*\.add\(/g) ||
    []).length + (code.match(/collection\(col\)\.add\(/g) || []).length;
  assert.ok(adds <= 1, `كاتبٌ خادميٌّ جديدٌ لطابورِ العميل (${adds})`);
});

t("(ج) مُعالِجٌ واحدٌ للطابورَين — نسختان تَنحرفان", () => {
  assert.ok(code.includes("const _processNotifQueueDoc = async (event) =>"));
  for (const e of ["exports.processServerNotificationQueue",
    "exports.processNotificationTriggers"]) {
    assert.ok(code.includes(e), `${e} غائب`);
  }
  assert.strictEqual(
      (code.match(/_processNotifQueueDoc\)/g) || []).length, 2,
      "المُعالِجُ ليس مُشتركاً بين التسجيلَين");
  assert.ok(code.includes("document: \"notification_queue/{id}\""));
  assert.ok(code.includes("document: \"notification_triggers/{id}\""));
});

t("(د) القواعدُ: لا مطابقةَ لـnotification_queue، وcreatedBy مُقيَّد", () => {
  assert.ok(!/match \/notification_queue\//.test(rules),
      "أُضيفت قاعدةٌ لـnotification_queue — الافتراضُ المُغلَقُ هو الحارس");
  assert.ok(rules.includes(
      "request.resource.data.get('createdBy', '') == request.auth.uid"),
  "قيدُ createdBy في القواعدِ غائب");
  assert.ok(!/match \/notification_triggers\/\{triggerId\} \{\s*\n\s*allow create: if isLoggedIn\(\);/
      .test(rules), "القاعدةُ المفتوحةُ عادت");
});

t("(هـ) المكنسةُ تُعيد كلَّ مستندٍ إلى طابورِه هو", () => {
  const i = code.indexOf("for (const col of [\"notification_queue\"");
  assert.ok(i > 0, "المكنسةُ لا تُغطّي الطابورَين");
  const body = code.substring(i, i + 1200);
  assert.ok(body.includes("db.collection(col).add(copy)"),
      "النسخُ إلى مجموعةٍ ثابتةٍ يَمنحُ مستندَ عميلٍ ثقةً لم يَملكها");
});

t("(و) كلُّ كاتبٍ عميليٍّ يَكتبُ معرّفَه هو", () => {
  // بلا هذا الفحصِ يَمرُّ كاتبٌ جديدٌ بلا الحقل فيُرفَض إشعارُه **بصمت** —
  // وهو ما حدثَ لـContracts.tsx حرفيّاً.
  const writers = {
    "lib/services/zyiarah_messaging_service.dart": 2,
    "lib/screens/admin/admin_compliance_screen.dart": 1,
    "admin_panel/src/pages/Contracts.tsx": 1,
  };
  for (const [rel, n] of Object.entries(writers)) {
    const src = strip(read(rel));
    const adds = (src.match(/notification_triggers['")]/g) || []).length;
    assert.ok(adds >= n, `${rel}: مواضعُ الكتابةِ ${adds} < ${n}`);
    const own = (src.match(/createdBy['"]?\s*:\s*[^,\n]*(uid|currentUser)/g) ||
      []).length;
    assert.ok(own >= n,
        `${rel}: ${own} من ${n} موضعاً يَكتبُ createdBy بمعرّفِ صاحبِه — ` +
        "الباقي سيُرفَض بصمت");
  }
});

t("(ز) حارسُ مكافحةِ الترحيلِ ما زال قائماً بشِقَّيه", () => {
  assert.ok(code.includes("refused_untrusted_sender"));
  assert.ok(code.includes("targetsOtherUser") && code.includes("targetsAdmins"),
      "أحدُ شِقَّي الحارسِ سقط");
  assert.ok(code.includes("r != null && r !== \"client\""),
      "فحصُ دورِ الموظّفِ سقط — فلا مسارَ شرعيَّ لتنبيهٍ من موظّف");
});

console.log(`\nnotification_trust tests: ${passed} passed`);
