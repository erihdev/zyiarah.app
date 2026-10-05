"use strict";

// أصالةُ الإشعاراتِ الواردة — تشغيل: node test/webhook_auth.test.js (ضمن npm test).
//
// ═══ لماذا ═══
//
// ثلاثُ نقاطٍ عامّةٍ على الشبكةِ (`onRequest`) تَقبلُ أحداثَ دفعٍ تُقلِّبُ
// `is_paid`، ولكلٍّ **آليّةُ أصالةٍ مختلفة** — و**لا فحصَ واحداً** كان يَشدُّ
// أيّاً منها. فإضعافُ أيٍّ منها صامتٌ تماماً: لا شيءَ في الواجهةِ يَتغيّر، ولا
// اختبارَ يَسقط، والطريقُ المفتوحُ هو تلفيقُ طلبٍ مدفوع.
//
//   • **ميسر**: سرٌّ مشتركٌ في الجسمِ (`event.secret_token`) **ثم** تحقّقٌ ثانٍ
//     من واجهةِ ميسر (`moyasar.getPayment`) — والثاني هو الحارسُ الحقيقيّ:
//     بدونه يَكفي جسمٌ مُلفَّقٌ يَحملُ السرَّ. ليس HMAC.
//   • **تمارا**: JWT موقَّعٌ (HS256) بـNotification Token — وتعليقُها يَقولُ
//     صراحةً «ليس HMAC للجسم ولا ترويسة tamara-signature».
//   • **تابي**: HMAC-SHA256 حقيقيٌّ على الجسمِ مع `timingSafeEqual`.
//
// و**CLAUDE.md كان يَقول «all HMAC-verified» عن الثلاثة** — وهو صحيحٌ في
// واحدٍ منها فقط. قارئٌ يَبني على ذلك لا يَعرفُ أنّ حارسَ ميسرَ الحقيقيَّ هو
// التحقّقُ الثاني من الواجهة، فيَحذفُه بلا أثر؛ أو «يُضيف HMAC» لتمارا حيث
// الـJWT هو الآليّةُ الموثَّقة. فهذا الفحصُ يُثبّتُ **الآليّةَ لكلٍّ بعينِها**.
//
// ═══ وعطلٌ وُجد بكتابتِه ═══
//
// تابي كان يَحسبُ HMAC على `JSON.stringify(req.body)` — وهي **ليست** البايتاتُ
// التي وقّعها تابي: الجسمُ يُحلَّلُ ثم يُعادُ بناؤه، فتَختلفُ المسافاتُ
// وتهريبُ اليونيكود وصياغةُ الأرقام، فيَفشلُ التوقيعُ على إشعارٍ **شرعيٍّ**
// ويُرَدُّ 401. `req.rawBody` هو ما تُوفّره Firebase لهذا بعينِه. والأثرُ
// محدودٌ ويَتقلّص (تابي صار استرداداً فقط منذ 2026-09-30، فلا مدفوعاتٍ جديدة)،
// لكنّه عطلٌ في فحصِ توقيعٍ لا يُقاس بحجمِ ضحاياه.
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
// يُجرَّدُ من أسطرِ التعليقِ: الشفرةُ تَشرحُ كلَّ آليّةٍ بتسميتِها.
const code = raw
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("//"))
    .join("\n");

/**
 * جسمُ دالّةٍ مُصدَّرةٍ بموازنةِ الأقواسِ — لا بقطعٍ بعددِ أسطرٍ ثابت.
 * @param {string} src النصّ
 * @param {string} name اسمُ الدالّة
 * @return {string} الجسم
 */
function bodyOf(src, name) {
  const i = src.indexOf(`exports.${name} = onRequest(`);
  assert.ok(i > -1, `${name} غير موجود`);
  const open = src.indexOf("(", i + `exports.${name} = onRequest`.length);
  let depth = 0;
  for (let j = open; j < src.length; j++) {
    if (src[j] === "(") depth++;
    if (src[j] === ")") {
      depth--;
      if (depth === 0) return src.slice(open, j);
    }
  }
  throw new Error(`${name}: أقواسٌ غيرُ متوازنة`);
}

t("(أ) النقاطُ العامّةُ ثلاثٌ بعينِها — رابعةٌ تُراجَع", () => {
  // كلُّ `onRequest` جديدٍ نقطةٌ عامّةٌ غيرُ مُصادَقةٍ ما لم تَتحقّقْ من شيء.
  const names = [...code.matchAll(/exports\.(\w+) = onRequest\(/g)]
      .map((m) => m[1])
      .sort();
  assert.deepStrictEqual(names,
      ["moyasarWebhook", "tabbyWebhook", "tamaraWebhook"],
      `تغيّرت مجموعةُ نقاطِ onRequest: ${names.join(", ")}`);
});

t("(ب) ميسر: سرٌّ مشتركٌ يَفشلُ مُغلَقاً — لا مفتوحاً", () => {
  const b = bodyOf(code, "moyasarWebhook");
  // بلا الشقِّ الأوّلِ كان أيُّ POST بلا سرٍّ يَمرّ (موثَّقٌ في تعليقِ الشفرة).
  assert.ok(b.includes("if (!webhookSecret || event.secret_token !== webhookSecret)"),
      "شرطُ السرِّ تغيّر — تأكّدْ أنّه ما زال يَفشلُ مُغلَقاً");
  assert.ok(/return res\.status\(401\)/.test(b), "الرفضُ ليس 401");
});

t("(ج) وحارسُ ميسرَ الحقيقيُّ: تحقّقٌ ثانٍ من واجهتِها قبل أيِّ ثقة", () => {
  const b = bodyOf(code, "moyasarWebhook");
  // جسمٌ مُلفَّقٌ يَحملُ السرَّ يَمرُّ الشقَّ الأوّل؛ وهذا ما يُبطله.
  assert.ok(b.includes("await moyasar.getPayment(secret, payment.id)"),
      "اختفى التحقّقُ الثاني من واجهةِ ميسر — جسمٌ مُلفَّقٌ يَكفي حينها");
  assert.ok(/if \(!verified\.ok\)[\s\S]{0,200}?return;/.test(b),
      "فشلُ التحقّقِ لا يَمنعُ المتابعة");
  // ولا يُقبَلُ إلّا ما تَقولُ الواجهةُ إنّه مدفوعٌ فعلاً.
  assert.ok(b.includes("verifiedPayment.status !== \"paid\"") &&
      b.includes("verifiedPayment.status !== \"captured\""),
  "حالةُ الدفعةِ لا تُفحَصُ من ردِّ الواجهة");
});

t("(د) تمارا: JWT موقَّعٌ بـHS256، ويُرَدُّ 401 عند الفشل", () => {
  const b = bodyOf(code, "tamaraWebhook");
  assert.ok(b.includes("jwt.verify(String(rawToken), tamaraNotificationToken.value()"),
      "التحقّقُ من الـJWT اختفى");
  assert.ok(b.includes("algorithms: [\"HS256\"]"),
      "بلا تثبيتِ الخوارزميّةِ يُقبَلُ توكنٌ بخوارزميّةٍ أخرى");
  assert.ok(b.includes("res.status(401).send(\"Invalid token\")"));
  assert.ok(b.includes("res.status(401).send(\"Unauthorized\")"),
      "توكنٌ غائبٌ يَجبُ أن يُرَدّ");
});

t("(هـ) وتمارا لا تَدّعي HMAC — تعليقُها يَقولُ ذلك", () => {
  // لو حُذف وأُضيف «HMAC» لتمارا فالآليّةُ الموثَّقةُ هي الـJWT.
  assert.ok(raw.includes("ليس HMAC للجسم ولا ترويسة tamara-signature"),
      "اختفى التعليقُ الذي يَنفي HMAC عن تمارا");
});

t("(و) تابي: HMAC-SHA256 على **البايتاتِ الخامّة** لا على إعادةِ تسلسلِها", () => {
  const b = bodyOf(code, "tabbyWebhook");
  // `JSON.stringify(req.body)` وحدَه يُفشلُ التوقيعَ على إشعارٍ شرعيّ.
  assert.ok(b.includes("const rawBody = req.rawBody || JSON.stringify(req.body);"),
      "عادَ الحسابُ على إعادةِ التسلسل — يَرفضُ إشعاراً شرعيّاً بـ401");
  assert.ok(b.includes("crypto.createHmac(\"sha256\", secret).update(rawBody)"),
      "HMAC لم يُحسَبْ على الخامّ");
  // والمضادّة: اللفظُ ما زال في الخامِّ (التعليقُ الشارحُ للعطل).
  assert.ok(raw.includes("JSON.stringify(req.body)"),
      "اختفى ذكرُ الشكلِ القديمِ من التوثيق — راجِعْ ما جرّده الفحص");
});

t("(ز) وتابي تُقارِنُ بزمنٍ ثابت، وفحصُ الطولِ حاملٌ لا زينة", () => {
  const b = bodyOf(code, "tabbyWebhook");
  assert.ok(b.includes("crypto.timingSafeEqual(sigBuf, expBuf)"),
      "المقارنةُ ليست بزمنٍ ثابت");
  // `timingSafeEqual` **يَرمي** على طولَين مختلفَين، فالفحصُ قبلَه ضروريّ.
  assert.ok(b.includes("sigBuf.length !== expBuf.length ||"),
      "بلا فحصِ الطولِ يَرمي timingSafeEqual فيَسقطُ المُشغّلُ بدل الرفض");
  assert.ok(b.includes("if (!signature)"), "ترويسةٌ غائبةٌ تَجبُ أن تُرَدّ");
  assert.ok(/return res\.status\(401\)[\s\S]{0,120}?Invalid signature/.test(b));
});

t("(ح) ولا نقطةَ تُعالِجُ قبل أن تَتحقّق — الرفضُ يَسبقُ العمل", () => {
  for (const [name, marker] of [
    ["moyasarWebhook", "event.secret_token !== webhookSecret"],
    ["tamaraWebhook", "jwt.verify("],
    ["tabbyWebhook", "crypto.timingSafeEqual("],
  ]) {
    const b = bodyOf(code, name);
    const gate = b.indexOf(marker);
    const ack = b.indexOf("res.status(200)");
    assert.ok(gate > -1, `${name}: بوّابةُ الأصالةِ اختفت`);
    if (ack > -1) {
      assert.ok(gate < ack,
          `${name}: الإقرارُ 200 يَسبقُ التحقّقَ من الأصالة`);
    }
  }
});

t("(ط) والتجريدُ أزالَ شيئاً فعلاً — وإلّا فالنمطُ معطوب", () => {
  assert.ok(code.length < raw.length);
});

console.log(`\nwebhook_auth tests: ${passed} passed`);
