/**
 * محرّك الاسترداد الآليّ (refund engine)
 * ────────────────────────────────────────────────────────────────────────
 * شأنٌ واحد: **طلبٌ مدفوع تعذّر تنفيذه — أو ثبت التلاعب بسعره — يُلغى تفويضه أو
 * يُستردّ مبلغه مرّةً واحدة، ويُبلَّغ العميل؛ وإن تعذّر ذلك تُبلَّغ الإدارة.**
 *
 * **هذه أوّل وحدة تلمس Firestore** — وهي تكسر عرف «الوحدات النقية» عن قصد (قرار
 * المالك). لكنّ كسر العرف ليس كسرَ قابلية الاختبار، وهي كانت سببَه: الوحدة
 * **تستقبل `db` وسيطاً ولا تستوردها**، وكذلك `queuePush` و(اختياراً) عميلَ
 * البوابة. فتُختبر بـ`db` مزيّفٍ بلا محاكٍ ولا شبكة، كما تُختبر النقية تماماً.
 * القاعدة الجديدة: **لا `getFirestore()` ولا `getApp()` داخل وحدة** — المرجع
 * يأتي وسيطاً دائماً، وإلّا رجعنا إلى وحدةٍ لا تُختبر إلّا بمحاكي Firestore.
 *
 * `FieldValue` مستوردةٌ مباشرةً: طوابعها (`delete`/`serverTimestamp`/`increment`)
 * قيمٌ حارسة تُبنى بلا تهيئة تطبيق، فلا تُخِلّ بما سبق.
 */

const {FieldValue} = require("firebase-admin/firestore");
const moyasar = require("./moyasar_api");
const amounts = require("./amounts");

/** أسبابُ فشل الاسترداد الآليّ ← نصٌّ عربيّ يقرأه الإداريّ في التنبيه. */
const FAILURE_NOTES = {
  no_amount: "لا مبلغ قابل للاسترداد أو لا عميل مرتبط بالطلب",
  wallet_error: "تعذّرت إعادة الرصيد إلى محفظة العميل",
  no_payment_id: "دفعٌ بلا معرّف بوابة — لا استرداد آليّ ممكن",
  gateway_error: "رفضت البوابة الاسترداد/الإلغاء",
};

/** الأسباب التي **تستوجب** تصعيداً إداريّاً (المال محصَّل والخدمة لم تُقدَّم). */
const ESCALATED_REASONS = Object.keys(FAILURE_NOTES);

/**
 * حقولُ إعادة فتح طلبٍ ألغاه **النظام** لعدم الدفع ثم وصل دفعُه متأخّراً.
 * تُدمَج في كتابة قلب `is_paid` كي لا يبقى الطلب ملغيّاً ومدفوعاً في آن.
 * @param {object} data بيانات الطلب قبل الكتابة.
 * @return {object} حقولٌ تُدمَج (فارغة إن لم يكن الإلغاء نظاميّاً).
 */
function reopenFieldsIfSystemCancelled(data) {
  if (data && data.status === "cancelled" &&
      data.cancel_reason === "unpaid_expired") {
    return {
      status: "pending",
      cancel_reason: FieldValue.delete(),
      cancelled_by: FieldValue.delete(),
      cancelled_at: FieldValue.delete(),
      reopened_after_late_payment: true,
    };
  }
  return {};
}

/**
 * مصالحةُ الحالة الحيّة عند البوابة ثمّ القرار: **إلغاء تفويضٍ غير مقبوض**
 * (`void`) أم **استردادُ مقبوض** (`refund`). كان هذا القرار مكتوباً بيدٍ في
 * موضعين — مسار التلاعب ومسار تعذّر التنفيذ — بصياغتين مختلفتين لنفس المنطق.
 *
 * `getPayment` تبلع أخطاء الشبكة **بقصد**: «تعذّر السؤال» يجب أن يُقرأ «لا
 * أعرف»، فنسلك المسار المحافظ — غير مفوَّضٍ ⇒ نحاول `refund`؛ فإن رفضته البوابة
 * بقي المال مكانه وصار الأمر للمراجعة اليدويّة، ولم يُقلب الطلب خطأً.
 * @param {string} secret مفتاح Moyasar السرّي.
 * @param {string} paymentId معرّف الدفعة عند البوابة.
 * @param {object} [gateway] عميل البوابة (يُستبدَل في الاختبار).
 * @return {Promise<{ok: boolean, already: boolean, action: string,
 *   status: ?string}>} النتيجة: `already` تعني أنّ البوابة ردّت سلفاً.
 */
async function reconcileAndSettle(secret, paymentId, gateway = moyasar) {
  const live = await gateway.getPayment(secret, paymentId);
  if (live.ok && (live.status === "refunded" || live.status === "voided")) {
    return {ok: true, already: true, action: live.status, status: live.status};
  }
  const authorized = live.ok &&
    (live.status === "authorized" || live.status === "initiated");
  const res = authorized ? await gateway.voidPayment(secret, paymentId) :
    await gateway.refund(secret, paymentId, undefined); // استرداد كامل
  return {ok: res.ok, already: false,
    action: authorized ? "voided" : "refunded", status: res.status};
}

/**
 * (#1 Tier B) استرداد/إلغاء آليّ لطلبٍ ثبت دفعُه الناقص الصارخ. idempotent عبر
 * مطالبة `tamper_handled` ذرّياً، ثم مصالحة الحالة الحيّة، وحجب إعادة الفتح.
 * لا يُنفَّذ إلّا خلف `ENFORCE_PRICE_TIER_B`.
 * @param {object} db مرجع Firestore (وسيطاً — لا تستورده الوحدة).
 * @param {string} secret مفتاح Moyasar السرّي.
 * @param {string} paymentId معرّف الدفعة.
 * @param {object} orderRef مرجع مستند الطلب.
 * @param {{gateway?: object}} [deps] اعتماديّات قابلة للاستبدال في الاختبار.
 * @return {Promise<{done: boolean, action: string}>} النتيجة.
 */
async function voidOrRefundTampered(db, secret, paymentId, orderRef, deps = {}) {
  const gateway = deps.gateway || moyasar;
  const claimed = await db.runTransaction(async (tx) => {
    const s = await tx.get(orderRef);
    const d = s.data() || {};
    if (d.tamper_handled === true || d.payment_status === "voided" ||
        d.payment_status === "refunded") return false;
    tx.update(orderRef, {tamper_handled: true, payment_status: "refunding"});
    return true;
  });
  if (!claimed) return {done: true, action: "already"};
  const settled = await reconcileAndSettle(secret, paymentId, gateway);
  if (settled.already) {
    await orderRef.update({payment_status: settled.action, is_paid: false,
      tamper_blocked: true, refund_credited: true}).catch(() => {});
    return {done: true, action: settled.action};
  }
  if (!settled.ok) {
    // لم يُعَد المال: **لا نقلب is_paid ولا نرمي** — نترك الطلب للمراجعة اليدوية.
    await orderRef.update({payment_status: "payment_review",
      tamper_gateway_failed: true}).catch(() => {});
    return {done: false, action: "gateway_error"};
  }
  await orderRef.update({
    payment_status: settled.action,
    moyasar_status: settled.status, is_paid: false,
    tamper_blocked: true, refund_credited: true,
    [settled.action === "voided" ? "voided_at" : "refunded_at"]:
      FieldValue.serverTimestamp(),
  }).catch(() => {});
  return {done: true, action: settled.action};
}

/**
 * إشعارٌ موحّد عند **نجاح** الاسترداد الآليّ: العميل + بثّ إداريّ.
 * @param {Function} queuePush طابور الإشعارات (وسيطاً — لا تستورده الوحدة).
 * @param {?string} clientId معرّف العميل.
 * @param {string} code رقم الطلب المعروض.
 * @param {string} orderId معرّف مستند الطلب.
 * @param {number} amount المبلغ بالريال.
 * @param {string} dest وجهة الإعادة (محفظتكِ/بطاقتكِ).
 * @param {string} adminTag وسمٌ للإداريّ (محفظة/استرداد/إلغاء تفويض).
 * @return {Promise<void>} لا شيء.
 */
async function notifyAutoRefund(
    queuePush, clientId, code, orderId, amount, dest, adminTag) {
  if (typeof queuePush !== "function") return;
  if (clientId) {
    await queuePush(clientId, "تعذّر تنفيذ طلبكِ — أُعيد المبلغ 💳",
        `تعذّر إيجاد فريق لطلبكِ #${code} فأُعيد ${amount} ر.س إلى ${dest}.`,
        "order_refunded", {orderId}).catch(() => {});
  }
  await queuePush("ADMIN_BROADCAST", "استُرد طلب مدفوع تعذّر تنفيذه ↩️",
      `أُعيد الطلب #${code} (${adminTag}، ${amount} ر.س) — لا سائق حتى بعد فوات الموعد.`,
      "admin_order_alert", {orderId}).catch(() => {});
}

/**
 * تصعيدُ **فشل** الاسترداد الآليّ إلى الإدارة.
 *
 * هذا هو موضع العلّة التي كشفها التفكيك: المعالِج كان يرفع علَم
 * `stranded_alerted` في مساراته الفاشلة الأربعة **بلا أن يُرسل تنبيهاً قط**،
 * والمكنسة تتخطّى تنبيهها اعتماداً على أنّ «المعالج نبّه». والعلَم نفسه يرفعه
 * فرعُ الإنذار المبكّر («فات موعد البدء، والمحاولة مستمرة») قبل ذلك بساعات —
 * فحتى لو لم تتخطَّ المكنسة لتخطّته بالعلَم. فكان الطلب المدفوع الذي تعذّر
 * استردادُه **يُدفَن صامتاً**: المال محصَّل، ولا خدمة، ولا أحد يُخبَر، ولا
 * محاولة ثانية (`auto_refund_processed` لا يُحَلّ).
 * علَمٌ **مستقلّ** (`auto_refund_alerted`) كي لا يكتمه الإنذار المبكّر، ويظلّ
 * التنبيه واحداً لكلّ طلب.
 * @param {Function} queuePush طابور الإشعارات.
 * @param {string} orderId معرّف المستند.
 * @param {string} code رقم الطلب المعروض.
 * @param {number} amount المبلغ المحصَّل بالريال.
 * @param {string} reason سببُ الفشل (أحد `ESCALATED_REASONS`).
 * @return {Promise<void>} لا شيء.
 */
async function escalateFailedAutoRefund(
    queuePush, orderId, code, amount, reason) {
  if (typeof queuePush !== "function") return;
  await queuePush("ADMIN_BROADCAST", "تعذّر استرداد طلبٍ مدفوع — تدخّل يدوي 🚨",
      `الطلب #${code} (${amount} ر.س) فات موعده بلا سائق وتعذّر استردادُه آلياً ` +
      `(${FAILURE_NOTES[reason] || reason}). المبلغ ما يزال محصَّلاً — يلزم ` +
      `استرداد يدويّ من لوحة الطلبات.`,
      "admin_order_alert",
      {orderId, code, autoRefundFailed: true, reason},
      ["super_admin", "orders_manager", "accountant_admin"]).catch(() => {});
}

/**
 * يُثبّت فشلاً ويُصعّده مرّةً واحدة.
 * @param {Function} queuePush طابور الإشعارات.
 * @param {object} orderRef مرجع المستند.
 * @param {object} orderDoc لقطةُ الطلب (للمعرّف والرقم).
 * @param {number} amount المبلغ.
 * @param {string} reason السبب.
 * @param {object} [extra] حقولٌ إضافية تُكتب مع التثبيت.
 * @return {Promise<{handled: boolean, reason: string}>} نتيجةٌ للمكنسة.
 */
async function _failAndEscalate(
    queuePush, orderRef, orderDoc, amount, reason, extra) {
  const already = orderDoc.data().auto_refund_alerted === true;
  await orderRef.update({
    auto_refund_failed: true,
    stranded_alerted: true,
    auto_refund_alerted: true,
    auto_refund_failed_reason: reason,
    ...(extra || {}),
  }).catch(() => {});
  if (!already) {
    await escalateFailedAutoRefund(queuePush, orderDoc.id,
        orderDoc.data().code || orderDoc.id, amount, reason);
  }
  return {handled: false, reason};
}

/**
 * (#18) استرداد/إلغاء آليّ لطلبٍ مدفوع تعذّر تنفيذه (فات موعده بلا سائق).
 * idempotent: مطالبة ذرّية بعلَم `auto_refund_processed` + مؤشّر
 * `payment_status='refunding'` قبل أي نداء بوابة، ثم مصالحة الحالة الحيّة،
 * وإعادة قراءة `driver_id` في الكتابة النهائية كي لا نستردّ طلباً أُسنِد أثناء
 * العملية.
 * @param {object} db مرجع Firestore (وسيطاً — لا تستورده الوحدة).
 * @param {string} secret مفتاح Moyasar السرّي.
 * @param {object} orderDoc لقطةُ مستند الطلب.
 * @param {{queuePush: Function, gateway?: object}} deps اعتماديّات مُمرَّرة.
 * @return {Promise<{handled: boolean, reason?: string, action?: string}>} نتيجة.
 */
async function autoResolveUnfulfilledPaidOrder(db, secret, orderDoc, deps = {}) {
  const queuePush = deps.queuePush;
  const gateway = deps.gateway || moyasar;
  const orderRef = orderDoc.ref;
  const d0 = orderDoc.data();
  const method = d0.payment_method || "";
  // طرق لا تُسترَد آلياً: الاشتراك (مبلغ 0، مدفوع بالعقد)، وتمارا/تابي (لا API استرداد
  // خادمي هنا، وإلغاؤها قد يُطلق إيداعاً بينما الأقساط قائمة). تصعيدُها للمكنسة.
  if (method === "subscription") return {handled: false, reason: "subscription"};
  if (method === "tamara" || method === "tabby") return {handled: false, reason: "bnpl"};

  // (1) مطالبة ذرّية تمنع كرونَين متزامنَين من ضرب البوابة لنفس الطلب.
  const claimed = await db.runTransaction(async (tx) => {
    const s = await tx.get(orderRef);
    const d = s.data() || {};
    if (d.driver_id || d.status !== "pending" || d.is_paid !== true) return false;
    if (d.auto_refund_processed === true || d.refund_credited === true ||
        d.payment_status === "refunded" || d.payment_status === "voided") return false;
    tx.update(orderRef, {
      auto_refund_processed: true,
      payment_status: "refunding", // مؤشّر دائم قابل للمصالحة عند تعافي عطل
    });
    return true;
  });
  if (!claimed) return {handled: false, reason: "claimed_or_ineligible"};

  const clientId = d0.client_id || d0.userId || null;
  const code = d0.code || orderDoc.id;
  // نفس تدرّج المبلغ المستعمَل في مسار الاسترداد الإداري (store=total_amount، عقد=planPrice…).
  const refundAmount = amounts.refundAmount(d0);
  const hasGatewayPayment = !!d0.moyasar_payment_id;

  // مسار المحفظة: نُعيد للرصيد مباشرةً داخل معاملة واحدة (لا نعتمد على onOrderRewards
  // الذي يخرج مبكراً ما لم يُوسَم rewards_handled_by='server').
  if (method === "wallet") {
    if (!clientId || !(refundAmount > 0)) {
      return _failAndEscalate(queuePush, orderRef, orderDoc, refundAmount,
          "no_amount", {payment_status: "paid"});
    }
    const walletRef = db.collection("wallets").doc(clientId);
    const txRef = walletRef.collection("transactions").doc(`refund_${orderDoc.id}`);
    try {
      await db.runTransaction(async (t) => {
        const s = await t.get(orderRef);
        if (s.get("driver_id")) throw new Error("assigned_midway");
        t.set(walletRef, {
          balance: FieldValue.increment(refundAmount),
          last_updated: FieldValue.serverTimestamp(),
        }, {merge: true});
        t.create(txRef, {
          amount: refundAmount, points: 0, type: "refund",
          description: `استرداد طلبٍ تعذّر تنفيذه #${code}`,
          order_id: orderDoc.id,
          created_at: FieldValue.serverTimestamp(),
        });
        t.update(orderRef, {
          status: "cancelled", cancelled_by: "system",
          cancel_reason: "unfulfilled_no_driver",
          cancelled_at: FieldValue.serverTimestamp(),
          refund_credited: true, needs_refund: false,
          rewards_handled_by: "server", payment_status: "refunded", is_paid: false,
        });
      });
    } catch (e) {
      if (e.message === "assigned_midway") {
        // أُسنِد سائق أثناء العملية ولم يُمَسّ المال: نُحلّ المطالبة ونُعيد الحالة.
        await orderRef.update({auto_refund_processed: false,
          payment_status: "paid"}).catch(() => {});
        return {handled: false, reason: "assigned_midway"};
      }
      return _failAndEscalate(queuePush, orderRef, orderDoc, refundAmount,
          "wallet_error");
    }
    await notifyAutoRefund(queuePush, clientId, code, orderDoc.id, refundAmount,
        "محفظتكِ", "محفظة");
    return {handled: true, action: "wallet_refund"};
  }

  // بطاقة/دفع أصلي بلا معرّف بوابة: يتعذّر الاسترداد الآلي — تصعيد إداري.
  if (!hasGatewayPayment) {
    return _failAndEscalate(queuePush, orderRef, orderDoc, refundAmount,
        "no_payment_id", {payment_status: "paid"});
  }

  // مسار البطاقة/الدفع الأصلي: مصالحة الحالة الحيّة ثم void (غير مقبوض) أو refund كامل.
  const settled = await reconcileAndSettle(secret, d0.moyasar_payment_id, gateway);
  const action = settled.action;
  if (!settled.ok) {
    // لا نُعيد ضبط العلَم (قد يكون نجح ثم انقطع الاتصال) — نُثبّت الفشل وننبّه للمصالحة.
    return _failAndEscalate(queuePush, orderRef, orderDoc, refundAmount,
        "gateway_error");
  }
  try {
    await db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (s.get("driver_id")) throw new Error("assigned_midway");
      t.update(orderRef, {
        status: "cancelled", cancelled_by: "system",
        cancel_reason: "unfulfilled_no_driver",
        cancelled_at: FieldValue.serverTimestamp(),
        payment_status: action === "voided" ? "voided" : "refunded",
        moyasar_status: settled.status, refund_credited: true, needs_refund: false,
        rewards_handled_by: "server", is_paid: false,
        refunded_amount: refundAmount,
        [action === "voided" ? "voided_at" : "refunded_at"]:
          FieldValue.serverTimestamp(),
      });
    });
  } catch {
    // البوابة نجحت لكن أُسنِد سائق لحظتها (نادر جداً): المال أُعيد فعلاً فنُكمل الإلغاء
    // (لا نُبقي طلباً «مدفوعاً» بلا مال) ونُعلّم التعارض للمراجعة.
    await orderRef.update({
      status: "cancelled", cancelled_by: "system",
      cancel_reason: "unfulfilled_no_driver_refunded",
      payment_status: action === "voided" ? "voided" : "refunded",
      refund_credited: true, is_paid: false, refund_after_assign_conflict: true,
    }).catch(() => {});
  }
  await notifyAutoRefund(queuePush, clientId, code, orderDoc.id, refundAmount,
      "بطاقتكِ", action === "voided" ? "إلغاء تفويض" : "استرداد");
  return {handled: true, action};
}

module.exports = {
  FAILURE_NOTES,
  ESCALATED_REASONS,
  reopenFieldsIfSystemCancelled,
  reconcileAndSettle,
  voidOrRefundTampered,
  notifyAutoRefund,
  escalateFailedAutoRefund,
  autoResolveUnfulfilledPaidOrder,
};
