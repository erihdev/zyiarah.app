"use strict";

// عميل HTTP لبوابة Moyasar — **النقل في موضع واحد** (قابل للاختبار عبر
// `node test/moyasar_api.test.js`، على نسق pricing.js وcapacity.js وvat.js
// وdrivers.js). بلا Firestore وبلا firebase-functions: نقلٌ خالص.
//
// ═══ لماذا استُخرج ═══
//
// كان النقل مكتوباً **مرّتين** لنقطتين من أربع:
//
//   POST /refund   في `_moyasarRefundCore`  **و** إنلاين في moyasarRefundPayment
//   POST /void     في `_moyasarVoidCore`    **و** إنلاين في moyasarVoidPayment
//   POST /capture  إنلاين فقط (بلا نظير)
//   GET  /{id}     في `_moyasarGetPayment`
//
// وترويسةُ التوثيق تُبنى في **سبعة** مواضع.
//
// **والنسختان لم تكونا متكافئتين، وهذا بيت المسألة:**
//
//   | الموضع            | تحليل JSON                  | الردّ غير الـJSON          |
//   |-------------------|-----------------------------|---------------------------|
//   | _moyasarRefundCore| `.catch(() => ({}))`        | يُعاد `{ok:false,...}`    |
//   | refund إنلاين     | `try` حول fetch والتحليل    | يُحرّر المطالبة ثم يرمي    |
//   | void إنلاين       | `await response.json()` عارياً | **يرمي خطأً خامّاً**   |
//   | capture إنلاين    | `await response.json()` عارياً | **يرمي خطأً خامّاً**   |
//
// فردٌّ غير JSON من وسيطٍ أو بوّابةٍ أمام Moyasar كان يُفقد الإلغاء والتحصيل
// رسالتَهما العربية المقصودة ويُظهر للعميل عطلاً عامّاً. والتحليل المتسامح هنا
// يُصلح ذلك: `result` يصير `{}` و`ok` false، فترمي الدالّة المُصدَّرة رسالتها
// الاحتياطية كما قُصد. **وهذا تغيُّر سلوكٍ متعمَّد إلى الأفضل، لا نقلٌ محايد.**
//
// ═══ وما لم يُوحَّد بقصد ═══
//
// **عقدُ الخطأ يبقى عند المُنادي.** الدوالّ المُصدَّرة (onCall) يجب أن ترمي
// `HttpsError` كي يرى العميل رسالةً، والمسارات الآليّة (المكنسة، الاسترداد
// التلقائي) يجب أن تُعيد حالةً كي تقرّر بنفسها. فالوحدة **لا ترمي أبداً** على
// حالة HTTP: تُعيد `{ok, httpStatus, status, result}` ويبنى العقد فوقها.
// (أخطاء الشبكة تصعد كما هي — إلّا في `getPayment`، انظر تعليقها.)

const BASE = "https://api.moyasar.com/v1/payments";

/**
 * ترويسة التوثيق الأساسية: المفتاح السرّي كاسم مستخدم بلا كلمة مرور.
 * @param {string} secret مفتاح Moyasar السرّي
 * @return {string}
 */
function authHeader(secret) {
  return `Basic ${Buffer.from(secret + ":").toString("base64")}`;
}

/**
 * تحليل متسامح: ردٌّ غير JSON يصير `{}` لا استثناءً.
 * @param {Response} r
 * @return {Promise<object>}
 */
async function _json(r) {
  return await r.json().catch(() => ({}));
}

/**
 * نداء POST على عملية دفع. `amountHalalas` اختياري — بغيابه تُرسَل العملية
 * كاملةً بلا جسم (وهكذا تفرّق Moyasar بين الجزئي والكامل).
 * @param {string} secret
 * @param {string} paymentId
 * @param {string} action refund | void | capture
 * @param {number|undefined} amountHalalas
 * @return {Promise<{ok: boolean, httpStatus: number, status: *, result: object}>}
 */
async function _post(secret, paymentId, action, amountHalalas) {
  const body = amountHalalas ? JSON.stringify({amount: amountHalalas}) : undefined;
  const r = await fetch(`${BASE}/${paymentId}/${action}`, {
    method: "POST",
    headers: {
      "Authorization": authHeader(secret),
      ...(body ? {"Content-Type": "application/json"} : {}),
    },
    ...(body ? {body} : {}),
  });
  const result = await _json(r);
  return {ok: r.ok, httpStatus: r.status, status: result && result.status, result};
}

/**
 * الحالة الحيّة لعملية دفع.
 *
 * **تبتلع أخطاء الشبكة وحدها** من بين دوالّ هذه الوحدة، وذلك مقصود: كل
 * مُناديها يستعملها لمصالحة الحالة **قبل** قرار إلغاء أو استرداد، وتعذُّر
 * السؤال ليس سبباً لإجهاض العملية — يُقرأ كـ«لا أعرف» فيُسلك المسار المحافظ.
 * @param {string} secret
 * @param {string} paymentId
 * @return {Promise<{ok: boolean, status: *, raw?: object, error?: string}>}
 */
async function getPayment(secret, paymentId) {
  try {
    const r = await fetch(`${BASE}/${paymentId}`, {
      method: "GET", headers: {"Authorization": authHeader(secret)},
    });
    const j = await _json(r);
    return {ok: r.ok, status: j && j.status, raw: j};
  } catch (e) {
    return {ok: false, status: null, error: e.message};
  }
}

/**
 * استرداد — جزئيّ بـ[amountHalalas] أو كامل بغيابه.
 * @param {string} secret
 * @param {string} paymentId
 * @param {number} [amountHalalas]
 * @return {Promise<{ok: boolean, httpStatus: number, status: *, result: object}>}
 */
async function refund(secret, paymentId, amountHalalas) {
  return _post(secret, paymentId, "refund", amountHalalas);
}

/**
 * إلغاء عملية غير مقبوضة. (`void` كلمة محجوزة في JS، فالاسم `voidPayment`.)
 * @param {string} secret
 * @param {string} paymentId
 * @return {Promise<{ok: boolean, httpStatus: number, status: *, result: object}>}
 */
async function voidPayment(secret, paymentId) {
  return _post(secret, paymentId, "void", undefined);
}

/**
 * تحصيل مبلغٍ محجوز — جزئيّ بـ[amountHalalas] أو كامل بغيابه.
 * @param {string} secret
 * @param {string} paymentId
 * @param {number} [amountHalalas]
 * @return {Promise<{ok: boolean, httpStatus: number, status: *, result: object}>}
 */
async function capture(secret, paymentId, amountHalalas) {
  return _post(secret, paymentId, "capture", amountHalalas);
}

/**
 * آخر [per] عملية دفع — للمصالحة الدوريّة (reconcileOrphanPayments).
 *
 * لا تبتلع أخطاء الشبكة: المصالحة مهمّة مجدولة، وسقوطها أصدق من تقريرٍ يقول
 * «لا شيء لاستعادته» وهو لم يسأل.
 * @param {string} secret
 * @param {number} [per] عدد العمليات (افتراضي 25)
 * @return {Promise<{ok: boolean, httpStatus: number, payments: Array<object>, result: object}>}
 */
async function listPayments(secret, per = 25) {
  const r = await fetch(`${BASE}?per=${per}`, {
    method: "GET", headers: {"Authorization": authHeader(secret)},
  });
  const result = await _json(r);
  return {
    ok: r.ok, httpStatus: r.status,
    payments: Array.isArray(result.payments) ? result.payments : [],
    result,
  };
}

module.exports = {
  BASE, authHeader, getPayment, listPayments, refund, voidPayment, capture,
};
