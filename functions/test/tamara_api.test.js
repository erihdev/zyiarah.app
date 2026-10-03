"use strict";

// عميل تمارا/تابي — تشغيل: node test/tamara_api.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// كان النقل مكتوباً ثلاث مرّات لنقطتين، والترويسة تسع مرّات:
//
//   GET  /merchants/orders/reference-id/{id}  ×٣  (مكنسة الطلبات، مكنسة العقود، المرتجع)
//   POST /orders/{id}/authorise               ×٣  (الـwebhook، والمكنستان)
//
// **والثلاث من كلٍّ تحلّل JSON عارياً** — `await r.json()` بلا حَرَس. وأثرُ ذلك
// يختلف بالموضع، وأسوأه الصامت:
//
//   في المكنستين: الاستثناء يُلتقط فيُتجاوَز المستند **بصمت** — طلبٌ وافقت عليه
//                 تمارا لا يُؤكَّد أبداً، ولا سطر في أي سجلّ يقول لماذا.
//   في المرتجع:   يُسجَّل «lookup» فيبدو أن تمارا لا تعرف الطلب أصلاً.
//
// والتحليل المتسامح في الوحدة يُصلح الثلاثة معاً. **تغيُّر سلوكٍ متعمَّد إلى
// الأفضل** — نفس صنف عطل void/capture في moyasar_api.
//
// وما لا يُوحَّد: عقدُ الخطأ. الوحدة لا ترمي على حالة HTTP — فالمكنسة تتجاوز،
// والـwebhook يُسجّل، والنداء من التطبيق يرمي بعد تحرير المطالبة. ثلاثة عقود.
//
// ولا شبكة هنا: `fetch` العالمي يُستبدَل بمسجِّل.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const tamara = require("../tamara_api");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 * @return {Promise<void>}
 */
async function t(name, fn) {
  await fn();
  console.log("  ok -", name);
  passed++;
}

/** يستبدل fetch بمسجِّل. */
function stubFetch({ok = true, status = 200, json = {}, throws = null} = {}) {
  const calls = [];
  const real = global.fetch;
  global.fetch = async (url, opts) => {
    calls.push({url, opts});
    if (throws) throw new Error(throws);
    return {
      ok, status,
      json: async () => {
        if (json === "__INVALID__") throw new Error("Unexpected token <");
        return json;
      },
      text: async () => JSON.stringify(json),
    };
  };
  return {calls, restore: () => { global.fetch = real; }};
}

/**
 * يزيل التعليقات — التعليقات هنا تشرح ما نُقل، ففحص الخام يسقط على شرحه هو.
 *
 * **ولا يُقطَع السطر عند أوّل `//`** كما في عرف الحُرّاس الأخرى: `https://`
 * يحمل `//`، فالقطع الساذج يمحو العنوان الذي نبحث عنه بعينه — فيصير الحارس
 * عاطلاً ويُقرأ نجاحه أماناً. (وقع ذلك هنا فعلاً، وكشفه فحصُ العضّ.)
 * فالسطرُ المحض تعليقاً يُحذف كاملاً، والتعليق الذيلي يُقطَع عند `//` التي لا
 * يسبقها `:` وحدها.
 * @param {string} file اسم الملف داخل functions/
 * @return {string} الشفرة بلا تعليقات
 */
function codeOf(file) {
  return fs.readFileSync(path.join(__dirname, "..", file), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .filter((l) => !/^\s*(\/\/|\*)/.test(l))
      .map((l) => l.replace(/(^|[^:])\/\/.*$/, "$1"))
      .join("\n");
}

(async () => {
  await t("ترويسة Bearer — كانت تُكتب بكتابتين في تسعة مواضع", () => {
    assert.strictEqual(tamara.bearer("tok_123"), "Bearer tok_123");
  });

  await t("getOrderByReference: GET بالمرجع، والطلب يصل مباشرةً", async () => {
    const s = stubFetch({json: {order_id: "tam_9", status: "approved"}});
    const r = await tamara.getOrderByReference("tok", "ORD-1");
    s.restore();
    assert.strictEqual(s.calls[0].url,
        "https://api.tamara.co/merchants/orders/reference-id/ORD-1");
    assert.strictEqual(s.calls[0].opts.headers.Authorization, "Bearer tok");
    assert.strictEqual(s.calls[0].opts.method, undefined, "GET افتراضاً");
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.order.status, "approved");
    assert.strictEqual(r.order.order_id, "tam_9", "المكنستان تقرآن order_id منه");
  });

  await t("**ردٌّ غير JSON لا يرمي** — وهذا ما كان يُسقط المستند بصمت", async () => {
    // كان في المكنستين `await r.json()` عارياً داخل try لكل مستند: جسمٌ فاسد
    // يرمي، فيُتجاوَز الطلب الموافَق عليه ولا يُؤكَّد أبداً بلا أي أثر.
    const s = stubFetch({ok: true, status: 200, json: "__INVALID__"});
    const r = await tamara.getOrderByReference("tok", "ORD-1");
    s.restore();
    assert.strictEqual(r.ok, true, "ok يبقى صحيحاً — المشكلة كانت في الجسم");
    assert.deepStrictEqual(r.order, {}, "الجسم الفاسد يُقرأ {} لا استثناءً");
    assert.strictEqual(r.order.status, undefined,
        "فيُقرأ كحالةٍ غير معروفة ويمضي المنطق، بدل أن يُجهَض");
  });

  await t("authorise: POST بلا جسم، على الطلب لا على المرجع", async () => {
    // إلزاميّ: approved→authorised، وبدونه لا يدخل الطلب دورة التسوية فلا يُقبض.
    const s = stubFetch({json: {status: "authorised"}});
    const r = await tamara.authorise("tok", "tam_9");
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.tamara.co/orders/tam_9/authorise");
    assert.strictEqual(s.calls[0].opts.method, "POST");
    assert.strictEqual(s.calls[0].opts.body, undefined);
    assert.strictEqual(s.calls[0].opts.headers["Content-Type"], "application/json");
    assert.strictEqual(r.ok, true);
  });

  await t("refund تمارا: المبلغ **بالريال** رقماً، مع العملة والتعليق", async () => {
    // بخلاف Moyasar التي تأخذ الهللات — خلطُهما يستردّ مئة ضعف أو واحداً من مئة.
    const s = stubFetch({json: {refund_id: "r1"}});
    await tamara.refund("tok", "tam_9", 230.5, "تعذّر التنفيذ");
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.tamara.co/orders/tam_9/refunds");
    assert.deepStrictEqual(JSON.parse(s.calls[0].opts.body), {
      total_amount: {amount: 230.5, currency: "SAR"},
      comment: "تعذّر التنفيذ",
    });
  });

  await t("refund تابي: المبلغ **نصّاً بخانتين** — تشترطه هكذا", async () => {
    const s = stubFetch({json: {id: "rf"}});
    await tamara.tabbyRefund("sec", "pay_7", 99.5, "سبب");
    s.restore();
    assert.strictEqual(s.calls[0].url,
        "https://api.tabby.ai/api/v2/payments/pay_7/refunds");
    assert.deepStrictEqual(JSON.parse(s.calls[0].opts.body),
        {amount: "99.50", reason: "سبب"});
    // 99.5 رقماً ≠ "99.50" نصّاً: تابي ترفض الأول.
    assert.strictEqual(typeof JSON.parse(s.calls[0].opts.body).amount, "string");
  });

  await t("checkout: الحِمل يمرّ كما بُني — شكل الطلب منطقُ عمل لا نقل", async () => {
    const s = stubFetch({json: {checkout_url: "https://pay/x"}});
    const payload = {order_reference_id: "ORD-1", instalments: 4};
    const r = await tamara.checkout("tok", payload);
    s.restore();
    assert.strictEqual(s.calls[0].url, "https://api.tamara.co/checkout");
    assert.deepStrictEqual(JSON.parse(s.calls[0].opts.body), payload);
    assert.strictEqual(r.result.checkout_url, "https://pay/x");
  });

  await t("فشل HTTP لا يرمي — الحالة تصل لتُترجَم رسالةً", async () => {
    // 401/403 ⇒ «تحقّق من الرمز»، و409 ⇒ «سبق استرداد هذه الدفعة». ولا تُعرف
    // هذه إلّا بوصول httpStatus إلى المُنادي.
    for (const code of [401, 403, 409, 500]) {
      const s = stubFetch({ok: false, status: code, json: {message: "nope"}});
      const r = await tamara.refund("tok", "t", 10, "r");
      s.restore();
      assert.strictEqual(r.ok, false);
      assert.strictEqual(r.httpStatus, code);
      assert.strictEqual(r.result.message, "nope");
    }
  });

  await t("خطأ الشبكة يصعد — المُنادي يُحرّر المطالبة قبل الرمي", async () => {
    // ابتلاعه هنا كان يُبقي الطلب محجوزاً (refund_claimed) بلا استرداد.
    for (const [fn, args] of [
      ["checkout", ["tok", {}]],
      ["getOrderByReference", ["tok", "x"]],
      ["authorise", ["tok", "x"]],
      ["refund", ["tok", "x", 1, "r"]],
      ["tabbyRefund", ["sec", "x", 1, "r"]],
    ]) {
      const s = stubFetch({throws: "ECONNRESET"});
      await assert.rejects(() => tamara[fn](...args), /ECONNRESET/, `${fn} يجب أن يصعد`);
      s.restore();
    }
  });

  await t("**تابي: المرتجع وحده** — قرار المالك لا يُوسّع من هنا", () => {
    // no_tabby_test.dart يحرس الاختيار والإقلاع والحزمة والمفتاح في lib/؛
    // وهذا يحرس **سطح الخادم**: لا نقطة تابي إلّا المرتجع. فإضافة checkout
    // أو capture لتابي تُعيدها بوابةَ دفعٍ من الباب الخلفي.
    // **الدوالّ** وحدها هي السطح؛ TABBY_BASE ثابتُ عنوانٍ لا عملية.
    const ops = Object.keys(tamara)
        .filter((k) => /tabby/i.test(k) && typeof tamara[k] === "function");
    assert.deepStrictEqual(ops, ["tabbyRefund"],
        "عمليةُ تابي يجب أن تبقى المرتجع وحده، فوُجد: " + ops.join(", "));
    // ونقطةُ تابي في الشفرة: `${TABBY_BASE}` يُستعمل مرّةً واحدة، ومسارها
    // المرتجع. (العنوان الحرفي يظهر في الثابت وحده، فالفحص على المسار.)
    const src = codeOf("tamara_api.js");
    const paths = (src.match(/\$\{TABBY_BASE\}[^`]*/g) || [])
        .map((u) => u.replace(/\$\{[^}]*\}/g, "{}"));
    assert.deepStrictEqual(paths, ["{}/api/v2/payments/{}/refunds"],
        "مسار تابي الوحيد هو المرتجع، فوُجد: " + paths.join(" | "));
  });

  await t("**لا نداء تقسيط خارج هذه الوحدة** — الحارس الذي يمنع عودة التكرار", () => {
    // بلا حدٍّ للنقل يُضاف نداءٌ عاشرٌ إنلاين في أوّل ميزةٍ قادمة — كما حدث تسع
    // مرّات قبله — ولا يسقط شيء. والتعليقات تُزال أوّلاً: تعليقان في index.js
    // يذكران العنوانين ليشرحا أي سرٍّ تستعمل الدالّة، وهما عرف المستودع.
    // ولماذا يُزال التعليق هنا ولا يُزال في حارس moyasar_api؟ لأن index.js
    // يحمل تعليقين يسمّيان عنواني تمارا وتابي ليشرحا أي سرٍّ تستعمل كل دالّة،
    // ولا يحمل تعليقاً يسمّي عنوان Moyasar. فذاك يفحص الخام (أصرم، ولا سلبيّة
    // كاذبة فيه)، وهذا يُزيل التعليق بالضرورة. لا تُوحَّد إحداهما بالأخرى.
    const root = path.join(__dirname, "..");
    const offenders = [];
    for (const f of fs.readdirSync(root).filter((x) => x.endsWith(".js"))) {
      if (f === "tamara_api.js") continue;
      const src = codeOf(f);
      if (/api\.tamara\.co|api\.tabby\.ai/.test(src)) {
        offenders.push(`${f}: عنوان بوابة تقسيط مباشر`);
      }
      if (/["'`]Bearer \$\{/.test(src) || /Authorization.{0,4}`Bearer /.test(src)) {
        offenders.push(`${f}: بناء ترويسة Bearer يدويّاً`);
      }
    }
    assert.deepStrictEqual(
        offenders, [],
        "نداءٌ مباشر لبوابة تقسيط خارج tamara_api.js — استعمل الوحدة:\n" +
        offenders.map((o) => "  - " + o).join("\n"));
  });

  console.log(`\ntamara_api tests: ${passed} passed`);
})();
