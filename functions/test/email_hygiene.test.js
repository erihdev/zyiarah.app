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
const proc = body("exports.processNotificationTriggers");
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

console.log(`email_hygiene: ${passed} passed`);
