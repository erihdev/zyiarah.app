"use strict";

// مرآةُ `lib/utils/phone_format.dart` — **جدولُ الحالاتِ يُقرأُ من فحصِ
// الدارت حرفيّاً** فافتراقُ جهةٍ يَسقطُ الفحص (نمطُ `ticket_authorship`).
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const phone = require("../phone");

let pass = 0; let fail = 0;
const check = (name, fn) => {
  try {
    fn();
    console.log(`  ok - ${name}`);
    pass++;
  } catch (e) {
    console.log(`  not ok - ${name}: ${e.message}`);
    fail++;
  }
};

/** @return {Array} جدولُ الحالاتِ من فحصِ الدارت. */
function sharedCases() {
  const src = fs.readFileSync(
      path.join(__dirname, "../../test/saudi_mobile_test.dart"), "utf8");
  const b = src.indexOf("SAUDI_MOBILE_CASES_BEGIN");
  const e = src.indexOf("SAUDI_MOBILE_CASES_END");
  if (b < 0 || e < 0) throw new Error("علامتا الجدولِ اختفتا من فحصِ الدارت");
  const seg = src.slice(b, e);
  // الكتلةُ بين `'''` و`'''` — ومن **آخرِ** `]` إلى الوراءِ بموازنةِ
  // الأقواس، لا بأوّلِ `[` (فخُّ `indexOf('[')` المسجَّل).
  const open = seg.indexOf("'''");
  const close = seg.indexOf("'''", open + 3);
  if (open < 0 || close < 0) throw new Error("كتلةُ الجدولِ غيرُ مُغلَقة");
  const body = seg.slice(open + 3, close);
  const last = body.lastIndexOf("]");
  let depth = 0; let start = -1;
  for (let i = last; i >= 0; i--) {
    if (body[i] === "]") depth++;
    else if (body[i] === "[") {
      depth--;
      if (depth === 0) { start = i; break; }
    }
  }
  if (start < 0) throw new Error("لم تُوازَنْ أقواسُ الجدول");
  // `\uXXXX` في نصِّ دارتٍ خامٍّ (`'''…'''` بـ`\\u`) تُحَلُّ هنا كما يَحُلُّها
  // `jsonDecode` هناك — فالجهتانِ تَقرآنِ المحرفَ نفسَه.
  return JSON.parse(body.slice(start, last + 1));
}

console.log("# phone.js — رقمُ الجوالِ السعوديُّ: صيغةٌ واحدة");

const cases = sharedCases();

check("(١) الجدولُ المشترَكُ قُرئَ فعلاً — أرضيّةٌ وأصنافٌ مُسمّاة", () => {
  assert.ok(cases.length >= 20, `الجدولُ ${cases.length} صفّاً فقط`);
  const labels = new Set(cases.map((r) => r[0]));
  for (const must of [
    "دوليٌّ بصفرَين", "محلّيٌّ بصفرٍ", "مفتاحُ الدولةِ عارياً",
    "عربيٌّ-هنديّ", "فارسيّ", "علامةُ اتّجاهٍ لاصقة",
    "أرضيٌّ جازاني", "دولةٌ أخرى", "النائبُ المعروف", "فخُّ «آخرُ تسعة»",
  ]) {
    assert.ok(labels.has(must), `صنفٌ سقطَ من الجدول: ${must}`);
  }
});

check("(٢) الجهتانِ تُجيبانِ الجوابَ نفسَه — المرآةُ حقيقيّةٌ لا دعوى", () => {
  for (const [label, input, want] of cases) {
    assert.strictEqual(phone.saudiMobile(input), want,
        `${label}: «${input}»`);
  }
});

check("(٣) الدوليّةُ مُشتقَّةٌ من المحلّيّةِ لا مكتوبةٌ ثانيةً", () => {
  for (const [label, input, want] of cases) {
    const e164 = phone.saudiE164(input);
    if (want === null) {
      assert.strictEqual(e164, null, `${label}: مرفوضٌ محلّيّاً ومقبولٌ دوليّاً`);
    } else {
      assert.strictEqual(e164, "+966" + want.slice(1), `${label}`);
      assert.ok(/^\+9665\d{8}$/.test(e164), `${label}: ليست E.164 ⇒ ${e164}`);
    }
  }
});

check("(٤) الغيابُ لا يَرمي", () => {
  assert.strictEqual(phone.saudiMobile(null), null);
  assert.strictEqual(phone.saudiMobile(undefined), null);
  assert.strictEqual(phone.saudiE164(null), null);
  // ورقمٌ لا نصٌّ: الحِملُ يَأتي من `request.data` فقد يكونُ أيَّ نوع.
  assert.strictEqual(phone.saudiMobile(501234567), "0501234567");
});

check("(٥) الوحدةُ نقيّةٌ — لا `getFirestore()` ولا `initializeApp()`", () => {
  const src = fs.readFileSync(path.join(__dirname, "../phone.js"), "utf8");
  // **الحارسُ يَسقطُ على توثيقِه**: ترويسةُ الوحدةِ تَذكرُ الثلاثةَ لتُعلِنَ
  // القاعدةَ، فأوّلُ صياغةٍ سقطت عليها. فالمسحُ على المُجرَّدِ من
  // التعليقات، ومضادّةٌ تُثبِتُ أنّ الأسماءَ ما زالت في الخامِّ — فلا
  // يُجوَّفُ الفحصُ بحذفِ الترويسة.
  const code = src.split("\n")
      .filter((l) => {
        const t = l.trim();
        return !t.startsWith("//") && !t.startsWith("*") &&
               !t.startsWith("/*");
      })
      .join("\n");
  for (const banned of ["getFirestore(", "getApp(", "initializeApp("]) {
    assert.ok(!code.includes(banned), `الوحدةُ تُنادي ${banned}`);
    assert.ok(src.includes(banned),
        `زالَ ذكرُ ${banned} من الترويسةِ — فالتجريدُ أعلاه بلا موضوع`);
  }
});

check("(٦) `index.js` يُطبِّعُ **قبلَ** بادئةِ `+966`", () => {
  const idx = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  assert.ok(idx.includes("require(\"./phone\")"),
      "الوحدةُ غيرُ مُستورَدة");
  const at = idx.indexOf("phoneLib.saudiE164(customerPhone)");
  assert.ok(at > 0, "التطبيعُ زالَ من مسارِ تمارا");
  const prefix = idx.indexOf("`+966${customerPhone}`");
  assert.ok(prefix > at,
      "البادئةُ تَسبقُ التطبيعَ — فالتطبيعُ لا يَمنعُ شيئاً");
});

check("(٧) ولا بادئةَ `+966` مكتوبةً بيدٍ خارجَ ذلك الموضع", () => {
  // نسخةٌ ثانيةٌ من «أَلحِقْ 966 بما وصلَ» هي العطلُ بعينِه.
  const idx = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
  const code = idx.split("\n")
      .filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*"))
      .join("\n");
  const hits = code.match(/\+966\$\{/g) || [];
  assert.strictEqual(hits.length, 1,
      `بادئةُ +966 في ${hits.length} موضعاً — الثانيةُ تَتخطّى التطبيع`);
});

console.log(`\n${fail === 0 ? "OK" : "NOT OK"} — ${pass} passed, ${fail} failed`);
if (fail > 0) process.exitCode = 1;
