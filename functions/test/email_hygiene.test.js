"use strict";
// حرّاس مصدريون لصحّة البريد: تنقية المستلم قبل Resend، بديل HTML عند غياب
// القالب، وإعادة دفع الإشعارات التي فاتها حدث onCreate (انقطاع 8–18 أغسطس).
// تشغيل: node test/email_hygiene.test.js (ضمن npm test).
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
const fn = src.split("\n").filter((l) => {
  const t = l.trimStart();
  return !t.startsWith("//") && !t.startsWith("*") && !t.startsWith("/*");
}).join("\n");

/**
 * جسم دالة/مُشغّل من أول ظهور الاسم حتى exports التالية.
 * @param {string} name الاسم.
 * @return {string} الجسم.
 */
function body(name) {
  const i = fn.indexOf(name);
  assert.ok(i >= 0, `${name} غير موجودة`);
  const j = fn.indexOf("\nexports.", i + name.length);
  return j > i ? fn.substring(i, j) : fn.substring(i);
}

// نُشغّل الدالتين المساعدتين فعلياً (لا فحص نصّي فقط) بانتزاعهما من المصدر.
const helperSrc = (name) => {
  const i = src.indexOf(`function ${name}(`);
  assert.ok(i >= 0, `${name} غير معرّفة`);
  const j = src.indexOf("\n}\n", i);
  return src.substring(i, j + 2);
};
const _cleanEmail = new Function(helperSrc("_cleanEmail") + "; return _cleanEmail;")();
const _fallbackHtml = new Function(
    helperSrc("_buildTemplateFallbackHtml") + "; return _buildTemplateFallbackHtml;")();

let passed = 0;
const ok = (msg) => { passed++; console.log("  ok -", msg); };

// (a) التنقية: العيّنة الحيّة كانت «‏omarghamfi817@gmail.com» بـ U+200F في أولها.
assert.strictEqual(_cleanEmail("‏omarghamfi817@gmail.com"), "omarghamfi817@gmail.com");
assert.strictEqual(_cleanEmail(" Omar@X.com "), "omar@x.com");
assert.strictEqual(_cleanEmail("لا بريد"), "");
assert.strictEqual(_cleanEmail(null), "");
ok("(a) _cleanEmail يُسقط علامات الاتجاه والمسافات ويرفض ما بلا @");

// (b) المعالج يمرّر المستلم عبر التنقية قبل أي استخدام.
// المُعالِجُ صار دالّةً واحدةً مُشترَكةً بين تسجيلَي طابورَي الإشعارات
// (`notification_queue` الخادميُّ و`notification_triggers` للعميل) بعد أن تبيّن
// أنّ الثقةَ كانت تُحسَب من `createdBy` — حقلٍ يَكتبه العميل. التنقيةُ نفسُها
// لم تتغيّر، فنُعيد توجيهَ الحارسِ إلى اسمِ المُعالِجِ لا إلى التسجيل.
const proc = body("const _processNotifQueueDoc");
assert.ok(/let recipientEmail = _cleanEmail\(/.test(proc),
    "recipientEmail يجب أن يُشتقّ عبر _cleanEmail");
ok("(b) processNotificationTriggers يُنقّي المستلم");

// (c) قالب مفقود → إعادة إرسال بـ HTML بدل رمي الخطأ وإسقاط الرسالة.
assert.ok(/template not found/i.test(proc) && /_buildTemplateFallbackHtml\(/.test(proc),
    "بديل HTML عند Template not found");
const html = _fallbackHtml("تأكيد الطلب", {orderCode: "165-BLW", adminUrl: "https://x"});
assert.ok(html.includes("165-BLW") && !html.includes("https://x"),
    "البديل يعرض المتغيّرات ويُخفي الروابط الداخلية");
assert.ok(html.includes("&lt;") === false && _fallbackHtml("<b>", {}).includes("&lt;b&gt;"),
    "البديل يهرّب HTML");
ok("(c) بديل HTML عند غياب القالب — بمتغيّرات مُهرَّبة");

// (d) إعادة الدفع: نافذة 30 دقيقة–3 أيام، مرة واحدة (redriven_from)، ووسم الأصل.
const sweep = body("exports.opsHealthSweep");
assert.ok(/redriven_from/.test(sweep) && /status: "redriven"/.test(sweep),
    "إعادة الدفع توسم الأصل وتمنع التكرار");
assert.ok(/d\.error \|\| d\.emailStatus \|\| d\.redriven_from/.test(sweep),
    "لا تعيد دفع ما فشل فعلاً أو رُفض أو أُعيد من قبل");
ok("(d) opsHealthSweep يعيد دفع الإشعارات التي فاتها الحدث مرة واحدة فقط");

// (e) **المُرحِّلُ المفتوحُ مُغلَق: بريدُ «الإرسالِ إلى نفسِه» من المصادقةِ
// لا من السجلّ.** `emailSenderOk` كان يُقارِنُ `recipientEmail` بـ
// `users/{uid}.email` — حقلٌ **يَكتبُه العميلُ على مستندِه** (قواعدُ المالكِ
// تَمنعُ الدورَ والمحفظةَ والحظرَ ولم تَذكرِ البريد). فالمسار: اكتبْ بريدَك
// `victim@x.com`، ثمّ أنشئ `notification_triggers` موجَّهاً إلى نفسك
// بـ`recipientEmail: victim@x.com` وعنوانٍ ونصٍّ من اختيارك — يَمرُّ من
// `isAllowedEmailRecipient` (مستندُك يَحملُ العنوانَ) ومن حارسِ المُرسِلِ
// (الحقلانِ متساويان) — فيُرسِلُ الخادمُ من `no-reply@zyiarah.com` محتوًى
// من اختيارِ العميلِ إلى أيِّ عنوان. وهو عينُ ما يَقولُ تعليقُ ذلك الحارسِ
// إنّه يَمنعُه: «يمنع تصيّداً بنطاق الشركة عبر SDK الخام».
assert.ok(/const au = await getAuth\(\)\.getUser\(String\(cb\)\);/.test(proc),
    "بريدُ الإرسالِ الذاتيِّ يَجبُ أن يُقرأَ من المصادقةِ لا من Firestore");
assert.ok(/authEmail\.toLowerCase\(\) ===/.test(proc),
    "المقارنةُ على بريدِ المصادقة");
// ولا تَعودُ المقارنةُ إلى حقلِ السجلّ.
assert.ok(!/cu\.data\(\)\.email/.test(proc),
    "عادت المقارنةُ إلى `users.email` الذي يَكتبُه العميل");
// و`real_email` حُذف: كان مقروءاً في موضعٍ واحدٍ **ولا كاتبَ له في المستودعِ
// كلِّه** — حقلٌ آخرُ مكشوفٌ لكتابةِ العميلِ يُوسّعُ السطحَ بلا مقابل.
assert.ok(!/real_email/.test(fn),
    "`real_email` عاد — ولا كاتبَ له في المستودع");
// والدورُ ما زال يُقرأُ من السجلِّ بحقّ: القواعدُ تَحصرُ `role`/`staff_role`
// في المدير العام، فهو موضعُ ثقة.
assert.ok(/r != null && r !== "client"/.test(proc),
    "استثناءُ الموظّفِ اختفى — فبريدُ الإدارةِ والسائقِ يُرفَض");
// والمضادّة: الشرحُ ما زال في الخامِّ (الفحصُ يَقرأُ المُجرَّد).
assert.ok(/real_email/.test(src),
    "اختفى شرحُ حذفِ `real_email` — راجِعْ ما جرّدَه الفحص");
ok("(e) حارسُ المُرسِلِ يَقرأُ بريدَ المصادقةِ لا حقلاً يَكتبُه العميل");

// (f) والقواعدُ دفاعٌ ثانٍ: `email` على السجلِّ يُطابقُ بريدَ الرمز.
const rules = fs.readFileSync(
    path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
assert.ok(/request\.resource\.data\.email == request\.auth\.token\.email/
    .test(rules), "قاعدةُ البريدِ غائبة — السجلُّ يَبقى قابلاً للتلوين");
ok("(f) وقواعدُ `users` تَربطُ حقلَ البريدِ ببريدِ المصادقة");

console.log(`email_hygiene: ${passed} passed`);
