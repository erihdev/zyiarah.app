"use strict";

// عميل HTTP لبوابتي التقسيط — تمارا (الحيّة) وتابي (المرتجع وحده).
// بلا Firestore وبلا firebase-functions: نقلٌ خالص، كـmoyasar_api.js.
// (`node test/tamara_api.test.js` ضمن npm test.)
//
// ═══ لماذا استُخرج ═══
//
// كان النقل مكتوباً ثلاث مرّات لنقطتين، وترويسة التوثيق **تسع** مرّات:
//
//   GET  /merchants/orders/reference-id/{id}   ×٣  (مكنسة الطلبات، مكنسة العقود، المرتجع)
//   POST /orders/{id}/authorise                ×٣  (الـwebhook، والمكنستان)
//   POST /checkout                             ×١
//   POST /orders/{id}/refunds                  ×١
//   POST /api/v2/payments/{id}/refunds (تابي)  ×١
//
// **والنسخ الثلاث من كلٍّ تحلّل JSON عارياً** — `await r.json()` بلا حَرَس:
//
//   | الموضع                | عند !ok      | التحليل          |
//   |-----------------------|--------------|------------------|
//   | reference-id (طلبات)  | `continue`   | `r.json()` عارياً |
//   | reference-id (عقود)   | `continue`   | `r.json()` عارياً |
//   | reference-id (مرتجع)  | داخل try خاصّ | `r.json()` عارياً |
//
// فردٌّ غير JSON من وسيطٍ أمام تمارا يرمي استثناء تحليل: في المكنستين يُلتقط
// فيُتجاوَز المستند **بصمت** (طلبٌ موافَق عليه لا يُؤكَّد أبداً، ولا سطر يقول
// لماذا)، وفي المرتجع يُسجَّل «lookup» فيبدو أن تمارا لا تعرف الطلب. التحليل
// المتسامح هنا يُصلح الثلاثة معاً: الجسم الفاسد يُقرأ `{}` فيُقرأ `ok` وحده.
// **تغيُّر سلوكٍ متعمَّد إلى الأفضل** — نفس صنف عطل void/capture في moyasar_api.
//
// وكان `Authorization` يُكتب بكتابتين (مُقتبسة وغير مُقتبسة) في المواضع التسعة:
// دليلُ أنها كُتبت مستقلّةً مرّةً بعد مرّة.
//
// ═══ وما لا يُوحَّد ═══
//
// **عقدُ الخطأ عند المُنادي**، كما في moyasar_api: الوحدة لا ترمي على حالة
// HTTP بل تُعيد `{ok, httpStatus, ...}`. فالمكنسة تتجاوز، والـwebhook يُسجّل،
// والنداء من التطبيق يرمي `HttpsError` بعد تحرير المطالبة. ثلاثة عقود على نقلٍ
// واحد. وأخطاء الشبكة تصعد كما هي ليقرّر كلٌّ بنفسه.
//
// ═══ وتابي: المرتجع وحده ═══
//
// قرار المالك 2026-09-30: تابي محذوفة من الجذور كخيار دفع. والمُبقى عمداً هو
// `tabbyWebhook` و`tabbyRefundPayment` وحدهما، لأن طلبات مدفوعة بتابي قد تكون
// قائمة وفواتيرها ZATCA صادرة — فحذف الاسترجاع يترك عميلاً بلا طريق.
// (`test/no_tabby_test.dart` يحرس الاختيار والإقلاع والحزمة والمفتاح.)
// فهذه الوحدة تُصدّر لتابي **نقطةً واحدة: المرتجع**، ويحرس ذلك فحصُها.

const TAMARA_BASE = "https://api.tamara.co";
const TABBY_BASE = "https://api.tabby.ai";

/**
 * ترويسة التوثيق الحاملة.
 * @param {string} token
 * @return {string}
 */
function bearer(token) {
  return `Bearer ${token}`;
}

/**
 * تحليل متسامح: ردٌّ غير JSON يصير `{}` لا استثناءً.
 * @param {Response} r
 * @return {Promise<object>}
 */
async function _json(r) {
  return await r.json().catch(() => ({}));
}

/** ترويسات نداءٍ يحمل جسماً. */
const _jsonHeaders = (token) => ({
  "Authorization": bearer(token),
  "Content-Type": "application/json",
});

/**
 * إنشاء جلسة سدادٍ بالتقسيط. **الحِمل يُبنى عند المُنادي** — شكلُ الطلب
 * (البنود، العميل، العنوان) منطقُ عملٍ لا نقل.
 * @param {string} token
 * @param {object} payload جسم طلب الـcheckout كاملاً
 * @return {Promise<{ok: boolean, httpStatus: number, result: object}>}
 */
async function checkout(token, payload) {
  const r = await fetch(`${TAMARA_BASE}/checkout`, {
    method: "POST",
    headers: _jsonHeaders(token),
    body: JSON.stringify(payload),
  });
  return {ok: r.ok, httpStatus: r.status, result: await _json(r)};
}

/**
 * استحضار طلب تمارا بمرجعنا (معرّف مستندنا).
 *
 * يُعيد `order` مباشرةً للراحة: المُنادون يقرأون `.status` و`.order_id` منه.
 * @param {string} token
 * @param {string} referenceId معرّف مستند الطلب/العقد عندنا
 * @return {Promise<{ok: boolean, httpStatus: number, order: object}>}
 */
async function getOrderByReference(token, referenceId) {
  const r = await fetch(
      `${TAMARA_BASE}/merchants/orders/reference-id/${referenceId}`,
      {headers: {"Authorization": bearer(token)}});
  return {ok: r.ok, httpStatus: r.status, order: await _json(r)};
}

/**
 * نقل الطلب من approved إلى authorised — **إلزامي**: بدونه يبقى معلّقاً ولا
 * يدخل دورة التسوية فلا يُقبض المال.
 * @param {string} token
 * @param {string} tamaraOrderId
 * @return {Promise<{ok: boolean, httpStatus: number, result: object}>}
 */
async function authorise(token, tamaraOrderId) {
  const r = await fetch(`${TAMARA_BASE}/orders/${tamaraOrderId}/authorise`,
      {method: "POST", headers: _jsonHeaders(token)});
  return {ok: r.ok, httpStatus: r.status, result: await _json(r)};
}

/**
 * استرداد من تمارا. المبلغ **بالريال** (لا بالهللات، بخلاف Moyasar).
 * @param {string} token
 * @param {string} tamaraOrderId
 * @param {number} amountSar
 * @param {string} comment سبب الاسترداد
 * @return {Promise<{ok: boolean, httpStatus: number, result: object}>}
 */
async function refund(token, tamaraOrderId, amountSar, comment) {
  const r = await fetch(`${TAMARA_BASE}/orders/${tamaraOrderId}/refunds`, {
    method: "POST",
    headers: _jsonHeaders(token),
    body: JSON.stringify({
      total_amount: {amount: amountSar, currency: "SAR"},
      comment,
    }),
  });
  return {ok: r.ok, httpStatus: r.status, result: await _json(r)};
}

/**
 * استرداد من تابي — **النقطة الوحيدة لتابي**، لطلباتٍ دُفعت قبل حذفها.
 *
 * المبلغ نصّاً بخانتين عشريّتين (تشترطه تابي هكذا، بخلاف تمارا التي تأخذه رقماً).
 * @param {string} secret
 * @param {string} paymentId
 * @param {number} amountSar
 * @param {string} reason
 * @return {Promise<{ok: boolean, httpStatus: number, result: object}>}
 */
async function tabbyRefund(secret, paymentId, amountSar, reason) {
  const r = await fetch(`${TABBY_BASE}/api/v2/payments/${paymentId}/refunds`, {
    method: "POST",
    headers: _jsonHeaders(secret),
    body: JSON.stringify({amount: amountSar.toFixed(2), reason}),
  });
  return {ok: r.ok, httpStatus: r.status, result: await _json(r)};
}

module.exports = {
  TAMARA_BASE, TABBY_BASE, bearer,
  checkout, getOrderByReference, authorise, refund,
  tabbyRefund,
};
