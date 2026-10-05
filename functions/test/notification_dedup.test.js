"use strict";
// حرّاس مصدريون: توحيد دفعة تأكيد الدفع + توجيه targetRoles + استرداد تمارا/تابي.
// تشغيل: node test/notification_dedup.test.js (ضمن npm test).
const assert = require("assert");
const fs = require("fs");
const path = require("path");

// كنمط codeOnly() في اختبارات فلاتر: نُسقط أسطر التعليقات قبل الفحص كي لا
// يُرضي الفحصَ ذكرٌ في تعليق توثيقي.
const fn = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8")
    .split("\n")
    .filter((l) => {
      const t = l.trimStart();
      return !t.startsWith("//") && !t.startsWith("*") && !t.startsWith("/*");
    })
    .join("\n");

/**
 * يقتطع جسم دالة/مُشغّل من أول ظهور الاسم حتى exports التالية.
 * @param {string} name اسم الدالة/التصدير.
 * @return {string} الجسم.
 */
function body(name) {
  const i = fn.indexOf(name);
  assert.ok(i >= 0, `${name} غير موجودة في index.js`);
  const j = fn.indexOf("\nexports.", i + name.length);
  return j > i ? fn.substring(i, j) : fn.substring(i);
}

let passed = 0;
/**
 * مُشغّل اختبار مصغّر بنمط pricing.test.js.
 * @param {string} name اسم الاختبار.
 * @param {Function} f جسم الاختبار.
 */
function t(name, f) {
  f();
  passed++;
  console.log("  ok -", name);
}

// ── (1) توحيد دفعة تأكيد الدفع ────────────────────────────────────────────────
t("مطالبة payment_push_sent ذرّية داخل معاملة", () => {
  const b = body("async function _claimPaymentPush");
  assert.ok(b.includes("runTransaction"));
  assert.ok(b.includes("payment_push_sent === true) return false"));
  assert.ok(b.includes("tx.update(ref, {payment_push_sent: true})"));
});

t("دفعة نجاح الدفع (verify/webhook/wallet) تشارك المطالبة", () => {
  const b = body("async function notifyClientPaymentResult");
  assert.ok(b.includes("if (success && !(await _claimPaymentPush(col, orderId)))"));
});

t("مُشغّل الحالة: scheduled/under_review تشاركان المطالبة", () => {
  const b = body("exports.sendNotificationOnOrderStatusChange");
  assert.ok(b.includes(
      "(afterData.status === \"scheduled\" || afterData.status === \"under_review\") &&"));
  assert.ok(b.includes("!(await _claimPaymentPush(\"orders\", orderId))"));
});

t("زيارات الاشتراك لا تدفع «تم تأكيد حجزكِ» لكل زيارة", () => {
  const b = body("exports.sendNotificationOnOrderStatusChange");
  const i = b.indexOf("=== \"scheduled\"");
  const seg = b.substring(i, b.indexOf("under_review", i));
  assert.ok(seg.includes("if (!afterData.contract_id)"),
      "فرع scheduled يجب أن يكتم زيارات العقود (الملخّص يعوّضها)");
});

t("إشعار التطبيق الذاتي «تم استلام طلبك» يشارك المطالبة في المعالج", () => {
  // المُعالِجُ صار دالّةً واحدةً مُشترَكةً بين تسجيلَين
  // (`notification_queue` الخادميُّ و`notification_triggers` للعميل) بعد أن
  // تبيّن أنّ الثقةَ كانت تُحسَب من `createdBy` — حقلٍ يَكتبه العميل. القرارُ
  // المحروسُ هنا (مطالبةُ دفعِ الدفع) لم يتغيّر، فنُعيد توجيهَ الحارسِ إلى
  // اسمِ المُعالِجِ لا إلى التسجيل — الذي صار سطرَين.
  const b = body("const _processNotifQueueDoc");
  assert.ok(b.includes("type === \"order_update\" && toUid && trigger.createdBy === toUid"));
  assert.ok(b.includes("pushSkipped: \"payment_push_dedup\""));
  assert.ok(b.includes("!paymentDedupSkip && trigger.pushSent !== true"));
});

t("توليد زيارات الاشتراك: ملخّص واحد للعميل لكل تشغيلة", () => {
  // نقتطع onCall وحدها (تنتهي عند _generateContractVisits المجاورة).
  const whole = body("exports.generateSubscriptionVisits");
  const b = whole.substring(0, whole.indexOf("_generateContractVisits"));
  assert.ok(b.includes("تم جدولة زيارات باقتكِ"));
  assert.ok(b.includes("contract_visits_scheduled"));
  // الملخّص خارج حلقة الزيارات (بعد آخر إسناد) — دفعة واحدة لا لكل زيارة.
  assert.ok(b.indexOf("contract_visits_scheduled") >
    b.lastIndexOf("_assignDriverScheduled"));
});

// ── (2) توجيه targetRoles فعلي ────────────────────────────────────────────────
t("استعلام role لا يعيد كل الموظّفين — السوبر فقط يُضمّ دائماً", () => {
  // نفس إعادةِ التوجيه: المُعالِجُ صار دالّةً مُشترَكةً بين تسجيلَي الطابورَين.
  const b = body("const _processNotifQueueDoc");
  assert.ok(b.includes("where(\"staff_role\", \"in\", targetRoles)"));
  assert.ok(b.includes(
      "if (sd.staff_role && sd.staff_role !== \"super_admin\" &&"));
  assert.ok(b.includes("!targetRoles.includes(sd.staff_role)) continue;"));
});

// ── (3) استرداد تمارا/تابي ────────────────────────────────────────────────────
t("tamaraRefundPayment: أدمن + مطالبة + بوابة تمارا + إشعار العميل", () => {
  const b = body("exports.tamaraRefundPayment");
  assert.ok(b.includes("await _assertAdmin(request)"));
  assert.ok(b.includes("secrets: [\"TAMARA_API_TOKEN\"]"));
  assert.ok(b.includes("await _claimRefund(existing)"));
  // كان الفحصان يطابقان عنوان تمارا وشكل المبلغ **نصّاً داخل هذه الدالّة**،
  // وكيلاً عن «تضرب البوّابة الصحيحة بالمبلغ الصحيح». ثم استُخرج النقل إلى
  // tamara_api ليشترك فيه تسعةُ مواضع (كانت الترويسة تُبنى يدويّاً تسع مرّات،
  // والمسار مكتوباً ثلاثاً) — فانتقل النصّ ولم يتغيّر القرار المحروس.
  //
  // فالوكيل يُوجَّه إلى نداء الوحدة، وهو **أقوى**: الاسم نفسه يحدّد البوّابة
  // (tamara.refund لا tabbyRefund)، وشكل الجسم والعنوان يثبّتهما
  // test/tamara_api.test.js حيث يُفحَصان بـfetch مُستبدَل لا بمطابقة نصّية.
  assert.ok(b.includes("await tamara.refund(token, tamaraOrderId, refundAmount, reason)"),
      "استرداد تمارا يجب أن يمرّ على tamara.refund بالمبلغ والسبب");
  assert.ok(b.includes("is_paid: false"));
  assert.ok(b.includes("refunded: true"));
  assert.ok(b.includes("تم استرداد مبلغك 💳"));
});

t("tabbyRefundPayment: أدمن + مطالبة + بوابة تابي + إشعار العميل", () => {
  const b = body("exports.tabbyRefundPayment");
  assert.ok(b.includes("await _assertAdmin(request)"));
  assert.ok(b.includes("secrets: [\"TABBY_WEBHOOK_SECRET\"]"));
  assert.ok(b.includes("await _claimRefund(existing)"));
  // نفس التوجيه؛ و`tabbyRefund` هي **نقطة تابي الوحيدة** في الوحدة (قرار
  // المالك: المرتجع وحده)، ويحرس ذلك فحصُها هناك.
  assert.ok(b.includes(
      "await tamara.tabbyRefund(secret, tabbyPaymentId, refundAmount, reason)"),
  "استرداد تابي يجب أن يمرّ على tamara.tabbyRefund");
  assert.ok(b.includes("existing.data.tabby_payment_id"));
  assert.ok(b.includes("is_paid: false"));
  assert.ok(b.includes("refunded: true"));
  assert.ok(b.includes("تم استرداد مبلغك 💳"));
});

t("منع الاسترداد المزدوج موحّد (refund_claimed/refunded/refund_credited)", () => {
  const b = body("async function _claimRefund");
  assert.ok(b.includes("runTransaction"));
  assert.ok(b.includes("refund_credited === true"));
  assert.ok(b.includes(
      "cur.payment_status === \"refunded\" || cur.refunded === true ||"));
  assert.ok(b.includes("cur.refund_claimed === true"));
  assert.ok(b.includes("refund_claimed: true"));
});

t("معرّف تمارا يُخزَّن عند التأكيد (يلزم للاسترداد)", () => {
  const b = body("async function _tamaraFlipPaid");
  assert.ok(b.includes("tamara_order_id: String(tamaraOrderId)"));
  // كل مواضع النداء تمرّر المعرّف (الويب هوك + كرون التأكيد).
  const calls = fn.match(/_tamaraFlipPaid\(db, [^)]+\)/g) || [];
  assert.ok(calls.length >= 6, `مواضع نداء أقل من المتوقع: ${calls.length}`);
  for (const c of calls) {
    assert.ok(/, (tamaraOrderId|to\.order_id)\)$/.test(c),
        `نداء بلا معرّف تمارا: ${c}`);
  }
});

console.log(`\nnotification_dedup: ${passed} passed`);
