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

const {FieldValue, Timestamp} = require("firebase-admin/firestore");

/** علمُ الفشلِ لكلِّ مكافأة — المكنسةُ تَستعلمُه، والنجاحُ يَمحوه. */
const PENDING_FLAGS = {
  qatrat: "qatrat_pending",
  couponCount: "coupon_count_pending",
  visitAccounting: "visit_accounting_pending",
  referralPayout: "referral_payout_pending",
  ratingAggregation: "rating_agg_pending",
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

/**
 * يُسوّي رصيدَ زياراتِ الاشتراكِ لطلبٍ بلغَ حالةً نهائيّة، ويَقولُ الفشل.
 *
 * **العطلُ الذي يُغلقُه:** الكتلةُ كانت إنلاين في `syncOrderLinkedRecords`
 * بـ`catch` هو سطرُ `console.error` وحدَه، والمُشغّلُ `onDocumentUpdated`
 * **بلا `retry`** فلا يَعودُ لمستندٍ فاته الحدث. فمعامَلةٌ تَفشلُ لتنازعٍ
 * أو مهلةٍ تَعني:
 *
 *   • `completed` فشلَ خصمُه ⇒ العميلةُ تَحتفظُ بزيارةٍ مدفوعةٍ سلفاً
 *     استهلكَتها فعلاً، وبطاقةُ الباقةِ في لوحتِها تَعرضُ رصيداً أكبرَ من
 *     حقِّها فتَحجزُ زيارةً لا تَملكُها — تسريبُ إيرادٍ صامت.
 *   • `cancelled` فشلَ ردُّه ⇒ **تَفقدُ** زيارةً مدفوعةً تَستحقُّها، وهو
 *     مالُها، بلا كلمةٍ في أيِّ مكان.
 *
 * ولا شيءَ كان يَمسحُ عنه: لا علمَ، و`visit_counted` يَبقى كما كان فيَقرأُ
 * الطلبُ «غيرَ محسوب» فلا يُميّزُه شيءٌ عن طلبٍ لم يُكتمل بعد.
 *
 * عديمُ الأثرِ التكراريِّ بالبناء: `visit_counted` يُقرأُ **طازجاً داخلَ
 * المعامَلة** ويَحرُسُ الاتّجاهَين، والاتّجاهُ يُشتَقُّ من الحالةِ الراهنةِ
 * لا من حدثٍ مُخزَّن — فإعادةُ المحاولةِ تُصحّحُ نفسَها ولو تغيّرت الحالةُ
 * بينهما.
 *
 * @param {object} db Firestore.
 * @param {object} args المعطيات.
 * @param {object} args.orderRef مرجعُ الطلب.
 * @param {string} args.orderId معرّفُ الطلب.
 * @param {string} args.clientId معرّفُ العميلة.
 * @param {string} args.status حالةُ الطلبِ الراهنة.
 * @param {string} args.code رقمُ الطلبِ المعروض.
 * @param {boolean} [args.alreadyAlerted] هل صُعِّدَ الفشلُ سابقاً؟
 * @param {Function} queuePush طابورُ الإشعارات.
 * @return {Promise<{settled: boolean, delta?: number, skipped?: string,
 *   failed?: string}>} النتيجة.
 */
async function settleVisitAccounting(db, args, queuePush) {
  const {orderRef, orderId, clientId, status, code} = args;
  const userRef = db.collection("users").doc(clientId);
  let skipped = null;
  let delta = 0;
  try {
    await db.runTransaction(async (t) => {
      const oSnap = await t.get(orderRef);
      const counted = oSnap.get("visit_counted") === true;
      if (status === "completed") {
        if (counted) {
          skipped = "already_counted";
          return;
        }
        delta = -1;
      } else if (status === "cancelled") {
        // زيارةٌ لم تُستهلَك أصلاً لا تُردّ: كانت من الدفعةِ المدفوعةِ سلفاً،
        // وردُّها يَخلقُ زيارةً مجّانيّة.
        if (!counted) {
          skipped = "never_counted";
          return;
        }
        delta = 1;
      } else {
        // الحالةُ تَحرّكت بعد الفشل: لا شيءَ لِيُسوّى، والعلمُ يُمحى.
        skipped = "not_terminal";
        return;
      }
      const cId = oSnap.get("contract_id");
      t.set(userRef, {
        visits_remaining: FieldValue.increment(delta),
      }, {merge: true});
      // ومن عدّادِ العقدِ نفسِه كذلك كي تَعكسَ بطاقةُ الباقةِ رصيدَها الفعليّ.
      if (cId) {
        t.set(db.collection("contracts").doc(cId), {
          visits_remaining: FieldValue.increment(delta),
        }, {merge: true});
      }
      t.update(orderRef, {
        visit_counted: delta < 0,
        // العلمُ يُمحى عند النجاح كي لا تَتضخّمَ مجموعةُ المكنسة.
        [PENDING_FLAGS.visitAccounting]: FieldValue.delete(),
      });
    });
    if (skipped) {
      // طلبٌ سُوّيَ سلفاً (أو تَحرّكت حالتُه) وما زال موسوماً: يُنظّفُ العلمُ
      // فلا يُقرأُ للأبد.
      await orderRef.update({
        [PENDING_FLAGS.visitAccounting]: FieldValue.delete(),
      }).catch(() => {});
      return {settled: false, skipped};
    }
    return {settled: true, delta};
  } catch (e) {
    const note = e && e.message ? e.message : "unknown";
    await orderRef.update({
      [PENDING_FLAGS.visitAccounting]: true,
      visit_accounting_failed_reason: note,
      visit_accounting_alerted: true,
    }).catch(() => {});
    if (!args.alreadyAlerted && typeof queuePush === "function") {
      const what = status === "cancelled"
        ? "ردُّ زيارةٍ مدفوعةٍ إلى رصيد العميلة"
        : "خصمُ زيارةٍ مستهلَكةٍ من رصيد العميلة";
      await queuePush("ADMIN_BROADCAST",
          "تعذّرت تسويةُ رصيد زيارات الاشتراك ⚠️",
          `الطلب #${code} (${status}) — تعذّر ${what} (${note}). ` +
          "المكنسة تُعيد المحاولة؛ إن تكرّر فالتسويةُ يدويّة على " +
          "users/{uid}.visits_remaining وعلى عدّاد العقد.",
          "admin_order_alert",
          {orderId, code, visitAccountingFailed: true},
          ["super_admin", "accountant_admin"]).catch(() => {});
    }
    return {settled: false, failed: note};
  }
}

/**
 * Race-safe first-completed-order referral payout. The referral doc's
 * pending->rewarded flip inside the transaction is the single-winner mutex;
 * the referrer credit, ledger row and coupon are all written in the SAME
 * transaction so a crash cannot leave a half-paid referral, and deterministic
 * ids make a redelivery a no-op.
 * **ولا يُبتلَعُ الفشل (2026-10-05):** `catch` كان سطرَ `console.error`
 * وحدَه، والمعامَلةُ تَكتبُ خمسةَ مستنداتٍ معاً ومنها ٥٠ ر.س إلى محفظةِ
 * المُحيلِ وكوبونُ المُحالة. فالفشلُ يَكتبُ علمَه والمكنسةُ تُعيدُ
 * المحاولةَ، والتصعيدُ مرّةً واحدة.
 *
 * @param {object} db Firestore.
 * @param {object} args المعطيات.
 * @param {string} args.refereeUid معرّفُ المُحالة (المستخدمُ الجديد).
 * @param {string} args.orderId معرّفُ الطلبِ المكتمل.
 * @param {object} [args.orderRef] مرجعُ الطلب.
 * @param {string} [args.code] رقمُ الطلبِ المعروض.
 * @param {boolean} [args.alreadyAlerted] هل صُعِّدَ الفشلُ سابقاً؟
 * @param {Function} queuePush طابورُ الإشعارات.
 * @return {Promise<{paid: boolean, skipped?: string, failed?: string}>}
 *   النتيجة.
 */
async function payReferralBonus(db, args, queuePush) {
  const {refereeUid, orderId} = args;
  const orderRef = args.orderRef || db.collection("orders").doc(orderId);

  // Resolve the referral: deterministic id first, query fallback for legacy
  // random-id docs created before applyReferralCode switched to a fixed id.
  let referralRef = db.collection("referrals").doc(refereeUid);
  if (!(await referralRef.get()).exists) {
    const q = await db.collection("referrals")
        .where("referee_id", "==", refereeUid)
        .where("status", "==", "pending").limit(1).get();
    if (q.empty) return clearAndSkip(orderRef, "no_referral");
    referralRef = q.docs[0].ref;
  }

  const REFERRER_REWARD = 50;
  let payout = null;
  try {
    payout = await db.runTransaction(async (t) => {
      const rSnap = await t.get(referralRef);
      if (!rSnap.exists || rSnap.get("status") !== "pending") return null;
      const referrerId = rSnap.get("referrer_id");
      if (!referrerId) return null;
      const referralId = referralRef.id;
      const referrerWallet = db.collection("wallets").doc(referrerId);
      const bonusTx = referrerWallet.collection("transactions").doc(`refbonus_${referralId}`);
      const couponCode = `REF${refereeUid.substring(0, 6).toUpperCase()}10`;
      const couponRef = db.collection("promo_codes").doc(couponCode);

      t.update(referralRef, {
        status: "rewarded",
        rewarded_on_order: orderId,
        rewarded_at: FieldValue.serverTimestamp(),
      });
      t.update(orderRef, {referral_processed: true});
      t.set(referrerWallet, {
        balance: FieldValue.increment(REFERRER_REWARD),
        last_updated: FieldValue.serverTimestamp(),
      }, {merge: true});
      t.create(bonusTx, {
        amount: REFERRER_REWARD, points: 0, type: "referral_reward",
        description: "مكافأة إحالة صديق أتمّ أول طلب",
        order_id: orderId,
        created_at: FieldValue.serverTimestamp(),
      });
      // يجب أن يطابق مخطّط الكوبونات الذي يقرؤه التطبيق (validateCoupon):
      // type/value/maxUses/status/expiry — كان يكتب discount_type/is_active/expires_at
      // فيفشل التحقّق دائماً ولا يُطبَّق كوبون الإحالة أبداً.
      t.set(couponRef, {
        code: couponCode,
        type: "percentage",
        value: 10,
        maxUses: 1,
        uses: 0,
        status: "active",
        expiry: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
        target_user_id: refereeUid,
        description: "خصم الإحالة 10% — مكافأة الانضمام",
        created_at: FieldValue.serverTimestamp(),
      }, {merge: true});

      return {referrerId, couponCode};
    });
  } catch (e) {
    // **كان هذا السطرَ وحدَه.** والمعامَلةُ تَكتبُ خمسةَ مستنداتٍ معاً —
    // ومنها **٥٠ ر.س إلى محفظةِ المُحيل** وكوبونُ المُحالةِ — فالفشلُ يَعني
    // أنّ أحداً لم يَنَلْ ما وُعِد، ولا أحدَ عَلِم. وتعليقُ الدالّةِ يُطمئنُ
    // عن الذرّيّة («a crash cannot leave a half-paid referral») وهو صحيحٌ
    // ولا يَمَسُّ هذا الوجهَ: المُشغّلُ `onDocumentUpdated` بلا `retry`،
    // وحدثُ «أوّلُ طلبٍ مكتمل» لا يَعودُ أبداً.
    const note = e && e.message ? e.message : "unknown";
    await orderRef.update({
      [PENDING_FLAGS.referralPayout]: true,
      referral_payout_failed_reason: note,
      referral_payout_alerted: true,
    }).catch(() => {});
    if (!args.alreadyAlerted && typeof queuePush === "function") {
      await queuePush("ADMIN_BROADCAST",
          "تعذّر صرفُ مكافأةِ الإحالة ⚠️",
          `الطلب #${args.code || orderId} أتمّ أوّلَ طلبٍ لمُحالٍ، ولم تُصرَف ` +
          `مكافأةُ الإحالة (${REFERRER_REWARD} ر.س للمُحيل + كوبونُ المُحالة) ` +
          `(${note}). المكنسة تُعيد المحاولة؛ إن تكرّر فالصرفُ يدويّ.`,
          "admin_order_alert",
          {orderId, refereeUid, referralFailed: true},
          ["super_admin", "accountant_admin", "marketing_admin"]).catch(() => {});
    }
    return {paid: false, failed: note};
  }
  // لا شيءَ لِيُصرَف (لا إحالةَ، أو صُرِفت سلفاً): العلمُ يُنظَّفُ فلا
  // تَقرؤه المكنسةُ للأبد.
  if (!payout) return clearAndSkip(orderRef, "nothing_to_pay");

  await queuePush(payout.referrerId, "🎁 مكافأة إحالتك وصلت!",
      // وقائيٌّ: الثابتُ عددٌ صحيحٌ اليومَ فيُطبَعُ «50»، لكنّ اصطلاحَ
      // الخادمِ في رسائلِ العميلةِ خانتانِ دائماً (أربعةُ مواضعَ أخرى)،
      // فتغييرُ الثابتِ إلى كسرٍ يَومَاً لا يُنتجُ صيغةً خامسة.
      `أُضيفت ${REFERRER_REWARD.toFixed(2)} ر.س لمحفظتك مكافأة لإحالة صديق ` +
      "أتمّ أول طلب.",
      "referral_reward", {orderId: orderId});
  await queuePush(refereeUid, "🎉 كوبون الإحالة جاهز!",
      `حصلت على كوبون خصم 10% على طلبك القادم. الكود: ${payout.couponCode}`,
      "referral_coupon", {coupon_code: payout.couponCode});
  // والعلمُ يُمحى بعد النجاحِ كي لا تَتضخّمَ مجموعةُ المكنسةِ بما نُجِح.
  await orderRef.update({
    [PENDING_FLAGS.referralPayout]: FieldValue.delete(),
  }).catch(() => {});
  return {paid: true, referrerId: payout.referrerId};
}

/**
 * يُنظّفُ علمَ إعادةِ المحاولةِ حين لا شيءَ لِيُصرَف.
 * @param {object} orderRef مرجعُ الطلب.
 * @param {string} why السبب.
 * @return {Promise<object>} النتيجة.
 */
async function clearAndSkip(orderRef, why) {
  await orderRef.update({
    [PENDING_FLAGS.referralPayout]: FieldValue.delete(),
  }).catch(() => {});
  return {paid: false, skipped: why};
}

/**
 * يُدخِلُ تقييمَ طلبٍ في متوسّطِ السائق، مرّةً واحدةً، ويَقولُ الفشل.
 *
 * **العطلُ الذي يُغلقُه:** المعامَلةُ كانت إنلاين في `aggregateDriverRating`
 * و`catch`ها سطرُ `console.error` وحدَه، والمُشغّلُ بلا `retry`. والمتوسّطُ
 * **تزايديٌّ** (`(avg * count + r) / (count + 1)`) لا يُعادُ حسابُه من كلِّ
 * التقييمات — فمعامَلةٌ تَفشلُ تَعني أنّ ذلك التقييمَ **ضائعٌ من المتوسّطِ
 * ومن العدّادِ إلى الأبد**. ولا مالَ فيه، لكنّ `rating_count` هو **المُميِّزُ**
 * الذي تَقومُ عليه قاعدةُ «لا رقمَ قبل أن نعرفه» في `driver_rating.dart`،
 * وشاشةُ الأداءِ تُرتّبُ به وتُسمّي «الأفضل» — فعدّادٌ ناقصٌ يُفسِدُ ترتيباً
 * يَتّخذُ عليه الأدمنُ قراراً.
 *
 * **والمانعُ من التكرارِ كان حدثيّاً لا مستنديّاً** (`before.rating != null`)،
 * فالدالّةُ لم تَكن آمنةً للنداءِ مرّتَين — ولا يُمكِنُ أن تُعادَ من مكنسة.
 * فصارَ على الطلبِ علَمٌ (`rating_aggregated`) يُقرأُ **طازجاً داخلَ
 * المعامَلة**، فالإعادةُ آمنةٌ والسلوكُ الظاهرُ كما كان (تقييمٌ يُحرَّرُ
 * لاحقاً ما زالَ لا يُحتسَبُ مرّةً ثانية).
 *
 * @param {object} db Firestore.
 * @param {object} args المعطيات.
 * @param {object} args.orderRef مرجعُ الطلب.
 * @param {string} args.orderId معرّفُ الطلب.
 * @param {string} args.driverId معرّفُ السائق.
 * @param {number} args.rating التقييمُ (1–5).
 * @param {boolean} [args.alreadyAlerted] هل صُعِّدَ الفشلُ سابقاً؟
 * @param {Function} queuePush طابورُ الإشعارات.
 * @return {Promise<{aggregated: boolean, skipped?: string, failed?: string}>}
 *   النتيجة.
 */
async function aggregateRating(db, args, queuePush) {
  const {orderRef, orderId, driverId, rating} = args;
  const r = Number(rating);
  if (isNaN(r) || r < 1 || r > 5) {
    return {aggregated: false, skipped: "invalid_rating"};
  }
  const ref = db.collection("drivers").doc(driverId);
  let skipped = null;
  try {
    await db.runTransaction(async (tx) => {
      const oSnap = await tx.get(orderRef);
      if (oSnap.get("rating_aggregated") === true) {
        skipped = "already_aggregated";
        return;
      }
      const snap = await tx.get(ref);
      if (!snap.exists) {
        skipped = "no_driver";
        return;
      }
      const d = snap.data();
      const count = Number(d.rating_count || 0);
      // البذر الثابت (rating: 5 بلا عدّاد) لا يدخل المتوسط — أول تقييم حقيقي
      // يؤسس المتوسط من الصفر.
      const avg = count > 0 ? Number(d.rating_avg || d.rating || 0) : 0;
      const newCount = count + 1;
      const newAvg = Math.round(((avg * count + r) / newCount) * 100) / 100;
      tx.update(ref, {
        rating_count: newCount,
        rating_avg: newAvg,
        rating: newAvg, // الحقل الذي تعرضه بطاقات الإدارة والعميل حالياً
      });
      tx.update(orderRef, {
        rating_aggregated: true,
        [PENDING_FLAGS.ratingAggregation]: FieldValue.delete(),
      });
    });
    if (skipped) {
      await orderRef.update({
        [PENDING_FLAGS.ratingAggregation]: FieldValue.delete(),
      }).catch(() => {});
      return {aggregated: false, skipped};
    }
    return {aggregated: true};
  } catch (e) {
    const note = e && e.message ? e.message : "unknown";
    await orderRef.update({
      [PENDING_FLAGS.ratingAggregation]: true,
      rating_agg_failed_reason: note,
      rating_agg_alerted: true,
    }).catch(() => {});
    if (!args.alreadyAlerted && typeof queuePush === "function") {
      await queuePush("ADMIN_BROADCAST",
          "تعذّر إدخالُ تقييمٍ في متوسّطِ السائق ⚠️",
          `تقييمُ الطلب #${args.code || orderId} (${r}★) لم يَدخُلْ متوسّطَ ` +
          `السائقِ ولا عدّادَه (${note}). المتوسّطُ تزايديٌّ فالتقييمُ يَضيعُ ` +
          "بلا إعادة؛ المكنسة تُعيد المحاولة.",
          "admin_order_alert",
          {orderId, driverId, ratingAggFailed: true},
          ["super_admin", "orders_manager"]).catch(() => {});
    }
    return {aggregated: false, failed: note};
  }
}

module.exports = {
  aggregateRating,
  payReferralBonus,
  settleVisitAccounting,
  PENDING_FLAGS,
  grantQatratPoints,
  countCouponUse,
};
