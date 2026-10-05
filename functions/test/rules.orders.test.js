// Emulator rules test: proves the Stage-C order-create rule closes wallet minting.
// Run: firestore emulator on :8080, then `node test/rules.orders.test.js`.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {setDoc, updateDoc, doc} = require("firebase/firestore");

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-zyiarah-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const uid = "client_abc";
  const db = testEnv.authenticatedContext(uid).firestore();

  let pass = 0; let fail = 0;
  const check = async (name, promise, shouldSucceed) => {
    try {
      await (shouldSucceed ? assertSucceeds(promise) : assertFails(promise));
      console.log(`  ✓ ${name}`);
      pass++;
    } catch (e) {
      console.error(`  ✗ ${name} — ${e.message}`);
      fail++;
    }
  };

  console.log("Stage-C order-create rule — wallet-minting closure:");

  // The actual mint vector: forge a PAID order -> now DENIED at create.
  await check("mint: create is_paid=true -> DENIED",
      setDoc(doc(db, "orders/mint1"),
          {client_id: uid, status: "pending", is_paid: true, amount: 5000}),
      false);

  // Server trust fields cannot be seeded at create.
  await check("trust: needs_refund at create -> DENIED",
      setDoc(doc(db, "orders/t1"),
          {client_id: uid, status: "pending", needs_refund: true, amount: 200}),
      false);
  await check("trust: rewards_handled_by at create -> DENIED",
      setDoc(doc(db, "orders/t2"),
          {client_id: uid, status: "pending", rewards_handled_by: "server", amount: 200}),
      false);
  await check("trust: refund_credited at create -> DENIED",
      setDoc(doc(db, "orders/t3"),
          {client_id: uid, status: "pending", refund_credited: true, amount: 200}),
      false);

  // Legit new-flow creates (is_paid false / absent) still work.
  await check("legit: is_paid=false -> ALLOWED",
      setDoc(doc(db, "orders/ok1"),
          {client_id: uid, status: "pending", is_paid: false, amount: 200}),
      true);
  // awaiting_payment هي حالة الدخول الثانية المسموحة (يكتبها متجرُ العميل في
  // store_service.dart). كانت هنا pending_admin_approval — وهي حالة ميتة حُذفت
  // من الجذور، فكان الإنشاء يُرفض على الحالة لا على is_paid، ولم يُختبر الغياب أبداً.
  await check("legit: is_paid absent -> ALLOWED",
      setDoc(doc(db, "orders/ok2"),
          {client_id: uid, status: "awaiting_payment", amount: 200}),
      true);

  // ── أعلامُ الثقةِ الخادميّةُ الباقية (2026-10-05) ────────────────────
  //
  // القائمةُ كانت ثمانيةً، وبقيةُ أعلامِ الخادمِ مكشوفةً — **وواحدٌ منها
  // يُسكِتُ التنبيهَ الوحيدَ لمسارِ المحفظة**: `opsHealthSweep` يُنبّه عبر
  // `alertBatch(docs, "ops_alerted_mismatch")`، وهي تُسقِطُ كلَّ مستندٍ العلمُ
  // فيه `true` سلفاً؛ ومسارُ المحفظةِ يَسِمُ `price_mismatch` **بصمتٍ**
  // ويَتّكلُ على ذلك المسحِ وحدَه. فإنشاءُ الطلبِ بالعلمِ مضبوطاً ثمّ دفعُ
  // أقلَّ من نصفِ السعرِ وفوقَ خُمسِه (فلا يُرفَض) = خدمةٌ بسعرٍ ناقصٍ **بلا
  // تنبيهٍ أبداً**.
  await check("mute: ops_alerted_mismatch at create -> DENIED",
      setDoc(doc(db, "orders/mute1"),
          {client_id: uid, status: "pending", is_paid: false,
            ops_alerted_mismatch: true, amount: 200}),
      false);
  // الحجزُ الذي يُعطّلُ Tier B: ضبطُه سلفاً يَجعلُ `voidOrRefundTampered`
  // تُعيدُ «already» بلا نداءِ البوّابةِ أصلاً.
  await check("mute: tamper_handled at create -> DENIED",
      setDoc(doc(db, "orders/mute2"),
          {client_id: uid, status: "pending", is_paid: false,
            tamper_handled: true, amount: 200}),
      false);
  // `final_amount` يَتقدّمُ تدرّجَ المبالغِ كلَّه في `amounts.js` ولا يَكتبُه
  // شيءٌ في المستودعِ (١٢ قراءةً خادميّة، صفرُ كتابات).
  await check("trust: final_amount at create -> DENIED",
      setDoc(doc(db, "orders/mute3"),
          {client_id: uid, status: "pending", is_paid: false,
            final_amount: 1, amount: 200}),
      false);
  await check("mute: auto_refund_processed at create -> DENIED",
      setDoc(doc(db, "orders/mute4"),
          {client_id: uid, status: "pending", is_paid: false,
            auto_refund_processed: true, amount: 200}),
      false);
  // وأعلامُ إعادةِ المحاولةِ: المكنسةُ تَستعلمُ **العلمَ** لا الحالةَ، فعلمٌ
  // مضبوطٌ سلفاً يُدخِلُ طلباً سليماً في مجموعةِ إعادةِ المحاولةِ (أو يُسكِتُ
  // تصعيدَ استردادٍ فاشل).
  await check("mute: refund_credit_alerted at create -> DENIED",
      setDoc(doc(db, "orders/mute5"),
          {client_id: uid, status: "pending", is_paid: false,
            refund_credit_alerted: true, amount: 200}),
      false);
  await check("mute: qatrat_pending at create -> DENIED",
      setDoc(doc(db, "orders/mute6"),
          {client_id: uid, status: "pending", is_paid: false,
            qatrat_pending: true, amount: 200}),
      false);
  await check("mute: coupon_count_pending at create -> DENIED",
      setDoc(doc(db, "orders/mute7"),
          {client_id: uid, status: "pending", is_paid: false,
            coupon_count_pending: true, amount: 200}),
      false);
  // وتسويةُ رصيدِ زياراتِ الاشتراك (2026-10-05): نفسُ العائلة.
  await check("mute: visit_accounting_pending at create -> DENIED",
      setDoc(doc(db, "orders/mute7a"),
          {client_id: uid, status: "pending", is_paid: false,
            visit_accounting_pending: true, amount: 200}),
      false);
  await check("mute: visit_accounting_alerted at create -> DENIED",
      setDoc(doc(db, "orders/mute7b"),
          {client_id: uid, status: "pending", is_paid: false,
            visit_accounting_alerted: true, amount: 200}),
      false);
  // وعلمُ فئةِ «تعذّر التحقّق» — عضوٌ خامسٌ في عائلةِ `alertBatch` (أُضيف مع
  // مكنستِها): ضبطُه سلفاً يُسقِطُ المستندَ من نافذةِ التنبيهِ كأخواتِه.
  await check("mute: ops_alerted_unverifiable at create -> DENIED",
      setDoc(doc(db, "orders/mute8"),
          {client_id: uid, status: "pending", is_paid: false,
            ops_alerted_unverifiable: true, amount: 200}),
      false);
  // وشهادةُ المراجعةِ: `price_mismatch: false` هي ما تَكتبُه الإدارةُ عند
  // الاعتماد، و`price_review_decision` توقيعُها — فعميلةٌ تُنشئُ طلبَها
  // بهما تَكتبُ شهادةً لم يُوقّعها أحدٌ وتُخرِجُ مستندَها من المسحِ سلفاً.
  await check("mute: price_review_decision at create -> DENIED",
      setDoc(doc(db, "orders/mute9"),
          {client_id: uid, status: "pending", is_paid: false,
            price_review_decision: "approved", amount: 200}),
      false);
  await check("trust: price_paid at create -> DENIED",
      setDoc(doc(db, "orders/mute10"),
          {client_id: uid, status: "pending", is_paid: false,
            price_paid: 1, amount: 200}),
      false);
  await check("mute: client_stranded_notified at create -> DENIED",
      setDoc(doc(db, "orders/mute11"),
          {client_id: uid, status: "pending", is_paid: false,
            client_stranded_notified: true, amount: 200}),
      false);
  // ولا يُكسَرُ الإنشاءُ الشرعيُّ: الحقولُ التي يَكتبُها التطبيقُ فعلاً تمرّ.
  await check("legit: the app's own create fields -> ALLOWED",
      setDoc(doc(db, "orders/ok3"),
          {client_id: uid, status: "pending", is_paid: false, amount: 200,
            coupon_code: "X10", discount_amount: 20, zone_name: "فيفا",
            service_name: "تنظيف منزلي", hours_contracted: 4,
            booking_date: "2026-10-06", booking_time_slot: "10:00"}),
      true);

  // Existing protections still hold.
  await check("spoof: client_id != uid -> DENIED",
      setDoc(doc(db, "orders/spoof1"),
          {client_id: "someone_else", status: "pending", is_paid: false, amount: 200}),
      false);
  await check("status: bad initial status -> DENIED",
      setDoc(doc(db, "orders/bad1"),
          {client_id: uid, status: "completed", is_paid: false, amount: 200}),
      false);

  // ── الإلغاءُ العميليّ: `needs_refund` مربوطٌ بالواقعِ لا بإرادةِ الكاتب ──
  //
  // الفرعُ يُجيزُ العلمَ في `hasOnly` لأنّ التطبيقَ الشريفَ يَكتبُه في نفسِ
  // معامَلةِ الإلغاء، و`order_service.cancelOrder` يَضَعُ `is_paid == true`
  // بعينِه (وكذلك `Orders.tsx`). وكتابةٌ مباشرةٌ من الـSDK كانت تَضَعُ `true`
  // على طلبٍ **غيرِ مدفوع**: لا مالَ فيها (قارئا العلمِ كلاهما يَشترطُ
  // `is_paid === true`)، لكنّ المستندَ يَشغلُ خانةً من نافذةِ المكنسةِ ذاتِ
  // الـ200 إلى الأبد فيُزحزحُ استرداداً فاشلاً حقيقيّاً — بترتيبِ `__name__`
  // العشوائيّ، بصمتٍ تامّ.
  // **مستندٌ لكلِّ فحصٍ**: إلغاءٌ ناجحٌ يُغيّرُ الحالةَ إلى `cancelled`
  // فيَسقطُ شرطُ الفرعِ (`status in ['pending','awaiting_payment']`) عن أيِّ
  // فحصٍ تالٍ على المستندِ نفسِه. أوّلُ صياغةٍ شاركت المستندات، فحين أُزيلَ
  // الرباطُ في اختبارِ القضمِ **سقطَ فحصٌ ثانٍ تبعاً للأوّل** لا بعطلٍ في
  // القاعدة — فحصٌ يَعتمدُ على نجاحِ ما قبله يُضلّل.
  const seed = {
    cancelUnpaidForge: {is_paid: false},
    cancelUnpaidHonest: {is_paid: false},
    cancelPaidHonest: {is_paid: true},
    cancelPaidDeny: {is_paid: true},
    cancelNoField: {},
  };
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const admin = ctx.firestore();
    for (const [id, extra] of Object.entries(seed)) {
      await setDoc(doc(admin, `orders/${id}`),
          Object.assign({client_id: uid, status: "pending", amount: 200},
              extra));
    }
  });
  const cancelWith = (id, needsRefund) => updateDoc(doc(db, `orders/${id}`), {
    status: "cancelled", cancelled_at: new Date(), cancelled_by: "client",
    needs_refund: needsRefund, rewards_handled_by: "server",
  });
  await check("cancel: unpaid order claiming needs_refund -> DENIED",
      cancelWith("cancelUnpaidForge", true), false);
  await check("cancel: unpaid order with needs_refund=false -> ALLOWED",
      cancelWith("cancelUnpaidHonest", false), true);
  await check("cancel: paid order with needs_refund=true -> ALLOWED",
      cancelWith("cancelPaidHonest", true), true);
  await check("cancel: paid order denying its own refund -> DENIED",
      cancelWith("cancelPaidDeny", false), false);
  // وطلبٌ قديمٌ بلا الحقلِ أصلاً: `.get('is_paid', false)` يَقرؤه غياباً،
  // فالإلغاءُ يَمرُّ بـ`false` — ولو كان القوسَ المباشرَ لَرُفض كلُّ إلغاءٍ
  // لتلك الطلبات.
  await check("cancel: legacy order with no is_paid field -> ALLOWED",
      cancelWith("cancelNoField", false), true);

  await testEnv.cleanup();
  console.log(`\nRules test: ${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
