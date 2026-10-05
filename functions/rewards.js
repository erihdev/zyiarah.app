"use strict";

// ═══════════════════════════════════════════════════════════════════════
// مكافآتُ الطلبِ المكتمل، وعدُّ استعمالِ الكوبون — **مع قولِ الفشل**.
//
// كلٌّ من الاثنَين كان إنلاين في `index.js` بـ`catch` واحدٍ هو سطرُ
// `console.error` وحدَه:
//
//   `[rewards] qatrat txn failed for …`
//   `[coupon] use-count failed for order …`
//
// والمُشغّلانِ `onDocumentUpdated`/`onDocumentCreated` **بلا `retry`** ولا
// يَعودانِ لمستندٍ فاته الحدث، فمعامَلةٌ تَفشلُ لتنازعٍ أو مهلةٍ تَعني:
//
//   • **قطرات**: العميلةُ أتمّت طلباً ولم تُضَف نقاطُها (قيمتُها ريالٌ لكلِّ
//     خمسين نقطة — `lib/utils/qatrat.dart`)، ولا دفعةَ تُخبرها، ولا تنبيهَ
//     للإدارة، ولا محاولةً ثانية.
//   • **عدُّ الكوبون**: `uses` لم يُزَد، فكوبونٌ لمرّةٍ واحدةٍ يَبقى قابلاً
//     للإنفاق — و`coupons.couponProblem` يَبني «exhausted» على ذلك العدّادِ
//     بعينِه، فالمنعُ الخادميُّ يَسقطُ معه.
//
// وهي **العائلةُ نفسُها** التي أُغلقت في `refund_engine.creditCancelledRefund`
// (إلغاءٌ مدفوعٌ لم يُردّ) و`autoResolveUnfulfilledPaidOrder` (طلبٌ فات موعدُه
// بلا سائق). ثلاثةُ مواضعَ، سببٌ واحد: `catch` يَكتبُ سطراً ويُنسي.
//
// **والعِلاجُ هنا أنظفُ من أختِه**، لأنّ الاسترداد وجدَ علماً جاهزاً
// (`needs_refund`) تَستعلمُه المكنسة، وهذان لا. فالفشلُ يَكتبُ علمَه بنفسِه
// (`qatrat_pending` / `coupon_count_pending`)، والمكنسةُ تَستعلمُ **العلمَ**
// لا الحالة: فمجموعتُها لا تَحوي إلّا الفشلَ، فلا تَزدحمُ نافذتُها بما
// نُجِح — وهو العطلُ الذي وُجد مرّتَين هذه الجلسة (نافذةُ البثِّ المجدول،
// ونافذةُ «مدفوعٌ وعالق»).
//
// والوحدةُ تَأخذُ `db` وسيطاً أوّلَ ولا تُنادي `getFirestore()` أبداً
// (قاعدةُ `refund_engine.js`)، فتُختبَرُ على `db` مزيّفٍ بلا مُحاكٍ ولا شبكة.
// ═══════════════════════════════════════════════════════════════════════

const {FieldValue} = require("firebase-admin/firestore");

/** علمُ الفشلِ لكلِّ مكافأة — المكنسةُ تَستعلمُه، والنجاحُ يَمحوه. */
const PENDING_FLAGS = {
  qatrat: "qatrat_pending",
  couponCount: "coupon_count_pending",
};

/**
 * يَمنحُ نقاطَ قطرات لطلبٍ مكتمل، مرّةً واحدةً، ويَقولُ الفشل.
 *
 * عديمُ الأثرِ التكراريِّ بالبناء: `qatrat_granted` على الطلبِ و`t.create`
 * على معرّفٍ حتميٍّ `qatrat_{orderId}` — فإعادةُ المحاولةِ آمنة.
 *
 * @param {object} db Firestore.
 * @param {object} args المعطيات.
 * @param {object} args.orderRef مرجعُ الطلب.
 * @param {string} args.orderId معرّفُ الطلب.
 * @param {string} args.clientId معرّفُ العميلة.
 * @param {number} args.points النقاطُ (ريالٌ = نقطة).
 * @param {string} args.code رقمُ الطلبِ المعروض.
 * @param {boolean} [args.alreadyAlerted] هل صُعِّدَ الفشلُ سابقاً؟
 * @param {Function} queuePush طابورُ الإشعارات.
 * @return {Promise<{granted: boolean, skipped?: string, failed?: string}>} النتيجة.
 */
async function grantQatratPoints(db, args, queuePush) {
  const {orderRef, orderId, clientId, points, code} = args;
  const walletRef = db.collection("wallets").doc(clientId);
  const txRef = walletRef.collection("transactions").doc(`qatrat_${orderId}`);
  let skipped = null;
  try {
    let didFlip = false;
    await db.runTransaction(async (t) => {
      const oSnap = await t.get(orderRef);
      if (oSnap.get("qatrat_granted") === true) {
        skipped = "already_granted";
        return;
      }
      t.set(walletRef, {
        qatrat_points: FieldValue.increment(points),
        last_updated: FieldValue.serverTimestamp(),
      }, {merge: true});
      t.create(txRef, {
        amount: 0, points: points, type: "qatrat_reward",
        description: `نقاط زيارة مكتسبة من الطلب المكتمل #${code}`,
        order_id: orderId,
        created_at: FieldValue.serverTimestamp(),
      });
      t.update(orderRef, {
        qatrat_granted: true,
        qatrat_granted_at: FieldValue.serverTimestamp(),
        // العلمُ يُمحى عند النجاح كي لا تَتضخّمَ مجموعةُ المكنسة.
        [PENDING_FLAGS.qatrat]: FieldValue.delete(),
      });
      didFlip = true;
    });
    if (skipped) {
      // طلبٌ مُنِحَ سلفاً وما زال موسوماً: نُنظّفُ العلمَ فلا يُقرأُ للأبد.
      await orderRef.update({
        [PENDING_FLAGS.qatrat]: FieldValue.delete(),
      }).catch(() => {});
      return {granted: false, skipped};
    }
    if (didFlip && typeof queuePush === "function") {
      await queuePush(clientId, "حصلت على نقاط زيارة جديدة! ✨🎈",
          `أضيفت ${points} نقطة زيارة لرصيدك مكافأة على الطلب #${code}.`,
          "qatrat_credit", {orderId: orderId}).catch(() => {});
    }
    return {granted: didFlip};
  } catch (e) {
    const note = e && e.message ? e.message : "unknown";
    await orderRef.update({
      [PENDING_FLAGS.qatrat]: true,
      qatrat_failed_reason: note,
      qatrat_alerted: true,
    }).catch(() => {});
    if (!args.alreadyAlerted && typeof queuePush === "function") {
      await queuePush("ADMIN_BROADCAST",
          "تعذّر منح نقاط قطرات لطلبٍ مكتمل ⚠️",
          `الطلب #${code} اكتمل ولم تُضَف نقاطُه (${points} نقطة) لرصيد ` +
          `العميلة (${note}). المكنسة تُعيد المحاولة؛ إن تكرّر فالمنحُ يدويّ.`,
          "admin_order_alert",
          {orderId, code, qatratFailed: true},
          ["super_admin", "accountant_admin"]).catch(() => {});
    }
    return {granted: false, failed: note};
  }
}

/**
 * يَزيدُ عدّادَ استعمالِ الكوبون، مرّةً واحدةً، ويَقولُ الفشل.
 *
 * `coupon_overlimit` يُوسَمُ عند الاستهلاك: TOCTOU يُجيزُ لطلبَين متزامنَين
 * تجاوزَ الحدّ، والعلمُ للمراجعةِ الإداريّة. والمنعُ الفعليُّ في التسعيرِ
 * الخادميِّ (`coupons.couponProblem` ⇒ `exhausted`).
 *
 * @param {object} db Firestore.
 * @param {object} args المعطيات.
 * @param {object} args.orderRef مرجعُ الطلب.
 * @param {string} args.orderId معرّفُ الطلب.
 * @param {object} args.promoRef مرجعُ مستندِ الكوبون.
 * @param {string} args.code رمزُ الكوبون.
 * @param {boolean} [args.alreadyAlerted] هل صُعِّدَ الفشلُ سابقاً؟
 * @param {Function} queuePush طابورُ الإشعارات.
 * @return {Promise<{counted: boolean, skipped?: string, failed?: string}>} النتيجة.
 */
async function countCouponUse(db, args, queuePush) {
  const {orderRef, orderId, promoRef, code} = args;
  let skipped = null;
  try {
    let didCount = false;
    await db.runTransaction(async (t) => {
      const oSnap = await t.get(orderRef);
      if (oSnap.get("coupon_counted") === true) {
        skipped = "already_counted";
        return;
      }
      const pSnap = await t.get(promoRef);
      const uses = Number(pSnap.get("uses") || 0);
      const maxUses = Number(pSnap.get("maxUses") || 0);
      const overLimit = maxUses > 0 && uses >= maxUses;
      t.update(promoRef, {uses: FieldValue.increment(1)});
      t.update(orderRef, {
        coupon_counted: true,
        [PENDING_FLAGS.couponCount]: FieldValue.delete(),
        ...(overLimit ? {coupon_overlimit: true} : {}),
      });
      didCount = true;
    });
    if (skipped) {
      await orderRef.update({
        [PENDING_FLAGS.couponCount]: FieldValue.delete(),
      }).catch(() => {});
      return {counted: false, skipped};
    }
    return {counted: didCount};
  } catch (e) {
    const note = e && e.message ? e.message : "unknown";
    await orderRef.update({
      [PENDING_FLAGS.couponCount]: true,
      coupon_count_failed_reason: note,
      coupon_count_alerted: true,
    }).catch(() => {});
    if (!args.alreadyAlerted && typeof queuePush === "function") {
      await queuePush("ADMIN_BROADCAST",
          "تعذّر عدُّ استعمالِ كوبون ⚠️",
          `الطلب #${orderId} استعمل الكوبون ${code} ولم يُزَد عدّادُه ` +
          `(${note}) — فكوبونٌ لمرّةٍ واحدةٍ يَبقى قابلاً للإنفاق. المكنسة ` +
          "تُعيد المحاولة؛ إن تكرّر فالتعديلُ يدويّ من شاشة الكوبونات.",
          "admin_order_alert",
          {orderId, code, couponCountFailed: true},
          ["super_admin", "marketing_admin"]).catch(() => {});
    }
    return {counted: false, failed: note};
  }
}

module.exports = {
  PENDING_FLAGS,
  grantQatratPoints,
  countCouponUse,
};
