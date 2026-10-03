"use strict";

// عميل Moyasar — تشغيل: node test/moyasar_api.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// كان النقل إلى بوابة الدفع متكرّراً في index.js: ترويسة التوثيق تُبنى في
// **أربعة** مواضع نصّية، و`GET /payments/{id}` مكتوب **ثلاث** مرّات،
// و`POST /refund` و`POST /void` **مرّتين** كلٌّ.
//
// **والنسخ لم تكن متكافئة، وهذا ما يستحقّ الفحص لا عدد الأسطر:**
//
//   refund الداخلي:   `.catch(() => ({}))`        ← ردٌّ غير JSON يُقرأ {}
//   refund المُصدَّر:  try حول fetch والتحليل      ← يُحرّر المطالبة ثم يرمي
//   void المُصدَّر:    `await response.json()` عارياً ← **يرمي خطأً خامّاً**
//   capture المُصدَّر: `await response.json()` عارياً ← **يرمي خطأً خامّاً**
//
// فردٌّ غير JSON من وسيطٍ أمام Moyasar كان يُفقد الإلغاء والتحصيل رسالتهما
// العربية ويُظهر للعميل عطلاً عامّاً. والتحليل المتسامح هنا يُصلحه.
//
// **وما لم يُوحَّد بقصد:** عقدُ الخطأ. الوحدة **لا ترمي على حالة HTTP** بل
// تُعيد {ok, httpStatus, status, result} — فالدالّة المُصدَّرة ترمي HttpsError
// ليرى العميل رسالة، والمسار الآليّ يقرأ الحالة ويقرّر. عقدان على نقلٍ واحد.
//
// ولا شبكة في هذه الفحوص: `fetch` العالمي يُستبدَل بمسجِّلٍ يُعيد ما نُحدّده،
// فنفحص العنوان والطريقة والترويسة والجسم — لا سلوك Moyasar.
const assert = require("assert");
const moyasar = require("../moyasar_api");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص (قد يكون async)
 * @return {Promise<void>}
 */
async function t(name, fn) {
  await fn();
  console.log("  ok -", name);
  passed++;
}

/** يستبدل fetch بمسجِّل، ويُعيد سجلّ النداءات ودالّة الإرجاع. */
function stubFetch({ok = true, status = 200, json = {}, throws = null} = {}) {
  const calls = [];
  const real = global.fetch;
  global.fetch = async (url, opts) => {
    calls.push({url, opts});
    if (throws) throw new Error(throws);
    return {
      ok, status,
      json: async () => {
        if (json === "__INVALID__") throw new Error("Unexpected token < in JSON");
        return json;
      },
      text: async () => JSON.stringify(json),
    };
  };
  return {calls, restore: () => { global.fetch = real; }};
}

(async () => {
  await t("ترويسة التوثيق: المفتاح اسمَ مستخدم بلا كلمة مرور", () => {
    // Basic base64("sk:") — النقطتان لازمتان، وحذفهما يُفشل كل نداء بصمت.
    assert.strictEqual(moyasar.authHeader("sk_test"),
        "Basic " + Buffer.from("sk_test:").toString("base64"));
    assert.ok(moyasar.authHeader("x").endsWith("="), "base64 صالح");
    assert.strictEqual(Buffer.from(moyasar.authHeader("abc").slice(6), "base64").toString(),
        "abc:", "فكُّ الترميز يُعيد المفتاح والنقطتين");
  });

  await t("getPayment: GET على العنوان الصحيح بترويسة التوثيق", async () => {
    const s = stubFetch({json: {id: "p1", status: "paid", amount: 11500}});
    const r = await moyasar.getPayment("sk", "p1");
    s.restore();
    assert.strictEqual(s.calls.length, 1);
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments/p1");
    assert.strictEqual(s.calls[0].opts.method, "GET");
    assert.strictEqual(s.calls[0].opts.headers.Authorization, moyasar.authHeader("sk"));
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.status, "paid");
    assert.strictEqual(r.raw.amount, 11500, "الجسم الكامل يصل — verifyMoyasarPayment يحتاج metadata");
  });

  await t("getPayment وحدها تبتلع خطأ الشبكة — وذلك مقصود", async () => {
    // كل مُناديها يسألها **قبل** قرار إلغاء أو استرداد؛ وتعذُّر السؤال ليس
    // سبباً لإجهاض العملية، بل «لا أعرف» فيُسلك المسار المحافظ.
    const s = stubFetch({throws: "ECONNRESET"});
    const r = await moyasar.getPayment("sk", "p1");
    s.restore();
    assert.strictEqual(r.ok, false);
    assert.strictEqual(r.status, null);
    assert.match(r.error, /ECONNRESET/);
  });

  await t("refund كامل: بلا جسم وبلا Content-Type", async () => {
    // Moyasar تفرّق بين الجزئي والكامل بوجود الجسم — فإرسال جسمٍ فارغ أو
    // {amount: 0} يعني استرداداً جزئيّاً بصفر، لا استرداداً كاملاً.
    const s = stubFetch({json: {status: "refunded"}});
    const r = await moyasar.refund("sk", "p9", undefined);
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments/p9/refund");
    assert.strictEqual(s.calls[0].opts.method, "POST");
    assert.strictEqual(s.calls[0].opts.body, undefined, "لا جسم في الاسترداد الكامل");
    assert.strictEqual(s.calls[0].opts.headers["Content-Type"], undefined);
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.status, "refunded");
  });

  await t("refund جزئي: جسم بالمبلغ بالهللات وContent-Type", async () => {
    const s = stubFetch({json: {status: "refunded"}});
    await moyasar.refund("sk", "p9", 5000);
    s.restore();
    assert.strictEqual(s.calls[0].opts.body, JSON.stringify({amount: 5000}));
    assert.strictEqual(s.calls[0].opts.headers["Content-Type"], "application/json");
  });

  await t("voidPayment وcapture على نقطتيهما", async () => {
    let s = stubFetch({json: {status: "voided"}});
    const v = await moyasar.voidPayment("sk", "p3");
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments/p3/void");
    assert.strictEqual(s.calls[0].opts.body, undefined, "الإلغاء لا يحمل مبلغاً أبداً");
    assert.strictEqual(v.status, "voided");

    s = stubFetch({json: {status: "captured"}});
    await moyasar.capture("sk", "p4", 2500);
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments/p4/capture");
    assert.strictEqual(s.calls[0].opts.body, JSON.stringify({amount: 2500}));
  });

  await t("**ردٌّ غير JSON لا يرمي** — وهذا ما كان يكسر الإلغاء والتحصيل", async () => {
    // كان `await response.json()` عارياً في void وcapture: صفحةُ خطأ HTML من
    // وسيطٍ ترمي استثناء تحليلٍ خامّاً، فيضيع `result.message ?? "فشل ..."`.
    for (const op of ["voidPayment", "capture"]) {
      const s = stubFetch({ok: false, status: 502, json: "__INVALID__"});
      const r = await moyasar[op]("sk", "p1");
      s.restore();
      assert.strictEqual(r.ok, false, `${op}: ok=false`);
      assert.strictEqual(r.httpStatus, 502, `${op}: الحالة تصل للتسجيل`);
      assert.deepStrictEqual(r.result, {}, `${op}: الجسم الفاسد يُقرأ {} لا استثناءً`);
      assert.strictEqual(r.result.message, undefined,
          `${op}: فيسقط المُنادي إلى رسالته العربية الاحتياطية`);
    }
  });

  await t("فشل HTTP لا يرمي — العقد عند المُنادي لا في الوحدة", async () => {
    const s = stubFetch({ok: false, status: 422, json: {message: "amount too large"}});
    const r = await moyasar.refund("sk", "p1", 999999);
    s.restore();
    assert.strictEqual(r.ok, false);
    assert.strictEqual(r.httpStatus, 422);
    assert.strictEqual(r.result.message, "amount too large",
        "رسالة البوابة تصل كي يرميها onCall للعميل");
  });

  await t("خطأ الشبكة يصعد من refund/void/capture (بخلاف getPayment)", async () => {
    // الدالّة المُصدَّرة تلفّه بـtry كي **تحرّر المطالبة** قبل الرمي؛ فابتلاعه
    // هنا كان يُبقي الطلب محجوزاً بلا استرداد.
    for (const op of ["refund", "voidPayment", "capture"]) {
      const s = stubFetch({throws: "ETIMEDOUT"});
      await assert.rejects(() => moyasar[op]("sk", "p1"), /ETIMEDOUT/, `${op} يجب أن يصعد`);
      s.restore();
    }
  });

  await t("listPayments: العدد في العنوان والقائمة مضمونة مصفوفةً", async () => {
    let s = stubFetch({json: {payments: [{id: "a"}, {id: "b"}]}});
    const r = await moyasar.listPayments("sk", 25);
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments?per=25");
    assert.strictEqual(r.payments.length, 2);
    assert.strictEqual(r.result.payments.length, 2, "الجسم الخامّ يبقى — المصالحة تقرؤه");

    // غياب payments أو كونها غير مصفوفة لا يُسقط حلقة المصالحة.
    s = stubFetch({json: {}});
    const empty = await moyasar.listPayments("sk");
    s.restore();
    assert.deepStrictEqual(empty.payments, []);
    assert.strictEqual(s.calls[0].url, "https://api.moyasar.com/v1/payments?per=25",
        "الافتراضي 25");
  });

  await t("listPayments لا تبتلع خطأ الشبكة — تقريرُ «لا شيء» كذبٌ", async () => {
    const s = stubFetch({throws: "EAI_AGAIN"});
    await assert.rejects(() => moyasar.listPayments("sk"), /EAI_AGAIN/);
    s.restore();
  });

  await t("**لا نداء Moyasar خارج هذه الوحدة** — الحارس الذي يمنع عودة التكرار", () => {
    // هذا هو الفحص الذي يستحقّ الاستخراج كلّه: بلا حدٍّ واحد للنقل، يُضاف نداءٌ
    // سابعٌ إنلاين في أوّل ميزةٍ قادمة — كما حدث أربع مرّات قبله — ولا يسقط شيء.
    const fs = require("fs");
    const path = require("path");
    const root = path.join(__dirname, "..");
    const offenders = [];
    for (const f of fs.readdirSync(root).filter((x) => x.endsWith(".js"))) {
      if (f === "moyasar_api.js") continue;
      const src = fs.readFileSync(path.join(root, f), "utf8");
      if (/api\.moyasar\.com/.test(src)) offenders.push(`${f}: عنوان Moyasar مباشر`);
      // ترويسة التوثيق كانت تُبنى نصّياً في أربعة مواضع.
      if (/Buffer\.from\(\s*secret\s*\+/.test(src)) {
        offenders.push(`${f}: بناء ترويسة التوثيق يدويّاً`);
      }
    }
    assert.deepStrictEqual(
        offenders, [],
        "نداءٌ مباشر لبوابة الدفع خارج moyasar_api.js — استعمل الوحدة:\n" +
        offenders.map((o) => "  - " + o).join("\n"));
  });

  console.log(`\nmoyasar_api tests: ${passed} passed`);
})();
