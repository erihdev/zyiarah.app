const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onTaskDispatched} = require("firebase-functions/v2/tasks");
const {getFunctions} = require("firebase-admin/functions");
const {defineSecret} = require("firebase-functions/params");
// الواجهة المعيارية وحدها (firebase-admin/<module>): firebase-admin 14 حذف الواجهة المُسمّاة
// كلّها — firestore()/messaging()/auth() على التصدير الافتراضي القديم صارت undefined.
// test/admin_modular_api.test.js يحرس ذلك (اقرأ رأسه قبل تغيير هذه الاستيرادات).
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp, GeoPoint} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const geofire = require("geofire-common");
const {computeExpectedBasePrice, resolveMaterialsBase, applyTerrainSurcharge,
  resolveStoreCartBase} =
  require("./pricing");
const priceVerify = require("./price_verify");
const {isMarketingBroadcast, excludeOptedOut} = require("./notify_prefs");
const {countBookings, zoneDailyCap} = require("./capacity");
const {grossFromBaseRounded, grossFromBase} = require("./vat");
const {parseKsaIso, riyadhBookingFields, riyadhLocalDate, riyadhLocalSlot,
  riyadhStamp} = require("./ksa_time");
const coupons = require("./coupons");
const {isAssignableDriver, assignabilityProblem, chunk, GET_ALL_CHUNK} =
  require("./drivers");
const moyasar = require("./moyasar_api");
const tamara = require("./tamara_api");
const amounts = require("./amounts");
// محرّك الاسترداد الآلي — **أوّل وحدة تلمس Firestore**: تستقبل `db` وسيطاً
// ولا تستوردها، وكذلك `queuePush`، فتبقى قابلة للاختبار بلا محاكٍ.
const refunds = require("./refund_engine");
const rewards = require("./rewards");
const attachmentsGuard = require("./attachments");
const ticketAuthorship = require("./ticket_authorship");
// معرّفُ المشروع من بيئة التشغيل (Cloud Functions تضبطه) — يُقصر مرفقاتِ
// البريد على مخزن هذا المشروع وحده.
const PROJECT_ID = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
// نافذةُ شَغل السائق ومسندُ التداخل — وحدةٌ **نقيّة** (لا db): كان السؤال
// مكتوباً بيدٍ في ٢٣ موضعاً (مدّةُ الطلب ١٦، ومسحُ التعارض ٧).
const slots = require("./slots");
initializeApp();

// Secrets — stored in Firebase Secret Manager, never in source code
const tamaraApiToken = defineSecret("TAMARA_API_TOKEN");
// رمز الإشعارات (Notification Token) — يوقّع به تمارا الـ webhook (JWT/HS256).
// منفصل عن رمز API؛ يُجلب من لوحة تمارا (API keys) ويُضبط بـ functions:secrets:set.
const tamaraNotificationToken = defineSecret("TAMARA_NOTIFICATION_TOKEN");
const resendApiKeySecret = defineSecret("RESEND_API_KEY");
const moyasarSecretKey = defineSecret("MOYASAR_SECRET_KEY");
const moyasarWebhookSecret = defineSecret("MOYASAR_WEBHOOK_SECRET");
const tabbyWebhookSecret = defineSecret("TABBY_WEBHOOK_SECRET");

// (#1 Phase 2) بوّابة إنفاذ التسعير الخادمي (Tier B): استرداد/إلغاء آليّ عند دفعٍ ناقص
// صارخ. **فُعّلت بقرار المالك (2026-07-31)** بعد مراجعة سجلّات [price-shadow]:
// صفر إنذارات (كاذبة أو حقيقية) طوال فترة المراقبة. حرّاسها الثلاثة يبقون:
// ratio<0.2 فقط + طلب حديث موثوق الحساب + متوقَّع ≥ 5 ر.س (فأسعار الإطلاق
// التجريبي 1 ر.س خارج مداها أصلاً — تصبح فاعلة مع التسعير الحقيقي).
const ENFORCE_PRICE_TIER_B = true;

// حدُّ مسحِ المحافظِ السالبة (opsHealthSweep، الكتلة ٤). المجموعتانِ هناك
// جمهورُ **خللٍ** لا جمهورُ استعمال — صفرٌ في الحالةِ السليمة — فتُقرآنِ
// كاملتَين لا مقصوصتَين، وتجاوزُ هذا الحدِّ خبرٌ بذاته يُنبَّهُ عنه بالعددِ
// وحدَه بلا تعداد. لا يُستبدَلُ بـ`limit()` على الاستعلام: القصُّ قبلَ
// الترشيحِ هو العطلُ نفسُه الذي أُغلق.
const NEG_WALLET_SCAN_MAX = 500;
/// حدُّ مسحِ العقودِ المدفوعةِ العالقةِ — جمهورُ **خللٍ** لا استعمال، إلّا أنّ
/// المُتخطَّى منه (`plan_validation_failed`) لا يَخرُجُ أبداً، فتجاوزُ الحدِّ
/// هو الخبرُ بذاتِه (سابقةُ `NEG_WALLET_SCAN_MAX` أعلاه).
const STUCK_CONTRACT_SCAN_MAX = 300;

// 1. Notify user when admin replies to a support ticket
exports.sendNotificationOnTicketReply = onDocumentCreated({document: "support_tickets/{ticketId}/messages/{messageId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const newMessage = snap.data();
      const ticketId = event.params.ticketId;
      const ticketDoc = await getFirestore().collection("support_tickets")
          .doc(ticketId).get();
      if (!ticketDoc.exists) return null;
      const ticketData = ticketDoc.data();

      // كشف رد الإدارة: **القاعدةُ المشترَكةُ لا تعدادٌ هنا.** كان الفرعُ
      // `senderRole === "admin" || senderId === "admin"` — وكلا الحقلَين
      // تَكتبُهما العميلةُ، وقاعدةُ `messages` كانت بلا قيدٍ على المحتوى.
      // فرسالةٌ تَحملُ الادّعاءَ تَدخلُ فرعَ «ردُّ الدعم» فتُسقِطُ تنبيهَ
      // «رد جديد على تذكرة دعم» عن مديرِ الطلباتِ **كلَّه**: تَكتبُ إلى
      // الدعمِ ولا يُخبَرُ أحد. والمِعيارُ الآن الفاعلُ لا الادّعاء.
      // (`lib/utils/ticket_authorship.dart` يَحملُ الشرحَ كاملاً.)
      if (ticketAuthorship.ticketMessageIsFromTeam(
          newMessage, ticketData && ticketData.userId)) {
        // رد الدعم → أشعِر صاحب التذكرة (push + سجل داخل التطبيق).
        await queuePush(
            ticketData.userId,
            "تم الرد على تذكرتك 💬",
            "قام الدعم الفني بالرد على تذكرتك للتو.",
            "support_ticket", {ticketId});
      } else {
        // رد العميل → أشعِر الإدارة. لكن تخطَّ الرسالة الأولى (نصّ التذكرة عند إنشائها)
        // لأن sendNotificationToAdminsOnNewTicket يُشعر الإدارة بها أصلاً — منعاً لتنبيهٍ مزدوج.
        const msgs = await getFirestore().collection("support_tickets")
            .doc(ticketId).collection("messages").limit(2).get();
        if (msgs.size <= 1) return null;
        await queuePush(
            "ADMIN_BROADCAST",
            "رد جديد على تذكرة دعم 💬",
            "وصل رد جديد من عميل على تذكرة دعم — بانتظار المتابعة.",
            "admin_ticket_reply", {ticketId}, ["orders_manager"]);
      }
      return null;
    });

// 1.1 Notify Admins on a NEW support ticket (was previously missing — admins never
// learned a client opened a ticket until they manually checked the panel).
exports.sendNotificationToAdminsOnNewTicket = onDocumentCreated({document: "support_tickets/{ticketId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;
      const t = snap.data() || {};
      const subject = (t.subject || t.title || "استفسار جديد").toString().slice(0, 60);
      await queuePush(
          "ADMIN_BROADCAST",
          "تذكرة دعم جديدة 🎫",
          `فتح عميل تذكرة دعم جديدة: ${subject}`,
          "admin_new_ticket", {ticketId: event.params.ticketId}, ["orders_manager"]);
      return null;
    });

// 1.5 Notify Admins on New Order (Services)
exports.sendNotificationToAdminsOnNewOrder = onDocumentWritten({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before && change.before.exists ? change.before.data() : null;
      const after = change.after && change.after.exists ? change.after.data() : null;
      if (!after) return null; // حذف

      // نُشعِر الإدارة عند **تأكيد الدفع** لا عند الإنشاء. طلبات البطاقة تُنشأ
      // is_paid=false ثم يفتح العميل شاشة البطاقة — فكان التنبيه يصل الإدارة والعميل
      // لم يدفع بعد (وقد يهجر الدفع)، فتُغرَق بطلبات وهمية. الآن: طلبٌ مدفوع فعلاً فقط.
      const becamePaid =
        after.is_paid === true && (!before || before.is_paid !== true);
      if (!becamePaid) return null;

      const orderId = event.params.orderId;
      // زيارات الاشتراك تُنشأ دفعةً واحدة (باقة = عدة طلبات) فتُغرِق الإدارة؛ إشعار
      // «عقد اشتراك جديد» عند إنشاء العقد يكفي — نكتم إشعار كل زيارة على حدة.
      if (after.contract_id) return null;

      const displayCode = after.code || orderId.substring(0, 6);
      // عبر ADMIN_BROADCAST: يكتب admin_notifications (لوحة الويب) + FCM حسب الدور.
      await queuePush(
          "ADMIN_BROADCAST",
          "طلب خدمات جديد! 🚨",
          `وصلك طلب تنظيف جديد مدفوع من العميل. رقم الطلب: ${displayCode}`,
          "new_order_admin", {orderId: orderId}, ["orders_manager"]);
      return null;
    });

// 1.6 Notify Admins on New Store Order
exports.sendNotificationToAdminsOnNewStoreOrder = onDocumentWritten({document: "store_orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before && change.before.exists ? change.before.data() : null;
      const after = change.after && change.after.exists ? change.after.data() : null;
      if (!after) return null; // حذف

      // نُشعِر الإدارة عند **تأكيد الدفع** لا عند الإنشاء (كطلبات الخدمات — 490e166):
      // طلب متجر الشركات يُنشأ awaiting_payment قبل الدفع، فكان الإشعار والإيميل يصلان
      // الإدارة قبل أن يدفع العميل (وقد يهجر). الآن: طلبٌ مدفوع فعلاً فقط.
      const becamePaid =
        after.is_paid === true && (!before || before.is_paid !== true);
      if (!becamePaid) return null;

      const displayCode = after.code || event.params.orderId.substring(0, 6);
      // بيانات الطلب في الإيميل والإشعار (طلبها المالك): العميل، المبلغ، الأصناف.
      const items = Array.isArray(after.items) ? after.items : [];
      const itemsLine = items
          .map((it) => `${(it && it.name) || "منتج"} ×${(it && it.quantity) || 1}`)
          .join("، ");
      const total = Number(after.total_amount || after.final_amount || 0);
      const clientName = after.client_name || "عميل";
      const body = `طلب متجر مدفوع من ${clientName} بقيمة ${total.toFixed(2)} ر.س` +
        `${items.length ? ` — ${items.length} صنف: ${itemsLine}` : ""}. رقم الطلب: ${displayCode}`;

      // عبر ADMIN_BROADCAST: يكتب admin_notifications (تراها لوحة الويب لحظيّاً) + FCM
      // حسب الدور + إيميل لبريد الإدارة (نوع new_store_order_admin ضمن wantsEmail).
      await queuePush(
          "ADMIN_BROADCAST",
          "طلب متجر مدفوع! 🛒",
          body,
          "new_store_order_admin", {orderId: event.params.orderId}, ["orders_manager"]);
      return null;
    });

// 1.7 Notify Admins on New Maintenance Request
exports.sendNotificationToAdminsOnNewMaintenance = onDocumentCreated({document: "maintenance_requests/{requestId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      // عبر ADMIN_BROADCAST: يكتب admin_notifications (لوحة الويب) + FCM حسب الدور —
      // كان يرسل لموضوع "admins" فقط فلا يصل لوحة الويب فتبقى طلبات الصيانة دون متابعة.
      await queuePush(
          "ADMIN_BROADCAST",
          "طلب صيانة جديد! 🛠️",
          "وصلك طلب صيانة جديد من عميل ينتظر عرض السعر.",
          "new_maintenance_admin", {requestId: event.params.requestId}, ["orders_manager"]);
      return null;
    });

// 1.8 Notify Admins on New Contract (Pending Approval)
exports.sendNotificationToAdminsOnNewContract = onDocumentCreated({document: "contracts/{contractId}", cpu: 0.083},
    async (event) => {
      if (!event.data) return null;
      // لا نُشعِر الإدارة عند إنشاء العقد (لا دفع مؤكّد ولا زيارات بعد). الإشعار الإداري
      // الموحّد — بجدول كل الزيارات — يُرسَل مرة واحدة من activateContractOnPaid بعد تأكيد
      // الدفع وتوليد الزيارات. هذا يستبدل إشعاراً مبكّراً بلا تفاصيل + إشعاراً لكل زيارة.
      return null;
    });

// 2. Notify driver/client when order status changes
exports.sendNotificationOnOrderStatusChange = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;

      const beforeData = change.before.data();
      const afterData = change.after.data();
      const orderId = event.params.orderId;

      if (beforeData.status === afterData.status) return null;

      let targetUserId = null;
      let title = "تحديث على طلبكِ";
      let body = "تغيّرت حالة طلبكِ.";

      const greet = _clientGreeting(afterData);

      // FIX: field is `client_id` (snake_case) not `clientId`
      if (afterData.status === "accepted") {
        targetUserId = afterData.client_id;
        title = "تم قبول طلبكِ 🚚";
        body = `${greet}فريق زيارة في طريقه إليكِ.`;
      } else if (afterData.status === "arrived") {
        targetUserId = afterData.client_id;
        title = "وصل فريقكِ 🏠";
        body = `${greet}فريق زيارة عند بابكِ الآن — يسعدنا استقبالكِ ✨`;
      } else if (afterData.status === "scheduled") {
        // المسرحية (18 طلباً): 12 طلباً أُسنِدت والعميل لم يسمع حرفاً — لا فرع
        // لتأكيد الحجز إطلاقاً. السائق يُشعَر (notifyDriverOnAssignment) والعميل لا.
        // زيارات الاشتراك تُولَّد وتُسنَد دفعةً واحدة (باقة = عدة طلبات) فكان
        // العميل يتلقّى «تم تأكيد حجزكِ» عن **كل** زيارة — يكفيه إشعار الملخّص
        // الواحد من مسار التوليد/التفعيل، فنكتم زيارة العقد هنا.
        if (!afterData.contract_id) {
          targetUserId = afterData.client_id;
          title = "تم تأكيد حجزكِ 🎉";
          body = `${greet}دفعتكِ مؤكّدة وحُدِّد موعد خدمتكِ — فريق زيارة سيصلكِ في وقته.`;
        }
      } else if (afterData.status === "under_review") {
        targetUserId = afterData.client_id;
        title = "تم استلام طلبكِ 🧾";
        body = `${greet}دفعتكِ مؤكّدة وطلبكِ الآن تحت مراجعة الإدارة.`;
      } else if (afterData.status === "in_progress") {
        targetUserId = afterData.client_id;
        title = "بدأت خدمتكِ 🧽";
        body = `${greet}فريق زيارة يعمل الآن على منزلكِ.`;
      } else if (afterData.status === "completed") {
        targetUserId = afterData.client_id;
        title = "اكتملت خدمتكِ ✨";
        body = `${greet}نتمنّى أن ينال منزلكِ إعجابكِ 🌿 يسعدنا تقييمكِ.`;
      } else if (afterData.status === "cancelled") {
        // لا نُشعر عن إلغاء طلب **غير مدفوع** (سلّة مهجورة يلغيها كرون cancelStaleUnpaidOrders،
        // أو إلغاء لطلب لم يُدفَع) — يبقى targetUserId=null فلا دفعة. يُشعَر فقط عند إلغاء مدفوع.
        if (afterData.cancel_reason !== "unpaid_expired" &&
            afterData.cancelled_by !== "system" &&
            afterData.is_paid === true) {
          targetUserId = afterData.client_id;
          title = "تم إلغاء طلبكِ ⚠️";
          body = `${greet}أُلغي طلبكِ. لأي استفسار نحن بخدمتكِ.`;
        }
      }

      // (#43) مرساة زمنية خادميّة: نضمن start_time عند بدء الخدمة وend_time عند الإكمال
      // حتى للمسارات التي تكتب الحالة مباشرةً بلا مرساة (تغيير حالة إداري مباشر). كتابةٌ
      // مرّة واحدة فقط (لا نطمس القيمة الأولى الحقيقية). حارس الحالة الثابتة (السطر ~181)
      // يمنع إعادة إطلاق المُشغّل من كتابتنا (لا تُغيّر الحالة)، وبقية مُشغّلات orders
      // مشروطة بتغيّر status/is_paid/driver_id فلا يوقظها تحديث زمني صرف. قبل الخروج
      // المبكر لـ targetUserId كي تُرسى الطلبات الإدارية بلا عميل. try/catch: فشل الإرساء
      // لا يُسقط إشعار «بدأت خدمتكِ».
      try {
        if (afterData.status === "in_progress" &&
            !afterData.start_time && !afterData.end_time) {
          await change.after.ref.update({
            start_time: FieldValue.serverTimestamp(),
          });
        } else if (afterData.status === "completed" && !afterData.end_time) {
          await change.after.ref.update({
            end_time: FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        console.error("anchor backfill failed", orderId, e.message);
      }

      if (!targetUserId) return null;

      // (توحيد إشعار الدفع) scheduled/under_review نقلتان تعقبان قلب is_paid
      // مباشرةً (إسناد/ترقية فوريان بعد التأكيد) ونصّاهما «دفعتكِ مؤكّدة» — نفس
      // مضمون دفعة «تم تأكيد دفعتكِ» من مسار verify/webhook. المطالبة الذرّية على
      // الطلب تُبقي دفعة تأكيدٍ واحدة للعميل أيّاً كان المسار الأسبق.
      if ((afterData.status === "scheduled" || afterData.status === "under_review") &&
          !(await _claimPaymentPush("orders", orderId))) {
        return null;
      }

      // سجلّ الإشعارات داخل التطبيق يُكتب **دائماً وأولاً** — كان بعد فحص التوكن
      // وداخل try الإرسال: عميل بلا توكن FCM (ويب/جهاز جديد/رفض الإذن) لم يكن
      // يفقد الدفعة فحسب بل حتى أثرها في صندوق إشعاراته (كشفته المسرحية: صفر
      // إشعارات سيارات لدى عميل الويب).
      await getFirestore().collection("notifications").add({
        userId: targetUserId,
        title: title,
        body: body,
        type: "order_update",
        relatedId: orderId,
        sentAt: FieldValue.serverTimestamp(),
      });

      const tokenDoc = await getFirestore().collection("fcm_tokens")
          .doc(targetUserId).get();
      if (!tokenDoc.exists) return null;

      const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "order_update",
          orderId: orderId,
        },
        token: fcmToken,
      };

      try {
        await getMessaging().send(payload);
        console.log(`Notification sent to ${targetUserId} for order ${orderId}`);
      } catch (error) {
        console.error("Error sending order notification:", error);
      }
      return null;
    });

// 2.5 Notify all available drivers when a new pending order is created
exports.notifyAvailableDriversOnNewOrder = onDocumentCreated({document: "orders/{orderId}", cpu: 0.083},
    async () => {
      // مُعطَّل: التوجيه المباشر يُسنِد الطلب تلقائياً لسائق محدَّد ويُشعره
      // (notifyDriverOnAssignment). بثّ «طلب متاح للجميع — اضغط للقبول» كان يتعارض
      // (يتسابق السائقون على طلب يُسنَد آليّاً فيجدونه scheduled). أُبقيَ no-op.
      return null;
    });

// 2.6 Notify client when their order is cancelled by admin
// ملغاة عمداً: إلغاء الطلب صار يُشعِر العميل عبر sendNotificationOnOrderStatusChange
// (نص مؤنّث + سجل داخل التطبيق). إبقاء هذا المُشغّل كان يرسل إشعاراً ثانياً مذكّراً
// ("طلبك") بلا سجل — تكرار وتعارض مع معيار التأنيث. أُبقيَ كـ no-op لتفادي حذف الدالة.
exports.notifyClientOnOrderCancellation = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (before.status === "cancelled" || after.status !== "cancelled") return null;
      // لا تنبيه عن إلغاء طلب **غير مدفوع** (سلّة مهجورة يلغيها كرون cancelStaleUnpaidOrders
      // بـ cancelled_by='system'، أو إلغاء إداري لطلب لم يُدفَع) — لا مال ولا قيمة للتنبيه،
      // ويمنع سبام الكرون لكل سلّة مهجورة (تنبيه إدارة + دفعتَي عميل كل 15 دقيقة).
      if (after.cancel_reason === "unpaid_expired" ||
          after.cancelled_by === "system" || after.is_paid !== true) return null;
      const code = after.code || event.params.orderId;
      const by = after.cancelled_by === "client" ? "العميل" : "الإدارة";
      // تنبيه الإدارة **فقط** (خادميّاً — يحلّ محلّ نداء العميل ADMIN_BROADCAST المحجوب بالحارس).
      // إشعار العميل بالإلغاء يتكفّل به sendNotificationOnOrderStatusChange (مصدر واحد) —
      // أزلنا الدفعة الثانية المكرّرة (كان هذا المُشغّل no-op سابقاً تحديداً لتفاديها).
      await queuePush("ADMIN_BROADCAST", "تم إلغاء طلب ⚠️",
          `أُلغي الطلب #${code} بواسطة ${by}.`,
          "admin_order_alert",
          {orderId: event.params.orderId, needs_refund: String(after.needs_refund === true)},
          ["orders_manager"]).catch(() => {});
      return null;
    });

// (#3) تنبيه الإدارة بالتقييم المنخفض خادميّاً — كان يُرسله العميل عبر ADMIN_BROADCAST
// (يُحجَب الآن بالحارس). يُطلَق مرّة واحدة عند ظهور تقييم <= 2 (before.rating غائب).
exports.notifyAdminOnLowRating = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const r = Number(after.rating);
      if (isNaN(r) || r > 2) return null;
      if (before.rating != null) return null; // سبق التقييم — لا تكرار
      const code = after.code || event.params.orderId;
      const reason = after.rating_reason ? ` — ${after.rating_reason}` : "";
      await queuePush("ADMIN_BROADCAST", "تحذير: تقييم منخفض ⚠️",
          `تقييم ${r} نجوم على الطلب #${code}${reason}. يرجى المراجعة.`,
          "admin_low_rating", {orderId: event.params.orderId},
          ["orders_manager"]).catch(() => {});
      return null;
    });

// مُجمّع تقييم السائق: العميل يكتب rating على الطلب فقط (القواعد تمنعه من مستند
// السائق)، ولم يكن ثمة أي مُجمّع — rating_avg/rating_count على السائق لا تتراكم
// أبداً وبطاقات «التقييم 5» تعرض قيمة البذر الثابتة. يعمل مرة واحدة لكل طلب
// (before.rating غائب) بمعاملة ذرّية على مستند السائق.
exports.aggregateDriverRating = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const r = Number(after.rating);
      if (isNaN(r) || r < 1 || r > 5) return null;
      if (before.rating != null) return null; // تقييم سابق — لا تكرار
      const driverId = after.driver_id;
      if (!driverId) return null;
      const db = getFirestore();
      // **المنطقُ انتقلَ إلى `rewards.aggregateRating`.** كان هنا و`catch`ه
      // سطرَ `console.error` وحدَه، والمتوسّطُ **تزايديٌّ** لا يُعادُ حسابُه
      // من كلِّ التقييمات — فمعامَلةٌ تَفشلُ تَعني تقييماً ضائعاً من المتوسّطِ
      // ومن `rating_count` إلى الأبد، وذلك العدّادُ هو مُميِّزُ «لا رقمَ قبل
      // أن نعرفه» وأساسُ ترتيبِ شاشةِ الأداء. ومانعُ التكرارِ صارَ **علَماً
      // على المستند** لا شرطاً على الحدث، فالإعادةُ من المكنسةِ آمنة.
      const orderId = event.params.orderId;
      await rewards.aggregateRating(db, {
        orderRef: db.collection("orders").doc(orderId),
        orderId,
        driverId,
        rating: r,
        code: after.code || orderId,
      }, queuePush);
      return null;
    });

// إشعار عميل المتجر بتغيّر حالة طلبه (تحضير/شحن/تسليم) — كانت التغييرات صامتة،
// فلا يعرف العميل مصير طلبه بعد الدفع حتى يصله.
exports.notifyClientOnStoreOrderStatus = onDocumentUpdated({document: "store_orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      // (المتجر المباشر) أكّد الخادم الدفع (webhook/verify/reconcile) بينما مات
      // تطبيق العميل قبل كتابة under_review؟ رقِّ الحالة خادمياً كي لا يبقى طلب
      // مدفوع بمظهر «بانتظار الدفع» — وكتابتنا تعيد إطلاق المشغّل فيُشعَر العميل.
      if (after.is_paid === true && before.is_paid !== true &&
          after.status === "awaiting_payment") {
        await change.after.ref.update({
          status: "under_review",
          updated_at: FieldValue.serverTimestamp(),
        });
        return null;
      }
      if (before.status === after.status) return null;
      const clientId = after.client_id;
      if (!clientId) return null;
      const map = {
        // اعتماد الطلب (من تطبيق الأدمن أو لوحة الويب) → اطلب من العميل إتمام الدفع.
        // المصدر الوحيد للإشعار: كانت لوحة الويب تعتمد بصمت بلا تنبيه للعميل.
        approved: {t: "تم اعتماد طلبكِ 💳", b: "اعتمدت الإدارة طلبكِ من المتجر — يرجى إتمام الدفع لتجهيزه."},
        under_review: {t: "تم استلام طلبكِ 🧾", b: "دفعتكِ مؤكّدة وطلبكِ الآن تحت مراجعة الإدارة."},
        delivering: {t: "طلبكِ في الطريق 🚚", b: "جاري توصيل طلبكِ من المتجر إليكِ."},
        processing: {t: "جارٍ تجهيز طلبكِ 📦", b: "بدأنا تجهيز طلبكِ من المتجر."},
        preparing: {t: "جارٍ تجهيز طلبكِ 📦", b: "بدأنا تجهيز طلبكِ من المتجر."},
        shipped: {t: "طلبكِ في الطريق 🚚", b: "شُحن طلبكِ من المتجر وهو في طريقه إليكِ."},
        out_for_delivery: {t: "طلبكِ قارب الوصول 🚚", b: "خرج طلبكِ للتوصيل — يصلكِ قريباً."},
        delivered: {t: "تم تسليم طلبكِ ✅", b: "سُلّم طلبكِ من المتجر. نتمنى لكِ تجربة سعيدة 🌿"},
        completed: {t: "اكتمل طلبكِ ✅", b: "اكتمل طلبكِ من المتجر. شكراً لكِ 🌿"},
        cancelled: {t: "تم إلغاء طلب المتجر ⚠️", b: "أُلغي طلبكِ من المتجر."},
      };
      const m = map[after.status];
      if (!m) return null;
      const code = after.code || event.params.orderId.substring(0, 6);
      // (توحيد إشعار الدفع) under_review صدى تأكيد الدفع (يرقّيها العميل/الخادم فور
      // القلب) — تشارك مطالبة payment_push_sent كي لا تتكرّر دفعتها مع «تم تأكيد
      // دفعتكِ» من مسار verify/webhook. عند خسارة السباق يُكتم **الدفع فقط**:
      // النوع email يُبقي الإيميل (طلب المالك) وسجلّ الوارد. بقية النقلات إدارية
      // لاحقة فلا تُمسّ.
      let pushType = "store_update";
      if (after.status === "under_review" &&
          !(await _claimPaymentPush("store_orders", event.params.orderId))) {
        pushType = "email";
      }
      // إيميل + إشعار لكل نقلة (طلبها المالك): تحت المراجعة ⇒ جاري التوصيل ⇒ تم التسليم.
      // بريد العميل من الطلب (يُكتب عند الإنشاء) أو من users كاحتياط للطلبات القديمة؛
      // النوع store_update ضمن wantsEmail فيُرسَل الإيميل مع الإشعار.
      let clientEmail = after.client_email;
      if (!clientEmail) {
        try {
          const u = await getFirestore().collection("users").doc(clientId).get();
          clientEmail = u.exists ? (u.data() && u.data().email) : null;
        } catch { clientEmail = null; }
      }
      await queuePush(clientId, m.t, `${m.b} (#${code})`, pushType,
          {orderId: event.params.orderId}, null, clientEmail || undefined);
      return null;
    });

// إشعار العميل عند رفض طلب الصيانة — لم يكن يُشعَر إطلاقاً. قاصر على 'rejected' فقط كي
// لا يتضاعف مع إشعار عرض السعر (waiting_payment) الذي يُرسله تطبيق الأدمن/لوحة الويب مباشرةً.
exports.notifyClientOnMaintenanceRejected = onDocumentUpdated(
    {document: "maintenance_requests/{reqId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (before.status === after.status || after.status !== "rejected") return null;
      const uid = after.userId;
      if (!uid) return null;
      const code = after.requestId || after.code || event.params.reqId.substring(0, 6);
      await queuePush(uid, "بخصوص طلب الصيانة ⚠️",
          `نعتذر، تعذّر قبول طلب الصيانة رقم (#${code}). يمكنك التواصل مع الدعم أو إنشاء طلب جديد.`,
          "maintenance_rejected", {requestId: event.params.reqId});
      return null;
    });

/**
 * مُرشِّحُ الدورِ لجمهورِ البثّ — **قاعدةٌ واحدةٌ لمجموعتَين.**
 *
 * كانت مكتوبةً مرّتَين في `_deliverBroadcast` على بُعدِ ثمانيةِ أسطر،
 * **والنسختانِ افترقتا (2026-10-07):** استعلامُ `fcm_tokens` يَحملُ ثلاثةَ
 * فروعٍ (`clients`/`drivers`/`admins`) واستعلامُ `users` — الذي يُكتَبُ منه
 * صندوقُ الإشعاراتِ داخلَ التطبيق — **فرعَين فقط**. فـ`admins` كان يَسقطُ
 * إلى «بلا مُرشِّح»: الدفعةُ تَصِلُ أجهزةَ الإدارةِ وحدَها (صحيح) وسطرُ
 * الصندوقِ يُكتَبُ **لكلِّ مستخدمٍ في النظام** — كلِّ عميلةٍ وكلِّ سائق.
 *
 * **كامنٌ لا حيٌّ، ويُقالُ بحدِّه:** `admins` قيمةٌ لا يُنتجُها أيُّ مُحرِّرٍ
 * اليومَ (ثلاثةُ أزرارٍ في تطبيقِ الإدارةِ وثلاثةٌ في اللوحة)، فمَسلكُها
 * كتابةٌ بيدٍ في الكونسولِ أو زرٌّ رابعٌ يُضاف — وذاك قرارُ منتَجٍ مرفوعٌ
 * للمالكِ أصلاً. فالوحدةُ تَسدُّها قبلَ أن تُفتَح.
 *
 * و«الجميع» وما لا يُعرَفُ: بلا مُرشِّح — والفالُّ مُعلَنٌ ومُسجَّلٌ في
 * `_deliverBroadcast` نفسِه.
 *
 * @param {FirebaseFirestore.Query} query استعلامُ المجموعة.
 * @param {string} target جمهورُ البثِّ من `notifications_log.target`.
 * @return {FirebaseFirestore.Query} الاستعلامُ بعدَ المُرشِّح.
 */
function _applyAudienceRoleFilter(query, target) {
  if (target === "clients") return query.where("role", "==", "client");
  if (target === "drivers") return query.where("role", "==", "driver");
  if (target === "admins") {
    return query.where("role", "in", ["admin", "super_admin"]);
  }
  return query;
}

/**
 * Deliver a broadcast: push to the target topic + fan out to the `notifications`
 * collection for in-app viewing. Shared by the create-trigger and the scheduler.
 * @param {FirebaseFirestore.DocumentReference} docRef notifications_log doc ref.
 * @param {Object} data Notification payload (title, body, target).
 * @return {Promise<void>}
 */
/** من أوقف «العروض والتسويق» في تفضيلاته (users.notification_prefs.marketing=false). */
async function _marketingOptOutUids() {
  const snap = await getFirestore().collection("users")
      .where("notification_prefs.marketing", "==", false).get();
  return new Set(snap.docs.map((d) => d.id));
}

async function _deliverBroadcast(docRef, data) {
  const {title, body, target = "all"} = data;
  // تفضيلات التنبيهات: البثّ التسويقي لا يصل (بوش ولا صندوق داخل التطبيق) لمن أوقف
  // «العروض والتسويق»؛ التشغيلي (operational=true) يصل كل المستهدفين.
  const optOut = isMarketingBroadcast(data) ? await _marketingOptOutUids() : new Set();
  const payload = {
    notification: {title, body},
    data: {click_action: "FLUTTER_NOTIFICATION_CLICK", type: "global_broadcast"},
  };
  try {
    // إرسال لرموز الأجهزة مباشرةً بدل topic — أوثق بكثير: لا يعتمد على اشتراك المواضيع
    // ولا على تأخّر انتشارها (كان سبب عدم وصول البثّ لبعض الأجهزة رغم تسجيلها).
    // **الفالُّ إلى «الجميع» قرارٌ مُعلَنٌ لا مصادفة (2026-10-07).** كانت
    // الشاشةُ تُحوّلُ `all_users` (اسمُ موضوعِ FCM) إلى `all` في مسارَيها
    // الفوريِّ والمنبثقِ **ولا تُحوّلُ في المجدول**، فالحقلُ يَحملُ
    // التهجئتَين. والسلسلةُ أدناه كانت تَترُكُ ما لا تَعرفُه بلا مُرشِّحٍ —
    // أي «الجميع»، وهو المقصودُ — لكنْ بالفالِّ لا بالقرار: فرعٌ رابعٌ أو
    // تحقّقٌ هنا كان سيُحوّلُ كلَّ بثٍّ مجدولٍ «للجميع» إلى جمهورٍ آخرَ
    // بصمت. الكاتبُ أُصلِحَ (`utils/broadcast_target.dart`)، ومستنداتُ
    // الإنتاجِ القائمةُ تَحملُ `all_users` فيَبقى القبولُ — **مُسجَّلاً**.
    const KNOWN_TARGETS = ["all", "clients", "drivers", "admins"];
    if (!KNOWN_TARGETS.includes(target)) {
      console.warn(
          `broadcast: unknown target "${target}" -> delivering to everyone`);
    }
    const tokQuery = _applyAudienceRoleFilter(
        getFirestore().collection("fcm_tokens"), target);
    const tokSnap = await tokQuery.get();
    // fcm_tokens معرّفها uid (القواعد: request.auth.uid == tokenId) — فالإسقاط بالمعرّف.
    const uniqTokens = [...new Set(
        excludeOptedOut(tokSnap.docs, optOut)
            .map((d) => d.data().token || d.data().fcmToken).filter(Boolean))];
    // خريطةُ رمزٍ ← مرجعِ مستندِه. **تنظيفُ الرموزِ الميتةِ كان ميّتاً**:
    // كان يَستعلمُ `where("token","==",bad)` والعميلُ يَكتبُ الحقلَ
    // `fcmToken` وحدَه (بتعليقٍ صريحٍ في `notification_service`: «Backend
    // expects 'fcmToken', not 'token'») ولا شيءَ في المستودعِ يَكتبُ
    // `token` — فالاستعلامُ لا يُطابقُ مستنداً أبداً، والسطرُ يَطبعُ
    // `cleaned=N` لِـN لم يُحذَف منها شيء. والتعليقُ أعلاه يَقولُ الصوابَ
    // منذ البداية: «فالإسقاطُ بالمعرّف».
    const refByToken = new Map();
    for (const d of excludeOptedOut(tokSnap.docs, optOut)) {
      const t = d.data().token || d.data().fcmToken;
      if (t && !refByToken.has(t)) refByToken.set(t, d.ref);
    }
    let sent = 0; let failed = 0; const invalid = [];
    for (let i = 0; i < uniqTokens.length; i += 500) {
      const chunk = uniqTokens.slice(i, i + 500);
      const resp = await getMessaging().sendEachForMulticast({
        ...payload,
        tokens: chunk,
        apns: {payload: {aps: {sound: "default"}}},
      });
      sent += resp.successCount; failed += resp.failureCount;
      resp.responses.forEach((r, idx) => {
        if (!r.success) {
          const code = r.error && r.error.code;
          if (code === "messaging/registration-token-not-registered" ||
              code === "messaging/invalid-registration-token") invalid.push(chunk[idx]);
        }
      });
    }
    // نظّف الرموز الميتة (أجهزة أُلغي تثبيتها) كي لا تتضخّم المجموعة
    let cleaned = 0;
    for (const bad of invalid) {
      const ref = refByToken.get(bad);
      if (!ref) continue;
      await ref.delete().then(() => { cleaned++; }).catch(() => {});
    }
    // `cleaned` صارَ المحذوفَ فعلاً لا عددَ الرموزِ الميتة — الرقمُ كان دعوى.
    console.log(`broadcast(${target}) tokens: sent=${sent} failed=${failed} invalid=${invalid.length} cleaned=${cleaned} optOut=${optOut.size}`);

    // نفسُ القاعدةِ لا نسخةٌ ثانية: هذه هي التي أسقطَت `admins` فكُتبَ
    // سطرُ الصندوقِ لكلِّ مستخدمٍ في النظام.
    const query = _applyAudienceRoleFilter(
        getFirestore().collection("users"), target);
    const usersSnap = await query.get();
    let batch = getFirestore().batch();
    let count = 0;
    for (const userDoc of excludeOptedOut(usersSnap.docs, optOut)) {
      const notifRef = getFirestore().collection("notifications").doc();
      batch.set(notifRef, {
        userId: userDoc.id, title, body,
        type: "global_broadcast", isRead: false,
        sentAt: FieldValue.serverTimestamp(),
      });
      count++;
      if (count === 400) {
        await batch.commit();
        batch = getFirestore().batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    await docRef.update({
      processed: true, status: "sent",
      processed_at: FieldValue.serverTimestamp(),
      // المجدولُ يُكتَبُ بـ`sent_at: null` (الغيابُ يُخرِجُه من `orderBy`
      // كلِّه) فيُملأُ هنا بلحظةِ الإرسالِ الفعليّ. وما يَحملُ طابعاً سلفاً
      // لا يُلمَس: الفوريُّ أُرسِلَ لحظةَ كتابتِه.
      ...(data.sent_at ? {} : {sent_at: FieldValue.serverTimestamp()}),
    });
    console.log(`Notification delivered for target: ${target}`);
  } catch (error) {
    console.error("Error sending push notification:", error);
    await docRef.update({
      processed: true, status: "error",
      error: error.message || "Unknown error",
      processed_at: FieldValue.serverTimestamp(),
    });
  }
}

// 3. Unified Global Notification Trigger — delivers immediately, but DEFERS any
// notification scheduled for the future to releaseScheduledNotifications (it used
// to fire scheduled campaigns instantly).
exports.onNotificationCreated = onDocumentCreated({document: "notifications_log/{id}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newValue = snap.data();
      if (!newValue || !newValue.title || !newValue.body) {
        console.log("Missing data in notification log doc:", event.params.id);
        return;
      }

      // المنبثق (popup) نافذة داخل التطبيق فقط (يعرضها popup_service عند فتح التطبيق) —
      // لا يُبثّ Push ولا يملأ مركز التنبيهات. بدون هذا الحارس كان بثّ «إعلان منبثق»
      // يُطلق ثلاث قنوات دفعةً واحدة (push + مركز تنبيهات + منبثق).
      if (newValue.type === "popup") return;

      const sched = newValue.scheduled_at;
      const isFuture = sched && typeof sched.toMillis === "function" &&
        sched.toMillis() > Date.now();
      if (newValue.status === "scheduled" || isFuture) {
        // تنفيذ دقيق باللحظة المختارة عبر Cloud Task (بدل انتظار فحص الـcron). الـcron
        // كل دقيقة يبقى شبكة أمان لأي مهمّة تفشل/تُفقد أو مجدولة لأبعد من حدّ Cloud Tasks.
        try {
          if (isFuture && sched.toMillis() - Date.now() < 29 * 24 * 60 * 60 * 1000) {
            await getFunctions().taskQueue("deliverScheduledNotification").enqueue(
                {docId: event.params.id},
                {scheduleTime: new Date(sched.toMillis())});
            console.log(`Exact Cloud Task queued for ${event.params.id} at ${sched.toDate().toISOString()}`);
          }
        } catch (e) {
          console.error(`enqueue failed for ${event.params.id} — cron will cover:`, e.message);
        }
        return;
      }

      await _deliverBroadcast(snap.ref, newValue);
    });

// 3a. تسليم دقيق في اللحظة المختارة — تُشغّله Cloud Tasks عند حلول scheduled_at.
// يستخدم نفس مطالبة الحالة الذرّية (scheduled→sending) فلا يتكرّر مع الـcron الاحتياطي.
exports.deliverScheduledNotification = onTaskDispatched(
    {retryConfig: {maxAttempts: 3, minBackoffSeconds: 15}, rateLimits: {maxConcurrentDispatches: 5}, cpu: 0.083},
    async (req) => {
      const docId = req.data && req.data.docId;
      if (!docId) return;
      const db = getFirestore();
      const docRef = db.collection("notifications_log").doc(docId);
      const claimed = await db.runTransaction(async (tx) => {
        const s = await tx.get(docRef);
        const d = s.data() || {};
        if (d.status !== "scheduled" || d.processed === true) return null;
        tx.update(docRef, {status: "sending"});
        return d;
      });
      if (claimed) await _deliverBroadcast(docRef, claimed);
    });

// 3b. Release scheduled broadcasts whose time has come.
exports.releaseScheduledNotifications = onSchedule({schedule: "every 1 minutes", cpu: 0.083},
    async () => {
      const db = getFirestore();
      const now = Timestamp.now();
      // **الاستعلامُ يَسألُ ما تَسألُه المطالبةُ أدناه.** كان مساواةً صفراً
      // ومدًى واحداً (`scheduled_at <= now`) و«الحالةُ تُصفّى في الكود» — ومستندُ
      // بثٍّ **مُرسَلٍ** يَحتفظُ بـ`scheduled_at` ماضيةً فيَظلُّ مطابقاً للأبد.
      // والترتيبُ الضمنيُّ لاستعلامِ مدًى هو ذلك الحقلُ تصاعديّاً، فنافذةُ
      // الخمسين تَمتلئُ بأقدمِ خمسينَ بثٍّ مُرسَلٍ ولا يَبلغُها بثٌّ جديدٌ حلَّ
      // موعدُه: المطالبةُ تَنكُلُ عن كلِّ واحدٍ منها (`status !== "scheduled"`)
      // والجديدُ لا يُقرأُ أصلاً. ولأنّ `onNotificationCreated` **لا** يُجدول
      // مهمّةَ Cloud Task لما بَعُد عن 29 يوماً، فهذا الـcron هو مَساره
      // الوحيدُ لا شبكةَ أمانِه — فالبثُّ لا يُرسَل، بلا أثرٍ في أيِّ مكان.
      // (`scheduled_at: null` — مسارُ البثِّ الفوريِّ في اللوحة — لا يُطابق
      // `<=` أصلاً: مُختبَرٌ على المُحاكي، كما لا يُطابقُه غيابُ الحقل.)
      const due = await db.collection("notifications_log")
          .where("status", "==", "scheduled")
          .where("scheduled_at", "<=", now).limit(50).get();
      for (const doc of due.docs) {
        // مطالبة ذرّية قبل التسليم: نقلب scheduled→sending داخل معامَلة، فلو تداخل
        // تشغيلان (بثّ بطيء يتجاوز الدقائق العشر) لا يُبثّ الإشعار لكل المستخدمين مرّتين.
        const claimed = await db.runTransaction(async (tx) => {
          const s = await tx.get(doc.ref);
          const d = s.data() || {};
          if (d.status !== "scheduled" || d.processed === true) return null;
          tx.update(doc.ref, {status: "sending"});
          return d;
        });
        if (claimed) {
          await _deliverBroadcast(doc.ref, claimed);
        }
      }
      return null;
    });

// 4. Callable function for direct sending (admin only, validated)
exports.manualSendNotification = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }

  const {title, body, target = "all"} = request.data;

  if (!title || typeof title !== "string" || title.trim().length === 0) {
    throw new HttpsError("invalid-argument", "العنوان مطلوب");
  }
  if (!body || typeof body !== "string" || body.trim().length === 0) {
    throw new HttpsError("invalid-argument", "نص الإشعار مطلوب");
  }
  const validTargets = ["all", "drivers", "clients", "admins"];
  if (!validTargets.includes(target)) {
    throw new HttpsError("invalid-argument", "هدف الإشعار غير صالح");
  }

  const userDoc = await getFirestore()
      .collection("users").doc(request.auth.uid).get();
  const role = userDoc.exists ? userDoc.data()?.role : null;
  const adminRoles = [
    "super_admin", "admin", "orders_manager",
    "accountant_admin", "marketing_admin",
  ];
  if (!adminRoles.includes(role)) {
    throw new HttpsError("permission-denied", "غير مصرح بهذه العملية");
  }

  const payload = {
    notification: {title, body},
    data: {click_action: "FLUTTER_NOTIFICATION_CLICK"},
  };

  try {
    const topic = target === "all" ? "all_users" : target;
    await getMessaging().send({...payload, topic});
    return {success: true, topic, sentAt: new Date().toISOString()};
  } catch (error) {
    throw new HttpsError("internal", error.message);
  }
});

// 4.5 Create Tamara checkout session (server-side — token never exposed to client)
/**
 * **مالكُ المستندِ المدفوعِ هو المُنادي — وإلّا `permission-denied`.**
 *
 * السؤالُ كان مكتوباً بثلاثةِ أشكالٍ في أربعةِ مساراتٍ ماليّة، و**مفقوداً في
 * الرابع**: `payWithWallet` (`client_id !== uid`)، `payContractWithWallet`
 * (`c.userId !== uid`)، `verifyMoyasarPayment` (`client_id || userId`)،
 * و`createTamaraCheckout` **بلا أيِّ فحصٍ للملكيّة** — وتعليقُ قراءتِه يَقول
 * «prevent client tampering»، وهو يَمنعُ تلاعبَ **المبلغِ** لا الملكيّة.
 *
 * فأيُّ مسجَّلٍ يَملكُ معرّفَ طلبٍ — سائقٌ يَرى طلباتَه المُسنَدةَ مثلاً —
 * كان يُنشئُ جلسةَ تمارا على طلبِ عميلةٍ أخرى: صفحةُ الدفعِ تَعرضُ المبلغَ
 * واسمَ الخدمة، و**بريدُ العميلةِ** يُرسَلُ إلى تمارا كـ`consumer.email`؛
 * و`order_reference_id` معرّفُ الطلبِ نفسُه فدفعُه يَقلبُ **طلبَ غيرِه**
 * مدفوعاً (`_tamaraFlipPaid` بلا فحصِ مبلغٍ أصلاً). ولا فحصَ `is_paid` كذلك،
 * فجلسةٌ ثانيةٌ على طلبٍ مدفوعٍ = خصمٌ مكرَّرٌ واستردادُه يدويّ.
 *
 * التسامحُ مع غيابِ المالكِ مقصودٌ ومنقولٌ عن `verifyMoyasarPayment` بعينِه:
 * ذاك المسارُ **يُنشئُ** الطلبَ من بيانات الدفعِ (مسارُ Apple Pay) فقد يَقرأُ
 * مستنداً لم يُكتَبْ له مالكٌ بعد. ولا مسارَ في المستودعِ يُنشئُ طلباً بلا
 * `client_id`، فالفرقُ نظريّ — والاتّساقُ مع الشقيقِ أولى من تباينٍ جديد.
 * و`payContractWithWallet` يَبقى **أشدَّ** (غيابُ `userId` يَرفض) لأنّ العقودَ
 * لا تُنشَأُ خادميّاً بلا مالك، وهو قرارٌ مكتوبٌ لا سهو.
 *
 * @param {Object} data بياناتُ المستند (طلب/طلبِ متجر/عقد).
 * @param {string} uid معرّفُ المُنادي.
 * @param {string} message رسالةُ الرفضِ بصيغةِ المسار.
 */
function _assertDocOwner(data, uid, message) {
  const owner = (data && (data.client_id || data.userId)) || null;
  if (owner && owner !== uid) {
    throw new HttpsError("permission-denied", message);
  }
}

exports.createTamaraCheckout = onCall(
    {secrets: ["TAMARA_API_TOKEN"], cpu: 0.25},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
      }

      const {orderId, customerPhone, customerName} = request.data;

      if (!orderId || !customerPhone || !customerName) {
        throw new HttpsError("invalid-argument", "بيانات الطلب ناقصة");
      }

      // Fetch the true price + info from Firestore (prevent client tampering)
      let trueAmount = null;
      let info = {};
      const orderDoc = await getFirestore().collection("orders").doc(orderId).get();
      if (orderDoc.exists) {
        info = orderDoc.data();
        trueAmount = Number(info.amount);
      } else {
        const storeOrderDoc = await getFirestore().collection("store_orders").doc(orderId).get();
        if (storeOrderDoc.exists) {
          info = storeOrderDoc.data();
          // final_amount = السعر النهائي بعد تعديل الإدارة (رسوم توصيل مثلاً). كان
          // Tamara تشحن total_amount (سعر السلة) فتُحصّل مبلغاً مختلفاً عمّا وافق عليه العميل.
          trueAmount = Number(info.final_amount ?? info.total_amount);
        } else {
          // العقد/الاشتراك: يُمرَّر معرّفه كـ orderId ويعيش في contracts (planPrice شامل
          // الضريبة). بدون هذا الفرع كان دفع الاشتراك عبر تمارا يفشل بـ not-found — بينما
          // verifyMoyasarPayment و tamaraWebhook يعالجان العقود أصلاً (كان تناقضاً).
          const contractDoc = await getFirestore().collection("contracts").doc(orderId).get();
          if (contractDoc.exists) {
            info = contractDoc.data();
            trueAmount = Number(info.planPrice);
          }
        }
      }

      if (trueAmount === null || isNaN(trueAmount) || trueAmount <= 0) {
        throw new HttpsError("not-found", "تعذّر العثور على الطلب أو أنّ مبلغه غير صالح — أعيدي المحاولة");
      }

      // الملكيّةُ: كان هذا المسارُ **الوحيدَ** من أربعةٍ ماليّةٍ بلا فحصٍ لها.
      _assertDocOwner(info, request.auth.uid,
          "لا يمكن بدء دفع طلب مستخدم آخر");
      // ومدفوعٌ سلفاً لا يُفتَحُ له جلسةٌ ثانية: خصمٌ مكرَّرٌ واستردادُه يدويّ.
      if (info.is_paid === true) {
        throw new HttpsError("failed-precondition", "هذا الطلب مدفوعٌ بالفعل");
      }

      const amount = trueAmount;
      const token = tamaraApiToken.value();
      const phone = customerPhone.startsWith("+") ?
        customerPhone : `+966${customerPhone}`;
      // حقول تمارا الإلزامية: اسم مقسّم + بريد + مدينة + عناصر + عنوان شحن.
      const parts = String(customerName).trim().split(/\s+/);
      const firstName = parts[0] || "عميل";
      const lastName = parts.slice(1).join(" ") || "زيارة";
      const email = info.client_email || `${orderId}@zyiarah.com`;
      const city = info.zone_name || "جازان";
      const money = (a) => ({amount: a, currency: "SAR"});

      try {
        // الحِمل يُبنى هنا (منطق عمل)، والنقل في tamara_api.
        const res = await tamara.checkout(token, {
            order_reference_id: orderId,
            order_number: info.code || orderId,
            total_amount: money(amount),
            tax_amount: money(0),
            shipping_amount: money(0),
            country_code: "SA",
            locale: "ar_SA",
            payment_type: "PAY_BY_INSTALMENTS",
            instalments: 4,
            items: [{
              reference_id: orderId,
              type: "Service",
              name: info.service_name || info.service_type || "خدمة زيارة",
              sku: "ZYIARAH-SERVICE",
              quantity: 1,
              unit_price: money(amount),
              total_amount: money(amount),
            }],
            consumer: {
              first_name: firstName,
              last_name: lastName,
              phone_number: phone,
              email: email,
            },
            shipping_address: {
              first_name: firstName,
              last_name: lastName,
              line1: city,
              city: city,
              country_code: "SA",
              phone_number: phone,
            },
            merchant_url: {
              success: "https://zyiarah.com/payment-success",
              failure: "https://zyiarah.com/payment-failure",
              cancel: "https://zyiarah.com/payment-cancel",
              notification: "https://tamarawebhook-slpwb4s3aa-uc.a.run.app",
            },
            description: "خدمات منزلية - مؤسسة معاذ يحي محمد المالكي",
        });

        if (!res.ok) {
          // كان `await response.text()`؛ صار الجسم مُحلَّلاً متسامحاً فيُسجَّل
          // ككائن — نفس المعلومة، وبلا رميٍ على جسمٍ غير JSON.
          console.error(`Tamara API error ${res.httpStatus}:`, res.result);
          throw new HttpsError(
              "internal", "تعذّر بدء الدفع بالتقسيط — أعيدي المحاولة أو اختاري طريقةً أخرى");
        }

        return {checkoutUrl: res.result.checkout_url};
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message);
      }
    });

// 5. Tamara Webhook Handler
/**
 * (توحيد إشعار الدفع) مطالبة ذرّية بدفعة تأكيد الدفع الوحيدة على مستند الطلب.
 * ثلاثة مسارات كانت تتسابق فيصل العميل حتى 3 دفعات عن الدفعة الواحدة:
 * verify/webhook («تم تأكيد دفعتكِ»)، ومُشغّل الحالة (scheduled/under_review —
 * «دفعتكِ مؤكّدة»)، وإشعار التطبيق الذاتي («تم استلام طلبك» — notifyOrderCreated).
 * راية payment_push_sent تُقلَب داخل معامَلة فلا يفوز إلا مسارٌ واحد مهما تسابقت
 * المسارات أو أُعيدت المحاولة. فشل الحارس لا يمنع الإشعار (تكرارٌ نادر أهون من
 * صمتٍ كامل).
 * @param {string} col اسم المجموعة التي يوجد بها الطلب
 * @param {string} orderId معرّف مستند الطلب
 * @return {Promise<boolean>} true إن فاز النداء بحق إرسال الدفعة.
 */
async function _claimPaymentPush(col, orderId) {
  try {
    const ref = getFirestore().collection(col).doc(orderId);
    return await getFirestore().runTransaction(async (tx) => {
      const s = await tx.get(ref);
      if (!s.exists) return true; // بلا مستند لا حارس — أرسِل
      if (s.data().payment_push_sent === true) return false;
      tx.update(ref, {payment_push_sent: true});
      return true;
    });
  } catch (e) {
    console.error("_claimPaymentPush:", e.message);
    return true;
  }
}

/**
 * (F2) إشعار العميل بنتيجة الدفع (نجاح/فشل) لأي بوابة.
 * يكتب إشعاراً داخل التطبيق ويرسل Push. آمن — يُستدعى بعد فحص is_paid (idempotent).
 * @param {string} col اسم المجموعة التي يوجد بها الطلب
 * @param {string} orderId معرّف مستند الطلب
 * @param {object} data بيانات مستند الطلب (لاستخراج العميل والكود)
 * @param {boolean} success نجاح الدفع أم فشله
 */
async function notifyClientPaymentResult(col, orderId, data, success) {
  try {
    const clientUid = data?.client_id || data?.userId;
    if (!clientUid) return;

    // (توحيد إشعار الدفع) دفعة النجاح تشارك المطالبة الذرّية — إن سبقنا مسارٌ
    // آخر (مُشغّل الحالة أو إشعار التطبيق الذاتي) نصمت بدل التكرار. الفشل يمرّ
    // دائماً (لا يتنافس مع تأكيدٍ لم يحدث).
    if (success && !(await _claimPaymentPush(col, orderId))) {
      console.log(`notifyClientPaymentResult: dedup — payment push already sent for ${col}/${orderId}`);
      return;
    }

    const greet = _clientGreeting(data);
    const title = success ? "تم تأكيد دفعتكِ ✅" : "تعذّر إتمام الدفع ⚠️";
    const body = success ?
      `${greet}استلمنا دفعتكِ بنجاح ونبدأ بتجهيز طلبكِ فوراً 🌿` :
      `${greet}لم تكتمل عملية الدفع. يمكنكِ إعادة المحاولة من التطبيق.`;

    // 1) إشعار داخل التطبيق (سجل)
    await getFirestore().collection("notifications").add({
      userId: clientUid,
      title: title,
      body: body,
      type: "payment_update",
      relatedId: orderId,
      sentAt: FieldValue.serverTimestamp(),
    });

    // 2) Push عبر FCM
    const tokenDoc = await getFirestore().collection("fcm_tokens")
        .doc(clientUid).get();
    if (!tokenDoc.exists) return;
    const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
    if (!fcmToken) return;

    await getMessaging().send({
      notification: {title: title, body: body},
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        type: "payment_update",
        orderId: orderId,
      },
      token: fcmToken,
    });
    console.log(`notifyClientPaymentResult: ${success ? "PAID" : "FAILED"} -> ${clientUid} (${col}/${orderId})`);
  } catch (e) {
    console.error("notifyClientPaymentResult error:", e);
  }
}

// يقلب is_paid على طلب تمارا (idempotent) بالبحث في orders ثم store_orders ثم
// contracts (اشتراك) عبر order_reference_id (= معرّف مستند طلبنا/عقدنا).
// tamaraOrderId (اختياري): معرّف الطلب لدى تمارا — يُخزَّن على المستند لأن
// الاسترداد (tamaraRefundPayment) يخاطب تمارا به لا بمرجعنا.
async function _tamaraFlipPaid(db, orderRef, eventType, tamaraOrderId) {
  for (const col of ["orders", "store_orders", "contracts"]) {
    const ref = db.collection(col).doc(orderRef);
    let data = null;
    const flipped = await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return null;
      data = snap.data();
      if (data.is_paid) return false; // سبق تأكيده
      t.update(ref, {
        payment_status: "paid",
        is_paid: true,
        tamara_status: eventType,
        ...(tamaraOrderId ? {tamara_order_id: String(tamaraOrderId)} : {}),
        updated_at: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (flipped === null) continue;
    if (flipped) {
      console.log(`tamaraWebhook: ${col}/${orderRef} marked PAID (${eventType})`);
      await notifyClientPaymentResult(col, orderRef, data, true);
      // **تحقّقُ السعرِ الخادميُّ — لم يكن على هذا المسارِ شيءٌ منه.** هذه
      // الدالّةُ تَقلبُ `is_paid` من الويب هوكِ ومن مسحِ
      // `confirmPendingTamaraOrders`، وبلا أيِّ فحصِ مبلغٍ على الإطلاق: لا
      // «المدفوعُ = المُعلَن» ولا إعادةَ تسعيرٍ من المنطقة.
      //
      // و`paid` هنا هو مبلغُ الطلبِ نفسُه لا مبلغٌ مستقلٌّ من البوّابة، وذلك
      // **صحيحٌ** هنا: `createTamaraCheckout` يَبني الجلسةَ من
      // `info.amount` الخادميِّ لا من وسيطٍ يُرسلُه العميل، فلا يُمكنُ أن
      // يَختلفَ المدفوعُ عن المُعلَن. الشقُّ الذي يَهمُّ هو الآخر: **المُعلَنُ
      // مقابلَ سعرِ المنطقة**، وهو ما يَفحصُه هذا النداء.
      //
      // Tier A وحدَه عمداً: `voidOrRefundTampered` يَستدعي بوّابةَ ميسر
      // (`deps.gateway || moyasar`)، واستردادُ تمارا نداءٌ آخرُ بتوقيعٍ آخر —
      // فإنفاذُه هنا قرارٌ ماليٌّ مستقلّ. والطلبُ يُوسَمُ وتُنبَّهُ الإدارةُ،
      // وهو ما يَسدُّ «لا يَحدثُ شيءٌ ولا يُقالُ شيء».
      if (col === "orders" && !data.server_created_from_payment) {
        // `amounts.expectedAmount` لا تدرّجاً مكتوباً بيدِه — سؤالُه عينُ
        // سؤالِها: «كم كان يجب أن يُدفَع؟» (وكانت هنا سلسلةُ حقلَين).
        const amt = Number(amounts.expectedAmount(data));
        if (amt > 0) {
          await _verifyOrderPriceTierA(
              db, ref, orderRef, data, amt, "tamara");
        }
      }
    }
    break;
  }
}

exports.tamaraWebhook = onRequest(
    {secrets: ["TAMARA_API_TOKEN", "TAMARA_NOTIFICATION_TOKEN"], cpu: 0.083},
    async (req, res) => {
      // (تمارا) التحقق الصحيح: الإشعار يصل كـ JWT (HS256) موقّع بـ Notification
      // Token، في ترويسة Authorization: Bearer <jwt> أو كمعامل ?tamaraToken=.
      // (ليس HMAC للجسم ولا ترويسة tamara-signature).
      const jwt = require("jsonwebtoken");
      const authHeader = String(req.headers["authorization"] || "");
      const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
      const rawToken = bearer || req.query.tamaraToken;
      if (!rawToken) {
        console.warn("tamaraWebhook: missing tamaraToken");
        res.status(401).send("Unauthorized");
        return;
      }
      let payload;
      try {
        payload = jwt.verify(String(rawToken), tamaraNotificationToken.value(),
            {algorithms: ["HS256"]});
      } catch (e) {
        console.warn("tamaraWebhook: invalid token —", e.message);
        res.status(401).send("Invalid token");
        return;
      }

      // بيانات الحدث قد تكون داخل الـ JWT أو في جسم الطلب — نقبل الاثنين (الـ JWT
      // المُتحقَّق يضمن الأصالة في الحالتين).
      const body = req.body || {};
      const tamaraOrderId = payload.order_id || body.order_id; // معرّف تمارا (للتفويض)
      const orderRef = payload.order_reference_id || body.order_reference_id; // معرّف طلبنا
      const eventType = payload.event_type || body.event_type;
      console.log(`tamaraWebhook: event=${eventType} ref=${orderRef} tamaraId=${tamaraOrderId}`);
      if (!orderRef) {
        res.status(200).send("OK");
        return;
      }

      const db = getFirestore();
      try {
        if (eventType === "order_approved") {
          // إلزامي: نقل approved→authorised عبر Authorize API، وإلا يبقى الطلب
          // معلّقاً ولا يدخل دورة التسوية (لا نُقبض).
          const authRes = await tamara.authorise(
              tamaraApiToken.value(), tamaraOrderId);
          if (!authRes.ok) {
            console.error(`tamaraWebhook: authorise failed ${authRes.httpStatus}:`,
                authRes.result);
          } else {
            console.log(`tamaraWebhook: order ${tamaraOrderId} authorised`);
            await _tamaraFlipPaid(db, orderRef, eventType, tamaraOrderId);
          }
        } else if (eventType === "order_authorised" || eventType === "order_captured") {
          await _tamaraFlipPaid(db, orderRef, eventType, tamaraOrderId);
        } else if (eventType === "order_declined" ||
                   eventType === "order_expired" || eventType === "order_canceled") {
          for (const col of ["orders", "store_orders"]) {
            const ref = db.collection(col).doc(orderRef);
            const doc = await ref.get();
            if (doc.exists) {
              if (!doc.data().is_paid) {
                await ref.update({
                  payment_status: "failed",
                  tamara_status: eventType,
                  updated_at: FieldValue.serverTimestamp(),
                });
                await notifyClientPaymentResult(col, orderRef, doc.data(), false);
              }
              break;
            }
          }
        }
      } catch (error) {
        console.error("tamaraWebhook processing error:", error);
      }
      res.status(200).send("OK");
    });

const {Resend} = require("resend");

// 6. Unified Notification Trigger Processor
/**
 * Anti-relay guard for the client-writable notification_triggers queue.
 * An email may only be delivered to an address that belongs to a registered
 * user or driver, or to the configured admin address — never an arbitrary
 * external recipient supplied by a client.
 * @param {string} email Candidate recipient address.
 * @return {Promise<boolean>} True if the address is an allowed recipient.
 */
async function isAllowedEmailRecipient(email) {
  if (!email || typeof email !== "string") return false;
  const lower = email.trim().toLowerCase();
  if (!lower) return false;
  // Configured admin address + system fallbacks
  try {
    const cfg = await getFirestore().collection("system_configs").doc("main_settings").get();
    const adminEmail = (cfg.exists && cfg.data()?.admin_email ? String(cfg.data().admin_email) : "").toLowerCase();
    if (lower === adminEmail || lower === "admin@zyiarah.com" || lower === "no-reply@zyiarah.com") return true;
  } catch {
    // fall through to user/driver lookups
  }
  const u = await getFirestore().collection("users").where("email", "==", email).limit(1).get();
  if (!u.empty) return true;
  const d = await getFirestore().collection("drivers").where("email", "==", email).limit(1).get();
  if (!d.empty) return true;
  return false;
}

/**
 * تهريبُ HTML — **مُهرِّبٌ واحدٌ للملفّ.**
 *
 * كان `_buildTemplateFallbackHtml` يُعرّفُ `esc` محليّاً ويَستعمله، وشقيقُه
 * `_buildAdminAlertHtml` — على بُعدِ عشرينَ سطراً، وبنفسِ المهمّةِ تماماً —
 * يُحقِنُ `${k}` و`${v}` في HTML **خامَّين**. والقيمُ هي اسمُ العميلةِ
 * وجوّالُها واسمُ الخدمةِ والمنطقةِ والمبلغ: حقولٌ **يَكتبُها العميلُ**.
 * فاسمٌ مثل `<a href="https://evil/">اضغط لتأكيد الطلب</a>` يَصلُ بريدَ
 * المالكِ **من `no-reply@zyiarah.com`** مع كلِّ طلبٍ تُنشئُه — حقنُ HTML
 * في تنبيهٍ داخليّ، بلا حاجةٍ إلى أيِّ ثغرةٍ أخرى. (العملاءُ البريديّون
 * يُسقِطون النصوصَ البرمجيّة، لكنّ الروابطَ والصورَ وتشويهَ التصميمِ تَعمل.)
 *
 * @param {unknown} v القيمة.
 * @return {string} نصٌّ آمنٌ للحقنِ في HTML.
 */
function _escHtml(v) {
  return String(v ?? "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"}[c]));
}

/**
 * قشرةُ بريدِ التنبيهِ الإداريِّ — نقيّةٌ وتُهرّبُ كلَّ ما يُحقَن.
 *
 * فُصِلت عن `_buildAdminAlertHtml` (التي تَقرأُ Firestore) كي تُختبَرَ
 * بحملٍ حقنيٍّ حقيقيٍّ بلا محاكٍ.
 *
 * @param {string} heading العنوان.
 * @param {Array<Array<unknown>>} rows أزواجُ (مفتاح، قيمة).
 * @return {string} HTML.
 */
function _adminAlertShell(heading, rows) {
  const rowsHtml = (rows || []).map(([k, v]) =>
    "<tr><td style=\"padding:11px 10px;color:#64748b;font-size:14px;" +
    "border-bottom:1px solid #f1f5f9\">" + _escHtml(k) + "</td>" +
    "<td style=\"padding:11px 10px;font-weight:bold;color:#1e293b;" +
    "text-align:left;border-bottom:1px solid #f1f5f9\">" + _escHtml(v) +
    "</td></tr>").join("");
  return "<div dir=\"rtl\" style=\"font-family:Tajawal,Arial,sans-serif;" +
    "max-width:600px;margin:auto;background:#fff;border-radius:16px;" +
    "overflow:hidden;border:1px solid #e2e8f0\">" +
    "<div style=\"background:linear-gradient(135deg,#660033,#8B3D8C);" +
    "padding:28px;text-align:center\">" +
    "<h1 style=\"color:#fff;margin:0;font-size:22px\">" + _escHtml(heading) +
    " 🔔</h1>" +
    "<p style=\"color:#e9d5ea;margin:6px 0 0\">لوحة إدارة زيارة</p></div>" +
    "<div style=\"padding:28px\">" +
    "<p style=\"font-size:15px;color:#475569;margin:0 0 8px\">" +
    "وصلك طلب جديد يحتاج مراجعتك — التفاصيل:</p>" +
    "<table style=\"width:100%;border-collapse:collapse\">" + rowsHtml +
    "</table></div>" +
    "<div style=\"background:#f8fafc;padding:14px;text-align:center;" +
    "color:#94a3b8;font-size:12px\">زيارة — إشعار إداري آلي</div></div>";
}

// يبني بريد HTML منسّقاً لتنبيهات الإدارة بتفاصيل الطلب/العميل بدل نصّ عارٍ.
// يُرجع null إن لم يكن النوع تنبيهاً إدارياً معروفاً → يُستخدم النص العادي.
async function _buildAdminAlertHtml(type, data) {
  const db = getFirestore();
  const d = data || {};
  let heading = "تنبيه إداري";
  let rows = [];
  try {
    if (type === "new_order_admin" || type === "admin_order_alert") {
      heading = "طلب خدمة جديد";
      const o = (await db.collection("orders").doc(d.orderId).get()).data() || {};
      rows = [["رقم الطلب", o.code || d.orderId || "—"], ["العميل", o.client_name || "—"],
        ["الجوال", o.client_phone || "—"], ["الخدمة", o.service_name || o.service_type || "—"],
        ["المبلغ", o.amount != null ? `${o.amount} ر.س` : "—"],
        ["المنطقة", o.zone_name || "—"], ["الحالة", o.status || "—"]];
    } else if (type === "new_store_order_admin") {
      heading = "طلب متجر جديد";
      const o = (await db.collection("store_orders").doc(d.orderId).get()).data() || {};
      const items = Array.isArray(o.items) ? o.items.length : "—";
      rows = [["رقم الطلب", o.code || d.orderId || "—"], ["العميل", o.client_name || "—"],
        ["الجوال", o.client_phone || "—"], ["عدد المنتجات", items],
        ["الإجمالي", `${o.total_amount ?? o.final_amount ?? "—"} ر.س`]];
    } else if (type === "new_maintenance_admin") {
      heading = "طلب صيانة جديد";
      const o = (await db.collection("maintenance_requests").doc(d.requestId).get()).data() || {};
      rows = [["رقم الطلب", d.requestId || "—"], ["العميل", o.userName || o.client_name || "—"],
        ["الجوال", o.userPhone || o.phone || "—"], ["نوع الصيانة", o.serviceType || "—"]];
    } else if (type === "new_contract_admin") {
      heading = "اشتراك جديد";
      const o = (await db.collection("contracts").doc(d.contractId).get()).data() || {};
      rows = [["الباقة", o.planName || "—"], ["العميل", o.userName || o.clientName || "—"],
        ["الجوال", o.userPhone || "—"], ["القيمة", o.planPrice != null ? `${o.planPrice} ر.س` : "—"]];
      // جدول كل زيارات الاشتراك (أسبوعي/شهري) — كل زيارة صفٌّ بتاريخها ووقتها.
      try {
        const vs = await db.collection("orders")
            .where("contract_id", "==", d.contractId).get();
        const visits = vs.docs.map((x) => x.data())
            .sort((a, b) => (a.visit_index || 0) - (b.visit_index || 0));
        if (visits.length) {
          rows.push(["عدد الزيارات", String(visits.length)]);
          for (const v of visits) {
            rows.push([
              `زيارة ${v.visit_index || "—"}/${v.total_visits || visits.length}`,
              `${v.booking_date || "—"} — ${v.booking_time_slot || "—"}`,
            ]);
          }
        }
      } catch { /* التفاصيل الأساسية تكفي إن تعذّر جلب الزيارات */ }
    } else {
      return null;
    }
  } catch (e) {
    console.error("[EMAIL] admin alert html failed:", e.message);
    return null;
  }
  // الحقنُ كلُّه في القشرةِ المُهرِّبة — انظر `_escHtml`.
  return _adminAlertShell(heading, rows);
}

/**
 * يُنقّي بريداً قبل تسليمه لـ Resend: يُسقط كل ما ليس ASCII مطبوعاً (علامات
 * الاتجاه U+200F/U+202D، المسافات، أحرف التحكم) ويُصغّر الحروف. بريدٌ بلا @ = "".
 * @param {unknown} raw القيمة الخام.
 * @return {string} البريد النظيف أو "".
 */
function _cleanEmail(raw) {
  if (raw == null) return "";
  const s = String(raw).replace(/[^\x21-\x7E]/g, "").toLowerCase();
  return s.includes("@") ? s : "";
}

/**
 * HTML بديل عند غياب قالب Resend: العنوان + متغيّرات القالب كجدول RTL، بهوية
 * زيارة الخمرية. الأفضل من إسقاط الرسالة أو من نص عارٍ.
 * @param {string} title عنوان الرسالة.
 * @param {Object} variables متغيّرات القالب.
 * @return {string} HTML.
 */
function _buildTemplateFallbackHtml(title, variables) {
  // مُهرِّبٌ واحدٌ للملفّ: كان معرَّفاً هنا محليّاً، وشقيقُه الإداريُّ بلا
  // تهريبٍ إطلاقاً — نسختانِ لمهمّةٍ واحدةٍ إحداهما غائبة.
  const esc = _escHtml;
  const rows = Object.entries(variables || {})
      .filter(([k]) => !/url|link/i.test(k))
      .map(([k, v]) => `<tr><td style="padding:8px 12px;color:#64748b">${esc(k)}</td>` +
        `<td style="padding:8px 12px;font-weight:600">${esc(v)}</td></tr>`).join("");
  return `<!DOCTYPE html><html dir="rtl" lang="ar"><body style="margin:0;background:#f1f5f9;` +
    `font-family:Arial,sans-serif"><div style="max-width:600px;margin:32px auto;background:#fff;` +
    `border-radius:20px;overflow:hidden"><div style="background:#660033;color:#fff;padding:28px;` +
    `text-align:center;font-size:20px;font-weight:700">${esc(title)}</div><div style="padding:24px">` +
    `<p style="font-size:16px">${esc(variables?.greeting || "عزيزنا العميل،")}</p>` +
    `<table style="width:100%;border-collapse:collapse;font-size:14px">${rows}</table>` +
    `<p style="color:#64748b;font-size:13px;margin-top:24px">فريق زيارة — شكراً لثقتكم.</p>` +
    `</div></div></body></html>`;
}

// ════════════════════════════════════════════════════════════════════════
// طابورا الإشعارات: `notification_queue` خادميٌّ و`notification_triggers` للعميل.
//
// SECURITY: كانت الثقةُ تُحسَب من `trigger.createdBy === "server"` — **وهو حقلٌ
// يَكتبه العميل**: قاعدةُ `notification_triggers` هي `allow create: if
// isLoggedIn()` بلا أيِّ قيدٍ على الحقول، فأيُّ مستخدمٍ مسجَّلٍ يَكتب
// `createdBy: "server"` فيُعَدُّ موثوقاً ويَتخطّى الحارسَ كلَّه: إشعارُ Push
// وسجلٌّ داخلَ التطبيقِ بعنوانٍ ونصٍّ من اختيارِه إلى **أيِّ ضحيّة**، أو بثٌّ
// إداريٌّ مزيَّف، أو بريدٌ من نطاقِ المنشأةِ إلى أيِّ عنوان (`recipientEmail`
// يأتي من المستند). وهو عينُ التصيّدِ الذي كُتب الحارسُ لمنعه.
//
// ولا تستطيع الدالّةُ التمييزَ بين كاتبٍ وكاتبٍ من محتوى المستند — الذي
// يُميّزُهما هو **مَن كتب**، ولا تَعرفُه إلّا القواعد. فالفصلُ بالمجموعة:
// `notification_queue` **بلا قاعدةِ مطابقةٍ في firestore.rules**، فالعميلُ
// ممنوعٌ منها بالافتراضِ المُغلَق، وAdmin SDK يَتخطّى القواعدَ أصلاً. فالكتابةُ
// فيها إذنْ برهانُ أصلٍ خادميٍّ لا يُنتحَل. والثقةُ تُحسَب من **اسمِ المجموعة**
// (`snap.ref.parent.id`) لا من حقل.
//
// مُعالِجٌ واحدٌ للطابورَين كي لا يَفترقا: ٣٤٠ سطراً من بريدٍ وقوالبَ ومرفقاتٍ
// وإعادةِ محاولةٍ، ونسختان منها تَنحرفان.
// ════════════════════════════════════════════════════════════════════════
const _notifQueueOpts = {secrets: ["RESEND_API_KEY"], cpu: 0.25, retry: true};

// retry: إعادة المحاولة عند فشل عابر (Resend/FCM) بدل فقد الإشعار للأبد. سجلّ
// الصندوق (step 1) بمعرّف حتمي كي لا يتكرّر عند الإعادة.
const _processNotifQueueDoc = async (event) => {
      const snap = event.data;
      if (!snap) return;

      const trigger = snap.data();
      if (!trigger || trigger.processed === true) return;

      const {toUid, title, body, type, template, data = {}, targetRoles} = trigger;
      const attachmentUrls = Array.isArray(trigger.attachmentUrls) ? trigger.attachmentUrls : [];
      // تنقية البريد: علامات الاتجاه (U+200F) والمسافات الملتصقة من اللصق كانت تُفشل
      // Resend بـ «Invalid to field: non-ASCII» فيضيع الترحيب/تأكيد الطلب بصمت.
      let recipientEmail = _cleanEmail(
          trigger.recipientEmail || data.customerEmail || data.to) || "admin@zyiarah.com";
      // تنبيهات الإدارة تذهب لبريد الإدارة المُهيّأ (admin_email) لا لبريد العميل —
      // كان data.customerEmail قد يوجّه «تنبيه الإدارة» لبريد العميل بالخطأ.
      if (toUid === "ADMIN_BROADCAST") {
        try {
          const cfgA = await getFirestore()
              .collection("system_configs").doc("main_settings").get();
          const ae = (cfgA.exists && cfgA.data()?.admin_email) ?
            String(cfgA.data().admin_email).trim() : "";
          recipientEmail = ae || "admin@zyiarah.com";
        } catch { recipientEmail = "admin@zyiarah.com"; }
      }

      console.log(`Processing trigger ${event.params.id}`);

      try {
        // SECURITY: notification_triggers قابلة للكتابة من أي عميل (firestore.rules).
        // العميل غير الموثوق لا يجوز أن يخاطب **مستخدماً آخر** — كان بإمكانه انتحال إشعار
        // Push + سجلّ داخل التطبيق باسم زيارة لأي ضحية (تصيّد). نحسب ثقة المُرسِل مرّة
        // (server أو موظّف بدور != client) ونرفض أي trigger موجَّه لغير مُنشئه.
        // (تصلّب ADMIN_BROADCAST يُعالَج على حدة — تدفّقات إدارية شرعية تكتبه.)
        // الثقةُ من **اسمِ المجموعة**: `notification_queue` لا قاعدةَ لها في
        // firestore.rules فلا يَكتبها عميل. و`createdBy === "server"` لم يَعُد
        // إشارةَ ثقةٍ — كان العميلُ يَكتبه بنفسِه.
        let senderIsTrusted = snap.ref.parent.id === "notification_queue";
        if (!senderIsTrusted && trigger.createdBy) {
          try {
            const cu = await getFirestore().collection("users")
                .doc(String(trigger.createdBy)).get();
            const r = cu.exists ? cu.data().role : null;
            senderIsTrusted = r != null && r !== "client";
          } catch { senderIsTrusted = false; }
        }
        const targetsOtherUser = toUid && toUid !== "ADMIN_BROADCAST" &&
          toUid !== trigger.createdBy;
        // (#3) عميلٌ غير موثوق لا يبثّ للإدارة أيضاً — كان يحقن تنبيهاً إدارياً مزيّفاً
        // + Push لكل الموظّفين. الآن تُولَّد تنبيهات الإلغاء/الدفع/التقييم/الاشتراك/الصيانة
        // خادميّاً (createdBy='server') فتمرّ، وأي بثٍّ من عميل يُرفَض.
        const targetsAdmins = toUid === "ADMIN_BROADCAST";
        if (!senderIsTrusted && (targetsOtherUser || targetsAdmins)) {
          console.warn(`[NOTIF] Refused untrusted trigger from ${trigger.createdBy} to ${toUid}`);
          await snap.ref.update({processed: true, status: "refused_untrusted_sender"});
          return;
        }

        // 1. Sync to In-App Notification History
        if (toUid && toUid !== "ADMIN_BROADCAST") {
          await getFirestore().collection("notifications")
              .doc(`trig_${event.params.id}`).set({
                userId: toUid,
                title: title,
                body: (body || "").replace(/<[^>]*>?/gm, ""),
                type: type,
                // **كان يَقعُ على `event.params.id`** — معرّفُ مستندِ الطابورِ
                // التلقائيُّ. وهو عشرونَ محرفاً لا يَبدأُ بـ`ZY-` ولا
                // بـ`trig_`، فـ`relatedLooksLikeOrderDoc` في العميلِ تَقرؤه
                // **مستندَ طلبٍ صالحاً** وتَذهبُ به إلى `/track/<هذا>`:
                // شاشةُ تتبّعِ طلبٍ لا وجودَ له، تحتَ زرٍّ يَقول «عرض الطلب
                // والفاتورة» — وذلك ما كان يَحدُثُ لإشعاراتِ العقدِ، إذ لا
                // تَحملُ `orderId` ولا `code`. و`relatedLooksLikeOrderDoc`
                // تَستثني `trig_…` بنيّةِ استثناءِ هذا بعينِه، لكنّ الحقلَ
                // يَحملُ المعرّفَ **عارياً** فلم يَستثنِه قطّ. فلا بديلَ
                // مُختَرَع: `null` تَعني «لا مستندَ طلبٍ هنا».
                relatedId: data.orderId || data.code || null,
                isRead: false,
                sentAt: FieldValue.serverTimestamp(),
              });
        }
        // 1b. سجلّ تنبيهات الإدارة — تستمع إليه لوحة الويب لحظيّاً (لا FCM/VAPID).
        if (toUid === "ADMIN_BROADCAST") {
          // معرّف حتمي (بدل add): إعادة المحاولة تكتب فوق نفس المستند بدل تكرار التنبيه.
          await getFirestore().collection("admin_notifications")
              .doc(`admin_trig_${event.params.id}`).set({
                title: title,
                body: (body || "").replace(/<[^>]*>?/gm, ""),
                type: type,
                data: data || {},
                targetRoles: Array.isArray(targetRoles) ? targetRoles : null,
                // نفسُ البديلِ المُختَرَعِ المشروحِ أعلاه. ولا قارئَ له هنا
                // (مُستمِعُ اللوحةِ لا يَقرأُ الحقلَ) — فالتسويةُ تَنزعُ فخّاً
                // قبلَ أن يَقعَ فيه قارئٌ لاحق.
                relatedId: data.orderId || data.ticketId || data.code || null,
                createdAt: FieldValue.serverTimestamp(),
              });
        }

        // 2. Email via Resend (key from Secret Manager)
        // كل تنبيهات الإدارة للكيانات الجديدة تُرسل بريداً لبريد الإدارة المُهيّأ: طلب خدمة
        // (new_order_admin) + متجر + صيانة + عقد. كان البريد يصل للمتجر فقط لأن بقية
        // الأنواع لم تكن مُدرَجة هنا.
        const wantsEmailByType = (type === "email" || type === "hybrid" ||
          type === "admin_order_alert" || type === "new_store_order_admin" ||
          type === "new_order_admin" || type === "new_maintenance_admin" ||
          type === "new_contract_admin" ||
          // تحديثات طلب المتجر للعميل تصله إيميلاً أيضاً (طلبها المالك): تحت المراجعة/
          // جاري التوصيل/تم التسليم — recipientEmail = بريد العميل يمرّره المُشغّل.
          type === "store_update");
        // إشعار عميل (لا ADMIN_BROADCAST) بلا بريد صريح: لا نُرسِل إيميلاً إطلاقاً —
        // وإلا وقع recipientEmail على بريد الإدارة الافتراضي فيصل تحديثُ العميل للإدارة
        // (خصوصاً عملاء مصادقة الهاتف بلا بريد). الإدارة لها بريدها المُهيّأ فتُستثنى.
        const clientWithoutEmail = toUid !== "ADMIN_BROADCAST" &&
          !(trigger.recipientEmail || data.customerEmail);
        const wantsEmail = wantsEmailByType && !clientWithoutEmail;
        // SECURITY: notification_triggers is client-writable; refuse to relay
        // email to any address that isn't a registered user/driver/admin.
        const emailAllowed = wantsEmail ? await isAllowedEmailRecipient(recipientEmail) : false;
        if (wantsEmail && !emailAllowed) {
          console.warn(`[EMAIL] Refused relay to unregistered recipient: ${recipientEmail}`);
          await snap.ref.update({emailStatus: "refused_unregistered_recipient"});
        }
        // SECURITY: البريد لا يُرسله إلا الخادم (createdBy='server') أو موظّف (إدارة/سائق).
        // عميلٌ عادي لا مسوّغ له لإرسال بريد — يمنع تصيّداً بنطاق الشركة عبر SDK الخام.
        // (queuePush يختم createdBy='server'؛ بريد الصيانة/الإسناد ينشئه أدمن/سائق.)
        let emailSenderOk = true;
        if (wantsEmail) {
          const cb = trigger.createdBy;
          if (cb === "server") {
            emailSenderOk = true;
          } else if (!cb) {
            emailSenderOk = false;
          } else {
            try {
              const cu = await getFirestore().collection("users").doc(String(cb)).get();
              // الدورُ من السجلّ: القواعدُ تَمنعُ المالكَ من كتابةِ `role`
              // و`staff_role` (حكرٌ على المدير العام)، فهو موضعُ ثقةٍ.
              const r = cu.exists ? cu.data().role : null;
              if (r != null && r !== "client") {
                emailSenderOk = true;
              } else {
                // **SECURITY: بريدُ «الإرسالِ إلى نفسِه» من المصادقةِ لا من
                // السجلّ.** كان يُقارَنُ بـ`users/{uid}.email` — وهو حقلٌ
                // **يَكتبُه العميلُ على مستندِه** (قواعدُ المالكِ تَمنعُ
                // الدورَ والمحفظةَ والحظرَ ولا تَذكرُ البريد). فالمسارُ
                // كان: اكتبْ بريدَك `victim@x.com`، ثمّ أنشئ
                // `notification_triggers` موجَّهاً إلى نفسك بـ
                // `recipientEmail: victim@x.com` وعنوانٍ ونصٍّ من اختيارك —
                // فيَمرُّ من `isAllowedEmailRecipient` (مستندُك يَحملُ
                // العنوانَ الآن) ومن هذا الحارسِ (الحقلانِ متساويان)،
                // ويُرسِلُ الخادمُ بريداً **من `no-reply@zyiarah.com`**
                // بمحتوًى من اختيارِ العميلِ إلى أيِّ عنوان: مُرحِّلٌ مفتوحٌ
                // بنطاقِ الشركةِ وسُمعتِها — وهو عينُ ما يَقولُ تعليقُ هذا
                // الحارسِ إنّه يَمنعُه («يمنع تصيّداً بنطاق الشركة»).
                //
                // بريدُ المصادقةِ لا يَكتبُه العميلُ في Firestore، والمسارُ
                // الشرعيُّ الوحيدُ (`sendWelcomeEmail` عند التسجيل) يُرسِلُ
                // إلى العنوانِ الذي سَجّلت به — أي بريدَ المصادقةِ نفسِه.
                // و`real_email` حُذف: مقروءٌ هنا وحدَه، **ولا كاتبَ له في
                // المستودعِ كلِّه** (بقيّةُ مخطَّطِ الدخولِ بالجوّالِ الذي
                // لم يُشحَن أبداً) — فهو حقلٌ آخرُ مكشوفٌ لكتابةِ العميل.
                const au = await getAuth().getUser(String(cb));
                const authEmail = au && au.email ? String(au.email) : null;
                emailSenderOk = !!authEmail && !!recipientEmail &&
                  authEmail.toLowerCase() ===
                    String(recipientEmail).toLowerCase();
              }
            } catch {
              emailSenderOk = false;
            }
          }
          if (!emailSenderOk) {
            console.warn(`[EMAIL] Refused relay from non-staff creator: ${cb}`);
            await snap.ref.update({emailStatus: "refused_non_staff_sender"});
          }
        }
        if (wantsEmail && emailAllowed && emailSenderOk && trigger.emailStatus !== "sent") {
          const resendKey = resendApiKeySecret.value();
          if (!resendKey) {
            console.error("[EMAIL] RESEND_API_KEY secret is not set");
            throw new Error("Email service not configured");
          }

          let fromName = "Zyiarah | زيارة";
          let fromEmail = "no-reply@zyiarah.com";
          const configDoc = await getFirestore()
              .collection("system_configs").doc("email_settings").get();
          if (configDoc.exists) {
            fromName = configDoc.data()?.fromName || fromName;
            fromEmail = configDoc.data()?.fromEmail || fromEmail;
          }

          const fromString = `"${fromName}" <${fromEmail}>`;
          const resend = new Resend(resendKey);

          // SECURITY: `attachmentUrls` تأتي من مستندٍ يكتبه العميل، وكانت
          // تُجلب بـ`fetch` بلا تحقّقٍ من الأصل — فالخادمُ يطلب أيَّ عنوانٍ
          // يختاره العميل (SSRF بصلاحية خروج المشروع) ويُنزِّل أيَّ حجم.
          // وحارسا البريد القائمان لا يغطّيان هذا: أحدهما يحرس المستلِم
          // والآخر المُرسِل، وكلاهما يمرّ لعميلٍ يراسل **نفسه** ببريده
          // المسجَّل. القَصرُ على مخزن المشروع لا يمسّ مساراً قائماً: كلُّ
          // مرفقٍ في المستودع فاتورةُ ZATCA من `getDownloadURL()`.
          const attachments = [];
          for (const url of attachmentUrls) {
            if (!attachmentsGuard.isProjectStorageUrl(url, PROJECT_ID)) {
              console.warn(`[EMAIL] Refused foreign attachment origin: ${url}`);
              continue;
            }
            try {
              const res = await fetch(url);
              if (res.ok) {
                const declared = Number(res.headers.get("content-length") || 0);
                if (declared > attachmentsGuard.MAX_ATTACHMENT_BYTES) {
                  console.warn(`[EMAIL] Attachment too large (${declared}): ${url}`);
                  continue;
                }
                const buf = await res.arrayBuffer();
                if (buf.byteLength > attachmentsGuard.MAX_ATTACHMENT_BYTES) {
                  // بعضُ الردود بلا `content-length` — نفحص الحجمَ الفعليّ أيضاً.
                  console.warn(`[EMAIL] Attachment too large (${buf.byteLength}): ${url}`);
                  continue;
                }
                const filename = url.split("/").pop().split("?")[0] || "invoice.pdf";
                attachments.push({filename, content: Buffer.from(buf)});
              }
            } catch (attErr) {
              console.error(`[EMAIL] Attachment failed for ${url}:`, attErr);
            }
          }

          const emailPayload = {
            from: fromString,
            to: recipientEmail,
            subject: title,
            attachments: attachments.length > 0 ? attachments : undefined,
          };

          if (template && template.id) {
            emailPayload.template = {id: template.id, variables: template.variables || {}};
          } else {
            // تنبيهات الإدارة: قالب HTML منسّق بتفاصيل الطلب/العميل بدل النص العارٍ.
            const adminHtml = (toUid === "ADMIN_BROADCAST") ?
              await _buildAdminAlertHtml(type, data) : null;
            emailPayload.html = adminHtml || body;
          }

          let {data: resendData, error: resendError} = await resend.emails.send(emailPayload);
          // قالب غير موجود في Resend (order-confirmation لم يُنشأ قط) → لا نُسقط
          // الرسالة: نعيد الإرسال بـ HTML مبني من متغيّرات القالب نفسها.
          if (resendError && emailPayload.template &&
              /template not found/i.test(String(resendError.message))) {
            console.warn(`[EMAIL] Template ${emailPayload.template.id} missing — html fallback`);
            const fallback = {...emailPayload};
            delete fallback.template;
            fallback.html = _buildTemplateFallbackHtml(title, emailPayload.template.variables);
            ({data: resendData, error: resendError} = await resend.emails.send(fallback));
          }
          if (resendError) {
            throw new Error(`Resend Error: ${resendError.message}`);
          }
          await snap.ref.update({
            emailStatus: "sent",
            messageId: resendData.id,
            provider: "resend",
            processedAt: FieldValue.serverTimestamp(),
          });
          console.log(`[EMAIL] Sent. Message ID: ${resendData.id}`);
        }

        // (توحيد إشعار الدفع) «تم استلام طلبك» يكتبه التطبيق لنفسه بعد نجاح الدفع
        // (notifyOrderCreated) — كان دفعةً ثالثة عن الدفعة الواحدة بعد «تم تأكيد
        // دفعتكِ» و«تم تأكيد حجزكِ». يشارك في نفس المطالبة الذرّية على الطلب فلا
        // يُدفَع إلا إن لم يسبقه مسارٌ خادمي. سجلّ الوارد (step 1) يبقى كما هو.
        let paymentDedupSkip = false;
        if (type === "order_update" && toUid && trigger.createdBy === toUid &&
            data.orderId && trigger.pushSent !== true) {
          paymentDedupSkip = !(await _claimPaymentPush("orders", String(data.orderId)));
          if (paymentDedupSkip) {
            await snap.ref.update({pushSent: true, pushSkipped: "payment_push_dedup"});
          }
        }

        // 3. Push Notification via FCM (حارس pushSent يمنع تكرار الدفع عند إعادة المحاولة)
        if (type !== "email" && !paymentDedupSkip && trigger.pushSent !== true) {
          let targetTokens = [];
          if (toUid === "ADMIN_BROADCAST") {
            const allAdminRoles = ["admin", "super_admin", "orders_manager", "accountant_admin", "marketing_admin"];
            if (Array.isArray(targetRoles) && targetRoles.length > 0) {
              // توجيه فعلي حسب الدور الفرعي: نصفّي بـ staff_role (الدور الحقيقي على
              // التوكن) — الحقل role دائماً 'admin' للموظّفين فلا يصلح للتصفية. نضمّ
              // دائماً المدراء الكبار (role admin/super بلا staff_role) عبر استعلام ثانٍ.
              const [byStaff, bySuper] = await Promise.all([
                getFirestore().collection("fcm_tokens").where("staff_role", "in", targetRoles).get(),
                getFirestore().collection("fcm_tokens").where("role", "in", ["admin", "super_admin"]).get(),
              ]);
              const seen = new Set();
              for (const d of byStaff.docs) {
                const t = d.data()?.fcmToken || d.data()?.token;
                if (t && !seen.has(t)) { seen.add(t); targetTokens.push(t); }
              }
              // (توجيه فعلي) كل الموظّفين يحملون role='admin' مع staff_role فرعي،
              // فكان ضمّ استعلام role كاملاً يُعيد الجميع ويجعل targetRoles بلا أثر
              // (الكل يستلم كل شيء). لا نضمّ منه إلا المدير الكبير الحقيقي: بلا
              // staff_role (أو super_admin صراحةً) — يبقى يرى الكل كما في اللوحة.
              for (const d of bySuper.docs) {
                const sd = d.data() || {};
                if (sd.staff_role && sd.staff_role !== "super_admin" &&
                    !targetRoles.includes(sd.staff_role)) continue;
                const t = sd.fcmToken || sd.token;
                if (t && !seen.has(t)) { seen.add(t); targetTokens.push(t); }
              }
            } else {
              const snap2 = await getFirestore()
                  .collection("fcm_tokens").where("role", "in", allAdminRoles).get();
              targetTokens = snap2.docs
                  .map((d) => d.data()?.fcmToken || d.data()?.token)
                  .filter((t) => !!t);
            }
          } else if (toUid) {
            const tokenDoc = await getFirestore()
                .collection("fcm_tokens").doc(toUid).get();
            if (tokenDoc.exists) {
              const t = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
              if (t) targetTokens = [t];
            }
          }

          if (targetTokens.length > 0) {
            // FCM يتطلب كل قيم data نصوصاً — بيانات التطبيق تحوي أرقاماً (amount/rating/
            // visits) فكانت الدفعة تُرفَض بالكامل. نُحوّل كل القيم لنصوص.
            const strData = Object.fromEntries(
                Object.entries({...data, click_action: "FLUTTER_NOTIFICATION_CLICK"})
                    .map(([k, v]) => [k, v == null ? "" : String(v)]));
            const pushMsg = {
              notification: {title, body: (body || "").replace(/<[^>]*>?/gm, "")},
              data: strData,
            };
            if (targetTokens.length === 1) {
              await getMessaging().send({...pushMsg, token: targetTokens[0]});
            } else {
              await getMessaging().sendEachForMulticast({
                tokens: targetTokens,
                notification: pushMsg.notification,
                data: pushMsg.data,
              });
            }
            console.log(`Push sent to ${targetTokens.length} devices`);
            await snap.ref.update({pushSent: true}); // حتمية: لا يُعاد الدفع عند الإعادة
          }
        }

        await snap.ref.update({
          processed: true,
          processedAt: FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error(`Error processing trigger ${event.params.id}:`, error);
        const attempts = Number(trigger.attempts || 0) + 1;
        await snap.ref.update({
          processed: false,
          attempts,
          error: error.message,
          lastAttemptAt: FieldValue.serverTimestamp(),
        });
        // إعادة محاولة محدودة: كل الخطوات أعلاه حتمية/محروسة (in-app بمعرّف حتمي،
        // admin_notifications بمعرّف حتمي، البريد بحارس emailStatus، الدفع بحارس
        // pushSent) — فإعادة التشغيل لا تُكرّر شيئاً. نتوقّف بعد 3 محاولات لمنع
        // عاصفة إعادة المحاولات على فشل دائم (بريد غير صالح مثلاً).
        if (attempts < 3) throw error;
        await snap.ref.update({giveUp: true});
        console.error(`Trigger ${event.params.id} gave up after ${attempts} attempts`);
      }
    };

// الطابورُ الخادميُّ: كلُّ ما فيه موثوقٌ لأنّ العميلَ لا يستطيع الكتابةَ فيه.
exports.processServerNotificationQueue = onDocumentCreated(
    {...{document: "notification_queue/{id}"}, ..._notifQueueOpts},
    _processNotifQueueDoc);

// طابورُ العميل: يبقى كما هو (التطبيقُ واللوحةُ يَكتبانه)، وكلُّ ما فيه
// **غيرُ موثوقٍ** حتى يُثبت `createdBy` أنّه موظّف.
exports.processNotificationTriggers = onDocumentCreated(
    {...{document: "notification_triggers/{id}"}, ..._notifQueueOpts},
    _processNotifQueueDoc);

// 6b. Secure wallet — redeem Qatrat points for balance (server-authoritative).
// The wallet is (currently) client-writable, so this onCall is the trusted path:
// it validates the points server-side and performs the conversion atomically.
// Pairs with the deferred lockdown of the wallets write rule.
/**
 * **تحقّقُ كودِ الخصمِ خادميّاً — وقارئُ `promo_codes` العميليُّ يَزول.**
 *
 * `couponProblem` في `functions/coupons.js` تَقولُ في ترويستِها إنّها
 * «تُطابقُ حرفيّاً ما يَفحصه `order_service.validateCoupon` في العميل، وهذا
 * هو المقصود: **جهةٌ واحدةٌ تَقرّرُ والطرفان يَسألانها**». وكان الادّعاءُ
 * كاذباً من وجهَين: العميلُ يَحملُ **نسخةً مكتوبةً بيدٍ** بلغةٍ أخرى ولا
 * يَسألُ هذه الوحدةَ أصلاً، والنسختانِ **مختلفتان** — استعلامُ العميلِ
 * يَشترطُ `status == 'active'` حرفيّاً، فمستندٌ قديمٌ بلا `status` **غيرُ
 * مرئيٍّ** له، بينما `couponProblem` تَقبلُ الغيابَ وتَقولُ عن نفسِها «نفسُ
 * تسامحِ العميل». فالتسامحُ كان مُبطَلاً بمُرشِّحِ الاستعلامِ لا مكتوباً.
 *
 * والأهمُّ: الكوبونُ كان يُحلَّلُ **في العميل**، فـ`promo_codes` قراءتُها
 * `allow read: if isLoggedIn()` — وأيُّ عميلةٍ مسجَّلةٍ تَقرأُ **كلَّ** كودِ
 * خصمٍ في المستودع، ومنها ما وسَمَته الإدارةُ `show_in_offers: false`
 * بعينِه. وتعليقُ `PromoCoupon` يَقولُ غرضَ ذلك الحقلِ نصّاً: «الغيابُ = لا،
 * كي لا يُكشَفَ كودُ قناةٍ خاصّة (شريك/مؤثّر) لعمومِ العملاء» — قرارٌ
 * مُنفَّذٌ في الواجهةِ وحدَها، والبياناتُ مكشوفةٌ خلفَها.
 *
 * فالتحقّقُ هنا، والعميلُ لا يَحتاجُ بعدَه إلى قراءةِ المجموعةِ بالكودِ
 * إطلاقاً — وهو شرطُ تضييقِ القاعدةِ (انظر `firestore.rules`).
 *
 * يُعيدُ `{ok:false, reason}` بأحدِ أسبابِ `couponProblem` الستّة، أو
 * `{ok:true, coupon:{…}}` بالحقولِ التي تَعرضُها الشاشةُ وحدَها — لا
 * المستندَ كلَّه (`uses`/`target_user_id` لا شأنَ للعميلِ بهما).
 */
exports.validateCouponCode = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const code = String((request.data && request.data.code) || "")
      .trim().toUpperCase();
  if (!code) {
    throw new HttpsError("invalid-argument", "كود الخصم مطلوب");
  }
  const zoneName = request.data && request.data.zoneName ?
    String(request.data.zoneName) : null;
  // بلا مُرشِّحِ حالةٍ في الاستعلام: التسامحُ مع غيابِ `status` قرارُ
  // `couponProblem` وحدَها، وإقحامُه هنا يُعيدُ الافتراقَ الذي أُزيل.
  const snap = await getFirestore().collection("promo_codes")
      .where("code", "==", code).limit(1).get();
  const coupon = snap.empty ? null : snap.docs[0].data();
  const reason = coupons.couponProblem(coupon, {
    uid: request.auth.uid, zoneName,
  });
  if (reason) return {ok: false, reason};
  return {
    ok: true,
    coupon: {
      code: String(coupon.code || code),
      type: coupon.type === "fixed" ? "fixed" : "percentage",
      value: Number(coupon.value) || 0,
      // السقفُ يُعاد: العميلُ كان يَتجاهله بينما `couponDiscount` تُطبّقه،
      // فيَعرضُ خصماً أكبرَ مما يَمنحه الخادمُ ثمّ `trustedDiscount` تَأخذُ
      // الأصغرَ — فيَصيرُ `discount_amount` على الطلبِ أكبرَ من المحسوبِ
      // ويَنخفضُ `ratio` في تحقّقِ السعر. كامنٌ لا حيّ: لا محرّرَ يَكتبُ
      // `max_discount` في المستودعِ كلِّه.
      max_discount: coupon.max_discount != null ?
        Number(coupon.max_discount) || 0 : null,
      description: String(coupon.description || ""),
    },
  };
});

exports.redeemQatratPoints = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const pointsToRedeem = Number(request.data && request.data.pointsToRedeem);
  if (!Number.isInteger(pointsToRedeem) || pointsToRedeem < 50) {
    throw new HttpsError("invalid-argument", "الحد الأدنى للاستبدال 50 نقطة");
  }

  const walletRef = getFirestore().collection("wallets").doc(uid);
  const txRef = walletRef.collection("transactions").doc();

  const result = await getFirestore().runTransaction(async (t) => {
    const snap = await t.get(walletRef);
    const currentPoints = snap.exists ? Number(snap.data().qatrat_points || 0) : 0;
    const currentBalance = snap.exists ? Number(snap.data().balance || 0) : 0;
    if (currentPoints < pointsToRedeem) {
      throw new HttpsError("failed-precondition", "نقاطك غير كافية");
    }
    const financialCredit = pointsToRedeem / 50.0; // 50 points = 1 SAR
    t.set(walletRef, {
      qatrat_points: currentPoints - pointsToRedeem,
      balance: currentBalance + financialCredit,
      last_updated: FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(txRef, {
      amount: financialCredit,
      points: -pointsToRedeem,
      type: "qatrat_redeem",
      description: `استبدال ${pointsToRedeem} نقطة زيارة برصيد مالي`,
      created_at: FieldValue.serverTimestamp(),
    });
    return {newBalance: currentBalance + financialCredit, newPoints: currentPoints - pointsToRedeem};
  });

  return {success: true, ...result};
});

// 6c. Server-authoritative wallet rewards / refund on order status change.
// Mirrors sendNotificationOnOrderStatusChange. Gated on rewards_handled_by==='server'
// (written ONLY by the new app at order creation), so during rollout it never
// double-grants with the old app (which still grants client-side for its own,
// discriminator-less orders). Every effect is idempotent: an order flag checked+set
// inside the same wallet transaction PLUS a deterministic ledger doc id created with
// tx.create() — so at-least-once redelivery is a provable no-op.

/**
 * Enqueue an in-app + push notification via the existing trigger pipeline.
 * Server-originated (Admin SDK); type is never 'email' so no relay path is used.
 * @param {string} toUid Recipient uid (or "ADMIN_BROADCAST").
 * @param {string} title Notification title.
 * @param {string} body Notification body.
 * @param {string} type Notification type tag.
 * @param {object} data Extra data payload.
 * @return {Promise<void>}
 */
/**
 * يفكّ service_meta_json من بيانات دفعة Apple/Google/Samsung Pay بأمان.
 * الـ metadata نصوصٌ فقط، فنحمل service_meta كنصّ JSON ونعيد بناءه هنا — وإلّا
 * فُقِد تفصيل الخدمة (المكيفات/الكنب/السيارة) على الطلبات المُنشأة خادميّاً.
 * @param {string} s نصّ JSON.
 * @return {object|null}
 */
function _parseServiceMeta(s) {
  if (!s || typeof s !== "string") return null;
  try {
    const o = JSON.parse(s);
    return (o && typeof o === "object" && !Array.isArray(o)) ? o : null;
  } catch {
    return null;
  }
}

/**
 * مناداةُ العميلةِ باسمِها المسجَّل — أو بلا اسمٍ إن كان افتراضيّاً.
 *
 * كُتبت بيدٍ في **أربعةِ** مواضعَ متطابقةٍ حرفاً (تغيُّرُ حالةِ الطلب، نتيجةُ
 * الدفع، تذكيرُ الموعد، تأكيدُ تمارا)، وكنتُ على وشكِ كتابةِ الخامسةِ —
 * وهو شكلُ «٢٧ موضعاً للضريبة» بعينِه: إضافةُ اسمٍ افتراضيٍّ جديدٍ
 * («زائرة» مثلاً) تَعني تعديلَ أربعةِ مواضعَ معاً، وموضعٌ منسيٌّ يُنادي
 * العميلةَ «عميلة زيارة، موعدكِ…».
 *
 * @param {object} data مستندُ الطلب
 * @return {string} بادئةٌ تَنتهي بفاصلةٍ ومسافة، أو نصٌّ فارغ
 */
function _clientGreeting(data) {
  const rawName = ((data && data.client_name) || "").trim();
  return ["", "عميل", "عميلة", "عميل زيارة", "عميلة زيارة"].includes(rawName) ?
    "" : `${rawName}، `;
}

async function queuePush(toUid, title, body, type, data, targetRoles, recipientEmail) {
  // الطابورُ الخادميُّ — بلا قاعدةِ مطابقةٍ في firestore.rules، فلا يَكتبه عميل.
  await getFirestore().collection("notification_queue").add({
    toUid: toUid,
    title: title,
    body: body,
    type: type,
    data: data || {},
    // توجيه إشعارات الإدارة حسب الدور الفرعي (يُستخدم فقط مع ADMIN_BROADCAST).
    ...(Array.isArray(targetRoles) && targetRoles.length ? {targetRoles} : {}),
    // عنوان مستلم صريح للبريد (السائق مثلاً). بدونه يقع البريد على customerEmail
    // ثم على بريد الإدارة الافتراضي.
    ...(recipientEmail ? {recipientEmail} : {}),
    createdBy: "server",
    createdAt: FieldValue.serverTimestamp(),
    processed: false,
  });
}

/**
 * مسافة هافرساين بالأمتار بين نقطتين (محلّية — بلا اعتماديات) — تُستخدم للتحقّق
 * الهندسي من أن موقع الطلب داخل نصف قطر منطقته المُعلَنة.
 * @param {number} lat1 خط عرض النقطة الأولى.
 * @param {number} lng1 خط طول النقطة الأولى.
 * @param {number} lat2 خط عرض النقطة الثانية.
 * @param {number} lng2 خط طول النقطة الثانية.
 * @return {number} المسافة بالأمتار.
 */
function _haversineM(lat1, lng1, lat2, lng2) {
  const R = 6371000; // نصف قطر الأرض بالأمتار
  const toRad = (d) => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 2 * R * Math.asin(Math.sqrt(a));
}

/**
 * فحص هندسي لمسار التسعير الظلّي: المنطقة تُحَلّ باسم يرسله العميل (zone_name)
 * بلا أي تحقّق أن الموقع فعلاً داخلها — عميلٌ في منطقة أغلى يمكنه إرسال اسم
 * منطقة أرخص. عند تجاوز نصف القطر بهامش 20% (لحالات الأطراف) لا نحجب الدفع:
 * نَسِم الطلب zone_geo_mismatch + المسافة المقيسة وننبّه الإدارة (بنمط
 * price_unverifiable). يتجاهل بأمان الطلبات/المناطق بلا إحداثيات.
 * @param {FirebaseFirestore.DocumentReference} orderRef مرجع الطلب.
 * @param {string} orderId معرّف الطلب (للتنبيه).
 * @param {object} od بيانات الطلب (location, zone_name, code).
 * @param {object} zoneData بيانات المنطقة (centerLoc, radiusKm).
 * @return {Promise<number|null>} المسافة بالأمتار عند عدم التطابق، وإلا null.
 */
async function _flagZoneGeoMismatch(orderRef, orderId, od, zoneData) {
  if (!od || !zoneData) return null;
  if (od.zone_geo_mismatch === true) return null; // مُعلَّم ومُنبَّه سلفاً — لا تكرار
  const loc = od.location;
  const center = zoneData.centerLoc;
  const radiusKm = Number(zoneData.radiusKm);
  if (!loc || typeof loc.latitude !== "number" ||
      typeof loc.longitude !== "number") return null;
  if (!center || typeof center.latitude !== "number" ||
      typeof center.longitude !== "number") return null;
  if (!(radiusKm > 0)) return null;
  const distM = _haversineM(
      loc.latitude, loc.longitude, center.latitude, center.longitude);
  if (distM <= radiusKm * 1000 * 1.2) return null; // داخل النطاق (+هامش 20%)
  const distRounded = Math.round(distM);
  console.warn(`[price-shadow] ZONE_GEO_MISMATCH ${orderId}: ` +
      `${distRounded}m from «${od.zone_name || "?"}» center (radius ${radiusKm}km)`);
  await orderRef.update({
    zone_geo_mismatch: true,
    zone_geo_distance_m: distRounded,
  }).catch(() => {});
  await queuePush("ADMIN_BROADCAST", "موقع طلب خارج منطقته ⚠️",
      `الطلب #${od.code || orderId} موقعه يبعد ${(distM / 1000).toFixed(1)} كم عن ` +
      `مركز منطقة «${od.zone_name || "؟"}» المُسعَّر بها — يُرجى التحقّق من العنوان.`,
      "admin_price_review", {orderId, distanceM: String(distRounded)},
      ["super_admin", "orders_manager"]).catch(() => {});
  return distRounded;
}

// **`processReferralRewardServer` انتقلَ إلى `rewards.payReferralBonus`.**
// كان `catch`ه سطرَ `console.error("[referral] payout txn failed …")` وحدَه،
// والمعامَلةُ تَكتبُ خمسةَ مستنداتٍ معاً — ومنها ٥٠ ر.س إلى محفظةِ المُحيلِ
// وكوبونُ المُحالة — والمُشغّلُ بلا `retry` وحدثُ «أوّلُ طلبٍ مكتمل» لا
// يَعودُ أبداً. فصارَ الفشلُ يَكتبُ علمَه والمكنسةُ تُعيدُ المحاولة.

exports.onOrderRewards = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const orderId = event.params.orderId;

      const completed = before.status !== "completed" && after.status === "completed";
      const cancelled = before.status !== "cancelled" && after.status === "cancelled";
      if (!completed && !cancelled) return null;

      // Rollout gate: act ONLY on orders the new app created. Legacy/old-app
      // orders (no discriminator) keep being granted client-side by the old app.
      if (after.rewards_handled_by !== "server") {
        console.log(`[rewards] skip order ${orderId} reaching terminal status without server discriminator`);
        return null;
      }

      const db = getFirestore();
      const orderRef = db.collection("orders").doc(orderId);
      const clientId = after.client_id;
      const amount = Number(after.amount || 0);
      const code = after.code || orderId;

      // ── COMPLETION: Qatrat points (+ referral) ──
      if (completed) {
        if (clientId && amount > 0) {
          // **المنطقُ انتقلَ إلى `rewards.grantQatratPoints`.** كان هنا
          // إنلاين و`catch`ه سطرَ `console.error` وحدَه: فشلُ المعامَلةِ
          // يَعني نقاطاً لم تُضَف، ولا دفعةً للعميلة، ولا تنبيهاً للإدارة،
          // ولا محاولةً ثانية (هذا المُشغّلُ بلا `retry` ولا يَعودُ لمستندٍ
          // فاته الحدث). كان كلُّ ما يَبقى منه سطراً واحداً:
          // `[rewards] qatrat txn failed for …`. والفشلُ الآن يَكتبُ علمَه
          // و`opsHealthSweep` يُعيدُ المحاولة.
          await rewards.grantQatratPoints(db, {
            orderRef, orderId, clientId,
            points: Math.round(amount), code,
            alreadyAlerted: after.qatrat_alerted === true,
          }, queuePush);
        }
        if (clientId) {
          await rewards.payReferralBonus(db, {
        refereeUid: clientId, orderId, orderRef, code,
      }, queuePush);
        }
      }

      // ── CANCELLATION: refund a paid (non-subscription) order to the wallet ──
      if (cancelled) {
        // Guard against a DOUBLE refund: if the payment was already refunded through
        // the gateway (moyasarRefundPayment sets payment_status:'refunded'), do NOT
        // also credit the wallet.
        if (clientId && after.is_paid === true && after.needs_refund === true &&
            after.payment_method !== "subscription" && amount > 0 &&
            after.payment_status !== "refunded") {
          // **المنطقُ انتقلَ إلى `refunds.creditCancelledRefund`.** كان
          // هنا إنلاين و`catch`ه سطرَ `console.error` وحدَه: فشلُ المعامَلةِ
          // يَعني محفظةً لم تُودَع، ولا دفعةً للعميلة، ولا تنبيهاً للإدارة،
          // ولا محاولةً ثانيةً (هذا المُشغّلُ بلا `retry` ولا يَعودُ لمستندٍ
          // فاته الحدث) — مالُ العميلةِ يَبقى عندنا بلا أثر. والدالّةُ الآن
          // تُصعّدُ الفشلَ مرّةً واحدةً، و`opsHealthSweep` يُعيدُ المحاولة.
          await refunds.creditCancelledRefund(db, {
            orderRef, orderId, clientId, amount, code,
            alreadyAlerted: after.refund_credit_alerted === true,
          }, queuePush);
        }
      }
      return null;
    });

// 6c-bis. Sync order-linked records (maintenance request status + subscription visit
// count) fully server-side. The DRIVER cannot write users/maintenance_requests under
// the security rules, so doing this in the driver's client-side transaction failed and
// left subscription/maintenance orders stuck. This trigger (Admin SDK) does it instead.
// Idempotent: maintenance status mirroring is a plain set; visit accounting is guarded
// by a per-order `visit_counted` flag so re-delivery never double-counts, and a cancel
// only restores a visit that was actually consumed (kills the free-visit float).
exports.syncOrderLinkedRecords = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const orderId = event.params.orderId;

      const beforeStatus = before.status;
      const afterStatus = after.status;
      if (beforeStatus === afterStatus) return null;

      const db = getFirestore();
      const orderRef = db.collection("orders").doc(orderId);
      const maintenanceId = after.maintenance_id;
      const isSubscription = after.payment_method === "subscription";
      const clientId = after.client_id;

      // 1. Mirror status onto the linked maintenance request (set == idempotent)
      if (maintenanceId) {
        try {
          if (afterStatus === "in_progress") {
            await db.collection("maintenance_requests").doc(maintenanceId).set({
              status: "in_progress",
              startedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          } else if (afterStatus === "completed") {
            await db.collection("maintenance_requests").doc(maintenanceId).set({
              status: "completed",
              completedAt: FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        } catch (e) {
          console.error(`[linked] maintenance sync failed for ${orderId}:`, e.message);
        }
      }

      // 2. Subscription visit accounting — في `rewards.js`، **ومع قولِ الفشل**.
      //    كانت المعامَلتانِ إنلاين هنا بـ`catch` هو سطرُ `console.error`
      //    وحدَه، وهذا المُشغّلُ بلا `retry` فلا يَعودُ لمستندٍ فاته الحدث:
      //    فخصمٌ فاشلٌ يَترُكُ للعميلةِ زيارةً مدفوعةً استهلكَتها (تسريبُ
      //    إيرادٍ صامت)، وردٌّ فاشلٌ يُفقدُها زيارةً تَستحقُّها — بلا تنبيهٍ
      //    ولا محاولةٍ ثانية. والمكنسةُ تَستعلمُ **العلمَ** لا الحالة.
      if (isSubscription && clientId &&
          (afterStatus === "completed" || afterStatus === "cancelled")) {
        await rewards.settleVisitAccounting(db, {
          orderRef,
          orderId,
          clientId,
          status: afterStatus,
          code: after.code || orderId,
        }, queuePush);
      }
      return null;
    });

// 6c-ter. Count a coupon use server-side when an order carrying a coupon_code is
// created. The client never reliably incremented `uses`, so max_uses limits had no
// effect (unlimited reuse). Idempotent via a per-order `coupon_counted` flag.
exports.countCouponUseOnOrderCreate = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      // نعدّ استخدام الكوبون فقط عند تأكيد الدفع (is_paid يصبح true) — لا عند إنشاء
      // طلب قد يُهجَر بلا دفع (كان يستنزف maxUses بمحاولات فاشلة). idempotent.
      if (before.is_paid === true || after.is_paid !== true) return null;
      const code = after.coupon_code;
      if (!code || typeof code !== "string" || !code.trim()) return null;

      const db = getFirestore();
      const orderRef = change.after.ref;
      const q = await db.collection("promo_codes")
          .where("code", "==", code.toUpperCase()).limit(1).get();
      if (q.empty) return null;
      const promoRef = q.docs[0].ref;

      // **المنطقُ انتقلَ إلى `rewards.countCouponUse`.** كان هنا إنلاين
      // و`catch`ه سطرَ `console.error` وحدَه: فشلُ المعامَلةِ يَعني `uses`
      // لم يُزَد، فكوبونٌ لمرّةٍ واحدةٍ يَبقى قابلاً للإنفاق — و
      // `coupons.couponProblem` يَبني «exhausted» على ذلك العدّادِ بعينِه،
      // فالمنعُ الخادميُّ يَسقطُ معه. والمُشغّلُ بلا `retry` ولا يَعودُ
      // لمستندٍ فاته الحدث، فلا محاولةَ ثانية — وكلُّ ما يَبقى سطرٌ واحد:
      // `[coupon] use-count failed for order …`. والفشلُ الآن يَكتبُ علمَه
      // و`opsHealthSweep` يُعيدُ المحاولة.
      await rewards.countCouponUse(db, {
        orderRef, orderId: event.params.orderId, promoRef, code,
        alreadyAlerted: after.coupon_count_alerted === true,
      }, queuePush);
      return null;
    });

// 6c-ter. إشعار العميل والسائق عند **تغيير موعد الزيارة** لطلب مُسنَد نشط — كان تعديل
// الموعد من لوحة الإدارة يُكتب بصمت (لا مُشغّل يرصد service_date)، فيذهب السائق للموعد
// القديم أو ينتظر العميل في وقت خاطئ. لا نُشعر عند الإسناد الجديد (يغطّيه مُشغّل الإسناد).
exports.notifyOnAppointmentChange = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      const bSd = before.service_date;
      const aSd = after.service_date;
      const changed = bSd && aSd &&
        typeof bSd.toMillis === "function" &&
        typeof aSd.toMillis === "function" &&
        bSd.toMillis() !== aSd.toMillis();
      if (!changed) return null;
      if (after.is_paid !== true) return null;
      const activeStatuses = ["scheduled", "accepted", "assigned",
        "on_the_way", "in_progress"];
      if (!activeStatuses.includes(after.status)) return null;
      // تغيّر السائق مع الموعد: إشعار السائق الجديد يغطّيه notifyDriverOnAssignment
      // (والقديم freeOldDriverOnReassign) — لكن **العميل يجب أن يعرف موعده الجديد
      // دائماً**؛ كان الخروج الكامل هنا يتركه بلا أي إشعار عند تغيير الوقت+السائق معاً.
      const driverChanged =
        (before.driver_id || null) !== (after.driver_id || null);

      // توقيت الرياض (UTC+3) — الصيغة في ksa_time.js: الدوال تعمل بـUTC، فقراءة
      // المكوّنات المحلية من لحظة زمنية تُعلن للطرفين ساعةً أبكر بثلاث ساعات.
      const dateStr = riyadhStamp(aSd.toDate().getTime());
      const code = after.code || event.params.orderId;
      const oid = event.params.orderId;

      if (after.client_id) {
        await queuePush(after.client_id, "تم تغيير موعد زيارتك 🗓️",
            `موعد طلبك #${code} أصبح ${dateStr}.`,
            "appointment_changed", {orderId: oid}).catch((e) =>
          console.error("notifyOnAppointmentChange client:", e.message));
      }
      if (after.driver_id && !driverChanged) {
        await queuePush(after.driver_id, "تم تغيير موعد مهمة 🗓️",
            `موعد الطلب #${code} أصبح ${dateStr}.`,
            "appointment_changed", {orderId: oid}).catch((e) =>
          console.error("notifyOnAppointmentChange driver:", e.message));
      }
      return null;
    });

// 6d. Server-authoritative wallet-as-payment deduction. Replaces the client-side
// wallet balance write in payment_summary_screen (the LAST direct client wallet
// write), so the wallets write rule can be locked down later. Takes the amount
// because in the wallet-checkout flow the order doc is created AFTER payment.
// Atomic + server-side balance check so a client can never overdraw or forge it.
exports.payWithWallet = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const amount = Number(request.data && request.data.amount);
  const note = (request.data && request.data.description) || "دفع خدمة من المحفظة";
  // orderId اختياري (توافق رجعي). عند تمريره، خصم الرصيد وقلب is_paid على الطلب
  // يحدثان ذرّياً، فلا يمكن تزوير is_paid من العميل لمدفوعات المحفظة.
  const orderId = request.data && request.data.orderId;
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new HttpsError("invalid-argument", "المبلغ غير صالح");
  }

  const db = getFirestore();
  const walletRef = db.collection("wallets").doc(uid);
  const txRef = orderId ?
    walletRef.collection("transactions").doc(`wallet_pay_${orderId}`) :
    walletRef.collection("transactions").doc();
  const orderRef = orderId ? db.collection("orders").doc(orderId) : null;

  // (تسعير خادمي للمحفظة) حقل amount يكتبه العميل، وفحص المطابقة أدناه يقارن به
  // نفسَه — فكان طلبُ باقةٍ مزوَّر بـ1 ر.س يمرّ من المحفظة بلا أي علم (مسار ميسر
  // يحميه verifyMoyasarPayment، والمحفظة كانت مستثناة). نعيد حساب سعر الباقة من
  // zone.packages الموثوق: فجّ (<20%) يُرفض، ودون النصف يُعلَّم price_mismatch.
  let pkgExpectedGross = null;
  if (orderRef) {
    try {
      const pre = await orderRef.get();
      const od = pre.exists ? pre.data() : null;
      // كل الأنواع تُعاد تسعيرتها — كان الشرط `kind === 'home_package'` يترك بقية
      // الخدمات (بالساعة/الكنب/المكيفات/السيارات/المناسبات) تُدفع من المحفظة بأي
      // مبلغ يكتبه العميل. computeExpectedBasePrice تُرجع null لغير القابل للتحقق
      // (المتجر) فلا يُرفض دفعٌ بلا يقين — نفس سلوك مسار ميسر تماماً.
      // حلُّ المنطقةِ عبر `price_verify` نفسِه الذي يَستخدمُه مسارُ ميسر: كان
      // هنا `zone_name` وحدَه، ولو غابَ تُخطّى التحقّقُ كلُّه بلا وسمٍ ولا
      // تنبيه — وهي الثغرةُ التي سدَّها مسارُ ميسر بنصِّ تعليقِه («إسقاط
      // zone_name للتهرّب من التحقّق») مفتوحةً في المسارِ الآخر.
      const zoneData = od ? await priceVerify.resolveZone(db, od) : null;
      if (od && zoneData) {
        // تحقّق هندسي (نفس مسار ميسر): وسم + تنبيه إداري عند موقعٍ خارج نصف
        // قطر المنطقة المُعلَنة — لا يحجب الدفع.
        await _flagZoneGeoMismatch(orderRef, orderId, od, zoneData)
            .catch((e) => console.error("[wallet-pricing] geo:", e.message));
        // مواد التنظيف داخل الطلب: تُسعَّر من products قبل الحساب. null =
        // تعذّر التحقق ⇒ نترك pkgExpectedGross فارغاً (لا نرفض بلا يقين).
        const matBase = await resolveMaterialsBase(db, od.service_meta);
        const base0 = matBase === null ? null :
          computeExpectedBasePrice(
              {...od, materials_base_resolved: matBase}, zoneData);
        // رسوم الوعورة من مستند المنطقة (لا من الطلب) فوق الأساس قبل الضريبة.
        const base = base0 && base0 > 0 ?
          applyTerrainSurcharge(base0, zoneData) : base0;
        if (base && base > 0) {
          const surge = await _readSurgeFactor(db);
          const expected = grossFromBaseRounded(base, surge);
          // **الخصمُ الموثوقُ يُطرَح** — كما في مسارِ ميسر. كان غائباً هنا،
          // فكوبونٌ نسبتُه أكثرُ من 50% يُوسمُ دفعاً سليماً `price_mismatch`،
          // وأكثرُ من 80% يُرفضُ أصلاً برسالةِ «المبلغ لا يطابق السعر
          // المعتمد» — في وجهِ عميلةٍ تَدفعُ ما طُلب منها بالضبط.
          const trusted = await _computeTrustedDiscount(
              db, od, grossFromBase(base), surge, {orderRef, orderId});
          pkgExpectedGross = Math.max(0, expected - trusted);
        }
      } else if (od && priceVerify.isPriceableKind(od)) {
        // نوعٌ قابلٌ للتسعيرِ بلا منطقةٍ محلولة: مسارُ ميسر يَسِمُ ويُنبّه،
        // وهذا المسارُ كان يَمضي صامتاً. (التنبيهُ هنا لأنّ الوسمَ وحدَه
        // لا يَراه أحدٌ في حينِه.)
        console.warn(`[wallet-pricing] UNVERIFIABLE ${orderId}: priceable kind but no zone/base`);
        // **ثلاثُ مواضعَ تَسِمُ `price_unverifiable` ولا مكنسةَ لها** — فكانت
        // الدفعةُ المُبتلَعةُ هي كلَّ ما هناك: تَفشلُ فلا يَعلمُ أحدٌ أبداً.
        // الآن تُسجَّلُ نتيجةُ الدفعةِ في `ops_alerted_unverifiable`
        // والمكنسةُ تَستعلمُ ما لم يُنبَّه.
        const alertedU1 = await queuePush("ADMIN_BROADCAST", "طلب تعذّر التحقّق من سعره ⚠️",
            `الطلب #${od.code || orderId} مدفوعٌ من المحفظة ومن نوعٍ قابلٍ للتسعير لكن تعذّر التحقّق من مبلغه — يُرجى المراجعة.`,
            "admin_price_review", {orderId},
            ["super_admin", "orders_manager", "accountant_admin"])
            .then(() => true).catch(() => false);
        await orderRef.update({
          price_unverifiable: true,
          ops_alerted_unverifiable: alertedU1,
        }).catch(() => {});
      }
    } catch (e) {
      console.error("[wallet-pricing] recompute failed:", e.message);
    }
  }
  // **`0` ليس «لا تحقّق».** `null` تعني تعذّر التحقّق، والصفرُ يعني خصماً
  // يَبلغُ السعرَ كاملاً — ومع دفعٍ موجبٍ فهو مريب، وهو ما يُسمّيه مسارُ ميسر
  // `suspiciousZero` ويَسِمُه Tier A. وكان `if (pkgExpectedGross && …)`
  // يَقرأُ الصفرَ كاذباً **فيُطفئُ الفحصَين معاً** — نفسُ شكلِ «الصفرُ قرارٌ
  // لا غياب» في `amounts.js`. (أُدخلت هذه الحالةُ بطرحِ الخصمِ الموثوق؛
  // قبلَه كان `expected > 0` دائماً.)
  const verifiable = pkgExpectedGross !== null;
  const suspiciousZero = verifiable && pkgExpectedGross === 0 && amount > 0;
  if (verifiable && pkgExpectedGross > 0 &&
      amount < pkgExpectedGross * 0.2) {
    throw new HttpsError("failed-precondition",
        "المبلغ لا يطابق السعر المعتمد لمنطقتك");
  }
  // لا رفضَ على `suspiciousZero`: مسارُ ميسر لا يَرفضُه كذلك — أرضيّةُ
  // `expectedNet >= 5` فيه تَستثني كوبونَ الـ~100% عمداً، فرفضُه هنا كان
  // سيُعيدَ الخللَ الذي طرحُ الخصمِ أصلحَه، في الاتجاهِ المقابل.
  if (suspiciousZero ||
      (verifiable && pkgExpectedGross > 0 &&
       amount < pkgExpectedGross * 0.5)) {
    await orderRef.update({
      price_mismatch: true,
      // **العلمُ يُكتَبُ `false` صراحةً ولا يُترَكُ غائباً.** مكنسةُ
      // `opsHealthSweep` تَستعلمُ مساواتَين الآن — الوسمَ و«لم يُنبَّه بعد» —
      // فلا تَحوي نافذتُها إلّا ما لم يُنبَّه؛ ومستندٌ بحقلٍ **غائبٍ** لا
      // يُطابقُ `== false` فيَسقطُ منها. وهذا المسارُ يَسِمُ بصمتٍ عمداً
      // ويَتّكلُ على المسحِ وحدَه، فهو أوّلُ من يَخسرُ لو غابَ الحقل.
      ops_alerted_mismatch: false,
      price_expected: pkgExpectedGross,
      // والمدفوعُ يُحفَظُ: بطاقةُ المراجعةِ في شاشةِ الطلبِ تَقولُ «دُفع كذا
      // مقابل كذا» بلا حسابٍ عكسيٍّ من النسبة.
      price_paid: amount,
    }).catch(() => {});
  }

  const result = await db.runTransaction(async (t) => {
    const wSnap = await t.get(walletRef);
    let oSnap = null;
    if (orderRef) {
      oSnap = await t.get(orderRef);
      if (!oSnap.exists) {
        throw new HttpsError("not-found", "الطلب غير موجود");
      }
      if (oSnap.get("client_id") !== uid) {
        throw new HttpsError("permission-denied", "لا يمكن الدفع لطلب مستخدم آخر");
      }
      if (oSnap.get("is_paid") === true) {
        const bal = wSnap.exists ? Number(wSnap.data().balance || 0) : 0;
        return {success: true, newBalance: bal, alreadyPaid: true};
      }
      const trueAmount = Number(oSnap.get("amount") || 0);
      if (trueAmount > 0 && Math.abs(trueAmount - amount) > 0.01) {
        throw new HttpsError("failed-precondition", "المبلغ لا يطابق مبلغ الطلب");
      }
    }
    const balance = wSnap.exists ? Number(wSnap.data().balance || 0) : 0;
    if (balance < amount) {
      throw new HttpsError("failed-precondition", "الرصيد غير كافٍ");
    }
    t.set(walletRef, {
      balance: balance - amount,
      last_updated: FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(txRef, {
      amount: -amount, points: 0, type: "payment",
      description: note,
      ...(orderId ? {order_id: orderId} : {}),
      created_at: FieldValue.serverTimestamp(),
    });
    if (orderRef) {
      // دفاع في العمق لسباق cancelStaleUnpaidOrders: إن تأكّد دفعُ طلبٍ سبق أن
      // ألغاه الكرون آلياً (cancel_reason='unpaid_expired' بعد نافذة الـ30 دقيقة)
      // نُعيد فتحه (pending) بدل تركه ملغىً مدفوعاً بلا خدمة — داخل نفس معامَلة
      // قلب is_paid فلا سباق. المسارات الثلاثة الأخرى (verify/webhook/reconcile)
      // تفعل هذا، والمحفظة كانت الرابعة التي لا تفعله: التعليقُ الذي يصف هذا
      // الدفاع كان قائماً في الملف بلا الكود الذي يصفه. كامنٌ لا حيّ اليوم —
      // لا مسارَ واجهةٍ يُنشئ طلباً ثمّ يدفعه بالمحفظة بعد 30 دقيقة (الشاشة
      // تسكّ معرّفاً جديداً لكل محاولة) — لكن payWithWallet نداءٌ عامّ يقبل أي
      // معرّف طلبٍ يملكه العميل، فالتكافؤ هو الحارس.
      t.update(orderRef, {
        is_paid: true,
        payment_status: "paid",
        payment_method: "wallet",
        paid_at: FieldValue.serverTimestamp(),
        updated_at: FieldValue.serverTimestamp(),
        ...refunds.reopenFieldsIfSystemCancelled(oSnap && oSnap.data()),
      });
    }
    return {success: true, newBalance: balance - amount};
  });

  // إشعار العميل بتأكيد الدفع بالمحفظة (كان صامتاً) — بعد نجاح المعاملة، وأول مرّة فقط.
  if (orderId && !result.alreadyPaid) {
    getFirestore().collection("orders").doc(orderId).get()
        .then((s) => s.exists &&
          notifyClientPaymentResult("orders", orderId, s.data(), true))
        .catch((e) => console.error("notify after wallet pay:", e));
  }
  return result;
});

// (#1) عامل الذروة الخادمي — يعكس getSurgePricingFactor حرفياً (system_configs.surge_percent).
async function _readSurgeFactor(db) {
  try {
    const cfg = await db.collection("system_configs").doc("main_settings").get();
    const pct = Number(cfg.exists ? cfg.data().surge_percent : 0);
    if (!Number.isFinite(pct) || pct <= 0) return 1.0;
    const capped = Math.min(pct, 100);
    return Math.round((1 + capped / 100) * 100) / 100;
  } catch {
    return 1.0;
  }
}

// (#1) الخصم **الموثوق** — يُعاد حسابه من مستند الكوبون (promo_codes)، لا من حقل
// discount_amount الذي يكتبه العميل (وإلّا ضخّمه فألغى الإنفاذ). نأخذ الأصغر بين خصم
// العميل والخصم الخادمي: لا يستطيع تجاوز القيمة الخادمية، ونحترم خصمه الأقل.
//
// والأهليّة في coupons.js لا هنا: كانت هذه الدالّة تُجيب **المقدار** وتُغفل
// **مَن ومِن أين وكم مرّة** (target_user_id / restricted_zones / maxUses)،
// فيثق الخادم بالعميل في الأهليّة وحدها — وهو عين ما وُجدت الدالّة لتمنعه.
// وترفع {orderRef, orderId} كي يُسَم سببُ الرفض: رفضُ خصمٍ 10% يُنتج ratio=0.9
// فلا يبلغ عتبة الوسم (0.5) — إنفاذٌ بلا وسمٍ تجميليّ.
async function _computeTrustedDiscount(db, od, expectedGross, surge,
    {orderRef = null, orderId = null} = {}) {
  const code = (od.coupon_code || "").toString().trim();
  if (!code) return 0;
  try {
    const q = await db.collection("promo_codes")
        .where("code", "==", code.toUpperCase()).limit(1).get();
    const c = q.empty ? null : q.docs[0].data();
    const problem = coupons.couponProblem(c, {
      uid: od.client_id || od.userId || null,
      zoneName: od.zone_name || null,
    });
    if (problem) {
      console.warn(`[price-shadow] COUPON_REJECTED ${orderId || ""} ${code}: ${problem}`);
      if (orderRef) {
        await orderRef.update({
          coupon_rejected: true,
          coupon_rejected_reason: problem,
        }).catch(() => {});
      }
      if (coupons.ESCALATED_PROBLEMS.has(problem)) {
        await queuePush("ADMIN_BROADCAST", "كوبون غير مؤهَّل على طلب ⚠️",
            `الطلب #${od.code || orderId || ""} استعمل الكود ${code} وهو ` +
            `${problem === "other_user" ? "موجَّه لعميل آخر" : "مقيَّد بمنطقة أخرى"}` +
            " — أُلغي الخصم خادميّاً، يُرجى المراجعة.",
            "admin_coupon_review", {orderId: orderId || ""},
            ["super_admin", "orders_manager", "accountant_admin"]).catch(() => {});
      }
      return 0;
    }
    return coupons.trustedDiscount(od.discount_amount,
        coupons.couponDiscount(c, {chargedGross: expectedGross, surge}));
  } catch (e) {
    console.error("[price-shadow] discount recompute failed:", e.message);
    return 0;
  }
}

// (#1) هل الطلب من نوعٍ يُعاد تسعيره خادميّاً؟ (بالساعة أو كنب/مكيّف/سيارة). نستعمله
// لتعليم «تعذّر التحقّق» حين يبدو الطلب قابلاً للتسعير لكن غابت منطقته/تعذّر حسابه.

// 7. Secure Moyasar payment verification on Call function
/**
 * تحقّقُ السعرِ الخادميُّ (Tier A) — **مصدرٌ واحدٌ لكلِّ مسارٍ يَقلبُ `is_paid`
 * على `orders`**، بعد أن كان مكتوباً داخل `verifyMoyasarPayment` وحدَه.
 *
 * **الثغرةُ التي يَسدّها:** الحقلُ `amount` على الطلبِ يَكتبه العميلُ، وهذا
 * الفحصُ هو ما يُعيدُ حسابَ السعرِ من مستندِ المنطقةِ الموثوقِ ويَسِمُ النقصَ
 * ويُنبّهُ الإدارة. وكانت المسالكُ خمسةً إلى `is_paid: true` على طلبٍ دفعته
 * العميلة، والفحصُ على اثنتَين منها فقط — وكلتاهما `onCall` **يَختارُ العميلُ
 * نداءَها**:
 *
 *   * `moyasarWebhook` لا يُعيدُ تسعيراً إطلاقاً. فحصُه الوحيدُ
 *     `verifiedPayment.amount === expectedAmount(data)`، و`expectedAmount` هو
 *     `final_amount ?? total_amount ?? planPrice ?? amount` — **وكلُّها يَكتبها
 *     العميلُ عند الإنشاء**، فالمقارنةُ «المدفوعُ = المُعلَن» لا «المُعلَنُ =
 *     سعرُ المنطقة». ومُعلِنُ ريالٍ يَدفعُ ريالاً فيَمرّ.
 *   * و`verifyMoyasarPayment` يَرتدُّ مبكّراً على `is_paid === true` **قبلَ**
 *     الفحص، فالويب هوكُ إن سَبَقَ (وهو يَسبقُ كثيراً: تُطلقه ميسر من خادمٍ
 *     إلى خادمٍ لحظةَ الدفع، بينما النداءُ يَنتظرُ عودةَ التطبيق) **استَهلكَ
 *     الفحصَ كلَّه**. ومُتلاعبٌ لا يُناديه أصلاً.
 *   * و`_tamaraFlipPaid` (الويب هوك ومسحُ `confirmPendingTamaraOrders`) بلا
 *     أيِّ فحصِ مبلغٍ على الإطلاق.
 *
 * فالنتيجةُ: وسمُ `price_mismatch` والتنبيهُ الإداريُّ و**Tier B**
 * (`ENFORCE_PRICE_TIER_B === true`، أي الإلغاءُ/الاستردادُ الآليّ) كلُّها
 * تُتخطّى بمجرّدِ عدمِ نداءِ `verifyMoyasarPayment`.
 *
 * Tier B هنا يُعادُ **سبباً** لا فعلاً: المُنادي يَملكُ معرّفَ الدفعةِ وسرَّ
 * البوّابة. و`refunds.voidOrRefundTampered` **مُتماهلٌ** (يَحجزُ بمعامَلةٍ على
 * `tamper_handled`)، فنداؤه من مسارَين لا يُلغي مرّتَين.
 *
 * @param {object} db Firestore
 * @param {object} orderRef مرجعُ مستندِ الطلب
 * @param {string} orderId معرّفُ الطلب
 * @param {object} od بياناتُ الطلب
 * @param {number} paid المبلغُ المخصومُ فعلاً بالريال
 * @param {string} source المسارُ المُنادي — للسجلّ وحدَه (verify/webhook/tamara)
 * @return {Promise<?string>} سببُ Tier B أو `null`
 */
async function _verifyOrderPriceTierA(db, orderRef, orderId, od, paid, source) {
  try {
  // حلّ المنطقة في `price_verify.resolveZone` (zone_id ثمّ الاسم) —
  // مصدرٌ واحدٌ مع مسار المحفظة، وكان المسارانِ يَختلفان.
  const zoneData = await priceVerify.resolveZone(db, od);
  // تحقّق هندسي أن موقع الطلب داخل نصف قطر المنطقة المُعلَنة — الاسم وحده
  // كان يكفي لتسعير منطقةٍ أرخص لعنوان أبعد. لا يحجب الدفع (وسم + تنبيه).
  if (zoneData) {
    await _flagZoneGeoMismatch(orderRef, orderId, od, zoneData)
        .catch((e) => console.error(`[price-shadow:${source}] geo ${orderId}:`, e.message));
  }
  // مواد التنظيف المضافة داخل الطلب تُسعَّر من products قبل الحساب؛
  // null = تعذّر التحقق ⇒ لا نُعيد تسعيراً ولا نرفض دفعاً بلا يقين.
  const matBase = await resolveMaterialsBase(db, od.service_meta);
  const base0 = (zoneData && matBase !== null) ?
    computeExpectedBasePrice(
        {...od, materials_base_resolved: matBase}, zoneData) : null;
  // رسوم الوعورة (terrain_surcharge_percent على مستند المنطقة) فوق الأساس
  // قبل الضريبة — الذروة والخصم الموثوق والضريبة تُحسب على الأساس المُرسَّم.
  const base = base0 && base0 > 0 ?
    applyTerrainSurcharge(base0, zoneData) : base0;
  if (base && base > 0) {
    const surge = await _readSurgeFactor(db);
    const expected = grossFromBaseRounded(base, surge);
    const trustedDiscount =
        await _computeTrustedDiscount(db, od, grossFromBase(base),
            surge, {orderRef, orderId});
    const expectedNet = Math.max(0, expected - trustedDiscount);
    // expectedNet<=0 مع دفعٍ موجب = مريب (خصم يفوق السعر) → Tier A، لا نفترض ratio=1.
    const suspiciousZero = expectedNet <= 0 && paid > 0;
    const ratio = expectedNet > 0 ? paid / expectedNet : (suspiciousZero ? 0 : 1);
    const fresh = od.created_at &&
        typeof od.created_at.toMillis === "function" &&
        (Date.now() - od.created_at.toMillis()) < 2 * 60 * 60 * 1000;
    const kind = (od.service_meta && od.service_meta.kind) || "hourly";
    if (ratio < 0.5 || suspiciousZero) {
      console.warn(`[price-shadow:${source}] UNDERPAID ${orderId}: paid=${paid} expected=${expected} net=${expectedNet} ratio=${ratio.toFixed(3)} kind=${kind}`);
      // **التنبيهُ أوّلاً، ثمّ ادّعاؤه.** كان `ops_alerted_mismatch: true`
      // يُكتَبُ **قبلَ** دفعةٍ مُبتلَعةٍ بـ`.catch(() => {})`: ففشلُ الدفعةِ
      // يَترُكُ على المستندِ «نبّهنا عنه» وهو لم يُنبَّه، و`alertBatch`
      // تُسقِطُ كلَّ مستندٍ العلمُ فيه `true` — فيُدفَنُ الوسمُ للأبد. وهو
      // عكسُ النظامِ الذي تَنصُّ عليه `alertBatch` نفسُها: «الوسمُ **بعد**
      // نجاحِ الإشعارِ فقط — فشلُ الإرسالِ يَترُكُ الفئةَ لدورةٍ قادمةٍ بدلَ
      // إخراسِها للأبد».
      const alertedM = await queuePush("ADMIN_BROADCAST", "مراجعة سعر طلب ⚠️",
          `الطلب #${od.code || orderId} مدفوع ${paid} ر.س مقابل ${expectedNet} متوقَّع (${kind}) — يُرجى المراجعة.`,
          "admin_price_review",
          {orderId, ratio: String(Math.round(ratio * 1000) / 1000)},
          ["super_admin", "orders_manager", "accountant_admin"])
          .then(() => true).catch(() => false);
      await orderRef.update({
        price_mismatch: true,
        ops_alerted_mismatch: alertedM,
        price_paid: paid,
        price_expected: expected,
        price_expected_net: expectedNet,
        price_shadow_ratio: Math.round(ratio * 1000) / 1000,
      }).catch(() => {});
      // Tier B: أقل من خُمس المتوقَّع، على طلبٍ حديث موثوق الحساب، بمخرجٍ ≥ 5 ر.س
      // (أرضية تمنع إيجابيةً كاذبة من التقريب على مقامٍ ضئيل عند كوبون ~100%).
      const egregious = ratio < 0.2 && expectedNet >= 5 && fresh &&
          od.server_created_from_payment !== true;
      if (egregious && ENFORCE_PRICE_TIER_B) return "price_review";
    }
  } else if (priceVerify.isPriceableKind(od)) {
    // نوعٌ قابل للتسعير لكن تعذّر حسابه (منطقة غائبة/غير محلولة) → لا نُمرّره
    // بصمت؛ نُعلّم وننبّه (Tier A) — يسدّ ثغرة إسقاط zone_name للتهرّب من التحقّق.
    console.warn(`[price-shadow:${source}] UNVERIFIABLE ${orderId}: priceable kind but no zone/base`);
    const alertedU2 = await queuePush("ADMIN_BROADCAST", "طلب تعذّر التحقّق من سعره ⚠️",
        `الطلب #${od.code || orderId} من نوعٍ قابل للتسعير لكن تعذّر التحقّق من مبلغه — يُرجى المراجعة.`,
        "admin_price_review", {orderId},
        ["super_admin", "orders_manager", "accountant_admin"])
        .then(() => true).catch(() => false);
    await orderRef.update({
      price_unverifiable: true,
      ops_alerted_unverifiable: alertedU2,
    }).catch(() => {});
  }
  } catch (e) {
    console.error(`[price-shadow:${source}] ${orderId}:`, e.message);
  }
  return null;
}

/**
 * تحقّقُ سعرِ **طلبِ المتجر** (Tier A، وسمٌ وتنبيهٌ لا رفض).
 *
 * `store_service.dart` يُسعّرُ السلّةَ من `products` داخلَ معامَلةٍ ويَكتبُ
 * `total_amount` و`items` — **لكنّه يَفعلُ ذلك في العميل**، واسمُ متغيّرِه
 * `serverCalculatedTotal` يُوهِمُ بغيرِ ذلك. ومُتلاعبٌ يَكتبُ المستندَ من
 * الـSDK مباشرةً يُعلِنُ ما شاء: القواعدُ تَشترطُ `is_paid: false`
 * و`client_id` ولا تَفحصُ المبلغ، وفحصُ `moyasarWebhook` الوحيدُ «المدفوعُ =
 * المُعلَن» وكلُّ حقولِ `expectedAmount` يَكتبُها هو. فسلّةٌ بخمسِ مئةٍ
 * تُعلَنُ بريالٍ وتُدفَعُ بريالٍ وتُشحَن — ولا تحقّقَ خادميٌّ للمتجرِ من أيِّ
 * نوعٍ أصلاً (`computeExpectedBasePrice` تُعيدُ `null` له، فسلسلةُ Tier A
 * كلُّها مقصورةٌ على `orders`).
 *
 * **وسمٌ وتنبيهٌ فقط، ولا رفضَ بحال** — والقرارُ مقصود: الرفضُ يَحجبُ دفعةَ
 * عميلةٍ حقيقيّةٍ إن أخطأتُ في الضريبةِ أو التقريب، وهو عينُ ما عضَّ مسارَ
 * المحفظةِ مرّتَين هذه الجلسة (كوبونُ ما فوقَ 50%، ثمّ المتوقَّعُ صفراً).
 * فالمُلحُّ هو «لا يَعرفُ أحد»، وهذا ما يُغلقه.
 *
 * @param {object} db Firestore
 * @param {object} ref مرجعُ مستندِ طلبِ المتجر
 * @param {string} orderId معرّفُه
 * @param {object} od بياناتُه
 * @param {number} paid المبلغُ المخصومُ فعلاً بالريال
 * @param {string} source المسارُ المُنادي — للسجلّ
 * @return {Promise<void>}
 */
async function _verifyStoreOrderPrice(db, ref, orderId, od, paid, source) {
  try {
    if (!(paid > 0)) return;
    const base = await resolveStoreCartBase(db, od && od.items);
    // `null` = تعذّر التسعير (منتجٌ محذوفٌ أو عنصرٌ بلا معرّف) — لا وسمَ بلا
    // يقين، لكن لا صمتَ أيضاً: نُنبّهُ كما يفعلُ نظيرُه في `orders`.
    if (base === null) {
      console.warn(`[store-price:${source}] UNVERIFIABLE ${orderId}: cart not priceable`);
      const alertedU3 = await queuePush("ADMIN_BROADCAST", "طلب متجر تعذّر التحقّق من سعره ⚠️",
          `طلب المتجر #${od.code || orderId} تعذّر تسعيرُ سلّته من products — يُرجى المراجعة.`,
          "admin_price_review", {orderId},
          ["super_admin", "orders_manager", "accountant_admin"])
          .then(() => true).catch(() => false);
      await ref.update({
        price_unverifiable: true,
        ops_alerted_unverifiable: alertedU3,
      }).catch(() => {});
      return;
    }
    if (!(base > 0)) return;
    const expected = grossFromBaseRounded(base);
    // تفاوتُ ريالٍ واحدٍ مسموحٌ: التقريبُ ورسومٌ قد تُضافُ إداريّاً.
    if (paid >= expected - 1) return;
    const ratio = Math.round((paid / expected) * 1000) / 1000;
    console.warn(`[store-price:${source}] UNDERPAID ${orderId}: paid=${paid} expected=${expected} ratio=${ratio}`);
    // المكنسةُ تَمسحُ `store_orders` أيضاً الآن، فالعلمُ يُكتَبُ بقيمةِ
    // نجاحِ الدفعةِ لا `true` دائماً — وبلا هذا الترتيبِ كان توسيعُ المسحِ
    // **عقيماً**: العلمُ المضبوطُ سلفاً يُسكِتُه عن كلِّ مستند.
    const alertedS = await queuePush("ADMIN_BROADCAST", "مراجعة سعر طلب متجر ⚠️",
        `طلب المتجر #${od.code || orderId} مدفوع ${paid} ر.س مقابل ${expected} متوقَّع من أسعار products — يُرجى المراجعة.`,
        "admin_price_review", {orderId, ratio: String(ratio)},
        ["super_admin", "orders_manager", "accountant_admin"])
        .then(() => true).catch(() => false);
    await ref.update({
      price_mismatch: true,
      ops_alerted_mismatch: alertedS,
      price_paid: paid,
      price_expected: expected,
      price_shadow_ratio: ratio,
    }).catch(() => {});
  } catch (e) {
    console.error(`[store-price:${source}] ${orderId}:`, e.message);
  }
}

exports.verifyMoyasarPayment = onCall(
    {secrets: ["MOYASAR_SECRET_KEY"], cpu: 0.25},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
      }

      const {paymentId, orderId} = request.data;
      if (!paymentId || !orderId) {
        throw new HttpsError("invalid-argument", "بيانات التحقق غير مكتملة");
      }

      const secret = moyasarSecretKey.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح Moyasar السري غير مهيأ في الخادم");
      }
      // نجلب الدفعة من Moyasar أولاً — نحتاج metadata لإنشاء الطلب خادميّاً إن غاب.
      // `moyasar.getPayment` يبتلع خطأ الشبكة ويُعيد ok:false، فيُرمى هنا نفس
      // HttpsError المقصود بدل رسالة الاستثناء الخامّة التي كانت تصعد.
      const got = await moyasar.getPayment(secret, paymentId);
      if (!got.ok) {
        console.error("Moyasar API response error:", got.error ?? got.raw);
        throw new HttpsError("internal", "فشل التحقق من الدفع مع بوابة Moyasar");
      }
      const paymentData = got.raw;
      if (paymentData.status !== "paid") {
        throw new HttpsError("failed-precondition", `حالة عملية الدفع ليست مدفوعة: ${paymentData.status}`);
      }

      const db = getFirestore();

      // ابحث عن الطلب في المجموعات المعروفة (منع التلاعب: المبلغ المرجعي من الطلب).
      let trueAmount = null;
      let orderRef = db.collection("orders").doc(orderId);
      let orderDoc = await orderRef.get();
      if (orderDoc.exists) {
        trueAmount = Number(orderDoc.data().amount);
      } else {
        let r = db.collection("store_orders").doc(orderId);
        let d = await r.get();
        if (d.exists) { orderRef = r; orderDoc = d; trueAmount = Number(d.data().final_amount ?? d.data().total_amount); } else {
          r = db.collection("maintenance_requests").doc(orderId); d = await r.get();
          if (d.exists) { orderRef = r; orderDoc = d; trueAmount = Number(d.data().amount); } else {
            r = db.collection("contracts").doc(orderId); d = await r.get();
            if (d.exists) { orderRef = r; orderDoc = d; trueAmount = Number(d.data().planPrice); }
          }
        }
      }

      // إن غاب الطلب تماماً: أنشئه خادميّاً من metadata الدفعة. هذا يمنع «الدفعة اليتيمة»
      // نهائياً — الدفع الأصلي (Apple/Google/Samsung Pay) قد يفشل إنشاؤه للطلب في العميل
      // بعد الخصم. المبلغ المرجعي = المخصوم فعلاً (paymentData.amount) فلا مجال لتلاعب.
      if (!orderDoc.exists) {
        const md = paymentData.metadata || {};
        if (md.order_id === orderId && (md.service_name || md.is_hourly)) {
          const isHourly = String(md.is_hourly) === "1";
          const amountSar = Number(paymentData.amount) / 100;
          let code = `ZY-${Date.now().toString().slice(5)}`;
          try {
            code = await db.runTransaction(async (tx) => {
              const cRef = db.collection("metadata").doc("order_counter");
              const cs = await tx.get(cRef);
              const next = ((cs.exists ? cs.data().last_id : 100) || 100) + 1;
              if (cs.exists) tx.update(cRef, {last_id: next}); else tx.set(cRef, {last_id: next});
              return String(next);
            });
          } catch (e) { console.error("counter for server-created order:", e); }
          const lat = Number(md.lat); const lng = Number(md.lng);
          // اسم العميل: من الـmetadata، وإلا نجلبه من مستند المستخدم — وإلا تظهر
          // الطلبات المُنشأة خادمياً (Apple Pay) بلا اسم في لوحة الإدارة/السائق.
          let clientName = (md.client_name || "").trim();
          if (!clientName) {
            try {
              const uDoc = await getFirestore().collection("users")
                  .doc(md.client_id || request.auth.uid).get();
              if (uDoc.exists) clientName = (uDoc.data().name || "").trim();
            } catch { /* اسم العميل تحسين اختياري — الإشعار يُرسَل بدونه */ }
          }
          const payload = {
            code,
            client_id: md.client_id || request.auth.uid,
            client_name: clientName || "عميل زيارة",
            client_phone: md.client_phone || "",
            service_type: md.service_name || "خدمة زيارة",
            service_name: md.service_name || "خدمة زيارة",
            amount: amountSar,
            is_paid: false, // يُقلب أدناه ذرّياً
            status: "pending",
            payment_method: (paymentData.source && paymentData.source.type) || "native_pay",
            // `Number(x || DEFAULT)` تكتب `NaN` لقيمةٍ غير رقميّة في الـmetadata
            // (وهي قيمةٌ تمرّ عبر ميسر ويضبطها الجهاز) — والمكتوبُ يُقرأ بعد ذلك
            // في العدّ والعرض. `Number(x) || DEFAULT` تسقط على الافتراضي.
            hours_contracted: slots.orderHours({hours_contracted: md.hours}),
            worker_count: Number(md.worker_count) || 1,
            zone_name: md.zone_name || null,
            // بلا إحداثيات في الـmetadata ⇒ بلا حقل location إطلاقاً (كان يُختم
            // مركز الرياض زوراً) — الواجهات تُخفي الخرائط بأمان عند غيابه.
            ...((!isNaN(lat) && !isNaN(lng)) ?
              {location: new GeoPoint(lat, lng)} : {}),
            created_at: FieldValue.serverTimestamp(),
            server_created_from_payment: true,
            // أعِد بناء تفصيل الخدمة من الـ metadata (وإلّا فُقِد على طلب Apple Pay).
            ...(_parseServiceMeta(md.service_meta_json) ?
              {service_meta: _parseServiceMeta(md.service_meta_json)} : {}),
          };
          if (md.service_date) {
            const sd = parseKsaIso(md.service_date);
            if (!isNaN(sd.getTime())) {
              payload.service_date = Timestamp.fromDate(sd);
              if (isHourly) {
                // توقيت الرياض: قراءة المكوّنات المحلية من **لحظة زمنية** تعطي
                // ساعة UTC — كانت تخزّن الخانة أبكر بثلاث ساعات من موعد العميلة،
                // فيُحجز في capacity.js وقتٌ خاطئ ويبقى وقتُ الموعد فارغاً.
                const bf = riyadhBookingFields(sd);
                payload.booking_date = bf.bookingDate;
                payload.booking_time_slot = bf.bookingTimeSlot;
              }
            }
          }
          orderRef = db.collection("orders").doc(orderId);
          await orderRef.set(payload);
          orderDoc = await orderRef.get();
          trueAmount = amountSar;
          console.log(`Order ${orderId} CREATED server-side from payment metadata (${amountSar} SAR).`);
        }
      }

      if (trueAmount === null || isNaN(trueAmount) || trueAmount <= 0) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب في السيرفر أو أن المبلغ غير صالح");
      }

      // الملكية: مالك الطلب فقط يؤكّد دفعه.
      _assertDocOwner(orderDoc.data(), request.auth.uid,
          "لا يمكن تأكيد دفع طلب مستخدم آخر");
      // idempotent: مؤكَّد سلفاً.
      if (orderDoc.data().is_paid === true) {
        return {success: true, alreadyPaid: true};
      }

      const trueAmountHalalas = Math.round(trueAmount * 100);
      const paidAmountHalalas = Number(paymentData.amount);
      if (paidAmountHalalas !== trueAmountHalalas) {
        console.error(`Amount mismatch. Paid: ${paidAmountHalalas}, expected: ${trueAmountHalalas}`);
        throw new HttpsError("failed-precondition", "مبلغ الدفع لا يتطابق مع مبلغ الطلب");
      }

      // ── تسعير خادمي مرجعي (#1 Phase 2) ─────────────────────────────────────────
      // يكشف الدفع الناقص (تلاعب العميل بحقل amount أو تضخيم الخصم) بإعادة حساب السعر من
      // تسعير المنطقة الموثوق + الخصم المُعاد حسابه من الكوبون (لا نثق بـ discount_amount).
      // Tier A: تعليم + تنبيه إداري **مع خدمة العميل** (يعمل دائماً). Tier B: استرداد/إلغاء
      // آليّ للدفع الناقص الصارخ — خلف ENFORCE_PRICE_TIER_B، **وهي مُفعَّلةٌ بقرار
      // المالك 2026-07-31** (هذا السطرُ كان ما زال يقول «مطفأة»، انظر رأس الملفّ).
      // والفحصُ نفسُه في `_verifyOrderPriceTierA` — مصدرٌ واحدٌ للمسالكِ الثلاثة.
      if (orderRef.parent.id === "store_orders") {
        await _verifyStoreOrderPrice(db, orderRef, orderId, orderDoc.data(),
            Number(paymentData.amount) / 100, "verify");
      }
      let tierBReason = null;
      if (orderRef.parent.id === "orders") {
        const od = orderDoc.data();
        const method = od.payment_method || "";
        const paid = Number(paymentData.amount) / 100; // الشحن الفعلي من البوابة (لا od.amount)
        const nonMoyasar = ["wallet", "subscription", "tamara", "tabby"]
            .includes(method);
        // الدفع الأصلي (Apple/Google/Samsung) يُنشأ خادميّاً بالكوبون مضمَّناً وبلا
        // discount_amount — استثناؤه صريحٌ وإلزاميّ يمنع ردّ كل عميل native-pay بكوبون.
        const skip = od.server_created_from_payment === true || nonMoyasar || !(paid > 0);
        if (!skip) {
          tierBReason = await _verifyOrderPriceTierA(
              db, orderRef, orderId, od, paid, "verify");
        }
      }

      // (#1 Tier B) دفعٌ ناقص صارخ مؤكَّد + البوّابة مُفعَّلة → استردّ/ألغِ **قبل** قلب is_paid،
      // ثم أعِد {blocked} للعميل. طلبٌ ثبت تلاعبه لا يُقلَب مدفوعاً حتى لو فشلت البوابة (يبقى
      // payment_review للمراجعة اليدوية) — فلا عميلٌ مخصومٌ بلا خدمة يُخدَم بالخطأ.
      if (tierBReason && paymentId) {
        const secret = moyasarSecretKey.value();
        const r = await refunds.voidOrRefundTampered(db, secret, paymentId, orderRef);
        await queuePush("ADMIN_BROADCAST", "حُجب طلبٌ لدفعٍ ناقص صارخ 🛑",
            `الطلب #${orderId} حُجب (${r.done ? r.action : "بانتظار استرداد يدوي"}) لدفعٍ أقل من خُمس المتوقَّع.`,
            "admin_price_tamper", {orderId},
            ["super_admin", "orders_manager", "accountant_admin"]).catch(() => {});
        return {success: false, blocked: true,
          reason: r.done ? tierBReason : "payment_review"};
      }

      // قلب is_paid داخل معامَلة: إشعار مرّة واحدة عند الانتقال false→true.
      const flipped = await db.runTransaction(async (tx) => {
        const snap = await tx.get(orderRef);
        const cur = snap.data() || {};
        if (cur.is_paid === true) return false;
        // (#1) لا نُحيي طلباً حُجب لتلاعبٍ سعري (Tier B) واستُرد مبلغه.
        if (cur.tamper_blocked === true) return false;
        tx.update(orderRef, {
          payment_status: "paid",
          is_paid: true,
          moyasar_payment_id: paymentId,
          moyasar_status: paymentData.status,
          updated_at: FieldValue.serverTimestamp(),
          ...refunds.reopenFieldsIfSystemCancelled(snap.data()),
        });
        return true;
      });
      console.log(`Order ${orderId} verified via Moyasar (flipped=${flipped}).`);
      if (flipped) {
        notifyClientPaymentResult(orderRef.parent.id, orderId, orderDoc.data(), true)
            .catch((e) => console.error("notify after verify:", e));
      }
      return {success: true};
    },
);

// 8. GDPR Account Deletion — shared server-side cleanup
// Clients cannot delete their own users/{uid} doc (rule = isSuperAdmin), so the
// app records an account_deletions/{uid} request and this runs the real cleanup.
/**
 * Performs the full server-side cleanup for a GDPR account deletion.
 * @param {string} uid UID of the user whose data must be erased.
 * @return {Promise<void>}
 */
async function processAccountDeletion(uid) {
  console.log(`Processing legal account deletion for user: ${uid}`);
  try {
    // 0. رصيدُ المحفظةِ **قبل** حذفِ حسابِ المصادقة. لا شيءَ في هذا المسارِ
    //    كان يَنظرُ إلى `wallets/{uid}`: تُحذف هويّةُ المصادقةِ ويبقى الرصيدُ
    //    في وثيقةٍ مفتاحُها معرّفٌ لا يستطيع أحدٌ تسجيلَ الدخولِ به بعد اليوم
    //    — **مالُ العميلةِ محجوزٌ إلى الأبد، بلا إشعارٍ ولا سجلِّ دَينٍ**.
    //    لا نُصفّرُه: التصفيرُ يُتلف الدليلَ على الدَّين. نُسجّلُه على طلبِ
    //    الحذفِ، ونَسِمُ المحفظةَ، ونُنبّه المحاسبةَ لتُسوّيَه خارج التطبيق.
    //    وشاشةُ الملفِّ تُحذّر العميلةَ برصيدِها **قبل** التأكيد.
    let strandedBalance = 0;
    try {
      const wSnap = await getFirestore().collection("wallets").doc(uid).get();
      strandedBalance = wSnap.exists ? Number(wSnap.data().balance || 0) : 0;
      if (!Number.isFinite(strandedBalance)) strandedBalance = 0;
      if (strandedBalance > 0) {
        await wSnap.ref.update({
          owner_deleted: true,
          owner_deleted_at: FieldValue.serverTimestamp(),
        });
      }
    } catch (wErr) {
      // قراءةُ المحفظةِ تحسينٌ للسجلّ، لا تَحجبُ حقَّ الحذفِ (متطلّبُ Apple).
      console.error(`[deletion] wallet read failed for ${uid}:`, wErr.message);
    }

    // 1. Delete user from Firebase Auth
    try {
      await getAuth().deleteUser(uid);
      console.log(`Successfully deleted auth user: ${uid}`);
    } catch (authErr) {
      if (authErr.code === "auth/user-not-found") {
        console.warn(`User ${uid} not found in Firebase Auth`);
      } else {
        throw authErr;
      }
    }

    // 2. Delete user's document from users collection
    await getFirestore().collection("users").doc(uid).delete();
    console.log(`Successfully deleted users/${uid} document`);

    // 3. Clean up associated FCM tokens (both legacy collection names)
    await getFirestore().collection("fcm_tokens").doc(uid).delete().catch(() => {});
    await getFirestore().collection("fcm_token").doc(uid).delete().catch(() => {});

    // 4. Mark the request fully processed — ومعه الرصيدُ المحجوز، كي يبقى
    //    الدَّينُ مكتوباً في مكانٍ يَقرؤه البشرُ لا في وثيقةِ محفظةٍ يتيمة.
    await getFirestore().collection("account_deletions").doc(uid).update({
      completed_at: FieldValue.serverTimestamp(),
      status: "deleted_fully_processed",
      wallet_balance_at_deletion: strandedBalance,
    });
    console.log(`Successfully completed deletion workflow for ${uid}`);
    if (strandedBalance > 0) {
      await queuePush("ADMIN_BROADCAST", "رصيدُ محفظةٍ بعد حذفِ حساب 💸",
          `حُذف حسابٌ ورصيدُ محفظته ${strandedBalance} ر.س — لا يستطيع صاحبُه ` +
          "تسجيلَ الدخولِ بعد اليوم، فالتسويةُ يدويّة.",
          "admin_wallet_stranded", {uid},
          ["super_admin", "accountant_admin"]).catch((e) =>
        console.error(`[deletion] stranded alert failed for ${uid}:`, e.message));
    }
  } catch (error) {
    console.error(`Error processing account deletion for user ${uid}:`, error);
    // Record the failure so it can be retried/inspected by an admin
    await getFirestore().collection("account_deletions").doc(uid).update({
      error: error.message || "Unknown error",
      status: "failed_deletion",
      failed_at: FieldValue.serverTimestamp(),
    });
  }
}

// 8a. Self-service deletion: client creates the request doc with status 'deleted'
exports.onAccountDeletionRequested = onDocumentCreated({document: "account_deletions/{uid}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;
      const data = snap.data();
      if (data && data.status === "deleted") {
        await processAccountDeletion(event.params.uid);
      }
      return null;
    },
);

// 8b. Admin-approved deletion: a pending request is updated to status 'deleted'
exports.onAccountDeletionStatusChanged = onDocumentUpdated({document: "account_deletions/{uid}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const beforeData = change.before.data();
      const afterData = change.after.data();
      // Only when status transitions INTO 'deleted' (avoids re-firing on the
      // helper's own update to 'deleted_fully_processed')
      if (afterData && afterData.status === "deleted" && (!beforeData || beforeData.status !== "deleted")) {
        await processAccountDeletion(event.params.uid);
      }
      return null;
    },
);

// 9. Aggregation Pattern for Orders (total_revenue, active_orders, completed_orders)
exports.onOrderWritten = onDocumentWritten({document: "orders/{orderId}", cpu: 0.083}, async (event) => {
  const change = event.data;
  if (!change) return null;

  const beforeData = change.before ? change.before.data() : null;
  const afterData = change.after ? change.after.data() : null;

  // (لا طلب مدفوع بلا سائق — قرار المالك) الإسناد يُطلق خادمياً لحظةَ انقلاب is_paid.
  // كان الإسناد بيد تطبيق العميل بعد الدفع، والمكنسة الدورية (كل 15 دقيقة) ضماناً؛
  // فإن مات التطبيق لحظة نجاح الدفع (سيناريو Apple Pay المعروف) بقي الطلب المدفوع
  // بلا سائق حتى ربع ساعة. الآن النافذة ثوانٍ: قلْب is_paid (webhook/verify) يُسنِد
  // فوراً. آمنٌ من التكرار: كتابتنا تضع driver_id فيبطل الشرط، و_assignDriverScheduled
  // يعيد فحص حرّية السائق ذرّياً داخل معاملة فلا يُسنَد سائق مشغول ولو تسابقت المسارات.
  try {
    const paidFlipped = afterData && afterData.is_paid === true &&
        (!beforeData || beforeData.is_paid !== true);
    if (paidFlipped && !afterData.driver_id &&
        afterData.status === "pending" && afterData.service_date) {
      const db = getFirestore();
      const start = afterData.service_date.toDate();
      const hours = slots.orderHours(afterData);
      const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
      const driver = await _findFreeDriverForSlot(db, {startDateTime: start, endDateTime: end});
      if (driver) {
        // المسرحية (18 طلباً بثانية) كشفت أن السطر هنا كان يقول «assigned» حتى حين
        // ترفض المعاملة (سباق حجز مزدوج صدّه القفل الذرّي) — احترم قيمة الإرجاع.
        const res = await _assignDriverScheduled(db, event.params.orderId, driver, start);
        if (res.assigned) {
          console.log(`onOrderWritten: paid-flip assigned ${event.params.orderId} -> ${driver.id}`);
        } else {
          console.warn(`onOrderWritten: paid-flip REFUSED by atomic re-check (race) for ${event.params.orderId} — sweep will retry`);
        }
      } else {
        // نادر (سباق آخر خانة): تبقى المكنسة الدورية تعيد المحاولة.
        console.warn(`onOrderWritten: no free driver at paid-flip for ${event.params.orderId}`);
      }
    } else if (paidFlipped && !afterData.driver_id &&
        afterData.status === "pending" && !afterData.service_date) {
      // (نمط المتجر — قرار المالك) طلب مدفوع **بلا موعد** = خدمة مُدارة إدارياً
      // (تنظيف داخلية السيارة): لا إسناد سائق — يُرقّى لتحت المراجعة فور تأكيد
      // الدفع، والإدارة تقودها: under_review ⇒ in_progress ⇒ completed بإشعار
      // خادمي لكل نقلة (sendNotificationOnOrderStatusChange).
      await change.after.ref.update({
        status: "under_review",
        updated_at: FieldValue.serverTimestamp(),
      });
      console.log(`onOrderWritten: dateless paid order ${event.params.orderId} -> under_review`);
    }
  } catch (e) {
    console.error("onOrderWritten paid-flip assign failed:", e.message);
  }

  // (تكملة «لا طلب مدفوع بلا سائق») الضمان صار **حدثياً** لا مؤقّتاً فقط:
  // سباقُ آخر خانة يترك طلباً مدفوعاً بلا سائق، والسائق لا يتحرّر بمرور الوقت بل
  // بإلغاء/إكمال طلبٍ آخر — فلحظةَ التحرُّر نُعيد محاولة الإسناد فوراً بدل انتظار
  // المكنسة. آمنٌ من التسلسل: الطلب المُسنَد هنا مدفوع سلفاً (paidFlipped=false)
  // وdriver_id يمتلئ، فلا يعيد إطلاق أيٍّ من الكتلتين.
  try {
    // 'assigned' ضمن الحالات النشطة — استبعادها كان يجعل السائق «المُسنَد» حرّاً
    // في كل استعلامات الانشغال فيُحجَز لمهمتين متداخلتين. وهو **نفس السؤال** الذي
    // يسأله مسحُ التعارض («هل يُحسَب السائق مشغولاً؟») فالمجموعة واحدة ومصدرها واحد.
    const ACTIVE_WITH_DRIVER = slots.CONFLICT_STATUSES;
    const driverFreed = beforeData && afterData &&
        beforeData.driver_id && ACTIVE_WITH_DRIVER.includes(beforeData.status) &&
        (afterData.status === "cancelled" || afterData.status === "completed");
    if (driverFreed) {
      const db = getFirestore();
      // −13س كنافذة المكنسة: طلبٌ طويل فات بدؤه ونافذته قائمة يلتقط السائقَ المتحرر.
      const cutoff = Timestamp.fromDate(
          new Date(Date.now() - 13 * 60 * 60 * 1000));
      // نفس شكل استعلام المكنسة (فهرس status+service_date قائم).
      const snap = await db.collection("orders")
          .where("status", "==", "pending")
          .where("service_date", ">=", cutoff)
          .limit(25).get();
      const waiting = snap.docs.filter((d) => {
        const o = d.data();
        if (o.is_paid !== true || o.driver_id || !o.service_date) return false;
        // لا نُسند طلباً انتهت نافذته كاملةً (البدء + المدة) — ذاك للاسترداد.
        const endMs = o.service_date.toDate().getTime() +
          slots.orderHours(o) * 60 * 60 * 1000;
        return endMs > Date.now();
      }).slice(0, 5);
      // كل مسار يسجّل — الاختبار الحيّ الأول فشل صامتاً ولم نعرف أي فرع ابتلعه.
      console.log(`onOrderWritten: driver freed by ${event.params.orderId} — ` +
          `${snap.size} pending, ${waiting.length} paid+unassigned`);
      for (const doc of waiting) {
        const o = doc.data();
        const start = o.service_date.toDate();
        const hours = slots.orderHours(o);
        const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
        const driver = await _findFreeDriverForSlot(db, {startDateTime: start, endDateTime: end});
        if (driver) {
          const res = await _assignDriverScheduled(db, doc.id, driver, start);
          if (res.assigned) {
            console.log(`onOrderWritten: driver-freed assigned ${doc.id} -> ${driver.id}`);
          } else {
            console.warn(`onOrderWritten: driver-freed REFUSED by atomic re-check for ${doc.id}`);
          }
        } else {
          console.warn(`onOrderWritten: driver freed but none free for ${doc.id}`);
        }
      }
    }
  } catch (e) {
    console.error("onOrderWritten driver-freed reassign failed:", e.message);
  }

  let deltaRevenue = 0;
  let deltaActive = 0;
  let deltaCompleted = 0;

  // Deletion
  if (!afterData) {
    if (beforeData) {
      const oldStatus = beforeData.status || "pending";
      const oldAmount = Number(beforeData.amount) || 0;

      if (oldStatus !== "cancelled") {
        deltaRevenue -= oldAmount;
      }
      if (oldStatus === "completed") {
        deltaCompleted -= 1;
      } else if (oldStatus !== "cancelled") {
        deltaActive -= 1;
      }
    }
  } else if (!beforeData) {
    // Creation
    const newStatus = afterData.status || "pending";
    const newAmount = Number(afterData.amount) || 0;

    if (newStatus !== "cancelled") {
      deltaRevenue += newAmount;
    }
    if (newStatus === "completed") {
      deltaCompleted += 1;
    } else if (newStatus !== "cancelled") {
      deltaActive += 1;
    }
  } else {
    // Update
    const oldStatus = beforeData.status || "pending";
    const oldAmount = Number(beforeData.amount) || 0;

    const newStatus = afterData.status || "pending";
    const newAmount = Number(afterData.amount) || 0;

    // Revenue calculation
    const wasRevenue = oldStatus !== "cancelled";
    const isRevenue = newStatus !== "cancelled";

    if (wasRevenue && !isRevenue) {
      deltaRevenue -= oldAmount;
    } else if (!wasRevenue && isRevenue) {
      deltaRevenue += newAmount;
    } else if (wasRevenue && isRevenue) {
      deltaRevenue += (newAmount - oldAmount);
    }

    // Active & Completed calculations
    const wasCompleted = oldStatus === "completed";
    const isCompleted = newStatus === "completed";
    const wasCancelled = oldStatus === "cancelled";
    const isCancelled = newStatus === "cancelled";

    const wasActive = !wasCompleted && !wasCancelled;
    const isActive = !isCompleted && !isCancelled;

    if (wasActive && !isActive) {
      deltaActive -= 1;
    } else if (!wasActive && isActive) {
      deltaActive += 1;
    }

    if (wasCompleted && !isCompleted) {
      deltaCompleted -= 1;
    } else if (!wasCompleted && isCompleted) {
      deltaCompleted += 1;
    }
  }

  // Update the analytics_summary document atomically
  const summaryRef = getFirestore().collection("metadata").doc("analytics_summary");

  const updates = {};
  if (deltaRevenue !== 0) updates.total_revenue = FieldValue.increment(deltaRevenue);
  if (deltaActive !== 0) updates.active_orders = FieldValue.increment(deltaActive);
  if (deltaCompleted !== 0) updates.completed_orders = FieldValue.increment(deltaCompleted);

  if (Object.keys(updates).length > 0) {
    try {
      await summaryRef.update(updates);
    } catch (err) {
      if (err.code === 5 || err.message.includes("NOT_FOUND") || err.message.includes("does not exist")) {
        // Document doesn't exist yet, initialize it securely by running a set with merge
        const initData = {
          total_revenue: deltaRevenue > 0 ? deltaRevenue : 0,
          active_orders: deltaActive > 0 ? deltaActive : 0,
          completed_orders: deltaCompleted > 0 ? deltaCompleted : 0,
        };
        await summaryRef.set(initData, {merge: true});
      } else {
        throw err;
      }
    }
  }
  return null;
});

// 8. Surge Pricing Factor
// سعر الذروة: **يدوي بالكامل** — الإدارة تحدد النسبة وترفعها/تنقصها متى شاءت.
//
// كان يُحسب آلياً من حالة السائقين: إن كان أقل من 20% منهم status='available'
// يقفز السعر +15% على العميل. هذا منطق ندرة (نموذج أوبر) لا يناسب زيارة — السائقون
// برواتب شهرية — وكان يكفي أن ينسى السائقون تحديث حالتهم ليُشحن العميل زيادةً لم
// تقرّرها الإدارة ولا تراها. الآن: يقرأ system_configs/main_settings.surge_percent
// (0 = بلا ذروة، 15 = +15%). التوقيع كما هو فالنسخ المثبَّتة تعمل بلا تغيير.
exports.getSurgePricingFactor = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  try {
    const cfg = await getFirestore()
        .collection("system_configs").doc("main_settings").get();
    const pct = Number(cfg.exists ? cfg.data().surge_percent : 0);
    if (!Number.isFinite(pct) || pct <= 0) return {surgeFactor: 1.0};
    // سقف 100% حارس: خطأ إدخال (مثلاً 1500) لا يضاعف فاتورة عميل خمسة عشر ضعفاً.
    const capped = Math.min(pct, 100);
    return {surgeFactor: Math.round((1 + capped / 100) * 100) / 100};
  } catch (e) {
    console.error("[surge] read failed, defaulting to 1.0:", e.message);
    return {surgeFactor: 1.0};
  }
});

// 9. Smart Dispatch Core: findNearestDrivers
exports.findNearestDrivers = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }

  const {lat, lng} = request.data;
  if (lat == null || lng == null) {
    throw new HttpsError("invalid-argument", "إحداثيات الموقع مطلوبة");
  }

  const center = [Number(lat), Number(lng)];
  const radiusInM = 5000; // 5km

  // Each bounds is an array of [start, end] geohashes
  const bounds = geofire.geohashQueryBounds(center, radiusInM);
  const promises = [];

  for (const b of bounds) {
    const q = getFirestore().collection("users")
        .where("role", "==", "driver")
        .where("status", "in", ["available", "online"])
        .where("geohash", ">=", b[0])
        .where("geohash", "<=", b[1]);

    promises.push(q.get());
  }

  const snapshots = await Promise.all(promises);
  const matchingDocs = [];

  for (const snap of snapshots) {
    for (const doc of snap.docs) {
      const data = doc.data();
      // Ensure it has location data
      if (data.location && data.location.latitude && data.location.longitude) {
        // Double check exact distance using Haversine
        const driverLoc = [data.location.latitude, data.location.longitude];
        const distanceInKm = geofire.distanceBetween(center, driverLoc);
        const distanceInM = distanceInKm * 1000;

        if (distanceInM <= radiusInM) {
          matchingDocs.push({
            uid: doc.id,
            distance: distanceInM,
            data: data,
          });
        }
      }
    }
  }

  // Sort by distance ascending
  matchingDocs.sort((a, b) => a.distance - b.distance);

  // Return the nearest 3
  const nearest3 = matchingDocs.slice(0, 3).map((d) => d.uid);

  return {drivers: nearest3};
});

// ════════════════════════════════════════════════════════════════════════
// Direct Dispatch Engine — shared helpers
// ════════════════════════════════════════════════════════════════════════

/**
 * قراءة `users/{id}` لعدّة سائقين في **نداءٍ واحد** لكل قطعة (`getAll`) بدل نداءٍ
 * لكل سائق.
 *
 * `getAll` يحفظ ترتيب الطلب (BatchGetDocuments لا يحفظه، والـSDK يرتّب النتائج
 * على ترتيب المراجع — انظر `document-reader.js`)، فالمزاوجة بالفهرس صحيحة.
 * @param {FirebaseFirestore.Firestore} db
 * @param {Array<FirebaseFirestore.DocumentReference>} refs
 * @return {Promise<Array<FirebaseFirestore.DocumentSnapshot>>}
 */
async function _getAllChunked(db, refs) {
  if (!refs.length) return [];
  const out = [];
  for (const part of chunk(refs, GET_ALL_CHUNK)) {
    out.push(...await db.getAll(...part));
  }
  return out;
}

/**
 * مستندات السائقين **المؤهَّلين للإسناد** — نشطون ولهم حساب دخول بدور سائق.
 *
 * موضعٌ واحد للقاعدة: ينادونه المُسنِد الآلي وعدّاد السعة، فلا يتباعدان. وكان
 * تباعُدهما يُظهر يوماً «متاحاً» فيدفع العميل ثم لا يجد المُسنِد سائقاً مؤهَّلاً
 * فيعلق الطلب المدفوع حتى الاسترداد الآلي. (انظر رأس `drivers.js`.)
 *
 * الترتيب ترتيبُ `drivers` كما تُعيدها Firestore — المُسنِد يأخذ أوّل حرٍّ فيه،
 * فالاختيار لا يتغيّر بهذا التوحيد.
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<Array<FirebaseFirestore.QueryDocumentSnapshot>>}
 */
async function _eligibleDriverDocs(db) {
  const driversSnap = await db.collection("drivers").get();
  // الترشيح على النشاط أوّلاً: يوفّر قراءة `users` لكل سائق موقوف.
  const active = driversSnap.docs.filter((d) => d.data().is_active !== false);
  if (!active.length) return [];
  const userSnaps = await _getAllChunked(
      db, active.map((d) => db.collection("users").doc(d.id)));
  return active.filter((d, i) => isAssignableDriver(
      d.data(), userSnaps[i].exists ? userSnaps[i].data() : null));
}

/**
 * يتحقّق أن سائقاً **محدَّداً بالاسم** يجوز إسناده — للمسارات اليدوية التي يختار
 * فيها الأدمن السائق بنفسه، فلا تمرّ على `_eligibleDriverDocs`.
 *
 * يرمي `HttpsError` برسالة تقول للأدمن **ما العمل**، لا رفضاً مبهماً. ويُعيد
 * بيانات `drivers/{id}` كي لا يقرأها المُنادي مرّةً ثانية.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} driverId
 * @return {Promise<object>} بيانات مستند السائق
 */
async function _assertAssignableDriver(db, driverId) {
  const [dSnap, uSnap] = await Promise.all([
    db.collection("drivers").doc(driverId).get(),
    db.collection("users").doc(driverId).get(),
  ]);
  const dData = dSnap.exists ? dSnap.data() : null;
  const problem = assignabilityProblem(
      dData, uSnap.exists ? uSnap.data() : null);
  if (problem) {
    // not-found للمستند الغائب، وfailed-precondition لمن وُجد ولا يصلح.
    throw new HttpsError(
        dSnap.exists ? "failed-precondition" : "not-found", problem);
  }
  return dData;
}

/**
 * يجد سائقاً حرّاً لفترة زمنية.
 * - **بلا مناطق**: قرار المالك — السائق يقبل أي طلب يُسنَد إليه، والسعة تُضبط بالسقف
 *   اليومي المتفق عليه مسبقاً (max_orders_per_day) وبعدد السائقين، لا بالجغرافيا.
 *   (وواقعاً لم تُسنَد منطقة لسائق قط: zone_name غائب عن كل السائقين، و assigned_zones
 *   لم يُكتب في أي مكان — كان الترشيح يعمل دائماً على مسار «بلا منطقة».)
 * - الانشغال: السائق مشغول إن كان لديه طلب يتقاطع زمنياً بحالة
 *   scheduled/on_the_way/in_progress/accepted (لا يُحسب الانشغال "الآني" بل تقاطع الفترة).
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} opts {startDateTime, endDateTime}
 * @return {Promise<FirebaseFirestore.QueryDocumentSnapshot|null>}
 */
async function _findFreeDriverForSlot(db, {startDateTime, endDateTime}) {
  // نافذة الانشغال [البداية−24س، النهاية): تلتقط أي مهمة قد تتقاطع زمنياً، بما
  // فيها العابرة لمنتصف ليل UTC. كانت حدود اليوم التقويمي (getFullYear/Month/Date
  // بتوقيت UTC للخادم) تُفوّت مهمة سائقٍ في اليوم السابق UTC (سلوت الرياض
  // 00:00–02:59 = اليوم UTC السابق)، فيُعاد اختيار السائق نفسه ويرفضه الفحص الذرّي
  // فيبقى الطلب المدفوع عالقاً بلا سائق أبداً. (24س تغطي أي مدة مهمة ≤ يوم.)
  const winStart = slots.conflictWindowStart(startDateTime);

  // الأهلية من الموضع الواحد (نشط + حساب دخول بدور سائق) — كانت هنا حلقةٌ
  // تقرأ `users/{id}` لكل مرشّح على التوالي حتى تجد أوّل مؤهَّل. صارت نداءً
  // واحداً (`getAll`) ثم ترشيحاً في الذاكرة.
  const eligible = await _eligibleDriverDocs(db);
  if (eligible.length === 0) return null;

  // بناء مجموعة السائقين المشغولين بطلبات متقاطعة زمنياً
  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", Timestamp.fromDate(winStart))
      .where("service_date", "<", Timestamp.fromDate(endDateTime))
      .where("status", "in", slots.CONFLICT_STATUSES)
      .get();

  const busy = new Set();
  for (const doc of ordersSnap.docs) {
    const data = doc.data();
    if (!data.driver_id) continue; // غيابُ service_date يعالجه overlapsSlot
    if (slots.overlapsSlot(data, startDateTime, endDateTime)) {
      busy.add(data.driver_id);
    }
  }

  // أوّل مؤهَّل غير مشغول — نفس الترتيب ونفس الاختيار كما قبل التوحيد.
  // (فحص H3 كان هنا داخل الحلقة؛ صار في `_eligibleDriverDocs` أعلاه.)
  for (const doc of eligible) {
    if (!busy.has(doc.id)) return doc;
  }
  return null;
}

/**
 * يتحقق هل سائق محدد حرّ في فترة زمنية (لا يتقاطع مع مهمة أخرى له).
 * يستخدم نفس فهرس مُحدِّد التوفّر (service_date + status) ويصفّي السائق في JS.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} driverId
 * @param {Date} startDateTime
 * @param {Date} endDateTime
 * @return {Promise<boolean>}
 */
async function _isDriverFreeForSlot(db, driverId, startDateTime, endDateTime) {
  // نفس نافذة _findFreeDriverForSlot: [البداية−24س، النهاية) تلتقط العابر لمنتصف الليل.
  const winStart = slots.conflictWindowStart(startDateTime);

  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", Timestamp.fromDate(winStart))
      .where("service_date", "<", Timestamp.fromDate(endDateTime))
      .where("status", "in", slots.CONFLICT_STATUSES)
      .get();

  for (const doc of ordersSnap.docs) {
    const data = doc.data();
    if (data.driver_id !== driverId) continue;
    if (slots.overlapsSlot(data, startDateTime, endDateTime)) return false; // مشغول
  }
  return true;
}

/**
 * يُسنِد طلباً لسائق بحالة scheduled (التوجيه المباشر).
 * لا يُعدّ السائق مشغولاً الآن — يصبح مشغولاً فقط عند انتقاله إلى on_the_way.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} orderId
 * @param {FirebaseFirestore.DocumentSnapshot} driverDoc
 * @param {Date} startDateTime
 * @return {Promise<{driverId:string, driverName:string}>}
 */
async function _assignDriverScheduled(db, orderId, driverDoc, startDateTime) {
  const d = driverDoc.data();
  // موعد الرياض (UTC+3) — الصيغة في ksa_time.js: حساب المكوّنات بـUTC مباشرةً
  // كان يعطي ساعةً ناقصةً ثلاثاً (07:00 بدل 10:00) → تذكيرٌ بوقتٍ خاطئ وعدمُ
  // احتساب الفترة في السعة.
  const {bookingDate, bookingTimeSlot: timeSlot} =
    riyadhBookingFields(startDateTime);
  const orderRef = db.collection("orders").doc(orderId);

  // معامَلة: نُعيد قراءة الطلب ولا نكتب فوقه إن كان مُسنَداً سلفاً أو لم يعد قابلاً
  // للإسناد. يمنع سباق الازدواج: قبول السائق يدوياً مقابل الإسناد التلقائي، أو
  // تشغيل كرونين متزامنين (كل 3د/15د) يُسنِدان نفس الطلب لسائقين مختلفين.
  const assigned = await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) return false;
    const cur = snap.data();
    if (cur.driver_id) return false; // مُسنَد سلفاً — لا تكتب فوقه
    if (!["pending", "scheduled"].includes(cur.status)) {
      return false; // حالة غير قابلة للإسناد
    }

    // (منع التعارض) إعادة فحص حرّية السائق ذرّياً داخل المعاملة: _findFreeDriverForSlot
    // يفحص قبل المعاملة، لكن حجزَين متزامنَين (زيارة اشتراك ↔ طلب عميل آخر) قد يقرآن
    // السائق "حرّاً" ثم يُسنِدانه لفترة متداخلة. القراءة داخل المعاملة تجعلها آمنة من السباق
    // فلا تُحجَز زيارة تتعارض مع موعد اختاره عميل آخر مسبقاً.
    const slotEnd = slots.orderEnd(startDateTime, cur);
    // نافذة [البداية−24س، النهاية): تلتقط مهمّة عابرة لمنتصف ليل UTC، وأيضاً مهمة
    // طويلة (hours_contracted > 8) تبدأ قبل السلوت بأكثر من 8 ساعات (كانت −8 تُفوّتها).
    const winStart = slots.conflictWindowStart(startDateTime);
    const dayQ = db.collection("orders")
        .where("service_date", ">=", Timestamp.fromDate(winStart))
        .where("service_date", "<", Timestamp.fromDate(slotEnd))
        .where("status", "in", slots.CONFLICT_STATUSES);
    const daySnap = await tx.get(dayQ);
    for (const d2 of daySnap.docs) {
      const od = d2.data();
      if (od.driver_id !== driverDoc.id) continue;
      // تعارض زمني — لا تُسنِد
      if (slots.overlapsSlot(od, startDateTime, slotEnd)) return false;
    }

    // (تعليمات المنزل) ننسخ house_rules من مستند العميل إلى الطلب عند الإسناد —
    // قواعد Firestore تمنع السائق من قراءة مستندات users الأخرى، فكانت التعليمات
    // لا تصله. تطبيق السائق يقرؤها من الطلب مباشرةً.
    let houseRules = null;
    if (cur.client_id) {
      const uSnap = await tx.get(db.collection("users").doc(cur.client_id));
      const hr = uSnap.exists ? uSnap.data().house_rules : null;
      if (typeof hr === "string" && hr.trim()) houseRules = hr.trim();
    }

    tx.update(orderRef, {
      status: "scheduled",
      driver_id: driverDoc.id,
      ...(houseRules ? {house_rules: houseRules} : {}),
      driver_name: d.name || "سائق",
      // assigned_driver: شاشات تتبّع العميل تقرأ هذا الحقل — لولاه تُظهر «جاري
      // تعيين سائق» للأبد رغم إسناد السائق.
      assigned_driver: d.name || "سائق",
      driver_phone: d.phone || "000000000",
      // تقييمُ السائق لحظةَ الإسناد — شاشةُ التتبّع تعرضه للعميلة. لا يُكتب
      // إلّا إن وُجد فعلاً: كانت الشاشةُ تعرض «★ 5.0» افتراضاً لكلِّ سائق،
      // ولا شيءَ في المستودع يكتب هذا الحقل أصلاً، فكان الرقمُ مختلقاً دائماً.
      ...(Number.isFinite(Number(d.rating_avg)) && Number(d.rating_avg) > 0 ?
        {driver_rating_avg: Number(d.rating_avg)} : {}),
      assigned_at: FieldValue.serverTimestamp(),
      scheduled_at: Timestamp.fromDate(startDateTime),
      // service_date مطلوب حتى يحتسب مُحدِّد التوفّر هذه المهمة ضمن انشغال السائق
      service_date: Timestamp.fromDate(startDateTime),
      booking_date: bookingDate,
      booking_time_slot: timeSlot,
    });
    return true;
  });
  return {driverId: driverDoc.id, driverName: d.name || "سائق", assigned};
}

/**
 * (تسعير خادمي — إغلاق ثغرة العقد المُسعَّر عميلياً) العقد يُنشأ من جهاز العميل،
 * فكان بوسع عميل معدَّل كتابة planPrice=1 مع planVisits=100 ثم دفع ريال واحد
 * وتوليد كل الزيارات. نتحقّق هنا أن سعر/زيارات العقد يطابقان باقة
 * subscription_packages الحقيقية قبل أي توليد. المطابقة بالاسم (title) لأن العقد
 * لا يخزّن معرّف الباقة. يرمي HttpsError عند أي انحراف.
 * إن كان c.contract_kind === 'event_workers' تُقرأ الباقة من event_worker_packages
 * بدلاً من subscription_packages (نفس منطق السعر/الزيارات)، مع تحقّق إضافي لعدد
 * العاملات إن حدّدته الباقة.
 * @param {FirebaseFirestore.Firestore} db
 * @param {object} c بيانات العقد
 * @param {FirebaseFirestore.Transaction} [tx] معاملة اختيارية (القراءة داخلها)
 * @return {Promise<void>}
 */
async function _validateContractPlan(db, c, tx) {
  const isEventWorkers = c.contract_kind === "event_workers";
  const col = isEventWorkers ? "event_worker_packages" : "subscription_packages";
  const q = db.collection(col)
      .where("title", "==", String(c.planName || "")).limit(1);
  const snap = tx ? await tx.get(q) : await q.get();
  if (snap.empty) {
    throw new HttpsError("failed-precondition",
        "باقة العقد غير موجودة في قائمة الباقات — رُفض توليد الزيارات");
  }
  const pkg = snap.docs[0].data();
  // السعر المتوقّع = سعر الباقة + 15% ضريبة بنفس تقريب العميل لسنتين عشريتين
  // (انظر contract_signing_screen: _grossedPlanPrice) — سماحية قرش واحد للتعويم.
  const base = Number(pkg.price || 0);
  const expected = grossFromBaseRounded(base);
  const actual = Number(c.planPrice || 0);
  if (!(base > 0) || Math.abs(actual - expected) > 0.01) {
    throw new HttpsError("failed-precondition",
        `سعر العقد (${actual}) لا يطابق سعر الباقة شامل الضريبة (${expected}) — ` +
        "رُفض توليد الزيارات");
  }
  // عدد الزيارات: الحقل الرقمي في الباقة، أو (كما تستخرجه واجهة العميل احتياطياً)
  // العدد المجاور لكلمة «زيار» في العنوان/العنوان الفرعي/المزايا إن غاب الحقل.
  let pkgVisits = Number(pkg.visits || 0);
  if (pkgVisits <= 0) {
    const features = Array.isArray(pkg.features) ? pkg.features.join(" ") : "";
    const m = /(\d+)\s*زيار/.exec(
        `${pkg.title || ""} ${pkg.subtitle || ""} ${features}`);
    if (m) pkgVisits = Number(m[1]);
  }
  if (pkgVisits > 0 && Number(c.planVisits || 0) !== pkgVisits) {
    throw new HttpsError("failed-precondition",
        `عدد زيارات العقد (${Number(c.planVisits || 0)}) لا يطابق الباقة ` +
        `(${pkgVisits}) — رُفض توليد الزيارات`);
  }
  // (عاملات المناسبات) تحقّق عدد العاملات إن حدّدته الباقة — نفس أسلوب تحقّق
  // السعر/الزيارات أعلاه، مقصور على مسار event_workers فقط.
  if (isEventWorkers && Number(pkg.workers || 0) > 0 &&
      Number(c.workers || 0) !== Number(pkg.workers)) {
    throw new HttpsError("failed-precondition",
        `عدد عاملات العقد (${Number(c.workers || 0)}) لا يطابق الباقة ` +
        `(${Number(pkg.workers)}) — رُفض توليد الزيارات`);
  }
}

// ════════════════════════════════════════════════════════════════════════
// Subscription Visit Generator — pre-generate & auto-assign all contract visits
// ════════════════════════════════════════════════════════════════════════
exports.generateSubscriptionVisits = onCall({cpu: 0.5}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const {contractId} = request.data;
  if (!contractId) throw new HttpsError("invalid-argument", "معرف العقد مطلوب");
  const db = getFirestore();

  // العثور على العقد (قد يكون contractId هو معرّف المستند أو حقل contractId)
  let contractRef = db.collection("contracts").doc(contractId);
  let contractSnap = await contractRef.get();
  if (!contractSnap.exists) {
    const q = await db.collection("contracts")
        .where("contractId", "==", contractId).limit(1).get();
    if (q.empty) throw new HttpsError("not-found", "العقد غير موجود");
    contractRef = q.docs[0].ref;
    contractSnap = q.docs[0];
  }

  // SECURITY: مالك العقد أو أدمن فقط — يمنع توليد زيارات لعقود الآخرين
  if (contractSnap.data().userId !== request.auth.uid) {
    await _assertAdmin(request);
  }

  // مطالبة ذرّية بالتوليد (idempotent) لمنع التكرار عند تكرار نداء الدفع
  const claimed = await db.runTransaction(async (tx) => {
    const s = await tx.get(contractRef);
    const data = s.data();
    if (data.visits_generated === true) return false;
    if (data.status !== "active") {
      throw new HttpsError("failed-precondition", "لا تُولَّد الزيارات إلا بعد تفعيل العقد");
    }
    // تحقّق السعر/الزيارات ضد الباقة قبل المطالبة — الرمي هنا يُبطل المعاملة فلا
    // تُختَم visits_generated ويبقى العقد قابلاً للمعالجة الإدارية.
    await _validateContractPlan(db, data, tx);
    tx.update(contractRef, {
      visits_generated: true,
      visits_generated_at: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed) return {generated: 0, skipped: true, reason: "already_generated"};

  const c = contractSnap.data();
  const totalVisits = Number(c.planVisits || 0);
  if (totalVisits <= 0) return {generated: 0, skipped: true, reason: "no_visits"};

  // جدول الزيارات: مصفوفة scheduled_visits الصريحة (من واجهة الحجز) أو
  // افتراضياً تواتر أسبوعي ابتداءً من booking_date/booking_time_slot.
  let schedule = [];
  if (Array.isArray(c.scheduled_visits) && c.scheduled_visits.length > 0) {
    schedule = c.scheduled_visits.slice(0, totalVisits).map((v) => ({
      date: v.date, slot: v.slot || c.booking_time_slot || "10:00",
    }));
  } else if (c.booking_date) {
    const parts = String(c.booking_date).split("-").map(Number);
    const slot = c.booking_time_slot || "10:00";
    for (let i = 0; i < totalVisits; i++) {
      const dt = new Date(parts[0], parts[1] - 1, parts[2] + i * 7); // أسبوعي
      const ds = `${dt.getFullYear()}-` +
        `${String(dt.getMonth() + 1).padStart(2, "0")}-` +
        `${String(dt.getDate()).padStart(2, "0")}`;
      schedule.push({date: ds, slot});
    }
  } else {
    throw new HttpsError("failed-precondition", "لا توجد مواعيد للزيارات في العقد");
  }

  const zoneName = c.zone_name || null;
  // لا إحداثيات ملفّقة: عقد بلا موقع يولّد زياراته **بلا** حقل location (واجهة
  // السائق تُخفي الخرائط بأمان عند غيابه) بدل ختم مركز الرياض على عقود جازان.
  // location_inherited=false فقط عندما التُقط موقع حقيقي عند إنشاء العقد
  // (location_captured) — الموقع الموروث/القديم قد يكون مركز منطقة لا عنوان العميل.
  const location = c.location || null;
  const locationInherited = !(location && c.location_captured === true);
  // مدّةُ الزيارةِ من `slots.orderHours` لا بيدٍ: `Number(c.hours || 4)`
  // تُعطي `NaN` لحقلٍ تالف، فـ`endDateTime` تصير `Invalid Date`، وكلُّ
  // مقارنةٍ معها **كاذبة** في `overlapsSlot` — أي «السائق حرّ» دائماً،
  // فيُسنَدُ سائقٌ واحدٌ لكلِّ زيارات العقد وفوقَ ما لديه. و`c.hours`
  // يكتبه العميل ولا يفحصه `_validateContractPlan` (السعر والزيارات
  // والعاملات وحدها).
  const hours = slots.orderHours({hours_contracted: c.hours});
  const planName = c.planName || "باقة اشتراك";
  const results = [];
  if (!location) {
    // تنبيه إداري واحد لكل عقد (لا لكل زيارة — التوليد idempotent عبر visits_generated).
    await queuePush("ADMIN_BROADCAST", "عقد بلا موقع محدّد ⚠️",
        `العقد ${contractRef.id} (${planName}) بلا موقع حقيقي — وُلِّدت زياراته بلا ` +
        "إحداثيات ويحتاج تأكيد العنوان يدوياً.",
        "admin_contract_no_location", {contractId: contractRef.id},
        ["super_admin", "orders_manager"]).catch(() => {});
  }

  for (let i = 0; i < schedule.length; i++) {
    const v = schedule[i];
    const dp = String(v.date).split("-").map(Number);
    const hr = Number(String(v.slot).split(":")[0] || 10);
    // الدوال تعمل بـUTC، فبناء new Date(y,m,d,hr) يفسّر الساعة UTC = +3 عن الرياض.
    // نبنيها صراحةً بتوقيت الرياض (UTC+3 ثابت) كي تتّسق مع طلبات الساعة العادية.
    const startDateTime = new Date(Date.UTC(dp[0], dp[1] - 1, dp[2], hr - 3, 0, 0));
    const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);

    // معرّف حتمي: إعادة التوليد تكتب فوق نفس المستند بدل تكرار الزيارة.
    const orderRef = db.collection("orders").doc(`sub_${contractRef.id}_${i + 1}`);
    await orderRef.set({
      code: `SUB-${String(contractRef.id).slice(-5)}-${i + 1}`,
      contract_id: contractRef.id,
      visit_index: i + 1,
      total_visits: totalVisits,
      client_id: c.userId,
      client_name: c.userName || c.clientName || "عميل",
      client_phone: c.userPhone || "",
      service_type: planName,
      service_name: `${planName} — زيارة ${i + 1}/${totalVisits}`,
      amount: 0, // مدفوعة ضمن العقد
      is_paid: true,
      payment_method: "subscription",
      status: "pending", // إسنادها لحظيّ (paid-flip في onOrderWritten) والمكنسة ضمان
      ...(location ? {location: location} : {}),
      location_inherited: locationInherited,
      zone_name: zoneName,
      hours_contracted: hours,
      service_date: Timestamp.fromDate(startDateTime),
      booking_date: v.date,
      booking_time_slot: v.slot,
      created_at: FieldValue.serverTimestamp(),
      reminder_sent: false,
      // (عاملات المناسبات) يقرأه lib/widgets/service_meta_view.dart +
      // admin_panel/src/utils/serviceMeta.ts لعرض العدد/الساعات على بطاقة الزيارة.
      ...(c.contract_kind === "event_workers" ? {service_meta: {
        kind: "event_workers", workers: Number(c.workers || 0), event_hours: hours,
      }} : {}),
    });

    // محاولة الإسناد التلقائي (منطقة + فترة) → scheduled، وإلا تبقى للإدارة
    const driver = await _findFreeDriverForSlot(db, {startDateTime, endDateTime});
    if (driver) {
      const r = await _assignDriverScheduled(db, orderRef.id, driver, startDateTime);
      results.push({visit: i + 1, assigned: r.assigned !== false, driverId: r.driverId});
    } else {
      results.push({visit: i + 1, assigned: false});
    }
  }

  // إشعار موجز واحد للعميل عن دفعة التوليد كاملة — كان مُشغّل الحالة يدفع «تم
  // تأكيد حجزكِ» عن **كل** زيارة تُسنَد فور توليدها، فيُغرَق العميل بعدد زيارات
  // الباقة. (فرع scheduled يكتم زيارات العقود — هذا الملخّص يعوّضه.)
  if (c.userId) {
    await queuePush(c.userId, "تم جدولة زيارات باقتكِ 🗓️",
        `تم جدولة ${schedule.length} من الزيارات لاشتراككِ (${planName}) — ` +
        "تفاصيل المواعيد في قائمة طلباتكِ.",
        "contract_visits_scheduled", {contractId: contractRef.id}).catch(() => {});
  }

  return {generated: schedule.length, results};
});

// ════════════════════════════════════════════════════════════════════════
// Server-side subscription activation — يحلّ محلّ التفعيل العميلي الذي منعته
// قواعد Stage-C (العميل كان يكتب status='active' + visits_remaining بلا تحقّق دفع).
// ════════════════════════════════════════════════════════════════════════

/**
 * يولّد زيارات العقد (طلبات + إسناد سائقين). مشترك؛ لا يرمي — يُعيد {skipped}.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} contractRef
 * @param {object} c بيانات العقد
 * @return {Promise<object>}
 */
async function _generateContractVisits(db, contractRef, c) {
  const totalVisits = Number(c.planVisits || 0);
  if (totalVisits <= 0) return {generated: 0, skipped: true, reason: "no_visits"};
  let schedule = [];
  if (Array.isArray(c.scheduled_visits) && c.scheduled_visits.length > 0) {
    schedule = c.scheduled_visits.slice(0, totalVisits).map((v) => ({
      date: v.date, slot: v.slot || c.booking_time_slot || "10:00",
    }));
  } else if (c.booking_date) {
    const parts = String(c.booking_date).split("-").map(Number);
    const slot = c.booking_time_slot || "10:00";
    for (let i = 0; i < totalVisits; i++) {
      const dt = new Date(parts[0], parts[1] - 1, parts[2] + i * 7);
      schedule.push({date: `${dt.getFullYear()}-` +
        `${String(dt.getMonth() + 1).padStart(2, "0")}-` +
        `${String(dt.getDate()).padStart(2, "0")}`, slot});
    }
  } else {
    return {generated: 0, skipped: true, reason: "no_schedule"};
  }
  const zoneName = c.zone_name || null;
  // لا إحداثيات ملفّقة (نفس منطق generateSubscriptionVisits): عقد بلا موقع يولّد
  // زياراته بلا حقل location بدل ختم مركز الرياض، مع تنبيه إداري واحد لكل عقد.
  const location = c.location || null;
  const locationInherited = !(location && c.location_captured === true);
  // مدّةُ الزيارةِ من `slots.orderHours` لا بيدٍ: `Number(c.hours || 4)`
  // تُعطي `NaN` لحقلٍ تالف، فـ`endDateTime` تصير `Invalid Date`، وكلُّ
  // مقارنةٍ معها **كاذبة** في `overlapsSlot` — أي «السائق حرّ» دائماً،
  // فيُسنَدُ سائقٌ واحدٌ لكلِّ زيارات العقد وفوقَ ما لديه. و`c.hours`
  // يكتبه العميل ولا يفحصه `_validateContractPlan` (السعر والزيارات
  // والعاملات وحدها).
  const hours = slots.orderHours({hours_contracted: c.hours});
  const planName = c.planName || "باقة اشتراك";
  const results = [];
  if (!location) {
    await queuePush("ADMIN_BROADCAST", "عقد بلا موقع محدّد ⚠️",
        `العقد ${contractRef.id} (${planName}) بلا موقع حقيقي — وُلِّدت زياراته بلا ` +
        "إحداثيات ويحتاج تأكيد العنوان يدوياً.",
        "admin_contract_no_location", {contractId: contractRef.id},
        ["super_admin", "orders_manager"]).catch(() => {});
  }
  for (let i = 0; i < schedule.length; i++) {
    const v = schedule[i];
    const dp = String(v.date).split("-").map(Number);
    const hr = Number(String(v.slot).split(":")[0] || 10);
    // الدوال تعمل بـUTC، فبناء new Date(y,m,d,hr) يفسّر الساعة UTC = +3 عن الرياض.
    // نبنيها صراحةً بتوقيت الرياض (UTC+3 ثابت) كي تتّسق مع طلبات الساعة العادية.
    const startDateTime = new Date(Date.UTC(dp[0], dp[1] - 1, dp[2], hr - 3, 0, 0));
    const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
    // معرّف حتمي: إعادة التوليد تكتب فوق نفس المستند بدل تكرار الزيارة.
    const orderRef = db.collection("orders").doc(`sub_${contractRef.id}_${i + 1}`);
    await orderRef.set({
      code: `SUB-${String(contractRef.id).slice(-5)}-${i + 1}`,
      contract_id: contractRef.id,
      visit_index: i + 1,
      total_visits: totalVisits,
      client_id: c.userId,
      client_name: c.userName || c.clientName || "عميل",
      client_phone: c.userPhone || "",
      service_type: planName,
      service_name: `${planName} — زيارة ${i + 1}/${totalVisits}`,
      amount: 0,
      is_paid: true,
      payment_method: "subscription",
      status: "pending",
      ...(location ? {location: location} : {}),
      location_inherited: locationInherited,
      zone_name: zoneName,
      hours_contracted: hours,
      service_date: Timestamp.fromDate(startDateTime),
      booking_date: v.date,
      booking_time_slot: v.slot,
      created_at: FieldValue.serverTimestamp(),
      reminder_sent: false,
      // (عاملات المناسبات) نفس حقل service_meta الذي يكتبه generateSubscriptionVisits
      // — تُقرأ من service_meta_view.dart + admin_panel serviceMeta.ts.
      ...(c.contract_kind === "event_workers" ? {service_meta: {
        kind: "event_workers", workers: Number(c.workers || 0), event_hours: hours,
      }} : {}),
    });
    const driver = await _findFreeDriverForSlot(db, {startDateTime, endDateTime});
    if (driver) {
      const r = await _assignDriverScheduled(db, orderRef.id, driver, startDateTime);
      results.push({visit: i + 1, assigned: r.assigned !== false, driverId: r.driverId});
    } else {
      results.push({visit: i + 1, assigned: false});
    }
  }
  return {generated: schedule.length, results};
}

// مُشغّل: عند تأكيد دفع العقد (is_paid يصبح true عبر verify/webhook/wallet) نفعّل
// خادميّاً: status='active' + منح الزيارات + توليدها + إسناد السائقين. idempotent.
/**
 * تفعيلُ عقدٍ مدفوعٍ: مطالبةٌ ذرّيّةٌ + تحقّقُ الباقةِ + توليدُ الزياراتِ
 * + الإشعارات. **قاعدةٌ واحدةٌ بمُنادِيَين** — المُشغّلُ عند قلبِ `is_paid`،
 * والمكنسةُ عند عقدٍ مدفوعٍ بقي `pending` (فالمُشغّلُ بلا `retry` ولا يَعودُ
 * لمستندٍ فاته الحدث). وكانت هذه الشفرةُ داخلَ المُشغّلِ وحدَه، فلا سبيلَ
 * لإعادةِ محاولتِها إلّا بنسخةٍ ثانيةٍ تَنحرِف.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference} contractRef مستندُ العقد.
 * @param {string} contractId معرّفُه (للإشعاراتِ والسجلّ).
 * @return {Promise<{activated: boolean, reason?: string}>}
 */
async function _activateContractNow(db, contractRef, contractId) {
  // مطالبة ذرّية (idempotent) بالتفعيل + التوليد
  //
  // ⚠️ **كانت بلا `try`، والمُشغّلُ بلا `retry` (2026-10-05).** فمعامَلةٌ
  // تَفشلُ لتنازعٍ أو مهلةٍ تَرفعُ الاستثناءَ خارجَ المُعالِج، و
  // `onDocumentUpdated` لا يَعودُ لمستندٍ فاته الحدث: فيَبقى العقدُ
  // `is_paid: true` و`status: 'pending'` — لا تفعيلَ، ولا
  // `visits_remaining`، ولا زيارةَ واحدة، ولا سائق، **ولا تنبيهَ من أيِّ
  // نوع**، ولا محاولةَ ثانية. و`client_dashboard` يُرشِّحُ
  // `m['status'] != 'active'` فيَحجبُ العقدَ: فبطاقةُ الاشتراكِ **لا
  // تَظهرُ أصلاً** لعميلةٍ دفعت أغلى مبلغٍ في التطبيق (باقةُ زيارات).
  // وهي سادسُ مرّةٍ لعائلةِ «الفشلُ يَكتبُ سطراً ويُنسي» وأكبرُها مالاً.
  //
  // والعلَمُ هنا **أفضلُ جهد** لا شبكةَ أمان: كتابتُه قد تَفشلُ لنفسِ
  // سببِ فشلِ المعامَلة. والشبكةُ الحقيقيّةُ في `opsHealthSweep` وهي
  // **على الحالةِ لا على علَم** — عقدٌ مدفوعٌ ما زال `pending` هو
  // الحالةُ المتناقضةُ بعينِها، فلا تَضيعُ وإن ضاعَ العلَم.
  let claim;
  try {
    claim = await db.runTransaction(async (tx) => {
    const s = await tx.get(contractRef);
    const c = s.data() || {};
    if (c.visits_generated === true) return null;
    // (إغلاق ثغرة العقد المُسعَّر عميلياً) نتحقّق من السعر/الزيارات ضد الباقة
    // قبل التفعيل — عقد بسعر مُتلاعَب به يُختَم بالفشل ولا يُفعَّل ولا تُمنح زيارات،
    // ويُنبَّه الأدمن (لا نرمي: مشغّلات Firestore لا تُعيد المحاولة فيضيع الخطأ صامتاً).
    try {
      await _validateContractPlan(db, c, tx);
    } catch (e) {
      tx.update(contractRef, {
        plan_validation_failed: true,
        plan_validation_error: String(e.message || e),
        plan_validation_at: FieldValue.serverTimestamp(),
      });
      return {__invalid: String(e.message || e)};
    }
    tx.update(contractRef, {
      status: "active",
      activated_at: FieldValue.serverTimestamp(),
      visits_generated: true,
      visits_generated_at: FieldValue.serverTimestamp(),
    });
    // منح رصيد الزيارات + حقول عرض الاشتراك ذرّياً — بدونها كانت بطاقة الاشتراك
    // في لوحة العميل لا تظهر أبداً (has_active_subscription تبقى false).
    if (c.userId && Number(c.planVisits || 0) > 0) {
      const pv = Number(c.planVisits);
      // انتهاء الاشتراك = تاريخ آخر زيارة مجدولة + مهلة 7 أيام (بدل ثابت 90 يوماً
      // بلا صلة بالباقة). نشتق آخر تاريخ من scheduled_visits، أو من booking_date
      // بنمط الأسبوع (التاريخ الأول + (العدد-1)×7 أيام) كما يولّد _generateContractVisits.
      let lastVisitMs = Date.now();
      if (Array.isArray(c.scheduled_visits) && c.scheduled_visits.length > 0) {
        for (const v of c.scheduled_visits.slice(0, pv)) {
          const dp = String(v.date || "").split("-").map(Number);
          if (dp.length === 3 && !dp.some(isNaN)) {
            const ms = Date.UTC(dp[0], dp[1] - 1, dp[2]);
            if (ms > lastVisitMs) lastVisitMs = ms;
          }
        }
      } else if (c.booking_date) {
        const bp = String(c.booking_date).split("-").map(Number);
        if (bp.length === 3 && !bp.some(isNaN)) {
          lastVisitMs = Date.UTC(bp[0], bp[1] - 1, bp[2] + Math.max(0, pv - 1) * 7);
        }
      }
      const expiryMs = Math.max(
          lastVisitMs + 7 * 24 * 60 * 60 * 1000, // مهلة بعد آخر زيارة
          Date.now() + 24 * 60 * 60 * 1000); // لا يقلّ عن يوم من الآن
      tx.set(db.collection("users").doc(c.userId), {
        visits_remaining: FieldValue.increment(pv),
        has_active_subscription: true,
        subscription_total_visits: pv,
        subscription_type: c.planName || "باقة زيارة",
        subscription_expiry: Timestamp.fromMillis(expiryMs),
      }, {merge: true});
      // عدّادات مستقلّة لكل عقد — كي تعرض الرئيسية بطاقة منفصلة لكل باقة نشطة
      // (الشهرية + الأسبوعية معاً) بدل طمس حقول المستخدم المجمّعة بعضها بعضاً.
      tx.set(contractRef, {
        visits_remaining: pv,
        visits_total: pv,
        expiry: Timestamp.fromMillis(expiryMs),
      }, {merge: true});
    }
    return c;
    });
  } catch (e) {
    console.error(`_activateContractNow: claim txn failed for ` +
      `${contractId}:`, e.message);
    await contractRef.update({
      contract_activation_failed: true,
      contract_activation_error: String(e.message || e),
    }).catch(() => {});
    await queuePush("ADMIN_BROADCAST", "تفعيل عقد مدفوع فشل ⚠️",
        `العقد ${contractId} مدفوع ولم يُفعَّل (فشل المعامَلة) — ` +
        "لا زيارات ولا بطاقة اشتراك عند العميلة. تُعاد المحاولة دوريّاً.",
        "contract_activation_failed", {contractId: contractId},
        ["super_admin", "orders_manager", "accountant_admin"]).catch(() => {});
    return {activated: false, reason: "txn_failed"};
  }
  if (!claim) return {activated: false, reason: "already"};
  if (claim.__invalid) {
    console.error(`_activateContractNow: plan validation failed for ` +
      `${contractId}: ${claim.__invalid}`);
    await queuePush("ADMIN_BROADCAST", "عقد مدفوع بسعر لا يطابق الباقة ⚠️",
        `العقد ${contractId} دُفع لكن سعره/زياراته لا تطابق الباقة ` +
        `(${claim.__invalid}). لم يُفعَّل — راجعه يدوياً.`,
        "contract_plan_mismatch", {contractId: contractId},
        ["orders_manager"]).catch(() => {});
    return {activated: false, reason: "invalid_plan"};
  }
  // المعرّفات حتمية فإعادة التوليد idempotent. لا نُعيد راية visits_generated عند
  // الفشل حتى لا يتكرّر منح الزيارات.
  //
  // ⚠️ **وكان هذا الفرعُ `console.error` وحدَه، وتعليقُه يَقول «أي نقصٍ
  // يُكمِله مسار إداري» — وذلك المسارُ لا وجودَ له (2026-10-05).**
  // `_generateContractVisits` يُولّدُ الزياراتِ **تِباعاً** (`await
  // orderRef.set` ثمّ إسنادُ سائقٍ لكلِّ زيارة)، فاستثناءٌ عند الزيارةِ
  // *i* يَترُكُ 1..i−1 منشأةً و i..N **غائبة**: نقصٌ جزئيٌّ حقيقيّ. و
  // `status` صارَ `active` و`visits_remaining` مُنِحَ، فبطاقةُ الاشتراكِ
  // في لوحتِها تَعرضُ «N زيارة متبقية» بشريطِ تقدّمٍ — **ورصيدٌ لا
  // يُنفِقُه أيُّ مسارٍ عميليّ** (`visits_remaining` له أربعُ قراءاتٍ في
  // `lib/` كلُّها عرضٌ، ولا موضعَ يَخصِمُه)، ولا زيارةَ مجدولةً خلفَه.
  //
  // و«المسارُ الإداريُّ» المقصودُ هو `exports.generateSubscriptionVisits`:
  // نداءٌ **بلا مُنادٍ واحدٍ** في العميل (الموضعانِ في
  // `contract_signing_screen` تعليقانِ يُسمّيانِ حقولَه)، وهو على قائمةِ
  // الحذفِ في `functions_delete_once.yml` بملاحظةِ «استبدلها مُشغِّل
  // activateContractOnPaid» — فالتعليقانِ يُشيرُ كلٌّ منهما إلى الآخرِ
  // ولا يَعملُ أيٌّ منهما. ولا شاشةَ إداريّةَ تُعيدُ التوليدَ (الوحيدُ
  // `_regenerate` في سجلِّ الفواتير).
  //
  // فالفشلُ يَكتبُ **علَمَه**، والمكنسةُ تَستعلمُ العلَمَ لا الحالةَ:
  // `status == 'active'` هي الحالةُ السليمةُ لكلِّ عقدٍ فاعل، فاستعلامُها
  // يَغرقُ فيها — تمييزٌ سجّلَه هذا المستودعُ عند `referral_payout_pending`.
  // وإعادةُ التوليدِ آمنةٌ: المعرّفاتُ حتميّةٌ فتُكتَبُ فوقَ نفسِها.
  try {
    await _generateContractVisits(db, contractRef, claim);
    await contractRef.update({
      contract_visits_pending: FieldValue.delete(),
    }).catch(() => {});
  } catch (e) {
    console.error("_activateContractNow generate:", e);
    await contractRef.update({
      contract_visits_pending: true,
      contract_visits_error: String(e.message || e),
    }).catch(() => {});
    const alerted = await queuePush("ADMIN_BROADCAST",
        "زيارات اشتراك مدفوع لم تُولَّد ⚠️",
        `العقد ${contractId} فُعِّل ومُنِحت زياراته، لكن توليد ` +
        "الزيارات فشل — رصيدٌ بلا مواعيد. تُعاد المحاولة دوريّاً.",
        "contract_visits_failed", {contractId: contractId},
        ["super_admin", "orders_manager"])
        .then(() => true).catch(() => false);
    await contractRef.update({contract_visits_alerted: alerted})
        .catch(() => {});
  }
  // إشعار إداري موحّد واحد لكل اشتراك (أسبوعي/شهري) — بريده يسرد جدول كل الزيارات
  // (يُبنى في _buildAdminAlertHtml). داخل الـ claim الذرّي فيُرسل مرة واحدة لكل عقد،
  // ويحلّ محلّ إشعارات «طلب خدمة جديد» المكتومة لكل زيارة.
  await queuePush("ADMIN_BROADCAST", "اشتراك جديد! 📄",
      `اشتراك جديد في (${claim.planName || "باقة"}) — ${Number(claim.planVisits || 0)} ` +
      `زيارة. تفاصيل الجدول في البريد.`,
      "new_contract_admin", {contractId: contractId},
      ["orders_manager"]).catch(() => {});
  if (claim.userId) {
    await queuePush(claim.userId, "تم تفعيل باقتكِ ✨",
        `فُعِّل اشتراككِ وأُضيفت ${Number(claim.planVisits || 0)} زيارة لحسابكِ.`,
        "contract_activated", {contractId: contractId}).catch(() => {});
  }
  return {activated: true};
}

exports.activateContractOnPaid = onDocumentUpdated({document: "contracts/{contractId}", cpu: 0.25},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (before.is_paid === true || after.is_paid !== true) return null;
      await _activateContractNow(getFirestore(), change.after.ref,
          event.params.contractId);
      return null;
    });

// دفع باقة اشتراك بالمحفظة (خادميّاً) — يخصم planPrice ذرّياً ويقلب is_paid على
// العقد، فيُشغّل activateContractOnPaid. القواعد تمنع العميل من فعل ذلك بنفسه.
exports.payContractWithWallet = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  const uid = request.auth.uid;
  const contractId = request.data && request.data.contractId;
  if (!contractId) throw new HttpsError("invalid-argument", "معرف العقد مطلوب");
  const db = getFirestore();
  const contractRef = db.collection("contracts").doc(contractId);
  const walletRef = db.collection("wallets").doc(uid);
  return await db.runTransaction(async (t) => {
    const cSnap = await t.get(contractRef);
    if (!cSnap.exists) throw new HttpsError("not-found", "العقد غير موجود");
    const c = cSnap.data();
    if (c.userId !== uid) throw new HttpsError("permission-denied", "ليس عقدك");
    if (c.is_paid === true) return {alreadyPaid: true};
    const price = Number(c.planPrice || 0);
    if (price <= 0) throw new HttpsError("failed-precondition", "سعر الباقة غير صالح");
    const wSnap = await t.get(walletRef);
    const balance = wSnap.exists ? Number(wSnap.data().balance || 0) : 0;
    if (balance < price) throw new HttpsError("failed-precondition", "الرصيد غير كافٍ");
    const txRef = walletRef.collection("transactions").doc(`wallet_contract_${contractId}`);
    t.set(walletRef, {balance: balance - price,
      last_updated: FieldValue.serverTimestamp()}, {merge: true});
    t.set(txRef, {amount: -price, points: 0, type: "payment",
      description: "دفع باقة اشتراك", contract_id: contractId,
      created_at: FieldValue.serverTimestamp()});
    t.update(contractRef, {is_paid: true, payment_method: "wallet",
      paid_at: FieldValue.serverTimestamp()});
    return {success: true, newBalance: balance - price};
  });
});

// ════════════════════════════════════════════════════════════════════════
// Admin approve + assign (المسار الثاني: الكنب/المكيفات/المتجر)
// ════════════════════════════════════════════════════════════════════════
// مراحلُ حياة الطلب فيما يخصّ الإسناد — نسخةُ الخادم من `lib/utils/order_lifecycle.dart`
// (يُقرن الحارسُ المجموعتين حرفاً بحرف). القسمةُ على **وجود سائق** لا على الحالة
// وحدها، فالمساران يقسمان الفضاء كاملاً ولا يتداخلان:
//   PRE_DISPATCH + بلا driver_id  → approveAndAssignOrder  (إسنادٌ ابتدائي)
//   ACTIVE_ASSIGNED + بـdriver_id → rescheduleAssignedOrder (إعادة جدولة/إسناد)
// و`assigned` في المجموعتين بقصد: طلبٌ assigned بلا سائق ما زال إسناداً ابتدائياً.
const PRE_DISPATCH_STATUSES = [
  "pending", "under_review", "awaiting_payment", "assigned",
];

// سببُ رفضِ إسنادِ سائقٍ لطلبٍ غيرِ مدفوع — ثابتٌ واحدٌ لموضعَي الرفضِ
// (الفحصُ قبلَ المعاملةِ والفحصُ الذرّيُّ داخلَها) ومطابقٌ حرفيّاً لـ
// `kUnpaidDispatchRefusal` في `lib/utils/order_lifecycle.dart`: صياغتانِ
// لقرارٍ واحدٍ هي ما يُنتجُ هذا النوعَ من العطل، وكلا الجمهورَين هو الأدمن.
const UNPAID_DISPATCH_REFUSAL =
  "لا يمكن إسناد سائق لطلب غير مدفوع — انتظر تأكيد الدفع";

exports.approveAndAssignOrder = onCall({cpu: 0.25}, async (request) => {
  await _assertAdmin(request); // super_admin أو orders_manager
  const {orderId, driverId, scheduledIso} = request.data;
  if (!orderId || !driverId || !scheduledIso) {
    throw new HttpsError("invalid-argument", "البيانات ناقصة (الطلب/السائق/الموعد)");
  }
  const startDateTime = parseKsaIso(scheduledIso);
  if (isNaN(startDateTime.getTime())) {
    throw new HttpsError("invalid-argument", "موعد غير صالح");
  }
  const db = getFirestore();
  const orderRef = db.collection("orders").doc(orderId);

  // (H3 في المسار اليدوي) الأهلية كاملةً لا النشاط وحده: كان الفحص هنا
  // `exists` + `is_active` فقط، فيمرّ مستند سائقٍ بلا حساب دخول (مسودّات
  // `addDoc` القديمة من لوحة الويب) أو كادرٌ ليس سائق توصيل. وإسناد أحدهما
  // يُخفي الطلب المدفوع عن الجميع — القواعد وتطبيق السائق يربطان الرؤية
  // بـ`auth.uid == driver_id`. المُسنِد الآلي كان محصَّناً وهذا المسار مكشوفاً.
  const [orderSnap, driverData] = await Promise.all([
    orderRef.get(),
    _assertAssignableDriver(db, driverId),
  ]);
  if (!orderSnap.exists) throw new HttpsError("not-found", "الطلب غير موجود");

  const orderData = orderSnap.data();
  // كان الشرط `status !== "pending"` فقط، فطلبٌ under_review/awaiting_payment لا
  // يقبله الخادم — وتطبيقُ الأدمن كان يسقط حينها إلى كتابةٍ مباشرة بلا أيّ فحص
  // أهليّة. توسيعُ المقبول هنا هو ما يجعل «الخادم هو الحارس» صحيحاً فعلاً.
  if (!PRE_DISPATCH_STATUSES.includes(orderData.status)) {
    throw new HttpsError("failed-precondition", "لا يمكن اعتماد الطلب بحالته الحالية");
  }
  // طلبٌ يحمل سائقاً شأنُ rescheduleAssignedOrder (يستثني الطلب نفسه من فحص
  // التعارض) — ولو قبلناه هنا لحُسب السائق الحاليّ تعارضاً مع نفسه.
  if (orderData.driver_id) {
    throw new HttpsError("failed-precondition",
        "الطلب مُسنَد سلفاً — استعمل إعادة الجدولة/الإسناد لتغيير سائقه");
  }

  // **لا سائقَ لطلبٍ غيرِ مدفوع.** القاعدةُ مُنفَّذةٌ في أربعةِ مساراتٍ هنا —
  // `onOrderWritten` لا يُسنِدُ إلّا على **انقلابِ** `is_paid`، وكتلتا
  // `sweepUnassignedPaidOrders` تتخطّيانِ `is_paid !== true`،
  // و`capacity.countBookings` تتخطّاه فلا يَستهلكُ سعة،
  // و`cancelStaleUnpaidOrders` تُلغيه بعد ثلاثين دقيقة — وكانت غائبةً عن هذا
  // المسارِ وحدَه، وهو ما يَنقُرُه الأدمنُ من سطحَين (شاشةُ تفاصيلِ الطلب،
  // وقائمةُ إجراءاتِ صفِّ لوحةِ الويب، وكلتاهما تَفتحُ الإسنادَ لكلِّ
  // `pending` بلا أيِّ نظرٍ إلى الدفع). شكلُ `isAssignableDriver` بعينِه:
  // مُنفَّذةٌ في اثنَين من أربعة، والمكشوفُ هو ما يُنقَر.
  //
  // وإسنادُ غيرِ المدفوعِ ثلاثُ نتائج: (أ) الحالةُ تصيرُ `scheduled` ومكنسةُ
  // الإلغاءِ تَستعلمُ `status == "pending"` وحدَها، فالطلبُ غيرُ المدفوعِ
  // **لا يُلغى أبداً**؛ (ب) `scheduled` داخلَ `CONFLICT_STATUSES` فيَشغلُ
  // السائقَ، و`countBookings` تتخطّى غيرَ المدفوعِ فلا يَستهلكُ سعة — فتُعرَضُ
  // الساعةُ على عميلةٍ تَدفعُ ثمّ لا يُوجَدُ سائقٌ حرٌّ فتَعلقُ حتى الاستردادِ
  // الآلي، وهي الحادثةُ المسجَّلةُ بنصِّها؛ (ج) السائقُ يُرسَلُ، وشرطُ
  // `remindClientsUpcomingAppointments` هو `is_paid === true || driverAssigned`
  // و`driverAssigned` يَكفيه `scheduled` — فتَصِلُها «فريقنا في الطريق إليكِ»
  // لخدمةٍ لم تُدفَع.
  //
  // و`pending` بلا دفعٍ هي الحالةُ الطبيعيّةُ **قبلَ** الدفعِ لكلِّ طلبِ خدمة،
  // فالنافذةُ ثوانٍ في البطاقةِ وساعاتٌ في تمارا — ليست نظريّة.
  if (orderData.is_paid !== true) {
    throw new HttpsError("failed-precondition", UNPAID_DISPATCH_REFUSAL);
  }

  // (الثغرة #2) تأكّد أن السائق المختار حرّ فعلاً في الفترة المطلوبة
  const hours = slots.orderHours(orderData);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
  const free = await _isDriverFreeForSlot(db, driverId, startDateTime, endDateTime);
  if (!free) {
    throw new HttpsError(
        "failed-precondition",
        "السائق مشغول بمهمة أخرى في هذا الوقت — اختر سائقاً أو موعداً آخر");
  }

  // (الثغرة #2) Transaction ذرّي: يُعيد فحص حالة الطلب قبل الإسناد لمنع التعيين
  // المزدوج عند موافقة مديرَين على نفس الطلب معاً.
  const d = driverData;
  // موعد الرياض (UTC+3) — الصيغة في ksa_time.js: حساب المكوّنات بـUTC مباشرةً
  // كان يعطي ساعةً ناقصةً ثلاثاً (07:00 بدل 10:00) → تذكيرٌ بوقتٍ خاطئ وعدمُ
  // احتساب الفترة في السعة.
  const {bookingDate, bookingTimeSlot: timeSlot} =
    riyadhBookingFields(startDateTime);

  // (تعليمات المنزل) ننسخها من مستند العميل إلى الطلب عند الإسناد اليدوي — نفس
  // منطق _assignDriverScheduled: السائق لا يستطيع قراءة users الأخرى بالقواعد.
  let houseRules = null;
  if (orderData.client_id) {
    const uSnap = await db.collection("users").doc(orderData.client_id).get();
    const hr = uSnap.exists ? uSnap.data().house_rules : null;
    if (typeof hr === "string" && hr.trim()) houseRules = hr.trim();
  }

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(orderRef);
    const fd = fresh.data() || {};
    // نفسُ القاعدة ذرّياً: الحالة مقبولة **ولا سائق** — فمديرٌ آخر أسند الطلب
    // أثناء العملية يُوقِف هذه. (كان الفحص `!== "pending"` فيتجاوز الحالات الأخرى.)
    if (!PRE_DISPATCH_STATUSES.includes(fd.status) || fd.driver_id) {
      throw new HttpsError("failed-precondition", "تم اعتماد الطلب بالفعل من مدير آخر");
    }
    // ونفسُ شرطِ الدفعِ ذرّياً: استردادٌ جرى أثناءَ العمليّة يَكتبُ
    // `is_paid: false`، فالقراءةُ الطازجةُ هي ما يَمنعُ إسنادَ المُستردِّ.
    if (fd.is_paid !== true) {
      throw new HttpsError("failed-precondition", UNPAID_DISPATCH_REFUSAL);
    }
    // (منع الحجز المزدوج) إعادة فحص حرّية السائق ذرّياً داخل المعاملة — الفحص أعلاه
    // خارج المعاملة كان يسمح لموافقتين متزامنتين على طلبين مختلفين بإسناد نفس السائق
    // لفترة متداخلة. النافذة −24س (كانت −8 فتُفوِّت مهمة hours_contracted>8 تبدأ
    // قبلها بأكثر من 8س — باقات السكن تتيح مدداً حتى 12س؛ نفس إصلاح _assignDriverScheduled).
    const slotEnd = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
    const winStart = slots.conflictWindowStart(startDateTime);
    const conflictQ = db.collection("orders")
        .where("service_date", ">=", Timestamp.fromDate(winStart))
        .where("service_date", "<", Timestamp.fromDate(slotEnd))
        .where("status", "in", slots.CONFLICT_STATUSES);
    const conflictSnap = await tx.get(conflictQ);
    for (const d2 of conflictSnap.docs) {
      const od = d2.data();
      if (od.driver_id !== driverId) continue;
      if (slots.overlapsSlot(od, startDateTime, slotEnd)) {
        throw new HttpsError("failed-precondition",
            "السائق مشغول بمهمة أخرى في هذا الوقت — اختر سائقاً أو موعداً آخر");
      }
    }
    tx.update(orderRef, {
      status: "scheduled",
      driver_id: driverId,
      ...(houseRules ? {house_rules: houseRules} : {}),
      driver_name: d.name || "سائق",
      // assigned_driver: شاشات التتبّع تقرأ هذا الحقل — بدونه يعلق العميل على «جاري
      // تعيين سائق» للأبد في مسار الاعتماد اليدوي (كنب/مكيفات/متجر).
      assigned_driver: d.name || "سائق",
      driver_phone: d.phone || "000000000",
      // تقييمُ السائق لحظةَ الإسناد — شاشةُ التتبّع تعرضه للعميلة. لا يُكتب
      // إلّا إن وُجد فعلاً: كانت الشاشةُ تعرض «★ 5.0» افتراضاً لكلِّ سائق،
      // ولا شيءَ في المستودع يكتب هذا الحقل أصلاً، فكان الرقمُ مختلقاً دائماً.
      ...(Number.isFinite(Number(d.rating_avg)) && Number(d.rating_avg) > 0 ?
        {driver_rating_avg: Number(d.rating_avg)} : {}),
      assigned_at: FieldValue.serverTimestamp(),
      scheduled_at: Timestamp.fromDate(startDateTime),
      service_date: Timestamp.fromDate(startDateTime),
      booking_date: bookingDate,
      booking_time_slot: timeSlot,
      // **تصفيرُ أعلامِ التذكير** كما يَفعلُ `rescheduleAssignedOrder`: هذا
      // النداءُ يَكتبُ موعداً جديداً، و`remindClientsUpcomingAppointments`
      // يَتخطّى ما عَلَمُه مرفوع. و`realAppointment` فيه هو
      // `is_paid === true || driverAssigned` — فطلبٌ **مدفوعٌ بلا سائق**
      // يُذكَّرُ عنه ويُرفَعُ علَمُه قبلَ أيِّ إسناد، فاعتمادٌ يُحرّكُ الموعدَ
      // بلا تصفيرٍ كان يَعني **لا تذكيرَ للموعدِ الجديدِ أبداً**.
      // (`reminder_sent` تذكيرُ السائقِ: لم يَكُنْ له سائقٌ فلا يَرتفعُ، ويُصفَّرُ
      // اتّساقاً مع القاعدةِ الواحدة.)
      reminder_sent: false,
      client_reminder_24h_sent: false,
      client_reminder_soon_sent: false,
    });
  });

  return {assigned: true, driverId: driverId, driverName: d.name || "سائق"};
});

// (#23) إعادة جدولة طلب مُسنَد نشط ذرّياً — يعيد فحص تعارض السائق **داخل معاملة**
// (مستثنياً هذا الطلب نفسه) قبل كتابة الموعد الجديد. المسار المباشر في تطبيق الأدمن كان
// يكتب service_date بلا فحص، فيصير السائق محجوزاً لمهمتين متداخلتين. (الإسناد الابتدائي
// على pending يغطّيه approveAndAssignOrder؛ هذه للطلب المُسنَد فعلاً.)
// يعالج طلباً مُسنَداً نشطاً: **إعادة جدولة** (scheduledIso) و/أو **إعادة إسناد لسائق
// آخر** (newDriverId) — كلاهما بفحص تعارض ذرّي على السائق **المستهدَف** داخل معاملة
// (مستثنياً هذا الطلب). السائق القديم عند التبديل يحرّره مُشغّل freeOldDriverOnReassign.
exports.rescheduleAssignedOrder = onCall({cpu: 0.25}, async (request) => {
  await _assertAdmin(request);
  const {orderId, scheduledIso, newDriverId} = request.data;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "البيانات ناقصة (الطلب)");
  }
  if (!scheduledIso && !newDriverId) {
    throw new HttpsError("invalid-argument", "لا تغيير مطلوب (موعد أو سائق)");
  }
  let parsedStart = null;
  if (scheduledIso) {
    parsedStart = parseKsaIso(scheduledIso);
    if (isNaN(parsedStart.getTime())) {
      throw new HttpsError("invalid-argument", "موعد غير صالح");
    }
  }
  const db = getFirestore();
  const orderRef = db.collection("orders").doc(orderId);
  // 'assigned' حالة نشطة يحملها السائق في كل الشاشات — استبعادها كان يدفع تعديل
  // زيارتها للمسار المباشر غير الذرّي في لوحتي الأدمن.
  const active = slots.CONFLICT_STATUSES;

  // إعادة الإسناد لسائق آخر: **الأهلية كاملةً** لا النشاط وحده (قراءة قبل
  // المعاملة كافية). كان الفحص `exists` + `is_active` فقط — نفس فجوة
  // approveAndAssignOrder: إسنادٌ لمستندٍ بلا حساب دخول ينقل الطلب من سائقٍ
  // يراه إلى من لا يراه أحد، فيختفي بعد أن كان ظاهراً.
  let newDriverName = null;
  let newDriverPhone = null;
  if (newDriverId) {
    const dData = await _assertAssignableDriver(db, newDriverId);
    newDriverName = dData.name || "سائق";
    newDriverPhone = dData.phone || "000000000";
  }

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) throw new HttpsError("not-found", "الطلب غير موجود");
    const o = snap.data();
    if (!o.driver_id || !active.includes(o.status)) {
      throw new HttpsError("failed-precondition",
          "الطلب غير مُسنَد نشط — لا يمكن إعادة جدولته بهذا المسار");
    }
    const reassign = !!(newDriverId && newDriverId !== o.driver_id);
    const targetDriver = reassign ? newDriverId : o.driver_id;
    // الموعد الفعّال: الجديد إن وُجد، وإلّا الحالي (لفحص التعارض عند تبديل السائق فقط).
    const startDateTime = parsedStart ||
      (o.service_date && o.service_date.toDate ? o.service_date.toDate() : null);
    if (!startDateTime) {
      throw new HttpsError("failed-precondition", "لا موعد للطلب لإعادة الفحص");
    }
    const hours = slots.orderHours(o);
    const slotEnd = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
    // −24س: تلتقط مهمة طويلة (hours_contracted>8، باقات السكن حتى 12س) تبدأ قبل
    // الموعد الجديد بأكثر من 8 ساعات — كانت −8 تُفوِّتها فيُحجَز السائق لمهمتين.
    const winStart = slots.conflictWindowStart(startDateTime);
    const conflictQ = db.collection("orders")
        .where("service_date", ">=", Timestamp.fromDate(winStart))
        .where("service_date", "<", Timestamp.fromDate(slotEnd))
        .where("status", "in", active);
    const conflictSnap = await tx.get(conflictQ);
    for (const d2 of conflictSnap.docs) {
      if (d2.id === orderId) continue; // استثناء الطلب الحالي
      const od = d2.data();
      if (od.driver_id !== targetDriver) continue;
      if (slots.overlapsSlot(od, startDateTime, slotEnd)) {
        throw new HttpsError("failed-precondition",
            "السائق مشغول بمهمة أخرى في هذا الوقت — اختر موعداً أو سائقاً آخر");
      }
    }
    const upd = {rescheduled_at: FieldValue.serverTimestamp()};
    if (parsedStart) {
      const rbf = riyadhBookingFields(startDateTime);
      upd.service_date = Timestamp.fromDate(startDateTime);
      upd.scheduled_at = Timestamp.fromDate(startDateTime);
      upd.booking_date = rbf.bookingDate;
      upd.booking_time_slot = rbf.bookingTimeSlot;
      // موعد جديد = تذكيرات جديدة: كرونا تذكير السائق والعميل يتخطيان من سبق
      // تذكيره — نقلُ زيارةٍ بعد إرسال تذكيرها كان يترك موعدها الجديد بلا تذكير.
      upd.reminder_sent = false;
      upd.client_reminder_24h_sent = false;
      upd.client_reminder_soon_sent = false;
    }
    if (reassign) {
      upd.driver_id = newDriverId;
      upd.driver_name = newDriverName;
      upd.assigned_driver = newDriverName;
      // زر «اتصال بالسائق» عند العميل يقرأ driver_phone — تركه القديم كان يجعل
      // العميل يهاتف السائق **السابق** بعد كل تبديل.
      upd.driver_phone = newDriverPhone;
      upd.assigned_at = FieldValue.serverTimestamp();
      // status يبقى نشطاً؛ إشعار السائق الجديد يُطلقه notifyDriverOnAssignment،
      // وتحرير السائق القديم يتكفّل به freeOldDriverOnReassign.
    }
    tx.update(orderRef, upd);
    return {rescheduled: true, reassigned: reassign};
  });
});

// ════════════════════════════════════════════════════════════════════════
// (الثغرة #1) تحرير السائق آلياً عند إلغاء الطلب — يمنع بقاء السائق "عالقاً"
// ════════════════════════════════════════════════════════════════════════
exports.freeDriverOnOrderCancel = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!before || !after) return;
      // فقط عند الانتقال الفعلي إلى cancelled
      if (before.status === "cancelled" || after.status !== "cancelled") return;

      const driverId = after.driver_id || before.driver_id;
      if (!driverId) return; // لم يكن الطلب مُسنَداً لأي سائق

      const db = getFirestore();
      const driverRef = db.collection("drivers").doc(driverId);

      await db.runTransaction(async (tx) => {
        const ds = await tx.get(driverRef);
        if (!ds.exists) return;
        // حرّر السائق فقط إن كان منشغلاً بهذا الطلب الملغى تحديداً،
        // حتى لا نلمس مهمة أخرى يكون قد بدأها بالفعل.
        if (ds.data().current_order_id !== event.params.orderId) return;
        tx.update(driverRef, {
          status: "available",
          current_order_id: null,
          is_available: true,
        });
      });

      // إشعار السائق بإلغاء مهمته — مصدر واحد خادميّ لكل الإلغاءات. كان تطبيق
      // العميل يُشعره عند إلغائه هو/الإدارة عبر cancelOrder، لكنّ الإلغاء المباشر
      // (قائمة حالة الأدمن، أو أي كتابة status='cancelled') يحرّر السائق هنا بلا
      // إشعار — فتختفي المهمة من لوحته فجأة. queuePush تكتب الوارد وتدفع.
      await queuePush(
          driverId,
          "أُلغيت مهمة 🚫",
          `أُلغيت المهمة #${after.code || event.params.orderId} وأُزيلت من قائمتك.`,
          "driver_task_removed",
          {orderId: event.params.orderId, code: after.code || event.params.orderId},
      );

      console.log(
          `freeDriverOnOrderCancel: freed+notified driver ${driverId} ` +
          `(order ${event.params.orderId} cancelled)`);
    },
);

/**
 * حِمْلُ فكِّ الإسنادِ عن سائقٍ معطَّل — **موضعٌ واحدٌ بمُنادِيَين**:
 * المُشغّلُ عند التعطيل، ومكنسةُ إعادةِ المحاولةِ في `opsHealthSweep`.
 * دالّةٌ لا ثابتٌ، لأنّ `serverTimestamp()` يُبنى لكلِّ كتابة. وكان مكتوباً
 * مرّتَين فأُوحِّد: نسخةٌ ثانيةٌ تَنحرِفُ — وانحرافُها هنا يَعني مهمّةً
 * تُستَردُّ بحقولٍ ناقصةٍ فتَبقى غيرَ قابلةٍ للإسناد.
 * @param {string} reason سببُ فكِّ الإسنادِ كما يُدوَّنُ على المستند.
 * @return {Record<string, unknown>} حِمْلُ التحديث.
 */
function _unassignPayload(reason) {
  return {
    driver_id: FieldValue.delete(),
    driver_name: FieldValue.delete(),
    assigned_driver: FieldValue.delete(),
    driver_phone: FieldValue.delete(),
    // pending المدفوع تلتقطه sweepUnassignedPaidOrders كل 5 دقائق.
    status: "pending",
    unassigned_reason: reason,
    unassign_pending: FieldValue.delete(),
    unassign_driver_id: FieldValue.delete(),
    updated_at: FieldValue.serverTimestamp(),
  };
}

// ════════════════════════════════════════════════════════════════════════
// تعطيل/إيقاف سائق كان يترك مهامه **المستقبلية** مسندةً له: لا أحد ينفّذها،
// ولا مكنسة تلتقطها (driver_id ممتلئ)، والعميل ينتظر سائقاً لن يأتي. نفكّ
// إسناد غير المبدوءة فور التعطيل فتعود «قيد الانتظار» وتلتقطها مكنسة الإسناد،
// وننبّه الإدارة بعددها. الجارية فعلاً (on_the_way/in_progress) تُترك عمداً —
// قرارها بشري: قد يُكملها السائق قبل مغادرته.
// ════════════════════════════════════════════════════════════════════════
exports.unassignJobsOnDriverDisable = onDocumentUpdated(
    {document: "drivers/{driverId}", cpu: 0.083},
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const wasUsable = before.is_active !== false && before.is_suspended !== true;
      const nowDisabled = after.is_active === false || after.is_suspended === true;
      if (!wasUsable || !nowDisabled) return null;

      const driverId = event.params.driverId;
      const db = getFirestore();
      const nowMs = Date.now();
      // نفس شكل فهرس لوحة السائق (driver_id + status in).
      const snap = await db.collection("orders")
          .where("driver_id", "==", driverId)
          .where("status", "in", ["scheduled", "assigned", "accepted"])
          .get();

      let n = 0;
      let failed = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        const sd = d.service_date && d.service_date.toDate ?
          d.service_date.toDate().getTime() : null;
        if (sd !== null && sd < nowMs) continue; // فات موعدها — شأن مكانس الإنقاذ
        // ⚠️ **كان `.catch` يَبتلعُ الفشلَ و`n++` يَجري على كلِّ حال
        //    (2026-10-05).** فمهمّةٌ فشلَ فكُّ إسنادِها تَبقى **مُسنَدةً
        //    لسائقٍ معطَّل**: لا سَحبَ، ولا محاولةً ثانيةً (المُشغّلُ بلا
        //    `retry`)، ولا علَمَ — و`sweepUnassignedPaidOrders` تَستعلمُ
        //    `status == "pending"` فلا تَراها (حالتُها بقيت `scheduled`
        //    أو `assigned`). والعدّادُ كان يَضمُّها، فالتنبيهُ يَقولُ
        //    «أُعيدت لقائمة الإسناد» عن مهمّةٍ لم تُعَد: **دعوى تُخالِفُ
        //    الحالةَ**، فيَطمئنُّ الأدمنُ ولا يُسنِدُ أحداً، والعميلةُ
        //    تَنتظرُ سائقاً لن يَأتي حتى يَستردَّ `autoResolveUnfulfilled`
        //    مالَها بعد فواتِ الموعد.
        //
        //    فالعدُّ على النجاحِ وحدَه، والفشلُ يَكتبُ **علَمَه** (لا
        //    الحالةَ: الحالةُ هنا `assigned` وهي الحالةُ السليمةُ لكلِّ
        //    مهمّةٍ قائمةٍ فتَغرقُ فيها) والمكنسةُ تَستعلمُ العلم.
        try {
          await doc.ref.update(_unassignPayload("driver_disabled"));
          n++;
        } catch (e) {
          console.error(`unassignJobsOnDriverDisable ${doc.id}:`, e.message);
          failed++;
          await doc.ref.update({
            unassign_pending: true,
            unassign_driver_id: driverId,
          }).catch(() => {});
        }
      }

      if (n > 0 || failed > 0) {
        const tail = failed > 0 ?
          ` و**${failed} تعذّر فكُّ إسنادِها** وما زالت معه — تُعاد المحاولة.` :
          " وستُوزَّع تلقائياً أو يدوياً.";
        await queuePush("ADMIN_BROADCAST", "فُكّ إسناد مهام سائق معطَّل ⚠️",
            `عُطّل السائق ${after.name || driverId}: ${n} مهمة أُعيدت ` +
            `لقائمة الإسناد${tail}`,
            "admin_order_alert", {driverId}).catch(() => {});
      }
      console.log(`unassignJobsOnDriverDisable: ${driverId} → ${n} unassigned`);
      return null;
    });

// ════════════════════════════════════════════════════════════════════════
// تحرير السائق **السابق** آلياً عند إعادة إسناد الطلب لسائق آخر. إعادة الإسناد
// تكتب driver_id الجديد فقط ولا تلمس مستند السائق القديم، فيبقى current_order_id
// لديه مشيراً لطلبٍ لم يعد له — وحارس _ensureAlwaysAvailable في لوحة السائق يرى
// current_order_id != null فيقفله «مشغولاً» للأبد (is_available لا يعود true).
// ════════════════════════════════════════════════════════════════════════
exports.freeOldDriverOnReassign = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!before || !after) return;
      const oldDriver = before.driver_id || null;
      const newDriver = after.driver_id || null;
      // فقط عند تغيّر السائق فعلاً وكان هناك سائق سابق مختلف (null→A إسنادٌ جديد لا يعنينا).
      if (!oldDriver || oldDriver === newDriver) return;

      const db = getFirestore();
      const driverRef = db.collection("drivers").doc(oldDriver);
      const freed = await db.runTransaction(async (tx) => {
        const ds = await tx.get(driverRef);
        if (!ds.exists) return false;
        // حرّره فقط إن كان لا يزال منشغلاً بهذا الطلب تحديداً (لا نلمس مهمة جديدة بدأها).
        if (ds.data().current_order_id !== event.params.orderId) return false;
        tx.update(driverRef, {
          status: "available",
          current_order_id: null,
          is_available: true,
        });
        return true;
      });
      if (!freed) return;

      // إشعار السائق القديم أن المهمة أُعيد إسنادها (اختفت من قائمته) — مصدر خادمي واحد.
      await queuePush(
          oldDriver,
          "أُعيد إسناد مهمة 🔄",
          `أُعيد إسناد المهمة #${after.code || event.params.orderId} إلى زميلٍ آخر وأُزيلت من قائمتك.`,
          "driver_task_removed",
          {orderId: event.params.orderId, code: after.code || event.params.orderId},
      ).catch(() => {});

      console.log(
          `freeOldDriverOnReassign: freed old driver ${oldDriver} ` +
          `(order ${event.params.orderId} reassigned to ${newDriver || "none"})`);
    },
);

// (أُزيلت _pushToUid: صارت بلا مستدعٍ بعد تحويل كل الإشعارات إلى queuePush التي
//  تكتب صندوق الوارد دائماً — _pushToUid كانت تتخطّى بصمت من لا توكن له.)

// ════════════════════════════════════════════════════════════════════════
// حارس ملكية رمز FCM — رمز الجهاز يخصّ حساباً واحداً فقط (آخر من سجّل به).
// عند كتابة fcm_tokens/{uid} نحذف نفس الرمز من أي وثيقة حساب آخر، فنمنع تسرّب
// إشعارات حساب قديم (سائق ثم عميل على نفس الجهاز) حين لا يُنظَّف الخروج.
// Admin SDK يتجاوز القواعد التي تمنع العميل من فعل ذلك بنفسه.
// ════════════════════════════════════════════════════════════════════════
exports.dedupeFcmToken = onDocumentWritten(
    {document: "fcm_tokens/{uid}", cpu: 0.083},
    async (event) => {
      const after = event.data?.after?.data();
      if (!after) return; // حذف — لا شيء نفعله (ويمنع الحلقة اللانهائية)
      const token = after.fcmToken || after.token;
      if (!token) return;
      const uid = event.params.uid;
      const db = getFirestore();
      const dupes = await db.collection("fcm_tokens")
          .where("fcmToken", "==", token).get();
      const batch = db.batch();
      let n = 0;
      dupes.forEach((doc) => {
        if (doc.id !== uid) {
          batch.delete(doc.ref);
          n++;
        }
      });
      if (n > 0) {
        await batch.commit();
        console.log(`dedupeFcmToken: removed ${n} stale token doc(s); ` +
          `device token now owned solely by ${uid}`);
      }
    },
);

// ════════════════════════════════════════════════════════════════════════
// (2c) تذكير السائق — Cron كل 15 دقيقة بالمهام التي تبدأ بعد ساعة تقريباً
// ════════════════════════════════════════════════════════════════════════
exports.remindDriversUpcomingTasks = onSchedule(
    {schedule: "every 15 minutes", timeZone: "Asia/Riyadh"},
    async () => {
      const db = getFirestore();
      const now = Date.now();
      const windowStart = new Date(now + 60 * 60 * 1000); // +1h
      const windowEnd = new Date(now + 75 * 60 * 1000); // +1h15m

      const snap = await db.collection("orders")
          .where("status", "==", "scheduled")
          .where("scheduled_at", ">=", Timestamp.fromDate(windowStart))
          .where("scheduled_at", "<", Timestamp.fromDate(windowEnd))
          .get();

      let sent = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.reminder_sent === true || !d.driver_id) continue;
        const code = d.code || doc.id;
        // queuePush لا _pushToUid: الأخير يتخطّى بصمت السائق بلا توكن FCM (ويب/جهاز
        // جديد/إذن مرفوض) فلا يصله شيء رغم reminder_sent=true. queuePush تكتب صندوق
        // الوارد داخل التطبيق **دائماً** (processNotificationTriggers) ثم تدفع إن توفّر توكن.
        await queuePush(
            d.driver_id,
            "تذكير: مهمتك بعد ساعة ⏰",
            `لديك مهمة (#${code}) تبدأ خلال ساعة تقريباً — استعد للانطلاق.`,
            "task_reminder",
            {orderId: doc.id, code: code},
        );
        await doc.ref.update({reminder_sent: true});
        sent++;
      }
      console.log(`remindDriversUpcomingTasks: sent ${sent} reminder(s)`);
    },
);

// ════════════════════════════════════════════════════════════════════════
// (2c) تذكير العميل بموعده المجدول — Cron كل 30 دقيقة.
// تذكيران: مبكّر (خلال 24 ساعة قبل الموعد) + قريب (خلال ~ساعتين). حقول علم
// منفصلة عن تذكير السائق (reminder_sent) لتجنّب التعارض. التوقيت يُعرض من
// booking_time_slot/booking_date المحليّين لتفادي انزياح المنطقة الزمنية.
// ════════════════════════════════════════════════════════════════════════
exports.remindClientsUpcomingAppointments = onSchedule(
    {schedule: "every 30 minutes", timeZone: "Asia/Riyadh"},
    async () => {
      const db = getFirestore();
      const now = Date.now();
      const in24h = new Date(now + 24 * 60 * 60 * 1000);
      // نطاق مفرد على service_date (مُفهرَس تلقائياً) — الحالة تُصفّى في الكود.
      const snap = await db.collection("orders")
          .where("service_date", ">=", Timestamp.fromDate(new Date(now)))
          .where("service_date", "<=", Timestamp.fromDate(in24h))
          .get();

      const ACTIVE = ["pending", "scheduled", "assigned", "accepted"];
      let sent = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        // موعد حقيقي يستحق التذكير: مدفوع مسبقاً أو مُسنَد لسائق. نستثني فقط
        // المعلّق غير المدفوع (محاولة دفع فاشلة/مهجورة).
        // (شرط cash_on_delivery أُزيل: الدفع عند الاستلام حُذف من الجذور.)
        const driverAssigned = d.status === "scheduled" ||
          d.status === "assigned" || d.status === "accepted";
        const realAppointment = d.is_paid === true || driverAssigned;
        if (!d.client_id || !d.service_date || !realAppointment) continue;
        if (!ACTIVE.includes(d.status)) continue;

        const apptMs = d.service_date.toMillis();
        const hoursUntil = (apptMs - now) / (60 * 60 * 1000);
        const serviceName = d.service_name || d.service_type || "خدمتك";
        const greet = _clientGreeting(d);
        const timeStr = d.booking_time_slot || riyadhLocalSlot(apptMs);

        // وسم اليوم (اليوم/غداً/بعد N أيام) بالتقويم المحلي.
        const apptDateStr = d.booking_date || riyadhLocalDate(apptMs);
        const dDiff = Math.round(
            (new Date(`${apptDateStr}T00:00:00Z`).getTime() -
             new Date(`${riyadhLocalDate(now)}T00:00:00Z`).getTime()) / 86400000);
        const dayLabel = dDiff <= 0 ? "اليوم" : dDiff === 1 ? "غداً" : `بعد ${dDiff} أيام`;

        // (باقات السكن) الساعة مُرساة آلياً ولم يخترها العميل — تذكير الغد لا
        // يعِد بساعةٍ قد تعدّلها الإدارة؛ تذكير الساعتين يذكرها (استقرّت عندئذٍ).
        const isHomePkg =
          d.service_meta && d.service_meta.kind === "home_package";

        if (hoursUntil > 2.5 && d.client_reminder_24h_sent !== true) {
          // queuePush: يكتب صندوق الوارد دائماً — كان _pushToUid يضبط علم الإرسال
          // ثم يتخطّى بصمت العميل بلا توكن، فيفقد التذكير للأبد ولا يُعاد.
          await queuePush(
              d.client_id,
              "موعد زيارتكِ اقترب 🏡",
              isHomePkg ?
                `${greet}زيارة «${serviceName}» ${dayLabel} ضمن ساعات عمل منطقتكِ — وتصلكِ رسالة بالوقت المحدد. بانتظاركِ 🌿` :
                `${greet}موعد «${serviceName}» ${dayLabel} الساعة ${timeStr}. بانتظاركِ 🌿`,
              "appointment_reminder",
              {orderId: doc.id},
          );
          await doc.ref.update({client_reminder_24h_sent: true});
          sent++;
        } else if (hoursUntil > 0 && hoursUntil <= 2.5 &&
                   d.client_reminder_soon_sent !== true) {
          // **«فريقنا في الطريق إليكِ» وعدٌ، ولا يُقالُ بلا فريق.** الاستعلامُ
          // يَشملُ `pending` و`realAppointment` يَكفيه `is_paid === true`، فطلبٌ
          // مدفوعٌ **بلا سائقٍ إطلاقاً** كان يَتلقّى هذه الجملةَ قبلَ موعدِه
          // بساعتَين — ثمّ لا يَأتي أحد. و`driverAssigned` أعلاه مبنيٌّ على
          // **الحالةِ** ويُجيبُ سؤالاً آخرَ («هل هذا موعدٌ حقيقي»)؛ سؤالُ
          // «هل يوجدُ فريق» يُجيبُه الحقلُ نفسُه.
          const hasCrew = !!d.driver_id;
          await queuePush(
              d.client_id,
              "اقترب موعد زيارتكِ ⏰",
              hasCrew ?
                `${greet}«${serviceName}» بعد ساعتين (الساعة ${timeStr}). فريقنا في الطريق إليكِ 🚗` :
                `${greet}«${serviceName}» بعد ساعتين (الساعة ${timeStr}). نُجهّز فريقكِ ونوافيكِ بتأكيد وصولِه 🌿`,
              "appointment_reminder",
              {orderId: doc.id},
          );
          await doc.ref.update({client_reminder_soon_sent: true});
          sent++;
        }
      }
      console.log(`remindClientsUpcomingAppointments: sent ${sent} reminder(s)`);
    },
);

// ════════════════════════════════════════════════════════════════════════
// احتياطي خادمي: إسناد الطلبات المدفوعة المعلّقة بلا سائق — Cron كل 15 دقيقة.
// التعيين الأساسي يتم في التطبيق كمهمة خلفية؛ لو أُغلق التطبيق بعد الدفع قد
// يبقى الطلب pending بلا سائق. هذا المسح يضمن إسناده خادمياً.
// ════════════════════════════════════════════════════════════════════════
exports.sweepUnassignedPaidOrders = onSchedule(
    {schedule: "every 5 minutes", timeZone: "Asia/Riyadh",
      secrets: ["MOYASAR_SECRET_KEY"]},
    async () => {
      const db = getFirestore();
      const now = Date.now();
      // −13س (أطول باقة 12س + هامش): كانت −1س فتتوقف إعادة المحاولة بعد ساعة من
      // موعد البدء رغم أن الزيارة الطويلة ما تزال قابلة للإنقاذ طوال نافذتها —
      // «منطقة ميتة» بلا محاولة ولا تنبيه حتى استرداد نهاية النافذة.
      const cutoff = Timestamp.fromDate(
          new Date(now - 13 * 60 * 60 * 1000));
      // (حذف الاعتمادات — قرار المالك) كان هنا استعلام ثانٍ على حالة
      // pending_admin_approval لزيارات الاشتراك؛ حُذفت الحالة من الجذور وكل
      // المنتجين يكتبون pending، فيغطيها هذا الاستعلام الواحد.
      const snapPending = await db.collection("orders")
          .where("status", "==", "pending")
          .where("service_date", ">=", cutoff).get();
      const docs = snapPending.docs;

      let assigned = 0;
      for (const doc of docs) {
        const d = doc.data();
        // فقط الطلبات المدفوعة، بلا سائق، وذات موعد.
        if (d.driver_id || d.is_paid !== true || !d.service_date) continue;
        const start = d.service_date.toDate();
        const hours = slots.orderHours(d);
        const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
        // انتهت نافذة الخدمة كلها → اتركه لمسار الاسترداد/التصعيد أدناه.
        if (end.getTime() <= now) continue;
        // فات موعد البدء ولم يُسنَد بعد → أنذر الإدارة مبكراً (مرة واحدة) مع
        // استمرار المحاولة — كان الصمت يمتد حتى نهاية النافذة + ساعتين.
        const latestart = start.getTime() < now - 60 * 60 * 1000;
        if (latestart && d.stranded_alerted !== true) {
          await queuePush(
              "ADMIN_BROADCAST",
              "طلب مدفوع تجاوز موعد بدئه بلا سائق ⚠️",
              `الطلب #${d.code || doc.id} مدفوع وفات موعد بدئه ولم يُسنَد — ` +
              `ما تزال نافذته قائمة والمحاولة مستمرة، وقد يلزم تدخّل يدوي.`,
              "admin_order_alert",
              {orderId: doc.id, code: d.code || doc.id}).catch(() => {});
          await doc.ref.update({stranded_alerted: true}).catch(() => {});
        }
        // **والعميلةُ تُخبَرُ أيضاً.** كان هذا المسارُ يُنبّهُ الإدارةَ وحدَها:
        // فعميلةٌ دَفعت، وتَلقّت قبلَ ساعتَين «موعد زيارتكِ… 🌿»، ثمّ فاتَ
        // موعدُها ولا فريق — ولا تَسمعُ شيئاً حتى نهايةِ النافذةِ
        // (باقةُ ١٢ ساعةً = ١٢ ساعةَ صمت) حين يَرِدُها إشعارُ الاسترداد.
        // الرسالةُ صادقةٌ بما نَعرفُه: نُحاولُ الآن، وإن تعذّر أُعيد المبلغُ
        // كاملاً تلقائيّاً — وهو ما يَفعلُه `autoResolveUnfulfilledPaidOrder`
        // فعلاً عند نهايةِ النافذة، فلا وعدَ بما لا يَحدث.
        //
        // **وعلمٌ خاصٌّ بها لا `stranded_alerted`**: علمٌ واحدٌ لجمهورَين
        // يَجعلُ أسبقَهما يُسكِتُ الآخرَ — وهو العطلُ المسجَّلُ حرفيّاً في
        // هذا المستودع (الإنذارُ المبكّرُ ضَبطَ `stranded_alerted` ساعاتٍ
        // قبلَه بمعنًى آخرَ فأسكتَ تنبيهَ الاستردادِ الفاشل).
        if (latestart && d.client_id && d.client_stranded_notified !== true) {
          await queuePush(
              d.client_id,
              "نعمل على تأكيد فريقكِ ⏳",
              `${_clientGreeting(d)}تأخّر إسنادُ فريقٍ لموعدكِ (#${d.code || doc.id}) ` +
              `ونحن نعمل عليه الآن. وإن تعذّر علينا تنفيذُه أعدنا المبلغ كاملاً ` +
              `تلقائيّاً. نأسف للانتظار 🌿`,
              "order_delayed",
              {orderId: doc.id, code: d.code || doc.id}).catch(() => {});
          await doc.ref.update({client_stranded_notified: true}).catch(() => {});
        }
        try {
          const driver = await _findFreeDriverForSlot(db, {
            startDateTime: start,
            endDateTime: end,
          });
          if (driver) {
            await _assignDriverScheduled(db, doc.id, driver, start);
            assigned++;
            console.log(`sweepUnassignedPaidOrders: assigned ${doc.id} -> ${driver.id}`);
          }
        } catch (e) {
          console.error(`sweepUnassignedPaidOrders: ${doc.id} failed:`, e.message);
        }
      }
      console.log(`sweepUnassignedPaidOrders: assigned ${assigned} order(s)`);

      // (تصعيد الطلب العالق) طلبٌ مدفوع بلا سائق فات موعده بأكثر من ساعة يخرج من
      // نافذة إعادة المحاولة أعلاه فلا يُسنَد ولا يُرى خادميّاً أبداً — مالٌ مقبوض
      // بلا خدمة. ننبّه الإدارة مرّة واحدة (علم stranded_alerted) لتتدخّل يدويّاً.
      const strandFloor = Timestamp.fromDate(
          new Date(now - 24 * 60 * 60 * 1000));
      const strandCeil = Timestamp.fromDate(
          new Date(now - 60 * 60 * 1000));
      const strandSnap = await db.collection("orders")
          .where("status", "==", "pending")
          .where("service_date", ">=", strandFloor)
          .where("service_date", "<", strandCeil).get();
      // (#18) استرداد آليّ للطلب المدفوع الذي **انتهى** موعده بمهلة ولم يُسنَد قط —
      // مالٌ مقبوض بلا خدمة. نبوّابه على **نهاية** الموعد (لا بدايته) + مهلة ساعتين كي
      // لا نصادر مالَ حجزٍ طويل/متأخّر ما زال قابلاً للخدمة أو في طابور إسناد إداري.
      const secret = moyasarSecretKey.value();
      const GRACE_MS = 2 * 60 * 60 * 1000;
      let alerted = 0; let autoResolved = 0;
      for (const doc of strandSnap.docs) {
        const d = doc.data();
        if (d.driver_id || d.is_paid !== true) continue;
        if (!d.service_date || typeof d.service_date.toDate !== "function") continue;
        const startMs = d.service_date.toDate().getTime();
        const endMs = startMs + slots.orderHours(d) * 60 * 60 * 1000;
        if (endMs >= now - GRACE_MS) continue; // لم ينتهِ الموعد + المهلة بعد
        const method = d.payment_method || "";
        const autoRefundable = secret &&
          !["subscription", "tamara", "tabby"].includes(method);
        if (autoRefundable) {
          const r = await refunds.autoResolveUnfulfilledPaidOrder(
              db, secret, doc, {queuePush});
          if (r.handled) { autoResolved++; continue; }
          // خطأ/تعذّر بعد بدء المعالجة → **المحرّك نفسه يُصعّد** للإدارة
          // (escalateFailedAutoRefund بعلَم auto_refund_alerted المستقلّ)، فلا
          // نُكرّر التنبيه هنا. قبل ذلك كان يرفع stranded_alerted بلا إرسال، وكان
          // فرعُ الإنذار المبكّر أعلاه قد رفعه سلفاً — فيُدفَن الطلب صامتاً.
          if (["gateway_error", "wallet_error", "no_amount", "no_payment_id"]
              .includes(r.reason)) continue;
        }
        // اشتراك/BNPL/مفتاح مفقود → تنبيه إداري مرّة واحدة فقط.
        if (d.stranded_alerted === true) continue;
        await queuePush(
            "ADMIN_BROADCAST",
            "طلب مدفوع بلا سائق ⚠️",
            `الطلب #${d.code || doc.id} مدفوع وفات موعده بلا إسناد سائق — يلزم تدخّل يدوي.`,
            "admin_order_alert",
            {orderId: doc.id, code: d.code || doc.id});
        await doc.ref.update({stranded_alerted: true});
        alerted++;
      }
      if (autoResolved) console.warn(`sweepUnassignedPaidOrders: auto-resolved ${autoResolved} unfulfillable paid order(s)`);
      if (alerted) console.warn(`sweepUnassignedPaidOrders: ${alerted} stranded paid order(s) escalated to admin`);
    },
);

// ════════════════════════════════════════════════════════════════════════
// فحص الصحة التشغيلية (كل 6 ساعات): يرصد الشذوذ الذي لا تغطيه المسارات الفورية —
// حالات لا يراها أحد إلا مصادفةً في اللوحة. كل فئة تُنبَّه مرة واحدة لكل مستند
// (علم ops_alerted_*) بدفعة إشعار إداري واحدة تلخّص الفئة، لا إشعاراً لكل مستند.
// الاستعلامات كلها على فهارس قائمة: (status+service_date) نفسها التي يستخدمها
// sweepUnassignedPaidOrders، والبقية مساواة/مدى بحقل واحد (فهرسة تلقائية).
// ════════════════════════════════════════════════════════════════════════
exports.opsHealthSweep = onSchedule(
    {schedule: "every 6 hours", timeZone: "Asia/Riyadh"},
    async () => {
      const db = getFirestore();
      const now = Date.now();
      const codeOf = (doc, d) => `#${d.code || doc.id}`;

      // إشعار إداري واحد يلخّص الفئة (حتى 5 أكواد + العدد الكلي) ثم وسم كل
      // مستند كي لا يتكرر التنبيه في الدورات القادمة. الوسم **بعد** نجاح الإشعار
      // فقط — فشل الإرسال يترك الفئة كاملة لدورة قادمة بدل إخراسها للأبد.
      // `audience` اختياريٌّ: فئاتُ السعرِ تَخصُّ المحاسبةَ أيضاً، ودفعاتُها
      // الفوريّةُ تُرسَلُ إلى `accountant_admin` — فكانت المكنسةُ وحدَها
      // تُخرِجُه من الجمهورِ لنفسِ الواقعة.
      const alertBatch = async (docs, flag, title, bodyOf,
          audience = ["super_admin", "orders_manager"]) => {
        const fresh = docs.filter(({d}) => d[flag] !== true);
        if (!fresh.length) return 0;
        const codes = fresh.slice(0, 5).map(({doc, d}) => codeOf(doc, d)).join("، ");
        const more = fresh.length > 5 ? ` و${fresh.length - 5} غيرها` : "";
        await queuePush("ADMIN_BROADCAST", title, bodyOf(codes + more, fresh.length),
            "admin_order_alert", {count: fresh.length}, audience);
        for (const {doc} of fresh) {
          await doc.ref.update({[flag]: true}).catch(() => {});
        }
        return fresh.length;
      };
      const endMsOf = (d) => d.service_date.toDate().getTime() +
        slots.orderHours(d) * 60 * 60 * 1000;

      // 1) مستند موسوم awaiting_payment لكنه مدفوع فعلاً — حالة متناقضة: مال مقبوض
      //    بلا مسار تشغيل. الحالة تعيش أساساً في store_orders (متجر الشركات المباشر —
      //    محوّل الترقية التلقائي قد يفشل بلا بديل)، وتُفحص orders أيضاً لأن القواعد
      //    تسمح بإنشائها عميلياً (مستندات قديمة/عدائية).
      //
      //    **النافذةُ تَسألُ عن الحالةِ المتناقضةِ نفسِها.** كانت مساواةً واحدةً
      //    على الحالةِ بـ`limit(500)` ثم يُرشَّحُ `is_paid` في الكود، وتعليقُها
      //    يَقول «تشبّعُه يَتطلّبُ مئاتِ المستنداتِ العالقةِ معاً» — وهي موجودةٌ
      //    بالفعل: `store_orders` يُنشَأُ **قبلَ** الدفعِ بـ`awaiting_payment`
      //    (قرارُ المالك: لا موافقةَ قبل الدفع)، وسلّةٌ متروكةٌ تَبقى كذلك
      //    للأبدِ — `cancelStaleUnpaidOrders` يَمسحُ `orders` بحالةِ `pending`
      //    وحدَها، والعميلةُ تَستأنفُ الدفعَ من بطاقةِ الطلبِ عندها فالبقاءُ
      //    مقصود. واستعلامٌ بمساواةٍ واحدةٍ يُرتَّبُ بـ`__name__` ومعرّفاتُ
      //    `store_orders` عشوائيّة: فطلبٌ **مدفوعٌ** عالقٌ — «مالٌ مقبوضٌ بلا
      //    مسارِ تشغيل»، وهو كلُّ موضوعِ هذا الفحص — يَسقطُ من النافذةِ
      //    بالاحتمالِ وحدَه. مساواتانِ بلا مدًى لا تَلزمُهما فهرسٌ مركَّب
      //    (دمجُ zigzag — كاستعلامِ `referrals` الحيِّ هنا بلا فهرس).
      for (const coll of ["store_orders", "orders"]) {
        try {
          const snap = await db.collection(coll)
              .where("status", "==", "awaiting_payment")
              .where("is_paid", "==", true).limit(500).get();
          const paid = snap.docs.map((doc) => ({doc, d: doc.data()}));
          const n = await alertBatch(paid, "ops_alerted_paid_awaiting",
              "طلب مدفوع عالق في «بانتظار الدفع» ⚠️",
              (codes, c) => `${c} طلب مدفوع وحالته ما تزال awaiting_payment (${codes}) — ` +
                "مال مقبوض بلا مسار تشغيل، يلزم تصحيح الحالة يدوياً.");
          // والمهجورةُ تُعَدُّ خادميّاً: `count()` بمساواةٍ واحدةٍ (لا فهرس،
          // ولا قراءةُ خمسِ مئةِ مستند) يُعطي الإجماليَّ الدقيقَ بدلَ رقمٍ
          // مقصوصٍ بنافذةٍ صارت لا تَرى غيرَ المدفوع. سجلٌّ فقط — تراكمُها
          // مقصودٌ ما دامت قابلةً للاستئناف.
          const openAgg = await db.collection(coll)
              .where("status", "==", "awaiting_payment").count().get();
          console.log(`opsHealthSweep[${coll}]: paid-awaiting alerted=${n}, ` +
            `awaiting_payment total=${openAgg.data().count}`);
        } catch (e) {
          console.error(`opsHealthSweep: awaiting_payment check failed (${coll}):`, e.message);
        }
      }

      // 2) غياب سائق (no-show): طلب مجدول/مسند انتهت نافذته كاملة + 3 ساعات وما
      //    بدأ ولا اكتمل — العميلة انتظرت ولم يصل أحد ولا أحد يعلم.
      // 3) عالق قيد التنفيذ: بدأ ولم يُكمَل حتى بعد نهاية النافذة + 12 ساعة —
      //    السائق نسي الإكمال فتتعطل إحصاءات اليوم وسعة الغد.
      try {
        const floor = Timestamp.fromDate(
            new Date(now - 72 * 60 * 60 * 1000));
        const ceil = Timestamp.fromDate(new Date(now));
        const perStatus = await Promise.all(
            ["scheduled", "assigned", "accepted", "on_the_way", "in_progress"]
                .map((s) => db.collection("orders")
                    .where("status", "==", s)
                    .where("service_date", ">=", floor)
                    .where("service_date", "<", ceil).get()));
        const all = perStatus.flatMap((snap) => snap.docs)
            .map((doc) => ({doc, d: doc.data()}))
            .filter(({d}) => d.service_date &&
              typeof d.service_date.toDate === "function");
        const noShow = all.filter(({d}) => d.status !== "in_progress" &&
          endMsOf(d) + 3 * 60 * 60 * 1000 < now);
        const stuck = all.filter(({d}) => d.status === "in_progress" &&
          endMsOf(d) + 12 * 60 * 60 * 1000 < now);
        const n1 = await alertBatch(noShow, "ops_alerted_noshow",
            "زيارة فات موعدها ولم تبدأ ⚠️",
            (codes, c) => `${c} زيارة انتهت نافذتها منذ 3+ ساعات دون بدء (${codes}) — ` +
              "تحقق من السائق وتواصل مع العميلة.");
        const n2 = await alertBatch(stuck, "ops_alerted_stuck",
            "زيارة عالقة «قيد التنفيذ» ⚠️",
            (codes, c) => `${c} زيارة تجاوزت نهايتها بـ12+ ساعة وما زالت قيد التنفيذ (${codes}) — ` +
              "غالباً نسي السائق الإكمال؛ أكملها يدوياً لتصحيح الإحصاءات والسعة.");
        console.log(`opsHealthSweep: no-show alerted=${n1}, stuck alerted=${n2}`);
      } catch (e) {
        console.error("opsHealthSweep: schedule checks failed:", e.message);
      }

      // 4) محافظ سالبة: كل الكتابة خادمية، فالسالب إما خلل منطق أو استرداد تجاوز
      //    الرصيد — يهم المحاسبة فوراً.
      //
      //    **عطلانِ في خمسةِ أسطر، كلاهما من عائلةٍ أُغلقت ثلاثَ مرّاتٍ هنا.**
      //    (أ) النافذةُ كانت `where("balance","<",0).limit(200)` ثم يُرشَّحُ
      //    `ops_negative_alerted` **في الكودِ بعدَ القصّ** — ولا شيءَ في
      //    المستودعِ يَمحو العلمَ ولا يُصلِّحُ رصيداً سالباً، فالموسومُ يَبقى
      //    في النافذةِ أبداً. ومدًى (`< 0`) يُرتَّبُ ضمناً بذلك الحقلِ
      //    **تصاعديّاً**، فالمئتانِ الأكثرُ سَلباً تَسُدُّ النافذةَ ومحفظةٌ
      //    جديدةٌ بسالبٍ صغيرٍ **لا تُقرأُ أصلاً**: لا احتمالاً بل بنيةً.
      //    والشكلُ الصحيحُ على بُعدِ أربعينَ سطراً — الكتلتانِ (٥) و(٦)
      //    تَستعلمانِ العلمَ لا الحالة.
      //    (ب) والعلمُ لا يُمحى عند التعافي: محفظةٌ عادَت موجَبةً ثم سَلبت
      //    مرّةً أخرى **لا يُنبَّهُ عنها إطلاقاً**، لأنّ العلمَ يَعني
      //    «أخبرناكَ مرّةً، يوماً ما» لا «أخبرناكَ عن هذه الحادثة». وهذا هو
      //    الفرعُ القريبُ الوقوع: استردادٌ زائدٌ يُصحِّحُه المحاسبُ، ثم آخرُ
      //    لاحقاً بلا كلمة.
      //
      //    والعلاجُ أن تُقرأَ المجموعتانِ كاملتَينِ لا مقصوصتَين: السالبُ
      //    الآن (ن) والموسومُ سابقاً (و). يُنبَّهُ عن ن\و ويُمحى العلمُ عن
      //    و\ن. وكلتاهما جمهورُ **خللٍ** لا جمهورُ استعمال — صفرٌ في الحالةِ
      //    السليمة — فقراءتُهما كاملةً آمنة، ويَحرُسُها عَدٌّ خادميٌّ أوّلاً
      //    (`count()` بمدًى واحدٍ أو بمساواةٍ واحدةٍ ⇒ لا فهرسَ مركَّب)،
      //    فانفجارُ العددِ نفسُه هو الخبرُ ولا يُعدَّدُ مستنداً مستنداً.
      try {
        const negQ = db.collection("wallets").where("balance", "<", 0);
        const flagQ = db.collection("wallets")
            .where("ops_negative_alerted", "==", true);
        const [negCount, flagCount] = await Promise.all([
          negQ.count().get().then((a) => a.data().count),
          flagQ.count().get().then((a) => a.data().count),
        ]);
        if (negCount > NEG_WALLET_SCAN_MAX || flagCount > NEG_WALLET_SCAN_MAX) {
          await queuePush("ADMIN_BROADCAST", "محافظ برصيد سالب ⚠️",
              `${negCount} محفظة رصيدها سالب — عددٌ يتجاوز حدَّ المسح ` +
              `(${NEG_WALLET_SCAN_MAX})، وهو بذاته خللٌ منهجيٌّ لا حالاتٌ ` +
              "فرديّة. كل الكتابة خادمية؛ راجع سجل المعاملات فوراً.",
              "admin_order_alert", {count: negCount},
              ["super_admin", "accountant_admin"]);
          console.error("opsHealthSweep: negative wallets above scan cap: " +
            `negative=${negCount}, flagged=${flagCount}`);
        } else {
          const [negSnap, flagSnap] = await Promise.all([negQ.get(), flagQ.get()]);
          const negs = negSnap.docs.map((doc) => ({doc, d: doc.data()}));
          const fresh = negs.filter(({d}) => d.ops_negative_alerted !== true);
          if (fresh.length) {
            const sample = fresh.slice(0, 5)
                .map(({doc, d}) => `${doc.id.slice(0, 6)}…: ${Number(d.balance).toFixed(2)}`)
                .join("، ");
            // الوسم بعد نجاح الإشعار فقط — فشله يعيد المحاولة الدورة القادمة.
            await queuePush("ADMIN_BROADCAST", "محافظ برصيد سالب ⚠️",
                `${fresh.length} محفظة رصيدها سالب (${sample}` +
                `${fresh.length > 5 ? ` و${fresh.length - 5} غيرها` : ""}) — ` +
                "كل الكتابة خادمية؛ راجع سجل المعاملات فقد يكون خللاً أو استرداداً زائداً.",
                "admin_order_alert", {count: fresh.length},
                ["super_admin", "accountant_admin"]);
            for (const {doc} of fresh) {
              await doc.ref.update({ops_negative_alerted: true}).catch(() => {});
            }
          }
          // تَصريفُ العلم: ما عادَ رصيدُه ≥ 0 يُمحى وسمُه (و\ن). بلا هذا يَعني
          // العلمُ «مرّةً يوماً ما» فتُبتلَعُ الحادثةُ الثانية. وغيرُ الرقميِّ
          // لا يُمحى: `NaN >= 0` كاذب، وهو التصرّفُ المحافظ.
          let cleared = 0;
          for (const doc of flagSnap.docs) {
            if (Number(doc.data().balance ?? 0) >= 0) {
              await doc.ref.update({
                ops_negative_alerted: FieldValue.delete(),
              }).catch(() => {});
              cleared += 1;
            }
          }
          console.log("opsHealthSweep: negative wallets total=" +
            `${negs.length}, newly alerted=${fresh.length}, ` +
            `flags cleared=${cleared}`);
        }
      } catch (e) {
        console.error("opsHealthSweep: wallet check failed:", e.message);
      }

      // 5) وسومُ مراجعةِ السعرِ التي لم يُنبَّه عنها — **والنافذةُ تُصرَّفُ
      //    الآن.** كان الاستعلامُ `where("price_mismatch","==",true).limit(200)`
      //    على `orders` وحدَها، ولا شيءَ في المستودعِ يَمحو العلم: فكلُّ طلبٍ
      //    وُسِمَ يَبقى في مجموعةِ الاستعلامِ للأبد، وهو عطلُ «نافذةٌ تَمتلئُ
      //    بما لا يُزيلُه أحد» ثالثةً في هذه الجلسة. والسببُ الجذريُّ أنّ
      //    **الوسمَ لم يكن له قارئٌ في أيِّ واجهة** (صفرُ ورودٍ في `lib/`
      //    و`admin_panel/src/`)، فلا سبيلَ إلى اعتمادِه أصلاً. شاشةُ الطلبِ
      //    تَعرضُه الآن وتَكتبُ `price_mismatch: false` عند الاعتماد.
      //
      //    والاستعلامُ مساواتانِ: الوسمُ و«لم يُنبَّه بعد» — فنافذتُه لا
      //    تَحوي إلّا ما يَلزمُه تنبيه، ومساواتانِ بلا مدًى لا تَلزمُهما
      //    فهرسٌ مركَّب (دمجُ zigzag — سابقةُ `referrals` الحيّة).
      //    وكلُّ كاتبٍ يَكتبُ العلمَ صراحةً (`false` عند عدمِ الإرسال) لأنّ
      //    الحقلَ الغائبَ لا يُطابقُ `== false`.
      //
      //    والمجموعتانِ معاً: `store_orders` يُوسَمُ بنفسِ الحقولِ من
      //    `_verifyStoreOrderPrice`، و`try` لكلِّ مجموعةٍ على حِدة — كحلقةِ
      //    إعادةِ الطابورَين، لأنّ سقوطَ الأولى كان يَقطعُ الثانية.
      for (const coll of ["orders", "store_orders"]) {
        try {
          const mSnap = await db.collection(coll)
              .where("price_mismatch", "==", true)
              .where("ops_alerted_mismatch", "==", false).limit(200).get();
          const n = await alertBatch(
              mSnap.docs.map((doc) => ({doc, d: doc.data()})),
              "ops_alerted_mismatch",
              "طلبات بمبلغ لا يطابق التسعيرة ⚠️",
              (codes, c) => `${c} طلب دُفع بمبلغ أدنى من المتوقع ووُسم price_mismatch (${codes}) — ` +
                "راجع المبالغ واسترد الفارق أو اعتمده من شاشة الطلب.",
              ["super_admin", "orders_manager", "accountant_admin"]);
          // و«تعذّر التحقّق» فئةٌ ثانيةٌ لم تكن لها مكنسةٌ إطلاقاً: ثلاثةُ
          // مواضعَ تَسِمُها ودفعةٌ واحدةٌ مُبتلَعةٌ هي كلُّ ما هناك.
          const uSnap = await db.collection(coll)
              .where("price_unverifiable", "==", true)
              .where("ops_alerted_unverifiable", "==", false).limit(200).get();
          const u = await alertBatch(
              uSnap.docs.map((doc) => ({doc, d: doc.data()})),
              "ops_alerted_unverifiable",
              "طلبات تعذّر التحقّق من سعرها ⚠️",
              (codes, c) => `${c} طلب من نوعٍ قابل للتسعير تعذّر التحقّق من مبلغه (${codes}) — ` +
                "راجعه واعتمده من شاشة الطلب.",
              ["super_admin", "orders_manager", "accountant_admin"]);
          console.log(`opsHealthSweep[${coll}]: price_mismatch alerted=${n}, ` +
            `price_unverifiable alerted=${u}`);
        } catch (e) {
          console.error(`opsHealthSweep: price review check failed (${coll}):`, e.message);
        }
      }

      // 5-bis) إلغاءٌ مدفوعٌ لم يُردّ إلى المحفظة — **إعادةُ المحاولةِ لا
      //    التنبيهُ وحدَه.** `onOrderRewards` يُودِع داخلَ معامَلةٍ، وفشلُها
      //    كان سطرَ `console.error` وحدَه: لا محفظةً أُودِعت، ولا دفعةً
      //    للعميلة، ولا تنبيهاً للإدارة، ولا محاولةً ثانية — لأنّ
      //    `onDocumentUpdated` بلا `retry` ولا يَعودُ لمستندٍ فاته الحدث.
      //    فمالُ العميلةِ يَبقى عندنا بلا أثر. وهو نفسُ البُرجِ الصامتِ الذي
      //    أُغلق في `autoResolveUnfulfilledPaidOrder`، من مسارٍ آخر.
      //
      //    والإيداعُ عديمُ الأثرِ التكراريِّ بالبناء (`refund_credited` +
      //    `t.create` على معرّفٍ حتميٍّ `refund_{orderId}`) فإعادتُه آمنة.
      //    مساواتانِ بلا مدًى ⇒ لا فهرسَ مركَّب (سابقةُ `referrals`).
      try {
        // المساواةُ الثالثةُ ليست زينةً: `needs_refund` **يَكتبُه العميلُ**
        // على طلبِه عند الإلغاء (`firestore.rules`: فرعُ الإلغاءِ يُجيزُه في
        // `hasOnly`)، والتطبيقُ الشريفُ يَكتبُ `is_paid == true` — لكنّ
        // كتابةً مباشرةً من الـSDK تَضَعُ `true` على طلبٍ **غيرِ مدفوع**،
        // فيَشغلُ خانةً من الـ200 بلا حقّ. وثلاثُ مساواتٍ بلا مدًى لا
        // تَلزمُها فهرسٌ مركَّب (دمجُ zigzag — سابقةُ `referrals` الحيّة).
        const snap = await db.collection("orders")
            .where("status", "==", "cancelled")
            .where("needs_refund", "==", true)
            .where("is_paid", "==", true).limit(200).get();
        let retried = 0; let stuck = 0; let released = 0; let unknown = 0;
        // **مُرشِّحاتُ الطريقِ السريعِ كانت تَتخطّى بـ`continue` وتُبقي العلمَ،
        // فيَبقى المستندُ في النافذةِ إلى الأبد — وهو العطلُ الذي أُغلق في
        // المحرّكِ نفسِه ثمّ أُعيد من هنا.** وأخطرُها `payment_method ===
        // "subscription"`: زيارةُ باقةٍ تُولَّدُ `is_paid: true` و`amount: 0`،
        // وإلغاءُ العميلةِ لها (الزرُّ يَظهرُ على `pending`) يَكتبُ
        // `needs_refund = is_paid` أي **`true`** — و`onOrderRewards` يَستثني
        // الاشتراكَ فلا يُودِعُ شيئاً، ولا شيءَ يَمسحُ العلم. فكلُّ زيارةِ
        // باقةٍ مُلغاةٍ تَشغلُ خانةً من الـ200 دائماً، وعدّادُها عددُ
        // الإلغاءاتِ في عمرِ التطبيقِ كلِّه: فحين تَتجاوزُ المئتَين يَسقطُ
        // استردادٌ **فاشلٌ حقيقيٌّ** من النافذةِ بترتيبِ `__name__` العشوائيِّ
        // بلا خطأٍ ولا سطرِ سجلّ.
        //
        // فما لا دَينَ فيه يُطفأُ علمُه (`needs_refund: false`) بدلَ تخطّيه:
        // لا مالٌ مستحقٌّ ⇒ العلمُ خاطئ. والثلاثةُ الأولى تُسوِّيها المحرّكةُ
        // نفسُها إن بَلغتها، لكنّ المُرشِّحَ يَسبقُها فلا تَبلغُها أبداً.
        const release = async (ref) => {
          await ref.update({needs_refund: false}).catch(() => {});
          released++;
        };
        for (const doc of snap.docs) {
          const d = doc.data();
          const amt = Number(d.amount || 0);
          if (d.refund_credited === true ||
              d.payment_status === "refunded" ||
              d.auto_refund_processed === true ||
              d.payment_method === "subscription" ||
              !(amt > 0)) {
            await release(doc.ref);
            continue;
          }
          // لا مالكَ ⇒ لا نَعرفُ لمن نُودِع، والعلمُ يَبقى بحقّ. والقواعدُ
          // تَشترطُ `client_id` عند الإنشاءِ فهو غيرُ قابلِ الوصولِ عملياً —
          // يُعَدُّ كي لا يَصيرَ تراكماً صامتاً إن صارَ قابلاً.
          if (!d.client_id) { unknown++; continue; }
          const r = await refunds.creditCancelledRefund(db, {
            orderRef: doc.ref,
            orderId: doc.id,
            clientId: d.client_id,
            amount: amt,
            code: d.code || doc.id,
            alreadyAlerted: d.refund_credit_alerted === true,
          }, queuePush);
          if (r.credited) retried++;
          else if (r.failed) stuck++;
        }
        console.log(`opsHealthSweep: cancelled-refund retried=${retried} ` +
            `stuck=${stuck} released=${released} unknown=${unknown}`);
      } catch (e) {
        console.error("opsHealthSweep: cancelled-refund retry failed:", e.message);
      }

      // 5-ter) مكافآتٌ فشل منحُها: نقاطُ قطرات وعدُّ الكوبون — **إعادةُ
      //    المحاولة.** كلٌّ كان `catch`ه سطرَ سجلٍّ وحدَه في مُشغّلٍ بلا
      //    `retry`، فالعميلةُ تَخسرُ نقاطَها وكوبونُ المرّةِ الواحدةِ يَبقى
      //    قابلاً للإنفاق، بلا تنبيهٍ ولا محاولةٍ ثانية.
      //
      //    **والاستعلامُ على علمِ الفشلِ لا على الحالة**: مجموعتُه لا تَحوي
      //    إلّا ما فشل، فلا تَزدحمُ نافذتُها بما نُجِح — وهو العطلُ الذي
      //    وُجد مرّتَين هذه الجلسة (نافذةُ البثِّ المجدول، ونافذةُ «مدفوعٌ
      //    وعالق»). مساواةٌ واحدة ⇒ لا فهرسَ مركَّب، والنجاحُ يَمحو العلم.
      try {
        const qSnap = await db.collection("orders")
            .where(rewards.PENDING_FLAGS.qatrat, "==", true).limit(200).get();
        let fixed = 0; let stuck = 0;
        for (const doc of qSnap.docs) {
          const d = doc.data();
          const amt = Number(d.amount || 0);
          if (!d.client_id || !(amt > 0)) continue;
          const r = await rewards.grantQatratPoints(db, {
            orderRef: doc.ref,
            orderId: doc.id,
            clientId: d.client_id,
            points: Math.round(amt),
            code: d.code || doc.id,
            alreadyAlerted: d.qatrat_alerted === true,
          }, queuePush);
          if (r.granted) fixed++;
          else if (r.failed) stuck++;
        }
        console.log(`opsHealthSweep: qatrat retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: qatrat retry failed:", e.message);
      }

      try {
        const cSnap = await db.collection("orders")
            .where(rewards.PENDING_FLAGS.couponCount, "==", true)
            .limit(200).get();
        let fixed = 0; let stuck = 0;
        for (const doc of cSnap.docs) {
          const d = doc.data();
          const cc = typeof d.coupon_code === "string" ? d.coupon_code.trim() : "";
          if (!cc) continue;
          const pq = await db.collection("promo_codes")
              .where("code", "==", cc.toUpperCase()).limit(1).get();
          if (pq.empty) continue;
          const r = await rewards.countCouponUse(db, {
            orderRef: doc.ref,
            orderId: doc.id,
            promoRef: pq.docs[0].ref,
            code: cc,
            alreadyAlerted: d.coupon_count_alerted === true,
          }, queuePush);
          if (r.counted) fixed++;
          else if (r.failed) stuck++;
        }
        console.log(`opsHealthSweep: coupon-count retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: coupon-count retry failed:", e.message);
      }

      // رصيدُ زياراتِ الاشتراكِ الذي تعذّرت تسويتُه. الاستعلامُ على **العلمِ**
      // لا على الحالة: مجموعةُ `completed` تَمتلئُ بما نُجِح فيَسقطُ الفاشلُ من
      // النافذة (نافذةُ البثِّ المجدول، ونافذةُ «مدفوعٌ وعالق»)، ومجموعةُ
      // العلمِ لا تَحوي إلّا الفشل. ومساواةٌ واحدةٌ ⇒ لا فهرسَ مركَّب.
      try {
        const vSnap = await db.collection("orders")
            .where(rewards.PENDING_FLAGS.visitAccounting, "==", true)
            .limit(200).get();
        let fixed = 0; let stuck = 0;
        for (const doc of vSnap.docs) {
          const d = doc.data();
          if (!d.client_id) continue;
          const r = await rewards.settleVisitAccounting(db, {
            orderRef: doc.ref,
            orderId: doc.id,
            clientId: d.client_id,
            // الاتّجاهُ من الحالةِ **الراهنة** لا من حالةِ لحظةِ الفشل.
            status: d.status,
            code: d.code || doc.id,
            alreadyAlerted: d.visit_accounting_alerted === true,
          }, queuePush);
          if (r.settled) fixed++;
          else if (r.failed) stuck++;
        }
        console.log(
            `opsHealthSweep: visit-accounting retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: visit-accounting retry failed:",
            e.message);
      }

      // ومكافأةُ الإحالةِ التي تعذّر صرفُها: ٥٠ ر.س للمُحيلِ وكوبونُ المُحالة.
      // الاستعلامُ على **العلمِ** لا على `referrals.status == "pending"` —
      // تلك المجموعةُ هي الحالةُ الطبيعيّةُ (مُحالةٌ لم تُتمَّ أوّلَ طلبٍ
      // بعد) فيَغرقُ فيها الفاشل.
      try {
        const rSnap = await db.collection("orders")
            .where(rewards.PENDING_FLAGS.referralPayout, "==", true)
            .limit(200).get();
        let fixed = 0; let stuck = 0;
        for (const doc of rSnap.docs) {
          const d = doc.data();
          if (!d.client_id) continue;
          const r = await rewards.payReferralBonus(db, {
            refereeUid: d.client_id,
            orderId: doc.id,
            orderRef: doc.ref,
            code: d.code || doc.id,
            alreadyAlerted: d.referral_payout_alerted === true,
          }, queuePush);
          if (r.paid) fixed++;
          else if (r.failed) stuck++;
        }
        console.log(`opsHealthSweep: referral retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: referral retry failed:", e.message);
      }

      // وتقييمٌ لم يَدخُلْ متوسّطَ السائق. الاستعلامُ على **العلمِ** لا على
      // وجودِ `rating` — ذلك حالةٌ طبيعيّةٌ لكلِّ طلبٍ مُقيَّم.
      try {
        const gSnap = await db.collection("orders")
            .where(rewards.PENDING_FLAGS.ratingAggregation, "==", true)
            .limit(200).get();
        let fixed = 0; let stuck = 0;
        for (const doc of gSnap.docs) {
          const d = doc.data();
          if (!d.driver_id) continue;
          const r = await rewards.aggregateRating(db, {
            orderRef: doc.ref,
            orderId: doc.id,
            driverId: d.driver_id,
            rating: d.rating,
            code: d.code || doc.id,
            alreadyAlerted: d.rating_agg_alerted === true,
          }, queuePush);
          if (r.aggregated) fixed++;
          else if (r.failed) stuck++;
        }
        console.log(`opsHealthSweep: rating-agg retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: rating-agg retry failed:", e.message);
      }

      // 5-quater) **عقدٌ مدفوعٌ لم يُفعَّل، وزياراتُ عقدٍ لم تُولَّد
      //    (2026-10-05).** `opsHealthSweep` كان يَمسحُ `orders` و`store_orders`
      //    و`wallets` و`promo_codes` — و**لا يَمسُّ `contracts` إطلاقاً**،
      //    بينما باقةُ الاشتراكِ أغلى مبلغٍ في التطبيق.
      //
      //    والشقُّ الأوّلُ **على الحالةِ لا على علَم**، وذاك قرارٌ لا سهو:
      //    علَمُ الفشلِ يُكتَبُ بعد فشلِ المعامَلةِ فقد يَفشلُ لنفسِ السبب،
      //    أمّا «مدفوعٌ وما زال `pending`» فهي الحالةُ المتناقضةُ نفسُها ولا
      //    تَحتاجُ أن يَنجحَ شيءٌ لتُرى. ومساواتانِ بلا مدًى ⇒ لا فهرسَ
      //    مركَّب (`contracts` ليس له إلّا `userId`+`created_at`).
      //    **ولا تَغرقُ**: غيرُ المدفوعِ يَخرُجُ بـ`is_paid == false`،
      //    والمُفعَّلُ `active` خارجَ المجموعة. ويُتخطّى
      //    `plan_validation_failed`: ذاك عدمُ تفعيلٍ **مقصودٌ** نُبِّه عنه.
      //
      //    ⚠️ **وكانت `status == "pending"` وحدَها — وهي ليست الحالةَ التي
      //    يَترُكُها المسارُ الطبيعيّ.** الدفعُ يَقعُ من
      //    `approved_waiting_payment` (زرُّ العميلةِ مشروطٌ بها)،
      //    و`payContractWithWallet` لا يَمَسُّ `status`، و`_activateContractNow`
      //    لا يَكتبُ `active` إلّا عند النجاح — فالفاشلُ يَستقرُّ على
      //    `approved_waiting_payment` + `is_paid: true`، وكان **يُفلِتُ من
      //    هذه المكنسةِ ومن بطاقةِ الصحّةِ معاً**. و`pending` + مدفوع تَقعُ
      //    متى دُفِعَ قبلَ الاعتماد، فهي الطرَفُ النادرُ وكانت وحدَها
      //    المَحروسة. و`in` تَنحلُّ إلى مساواتَين، فلا فهرسَ مركَّباً.
      //    القائمةُ مرآةٌ لـ`kContractPreActiveStatuses` في
      //    `lib/utils/contract_health.dart` ويَشدُّ التطابقَ حارسٌ دارتيّ.
      //    ⚠️ **ونافذةُ الـ100 كانت تَسيلُ.** الحلقةُ تَتخطّى
      //    `plan_validation_failed` بـ`continue` — عدمُ تفعيلٍ **مقصودٌ**
      //    نُبِّه عنه سلفاً — وذلك العقدُ يَبقى `is_paid: true` وفي حالةٍ
      //    قبلَ التفعيلِ **إلى الأبد**، فلا يَخرُجُ من مطابقةِ الاستعلام.
      //    فبعدَ مئةٍ منها يُدفَعُ عقدٌ **عالقٌ حقيقيٌّ** خارجَ النافذةِ فلا
      //    يُفعَّلُ أبداً بلا خطأٍ ولا سطرِ سجلّ — وهو أكبرُ مبلغٍ في
      //    التطبيق. ومَسلكُها لا يَلزمُه تلاعبٌ: تغييرُ سعرِ باقةٍ أثناءَ
      //    تعاقدٍ جارٍ يُفشِلُ تحقّقَ خطّتِه، وتلك تَتراكمُ مع العمر.
      //
      //    والعلاجُ سابقةُ المحافظِ السالبةِ في هذا الملفِّ نفسِه: `count()`
      //    أوّلاً ثمّ قراءةُ **الجمهورِ كاملاً**، وانفجارُ العددِ نفسُه هو
      //    الخبرُ. و`!=` في Firestore تَشترطُ وجودَ الحقل، فاستثناءُ
      //    المُتخطَّى بمساواةٍ ثالثةٍ غيرُ متاحٍ أصلاً.
      try {
        const kQ = db.collection("contracts")
            .where("is_paid", "==", true)
            .where("status", "in", ["pending", "approved_waiting_payment"]);
        const kCount = await kQ.count().get().then((a) => a.data().count);
        if (kCount > STUCK_CONTRACT_SCAN_MAX) {
          await queuePush("ADMIN_BROADCAST", "عقود مدفوعة بلا تفعيل ⚠️",
              `${kCount} عقداً مدفوعاً ما زال قبل التفعيل — عددٌ يتجاوز حدَّ ` +
              `المسح (${STUCK_CONTRACT_SCAN_MAX})، وهو بذاته خللٌ منهجيٌّ لا ` +
              "حالاتٌ فرديّة. راجع تحقّق الخطط وسجل التفعيل فوراً.",
              "admin_order_alert", {count: kCount},
              ["super_admin", "accountant_admin"]);
          console.error("opsHealthSweep: stuck contracts above scan cap: " +
            `${kCount}`);
          // ولا تَعدادَ: الخبرُ العددُ. (إن/وإلّا كسابقةِ المحافظ — لا
          // `throw` فيَلتقطُه `catch` الكتلةِ ويُسجّلُ «فشلَ التفعيل» وهو
          // لم يَفشل.)
        } else {
          const kSnap = await kQ.get();
          let revived = 0; let deliberate = 0;
          for (const doc of kSnap.docs) {
            const d = doc.data();
            if (d.plan_validation_failed === true) {
              deliberate++;
              continue;
            }
            // **نُنادي المنطقَ نفسَه، لا نُعيدُ إطلاقَ المُشغّل.** لمسةُ
            // المستندِ لا تُطلِقُه: شرطُه `before.is_paid !== true` وهو
            // `true` سلفاً. ولذلك اُستُخرِجت `_activateContractNow` —
            // قاعدةٌ واحدةٌ بمُنادِيَين، بدلَ نسخةٍ ثانيةٍ تَنحرِف.
            const r = await _activateContractNow(db, doc.ref, doc.id);
            if (r.activated) revived++;
          }
          console.log(`opsHealthSweep: contracts revived=${revived} ` +
            `deliberate=${deliberate} scanned=${kSnap.size}`);
        }
      } catch (e) {
        console.error("opsHealthSweep: contract activation retry failed:",
            e.message);
      }

      //    والشقُّ الثاني **على العلَمِ** لأنّ حالتَه (`active`) هي الحالةُ
      //    السليمةُ لكلِّ عقدٍ فاعلٍ فيَغرقُ فيها الفاشل، و«لا زيارةَ خلفَه»
      //    ليس استعلاماً على مستندِ العقد. وإعادةُ التوليدِ آمنةٌ: معرّفاتُ
      //    الزياراتِ حتميّةٌ (`sub_{contractId}_{i}`) فتُكتَبُ فوقَ نفسِها.
      try {
        // ⚠️ **و`is_paid` شرطٌ لا زينة.** `_generateContractVisits` يُنشئُ
        //    زياراتٍ بـ`is_paid: true` و`amount: 0` بعددِ `planVisits`
        //    **الذي يَكتبُه العميلُ** عند الإنشاء، ويُسنِدُ لها سائقاً. فلو
        //    اكتفى الاستعلامُ بالعلَم لصارَ ضبطُه سلفاً على عقدٍ غيرِ مدفوعٍ
        //    **خدمةً مجّانيّةً بعددٍ يَختارُه**: مكنسةٌ كُتبت لسدِّ صمتٍ
        //    تَفتحُ ثغرةَ مال. والعلَمُ محجوبٌ في القواعدِ أيضاً، لكنّ
        //    `firestore.rules` محجوزةٌ خلفَ STAGE-C فلا تُنشَرُ من الأتمتة —
        //    فالحارسُ العاملُ اليومَ هو هذا الشرطُ. مساواتانِ بلا مدًى ⇒ لا
        //    فهرسَ مركَّب.
        const vSnap2 = await db.collection("contracts")
            .where("contract_visits_pending", "==", true)
            .where("is_paid", "==", true).limit(100).get();
        let fixed = 0; let stuck = 0;
        for (const doc of vSnap2.docs) {
          try {
            await _generateContractVisits(db, doc.ref, doc.data());
            await doc.ref.update({
              contract_visits_pending: FieldValue.delete(),
              contract_visits_alerted: FieldValue.delete(),
            });
            fixed++;
          } catch (e2) {
            stuck++;
            console.error(`opsHealthSweep: regen visits ${doc.id}:`, e2.message);
          }
        }
        console.log(`opsHealthSweep: contract visits retried=${fixed} ` +
          `stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: contract visits retry failed:",
            e.message);
      }

      // 5-quinquies) **مهمّةٌ فشلَ فكُّ إسنادِها عن سائقٍ معطَّل
      //    (2026-10-05).** `unassignJobsOnDriverDisable` كان يَبتلعُ فشلَ
      //    التحديثِ لكلِّ مستندٍ ويَعُدُّه ناجحاً، والمُشغّلُ بلا `retry`:
      //    فالمهمّةُ تَبقى مُسنَدةً لمن لا يَعمل. والاستعلامُ على **العلمِ**
      //    لا على الحالة (`assigned` هي حالةُ كلِّ مهمّةٍ قائمةٍ فتَغرقُ
      //    فيها) — مساواةٌ واحدةٌ ⇒ لا فهرسَ مركَّب.
      try {
        const uSnap = await db.collection("orders")
            .where("unassign_pending", "==", true).limit(100).get();
        let fixed = 0; let stuck = 0;
        for (const doc of uSnap.docs) {
          try {
            await doc.ref.update(_unassignPayload("driver_disabled"));
            fixed++;
          } catch (e2) {
            stuck++;
            console.error(`opsHealthSweep: unassign ${doc.id}:`, e2.message);
          }
        }
        console.log(`opsHealthSweep: unassign retried=${fixed} stuck=${stuck}`);
      } catch (e) {
        console.error("opsHealthSweep: unassign retry failed:", e.message);
      }

      // 5-sexies) **رمزُ دفعٍ موسومٌ بدورٍ قديم.** توجيهُ تنبيهاتِ الإدارةِ
      //    يَستعلمُ `fcm_tokens.role`/`staff_role`، و`syncRoleToPushToken`
      //    يُصحّحُها عند تغييرِ الدور — بـ`.catch(() => {})`: فشلٌ عابرٌ
      //    يُعيدُ العطلَ الذي كُتبت له (هاتفُ مَن أُقصي يَبقى مشتركاً في
      //    تنبيهاتِ الإدارة). و**الكونسولُ مسارٌ رابعٌ بلا شفرةٍ** يُغيّرُ
      //    الدورَ بلا إطلاقِ أيِّ مُشغّل.
      //
      //    فالفحصُ **بنيويٌّ لا على علَم**: يُقارِنُ ما على الرمزِ بما في
      //    `users` — فلا علَمَ يُلفَّقُ، ولا نافذةَ تَزدحمُ (الجمهورُ
      //    رموزُ الموظّفينَ وحدَها، وهي عشراتٌ لا آلاف)، ويُغطّي تعديلَ
      //    الكونسولِ أيضاً. و`in` على حقلٍ واحدٍ ⇒ لا فهرسَ مركَّب.
      try {
        const STAFF_TOKEN_ROLES = ["admin", "super_admin"];
        const tSnap = await db.collection("fcm_tokens")
            .where("role", "in", STAFF_TOKEN_ROLES).limit(300).get();
        let drifted = 0;
        for (const doc of tSnap.docs) {
          const uSnapshot = await db.collection("users").doc(doc.id).get();
          const u = uSnapshot.exists ? uSnapshot.data() : null;
          if (!u) {
            // المستخدمُ زال ولم يُحذَفِ الرمز: هو بعينُه العطلُ المسجَّل.
            await doc.ref.delete().catch(() => {});
            drifted++;
            continue;
          }
          if (_tokenRoleDrifted(doc.data(), u)) {
            await doc.ref.set(_tokenRolePayload(u), {merge: true})
                .catch(() => {});
            drifted++;
          }
        }
        console.log(`opsHealthSweep: staff token drift fixed=${drifted} ` +
          `scanned=${tSnap.size}`);
      } catch (e) {
        console.error("opsHealthSweep: token drift check failed:", e.message);
      }

      // 6) إشعارات لم يلمسها processNotificationTriggers أصلاً (انقطاع الدوال 8–18
      //    أغسطس ترك 122 ترحيباً بلا معالجة ولا خطأ): onDocumentCreated لا يعود لمستند
      //    فاته الحدث، فنعيد إنشاءه نسخةً جديدة (تُطلق الحدث) ونوسم الأصل. مرة واحدة
      //    فقط لكل مستند (redriven_from) كي لا يدور المكسور للأبد، وبنافذة 30 دقيقة
      //    إلى 3 أيام: الأحدث ما زال قيد المعالجة، والأقدم بريدٌ فات أوانه.
      // الطابوران معاً، وكلُّ مستندٍ يُعاد إلى **طابورِه** — نسخُ مستندِ عميلٍ
      // إلى الطابورِ الخادميِّ يَمنحُه ثقةً لم يَملكها.
      //
      // **`try` لكلِّ مجموعةٍ لا واحدٌ للحلقة.** الاستعلامُ مركَّب (مساواةٌ على
      // `processed` ومدًى وترتيبٌ على `createdAt`)، فيَلزمُه فهرسٌ لكلِّ مجموعةٍ
      // على حِدة — والفهارسُ في Firestore **لكلِّ مجموعةٍ لا مُشترَكة**. وكان
      // `try` واحدٌ يُحيط بالحلقةِ و`notification_queue` أوّلَها، فسقوطُ
      // الاستعلامِ الأوّلِ يَقطعُ الحلقةَ قبلَ `notification_triggers` أيضاً:
      // شبكةُ الأمانِ التي كُتبت لانقطاعِ أغسطس تَموتُ للطابورَين معاً، ولا
      // يَبقى منها إلّا سطرُ `console.error` واحد.
      let redriven = 0;
      for (const col of ["notification_queue", "notification_triggers"]) {
        try {
          // ⚠️ **والحدُّ الأدنى للعمرِ في الاستعلامِ لا في الحلقةِ وحدَها.**
          // كان `createdAt <= now-30m` يُطابِقُ **كلَّ** مستندٍ غيرِ مُعالَجٍ
          // على الإطلاق، والحلقةُ تَتخطّى ما تجاوزَ ثلاثةَ أيّامٍ بـ`continue`
          // — و`orderBy("createdAt","asc")` يُقدّمُ **الأقدمَ**. فبمئةٍ من
          // المستنداتِ العتيقةِ تَقرأُ المكنسةُ مئةً وتَتخطّاها كلَّها ولا
          // تَرى مستنداً حديثاً عالقاً واحداً: شبكةُ الأمانِ التي كُتبت
          // لانقطاعِ أغسطس تَصيرُ عاطلةً بصمت. والمَسلكُ قائمٌ في الشفرة:
          // فرعُ الفشلِ في مُعالِجِ المُشغّلِ يَكتبُ `processed: false` ثمّ
          // `giveUp: true` بعد ثلاثِ محاولاتٍ **ويَترُكُ العلمَ `false`** —
          // فكلُّ فشلٍ دائمٍ يُقيمُ في المطابقةِ للأبد.
          //
          // والمدَيانِ على حقلٍ واحدٍ يَخدمُهما الفهرسُ القائمُ نفسُه
          // (`processed ASC, createdAt ASC`) — لا فهرسَ جديد. وما بقي من
          // تخطٍّ (`error`/`emailStatus`/`redriven_from`) يَسيلُ داخلَ
          // ثلاثةِ أيّامٍ وحدَها ثمّ يَخرُجُ بنفسِه: نافذةٌ متدحرجة.
          const snap = await db.collection(col)
              .where("processed", "==", false)
              .where("createdAt", "<=", new Date(now - 30 * 60 * 1000))
              .where("createdAt", ">=", new Date(now - 3 * 24 * 60 * 60 * 1000))
              .orderBy("createdAt", "asc").limit(100).get();
          for (const doc of snap.docs) {
            const d = doc.data();
            if (d.error || d.emailStatus || d.redriven_from) continue;
            const copy = {...d, redriven_from: doc.id,
              createdAt: FieldValue.serverTimestamp()};
            await db.collection(col).add(copy);
            await doc.ref.update({processed: true, status: "redriven"});
            redriven++;
          }
        } catch (e) {
          console.error(`opsHealthSweep: redrive ${col} failed:`, e.message);
        }
      }
      console.log(`opsHealthSweep: stalled triggers redriven=${redriven}`);
    },
);

// ════════════════════════════════════════════════════════════════════════
// مُصالِح الدفعات اليتيمة (Apple/Google/Samsung Pay): يفحص دفعات Moyasar المدفوعة
// دورياً ويُنشئ أي طلب مفقود من الـ metadata — مستقلّ تماماً عن التطبيق. الدفع الأصلي
// يُعلّق التطبيق في الخلفية فقد لا يستدعي verifyMoyasarPayment، فيبقى مالٌ بلا طلب.
// هذا يضمن ظهور الطلب خادميّاً خلال دقائق دون أي اعتماد على التطبيق أو الويب هوك.
// ════════════════════════════════════════════════════════════════════════
exports.reconcileOrphanPayments = onSchedule(
    {schedule: "every 1 minutes", secrets: ["MOYASAR_SECRET_KEY"], cpu: 0.083},
    async () => {
      const secret = moyasarSecretKey.value();
      if (!secret) { console.error("[reconcile] Moyasar secret not set"); return null; }
      const db = getFirestore();
      let recovered = 0;
      try {
        const listed = await moyasar.listPayments(secret, 25);
        if (!listed.ok) {
          console.error("[reconcile] list failed", listed.httpStatus); return null;
        }
        const data = listed.result;
        // حدّ تجاهل: مدفوعات تجريبية/قديمة تمّ تنظيف طلباتها لا تُعاد مطابقتها أبداً.
        // يُضبط في system_configs/reconcile.ignore_before (ISO). بلا إعداد = السلوك السابق.
        let ignoreBeforeMs = 0;
        try {
          const rc = await db.collection("system_configs").doc("reconcile").get();
          const v = rc.exists ? rc.data().ignore_before : null;
          if (v) ignoreBeforeMs = new Date(v).getTime();
        } catch { /* افتراضياً بلا حدّ */ }
        for (const p of (data.payments || [])) {
          if (p.status !== "paid") continue;
          // تجاهُل الدفعات الأقدم من نقطة التنظيف (طلبات اختبار مُزالة عمداً).
          const pCreated = p.created_at || p.created;
          if (ignoreBeforeMs && pCreated &&
              new Date(pCreated).getTime() < ignoreBeforeMs) {
            continue;
          }
          const md = p.metadata || {};
          const oid = md.order_id;
          if (!oid) continue;
          let foundRef = null; let foundData = null;
          for (const col of ["orders", "store_orders", "maintenance_requests", "contracts"]) {
            const d = await db.collection(col).doc(oid).get();
            if (d.exists) { foundRef = d.ref; foundData = d.data(); break; }
          }
          // السجلّ موجود لكنه غير مدفوع (قُتل التطبيق قبل verify) → أكّده إن غطّى المبلغ
          // المدفوع المستحقَّ. flip is_paid يُشغّل مُشغّلاته (activateContractOnPaid للعقود…).
          if (foundRef) {
            // (#1) لا نؤكّد طلباً حُجب لتلاعبٍ سعري أو استُرد/أُلغيت دفعته.
            if (foundData.is_paid !== true && foundData.tamper_blocked !== true &&
                !["voided", "refunded", "payment_review"]
                    .includes(foundData.payment_status)) {
              const paidH = Math.round(Number(p.amount));
              // كان الترتيب هنا يقدّم `amount` على `final_amount` — بخلاف
              // moyasarWebhook وtabbyWebhook. ومقارنةُ `paidH >= expectedH`
              // تجعل الأثر باتجاهٍ واحد: تعديلٌ **هابط** يُنتج متوقَّعاً أكبر
              // من المدفوع، فيُرفض استرداد طلبٍ دفع العميل ثمنه فعلاً.
              const expectedH = amounts.toHalalas(amounts.expectedAmount(foundData));
              if (expectedH > 0 && paidH >= expectedH) {
                await foundRef.update({
                  is_paid: true, payment_status: "paid",
                  moyasar_payment_id: p.id, moyasar_status: "paid",
                  updated_at: FieldValue.serverTimestamp(),
                  ...refunds.reopenFieldsIfSystemCancelled(foundData),
                });
                console.log(`[reconcile] CONFIRMED existing ${oid} (paid ${paidH}/${expectedH})`);
                recovered++;
              } else {
                console.warn(`[reconcile] amount too low for ${oid}: paid ${paidH} expected ${expectedH} — skip`);
              }
            }
            continue; // موجود → لا نُنشئ
          }
          // غير موجود → نُنشئه من الـ metadata، لكن ذلك يحتاج تفاصيل كافية (نسخ قديمة
          // ترسل order_id فقط فلا يمكن بناء طلب حقيقي — تلك تبقى للاسترداد اليدوي).
          if (!md.service_name) continue;
          // باقات الاشتراك تُدار كعقود (contracts) لا كطلبات خدمة. لو لم نجد العقد
          // (نسخة قديمة أرسلت معرّفاً عشوائياً) نتخطّى بدل إنشاء «طلب اشتراك» شبحي.
          if (md.service_name.includes("باقة")) continue;
          const isHourly = String(md.is_hourly) === "1";
          const amountSar = Number(p.amount) / 100; // المخصوم فعلاً (مرجع موثوق)
          let code = `ZY-${Date.now().toString().slice(5)}`;
          try {
            code = await db.runTransaction(async (tx) => {
              const cRef = db.collection("metadata").doc("order_counter");
              const cs = await tx.get(cRef);
              const next = ((cs.exists ? cs.data().last_id : 100) || 100) + 1;
              if (cs.exists) tx.update(cRef, {last_id: next}); else tx.set(cRef, {last_id: next});
              return String(next);
            });
          } catch (e) { console.error("[reconcile] counter:", e); }
          const lat = Number(md.lat); const lng = Number(md.lng);
          let clientName = (md.client_name || "").trim();
          if (!clientName && md.client_id) {
            try {
              const uDoc = await getFirestore().collection("users").doc(md.client_id).get();
              if (uDoc.exists) clientName = (uDoc.data().name || "").trim();
            } catch { /* اسم العميل تحسين اختياري — الإشعار يُرسَل بدونه */ }
          }
          const payload = {
            code, client_id: md.client_id, client_name: clientName || "عميل زيارة", client_phone: md.client_phone || "",
            service_type: md.service_name || "خدمة زيارة", service_name: md.service_name || "خدمة زيارة",
            amount: amountSar, is_paid: true, payment_status: "paid",
            moyasar_payment_id: p.id, moyasar_status: "paid",
            status: "pending",
            payment_method: (p.source && p.source.type) || "applepay",
            // كأعلاه: لا `NaN` في مستندٍ يُعَدّ ويُعرَض (انظر verifyMoyasarPayment).
            hours_contracted: slots.orderHours({hours_contracted: md.hours}),
            worker_count: Number(md.worker_count) || 1,
            zone_name: md.zone_name || null,
            // بلا إحداثيات في الـmetadata ⇒ بلا حقل location إطلاقاً (كان يُختم
            // مركز الرياض زوراً) — الواجهات تُخفي الخرائط بأمان عند غيابه.
            ...((!isNaN(lat) && !isNaN(lng)) ?
              {location: new GeoPoint(lat, lng)} : {}),
            created_at: FieldValue.serverTimestamp(),
            server_created_from_payment: true, reconciled: true,
            // أعِد بناء تفصيل الخدمة من الـ metadata (وإلّا فُقِد على طلب Apple Pay).
            ...(_parseServiceMeta(md.service_meta_json) ?
              {service_meta: _parseServiceMeta(md.service_meta_json)} : {}),
          };
          if (md.service_date) {
            const sd = parseKsaIso(md.service_date);
            if (!isNaN(sd.getTime())) {
              payload.service_date = Timestamp.fromDate(sd);
              if (isHourly) {
                // توقيت الرياض: قراءة المكوّنات المحلية من **لحظة زمنية** تعطي
                // ساعة UTC — كانت تخزّن الخانة أبكر بثلاث ساعات من موعد العميلة،
                // فيُحجز في capacity.js وقتٌ خاطئ ويبقى وقتُ الموعد فارغاً.
                const bf = riyadhBookingFields(sd);
                payload.booking_date = bf.bookingDate;
                payload.booking_time_slot = bf.bookingTimeSlot;
              }
            }
          }
          await db.collection("orders").doc(oid).set(payload);
          console.log(`[reconcile] RECOVERED order ${oid} (${amountSar} SAR) code ${code}`);
          recovered++;
        }
      } catch (e) {
        console.error("[reconcile] error:", e);
      }
      if (recovered) console.log(`[reconcile] recovered ${recovered} orphan order(s).`);
      return null;
    });

// ════════════════════════════════════════════════════════════════════════
// احتياطي تمارا: تأكيد الطلبات غير المؤكّدة عبر واجهة تمارا مباشرةً — Cron كل
// 3 دقائق. يعوّض حجب الويب هوك (Cloud Run invoker): يستعلم حالة الطلب، يفوّض
// approved (فيلتقطها الحساب تلقائياً)، ويقلب is_paid. لا يعتمد على وصول الويب هوك.
// ════════════════════════════════════════════════════════════════════════
exports.confirmPendingTamaraOrders = onSchedule(
    {schedule: "every 3 minutes", secrets: ["TAMARA_API_TOKEN"], cpu: 0.083},
    async () => {
      const db = getFirestore();
      const since = Timestamp.fromDate(
          new Date(Date.now() - 6 * 60 * 60 * 1000));
      const snap = await db.collection("orders")
          .where("payment_method", "==", "tamara")
          .where("created_at", ">=", since)
          .get();
      const apiToken = tamaraApiToken.value();
      let confirmed = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.is_paid === true) continue;
        if (["order_declined", "order_expired", "order_canceled"]
            .includes(d.tamara_status)) continue;
        try {
          // كان `await r.json()` عارياً: جسمٌ غير JSON يرمي فيُتجاوَز المستند
          // **بصمت** — طلبٌ موافَق عليه لا يُؤكَّد أبداً ولا سطر يقول لماذا.
          const r = await tamara.getOrderByReference(apiToken, doc.id);
          if (!r.ok) continue;
          const to = r.order;
          const st = to.status;
          let justConfirmed = false;
          if (st === "approved") {
            const a = await tamara.authorise(apiToken, to.order_id);
            if (a.ok) {
              await _tamaraFlipPaid(db, doc.id, "order_authorised", to.order_id);
              justConfirmed = true;
            }
          } else if (["authorised", "captured", "fully_captured",
            "partially_captured"].includes(st)) {
            await _tamaraFlipPaid(db, doc.id, "order_" + st, to.order_id);
            justConfirmed = true;
          } else if (["declined", "expired", "canceled"].includes(st)) {
            // نُلغي الطلب (لا نتركه pending) كي يحرّر خانة الحجز ويُصحّح العدّاد — كان
            // يبقى pending فيستهلك السعة أبداً رغم فشل الدفع.
            await doc.ref.update({
              status: "cancelled",
              payment_status: "failed",
              cancel_reason: "tamara_" + st,
              tamara_status: "order_" + st,
              updated_at: FieldValue.serverTimestamp(),
            });
          }
          if (justConfirmed) {
            confirmed++;
            // إسناد فوري للساعة بعد التأكيد (بدل انتظار الـ sweep 15 دقيقة).
            if (d.service_date && !d.driver_id && d.status === "pending") {
              try {
                const start = d.service_date.toDate();
                const hours = slots.orderHours(d);
                const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
                const driver = await _findFreeDriverForSlot(db, {
                  startDateTime: start,
                  endDateTime: end,
                });
                if (driver) await _assignDriverScheduled(db, doc.id, driver, start);
              } catch (e) {
                console.error(`confirmPendingTamaraOrders assign ${doc.id}:`, e.message);
              }
            }
          }
        } catch (e) {
          console.error(`confirmPendingTamaraOrders ${doc.id}:`, e.message);
        }
      }

      // اشتراكات تمارا: يُمرَّر معرّف العقد كمرجع تمارا ويعيش في contracts (لا orders)،
      // فالحلقة أعلاه (تمسح orders فقط) لا تؤكّدها — والويب هوك محجوب. نمسح العقود غير
      // المؤكّدة الحديثة. العقد يستخدم createdAt (camelCase) وبلا payment_method، فنمرّ
      // على غير المدفوعة ونستعلم تمارا بمعرّفها (تعيد 404 لغير تمارا فنتخطّاه).
      try {
        const sinceC = Timestamp.fromDate(
            new Date(Date.now() - 6 * 60 * 60 * 1000));
        const csnap = await db.collection("contracts")
            .where("createdAt", ">=", sinceC).get();
        for (const cdoc of csnap.docs) {
          const cd = cdoc.data();
          if (cd.is_paid === true) continue;
          try {
            const r = await tamara.getOrderByReference(apiToken, cdoc.id);
            if (!r.ok) continue;
            const to = r.order;
            const st = to.status;
            if (st === "approved") {
              const a = await tamara.authorise(apiToken, to.order_id);
              if (a.ok) {
                await _tamaraFlipPaid(db, cdoc.id, "order_authorised", to.order_id);
                confirmed++;
              }
            } else if (["authorised", "captured", "fully_captured",
              "partially_captured"].includes(st)) {
              await _tamaraFlipPaid(db, cdoc.id, "order_" + st, to.order_id);
              confirmed++;
            }
          } catch (e) {
            console.error(`confirmPendingTamaraOrders contract ${cdoc.id}:`, e.message);
          }
        }
      } catch (e) {
        console.error("confirmPendingTamaraOrders contracts scan:", e.message);
      }

      console.log(`confirmPendingTamaraOrders: confirmed ${confirmed}`);
    },
);

// ════════════════════════════════════════════════════════════════════════
// تنظيف الطلبات المهجورة: يُنشأ الطلب is_paid=false status='pending' قبل بوابة الدفع،
// والمهجور منه (لم يُكمَل دفعه) كان يبقى أبداً فيستهلك سعة الحجز ويضخّم عدّاد الإيراد/
// النشط (onOrderWritten). نلغيه بعد 30 دقيقة → الانتقال إلى cancelled يُصحّح العدّاد
// (طرح تلقائي) ويحرّر الخانة. لا يمسّ المدفوع (is_paid===true) إطلاقاً.
// ════════════════════════════════════════════════════════════════════════
exports.cancelStaleUnpaidOrders = onSchedule(
    {schedule: "every 15 minutes", cpu: 0.083},
    async () => {
      const db = getFirestore();
      const cutoffMs = Date.now() - 30 * 60 * 1000;
      // استعلام أحادي الحقل (status) تفادياً لفهرس مركّب؛ نُرشّح is_paid+created_at كوداً.
      const snap = await db.collection("orders")
          .where("status", "==", "pending").get();
      let cancelled = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.is_paid === true) continue;
        // **لا نلغي طرق الدفع المؤجَّلة** (تمارا/تابي): تأكيدها يستغرق ساعات (نافذة
        // confirmPendingTamaraOrders 6س)، فإلغاؤها بعد 30د ثم تأكيدها لاحقاً = العميل
        // مخصوم لطلبٍ ملغى بلا خدمة ولا استرداد. وكذلك ما يحمل معرّف دفعة ميسر (قد يكون خُصم).
        if (["tamara", "tabby"].includes(d.payment_method)) continue;
        if (d.moyasar_payment_id) continue;
        const c = d.created_at;
        if (!c || typeof c.toMillis !== "function") continue;
        if (c.toMillis() > cutoffMs) continue; // أحدث من 30 دقيقة — قد يكون دفعاً جارياً
        try {
          await doc.ref.update({
            status: "cancelled",
            cancel_reason: "unpaid_expired",
            cancelled_by: "system", // إلغاء آلي — يُسكِت مُشغّلات تنبيه الإلغاء
            cancelled_at: FieldValue.serverTimestamp(),
          });
          cancelled++;
        } catch (e) {
          console.error(`cancelStaleUnpaidOrders ${doc.id}:`, e.message);
        }
      }
      if (cancelled) {
        console.log(`cancelStaleUnpaidOrders: cancelled ${cancelled} stale unpaid order(s).`);
      }
    });

// ════════════════════════════════════════════════════════════════════════
// (2c) تذكير العميل عند انطلاق السائق (on_the_way) — Event-driven
// ════════════════════════════════════════════════════════════════════════
exports.notifyClientOnDriverDeparture = onDocumentUpdated(
    {document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();
      if (!before || !after) return;
      // فقط عند الانتقال الفعلي إلى on_the_way
      if (before.status === "on_the_way" || after.status !== "on_the_way") return;

      const greet = _clientGreeting(after);
      // queuePush لا _pushToUid: الأخير يتخطّى العميل بلا توكن FCM بلا أثر في
      // صندوق الوارد — عميل الويب لا يُخبَر بانطلاق سائقه إطلاقاً. queuePush تكتب
      // الوارد دائماً ثم تدفع.
      await queuePush(
          after.client_id,
          "سائقكِ في الطريق إليكِ 🚗",
          `${greet}انطلق فريق زيارة لتنفيذ خدمتكِ — يسعدنا استقبالكِ ✨`,
          "order_update",
          {orderId: event.params.orderId},
      );
    },
);

// ════════════════════════════════════════════════════════════════════════
// نظام الإحالة — ربط الإحالة خادمياً (العميل يرسل الكود فقط، والخادم يتحقّق
// ويحدّد referrer_id — كي لا يمنح العميل مكافأة إحالة لأي شخص بضبط الحقل يدوياً).
// ════════════════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════════════
// Referral code — generated server-side because the collision check cannot
// run on the client
// ════════════════════════════════════════════════════════════════════════
// `ZyiarahReferralService.getOrCreateReferralCode` كانت تُولّدُ الكودَ على
// الجهازِ ثمّ تَفحصُ التصادمَ بـ
// `users.where('referral_code','==',code).limit(1)` — و**قاعدةُ `users` هي
// `isOwner(userId) || isAdmin()`**، فاستعلامُ قائمةٍ على المجموعةِ لا يُثبِتُ
// أيَّهما ويُرفَضُ عند كلِّ عميلة. والاستعلامُ بلا `try`، فالاستثناءُ يَخرجُ
// من الدالّةِ: **كلُّ عميلةٍ لا تَملكُ كوداً بعدُ لا تَستطيعُ الحصولَ على
// واحدٍ أبداً** — وبرنامجُ الإحالةِ كلُّه (٥٠ ر.س للمُحيل، ١٠٪ للمُحالة)
// يَبدأُ بذلك الكود. (مُثبَتٌ على المُحاكي لا مُستنتَجاً.)
//
// والتصادمُ ليس وسوسةً: `applyReferralCode` يَحُلُّ المُحيلَ بـ
// `where('referral_code','==',code).limit(1)` — فكودانِ متطابقانِ يَعنيانِ
// إسناداً خاطئاً لمكافأةٍ ماليّة، وهو بعينُه ما أُضيفت لأجلِه قاعدةُ
// «الكودُ يُكتَبُ مرّةً» في 2026-10-05. فالفحصُ لازمٌ، ومكانُه الخادمُ وحدَه.
//
// والنداءُ **عديمُ الأثرِ التكراريّ**: مَن يَملكُ كوداً يُعادُ له كما هو، فلا
// ضررَ في إعادةِ المحاولةِ بعدَ مهلة.
const REFERRAL_CODE_CHARS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/**
 * كودٌ عشوائيٌّ بطولِ ثمانيةٍ من الأبجديّةِ نفسِها التي كان يَستعملُها العميل
 * (بلا حروفٍ تُشبِهُ أرقاماً: I/L/O/0/1).
 * @return {string}
 */
function _randomReferralCode() {
  let out = "";
  for (let i = 0; i < 8; i++) {
    out += REFERRAL_CODE_CHARS[
        Math.floor(Math.random() * REFERRAL_CODE_CHARS.length)];
  }
  return out;
}

exports.ensureReferralCode = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "المستخدم غير موجود");
  const existing = snap.data().referral_code;
  if (typeof existing === "string" && existing !== "") {
    return {code: existing};
  }
  // خمسُ محاولاتٍ كما كان العميلُ يَفعل — والفحصُ هنا يَعمل.
  for (let i = 0; i < 5; i++) {
    const code = _randomReferralCode();
    const clash = await db.collection("users")
        .where("referral_code", "==", code).limit(1).get();
    if (!clash.empty) continue;
    // كتابةٌ ذرّيّةٌ تَحرُسُ نفسَها: نداءانِ متزامنانِ لا يُنتجانِ كودَين.
    const won = await db.runTransaction(async (t) => {
      const fresh = await t.get(userRef);
      const cur = fresh.exists ? fresh.data().referral_code : null;
      if (typeof cur === "string" && cur !== "") return cur;
      t.update(userRef, {referral_code: code});
      return code;
    });
    return {code: won};
  }
  throw new HttpsError("resource-exhausted",
      "تعذّر توليد كود إحالة فريد — حاولي لاحقاً");
});

exports.applyReferralCode = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const uid = request.auth.uid;
  const code = String(request.data && request.data.code || "").trim().toUpperCase();
  if (!code) throw new HttpsError("invalid-argument", "كود الإحالة مطلوب");
  const db = getFirestore();

  // (1) استخراج المُحيل من الكود خادمياً — لا يثق بأي referrer_id من العميل.
  const rq = await db.collection("users")
      .where("referral_code", "==", code).limit(1).get();
  if (rq.empty) return {ok: false, reason: "not_found"};
  const referrerDoc = rq.docs[0];
  const referrerId = referrerDoc.id;
  if (referrerId === uid) return {ok: false, reason: "self"};

  // (2) كل مستخدم يُحال مرّة واحدة — المعرّف الحتمي = uid المُحال إليه.
  const refRef = db.collection("referrals").doc(uid);
  const created = await db.runTransaction(async (t) => {
    const existing = await t.get(refRef);
    if (existing.exists) return false;
    t.set(refRef, {
      referrer_id: referrerId,
      referrer_name: referrerDoc.data().name || "",
      referee_id: uid,
      referral_code: code,
      status: "pending",
      created_at: FieldValue.serverTimestamp(),
      rewarded_at: null,
      rewarded_on_order: null,
    });
    t.set(db.collection("users").doc(uid),
        {used_referral_code: code, referred_by: referrerId}, {merge: true});
    return true;
  });
  return {ok: created, reason: created ? null : "already"};
});

// 10. Auto Assign Driver Directly (No acceptance required)
exports.autoAssignDriverDirectly = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const {orderId, durationHours} = request.data;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "معرف الطلب مطلوب");
  }

  const db = getFirestore();

  // 1. Fetch order details
  const orderDoc = await db.collection("orders").doc(orderId).get();
  if (!orderDoc.exists) {
    throw new HttpsError("not-found", "الطلب غير موجود");
  }

  const orderData = orderDoc.data();

  // SECURITY: صاحب الطلب أو أدمن فقط — يمنع إجبار إسناد سائق لطلبات الآخرين
  if (orderData.client_id !== request.auth.uid) {
    await _assertAdmin(request);
  }
  if (!orderData.service_date) {
    throw new HttpsError("failed-precondition", "تاريخ الخدمة غير محدد");
  }

  const startDateTime = orderData.service_date.toDate();
  const hours = slots.orderHours(orderData, durationHours);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);

  // (Direct Dispatch) اختيار أي سائق حرّ في الفترة ثم إسناده بحالة scheduled.
  // بلا منطقة: السائق يقبل أي طلب (قرار المالك).
  const driver = await _findFreeDriverForSlot(db, {
    startDateTime,
    endDateTime,
  });
  if (!driver) {
    return {assigned: false, error: "no_available_drivers"};
  }

  const r = await _assignDriverScheduled(db, orderId, driver, startDateTime);
  // إن رفضت المعامَلة الكتابة (الطلب مُسنَد سلفاً في سباق) لا نكذب على المستدعي
  // بأننا أسندنا السائق — نُعيد فشلاً كي لا تعرض الواجهة سائقاً خاطئاً.
  if (r.assigned === false) {
    return {assigned: false, error: "already_assigned"};
  }
  return {
    assigned: true,
    driverId: r.driverId,
    driverName: r.driverName,
    // لا نُعيد بريد السائق للعميل (تسريب PII للموظّف).
  };
});

// 11. Check hourly slot availability securely (server-side)
exports.checkHourlySlotAvailability = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const {startDateTimeIso, durationHours} = request.data;
  if (!startDateTimeIso) {
    throw new HttpsError("invalid-argument", "تاريخ البداية مطلوب");
  }

  const startDateTime = new Date(startDateTimeIso);
  const hours = Number(durationHours || 4);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
  const db = getFirestore();

  // (Direct Dispatch) التوفّر = وجود سائق حرّ في الفترة عبر نفس مُحدِّد الإسناد.
  const driver = await _findFreeDriverForSlot(db, {
    startDateTime,
    endDateTime,
  });
  if (!driver) {
    return {available: false, driverId: null, driverName: null};
  }
  const driverData = driver.data();
  return {
    available: true,
    driverId: driver.id,
    driverName: driverData.name || "سائق",
  };
});

// 12. Hourly slot availability for client UI — server-side to bypass Firestore rules.
// Returns daily order counts + per-slot counts for the requested date range.
// The client app uses these to colour date cells and slot buttons without
// needing read access to other users' orders.
// ── Zone opening schedule (server-authoritative) ─────────────────────────────
// المنطقة قد تُفتح بجدول: أيام أسبوعية ثابتة + تواريخ فتح استثنائية (windows) +
// تواريخ إغلاق (blackouts). الحساب هنا **مرجعيّ**: العميل يرسم منه، وبوابة الدفع
// تفرضه — فلا يمكن حجز موعد خارج ساعات عمل المنطقة.
//
// الشكل المخزَّن على مستند المنطقة:
//   schedule: {
//     enabled: bool,                       // false/غائب => مفتوحة 8..22 كل يوم (توافق خلفي)
//     weekly:  {"0":{open,start,end},...},  // 0=الأحد .. 6=السبت (يطابق getDay في JS و weekday%7 في Dart)
//     blackouts: ["yyyy-MM-dd"],            // مغلقة كلياً
//     windows:  [{from,to,start,end}]       // فتح استثنائي يتجاوز الأسبوعي
//   }
const DEFAULT_OPEN = [8, 22];

/**
 * جدول المنطقة في تاريخ محدد: نطاق الفتح + الساعات المقفلة داخله، أو null (مغلق).
 * `closed` (تحكم المالك ساعة-بساعة): ساعاتٌ داخل النطاق أقفلها من محرر الجدول —
 * تُعامَل في كل الحسابات كساعةٍ ممتلئة فلا تُحجز.
 * @param {object|undefined} schedule
 * @param {string} dateStr yyyy-MM-dd
 * @return {{range: number[], closed: number[]}|null}
 */
function zoneDayScheduleForDate(schedule, dateStr) {
  if (!schedule || schedule.enabled !== true) {
    return {range: DEFAULT_OPEN, closed: []};
  }

  const closedOf = (entry) => (Array.isArray(entry.closed) ? entry.closed : [])
      .map(Number).filter(Number.isInteger);

  const blackouts = Array.isArray(schedule.blackouts) ? schedule.blackouts : [];
  if (blackouts.includes(dateStr)) return null; // إغلاق صريح يتقدّم كل شيء

  // فتح استثنائي: تاريخ ضمن نافذة يتجاوز الأسبوعي.
  const windows = Array.isArray(schedule.windows) ? schedule.windows : [];
  for (const w of windows) {
    if (w && w.from && w.to && dateStr >= w.from && dateStr <= w.to) {
      const s = Number(w.start); const e = Number(w.end);
      if (Number.isInteger(s) && Number.isInteger(e) && e > s) {
        return {range: [s, e], closed: closedOf(w)};
      }
    }
  }

  // الجدول الأسبوعي.
  const weekday = new Date(`${dateStr}T00:00:00`).getDay(); // 0=الأحد..6=السبت
  const wk = schedule.weekly && schedule.weekly[String(weekday)];
  if (wk && wk.open === true) {
    const s = Number(wk.start); const e = Number(wk.end);
    if (Number.isInteger(s) && Number.isInteger(e) && e > s) {
      return {range: [s, e], closed: closedOf(wk)};
    }
  }
  return null; // جدولٌ مُفعَّل وهذا اليوم غير مشمول => مغلق
}

/**
 * ساعات فتح المنطقة في تاريخ محدد، أو null إن كانت مغلقة (غلاف توافقي).
 *
 * لا يناديها شيء داخل هذا الملف، لكنها مقصودة: يحرسها
 * test/zone_schedule_test.dart صراحةً («الغلاف التوافقي يبقى لأي مستهلك
 * قديم»). لا تُحذف اتّكالاً على أن الفحص يقول إنها غير مستعمَلة.
 * @param {object|undefined} schedule
 * @param {string} dateStr yyyy-MM-dd
 * @return {number[]|null} [startHour, endHour] أو null (مغلق)
 */
// eslint-disable-next-line no-unused-vars
function zoneOpenHoursForDate(schedule, dateStr) {
  const day = zoneDayScheduleForDate(schedule, dateStr);
  return day === null ? null : day.range;
}

exports.getHourlyAvailability = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }

  // zoneName تُستعمل **فقط** لجلب جدول فتح المنطقة (لا لترشيح السائقين — هم بلا
  // مناطق). قد تصل غائبة من نسخ قديمة، فنتعامل معها اختيارياً.
  const {startDate, endDate, zoneName} = request.data;
  if (!startDate || !endDate) {
    throw new HttpsError("invalid-argument", "startDate و endDate مطلوبان");
  }

  const db = getFirestore();

  // 0. جدول فتح المنطقة (إن وُجدت منطقة باسم zoneName ولها schedule) وسقفها
  //    اليومي الخاص (max_orders_per_day على مستند المنطقة — اختياري، يضيّق السقف
  //    العام فقط: قرار المالك 2026-09-16 لضبط المناطق البعيدة/الوعرة).
  let zoneSchedule = null;
  let zoneMaxOrdersPerDay = null;
  if (zoneName) {
    try {
      const zq = await db.collection("service_zones")
          .where("name", "==", zoneName).limit(1).get();
      if (!zq.empty) {
        zoneSchedule = zq.docs[0].data().schedule || null;
        zoneMaxOrdersPerDay = zoneDailyCap(zq.docs[0].data());
      }
    } catch { /* تعذّر جلب جدول المنطقة — يُعامَل كغير مقيَّد بجدول */ }
  }

  // 1. السعة الحقيقية للفترة = عدد السائقين المؤهَّلين. **بلا مناطق** (قرار
  // المالك): السائق يقبل أي طلب، فالسعة رقم واحد للنشاط كلّه لا لكل منطقة.
  //
  // **ونفس دالّة الأهلية التي يفرضها المُسنِد** — لا نسخةً تطابقها. عدّادٌ يفوق
  // ما يقبله `_findFreeDriverForSlot` كان يُظهر يوماً «متاحاً» فيدفع العميل ثم
  // لا يجد المُسنِد سائقاً مؤهَّلاً فيعلق الطلب المدفوع حتى الاسترداد الآلي.
  // كانت القاعدة مكتوبةً مرّتين ويحفظ تطابقَهما هذا التعليق؛ صارت `drivers.js`.
  const driverCount = (await _eligibleDriverDocs(db)).length;

  // 2. السعة اليومية تبقى من الإعدادات (سقف إضافي)
  let maxOrdersPerDay = 10;
  try {
    const hourlySnap = await db.collection("system_configs")
        .doc("hourly_settings").get();
    if (hourlySnap.exists) {
      maxOrdersPerDay = hourlySnap.data().max_orders_per_day ?? 10;
    }
  } catch { /* تعذّر جلب الإعدادات — يبقى الحدّ الافتراضي أعلاه */ }

  // 3. عدّ الطلبات التي تستهلك سائقاً في كل فترة (غير الملغاة)
  const snap = await db.collection("orders")
      .where("booking_date", ">=", startDate)
      .where("booking_date", "<=", endDate)
      .get();

  // العدّ في capacity.js (نقيّ ومختبَر): نعدّ طلبات **كل المناطق** لأن السائقين
  // بلا مناطق (driverCount عالمي — البسط والمقام من العالم نفسه)، ونعدّ طلبات
  // المنطقة المطلوبة على حدة لسقفها الخاص إن وُجد.
  const {dailyCounts, slotCounts, zoneDailyCounts} =
    countBookings(snap.docs.map((doc) => doc.data()), {zoneName: zoneName || null});

  // 4. اشتقاق جدول الفتح لكل يوم في المدى — مرجعيّ، يرسم منه العميل ويفرضه الدفع.
  const openHours = {};   // "yyyy-MM-dd" -> [start, end]
  const closedDates = []; // أيام مغلقة كلياً بالجدول
  const closedHours = {}; // "yyyy-MM-dd" -> [ساعات أقفلها المالك داخل النطاق]
  const start = new Date(`${startDate}T00:00:00`);
  const end = new Date(`${endDate}T00:00:00`);
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    const ds = `${y}-${m}-${day}`;
    const daySched = zoneDayScheduleForDate(zoneSchedule, ds);
    if (daySched === null) closedDates.push(ds);
    else {
      openHours[ds] = daySched.range;
      if (daySched.closed.length) closedHours[ds] = daySched.closed;
    }
  }

  // maxTeamsPerSlot يعكس الآن عدد السائقين الحقيقي (لا قيمة ثابتة من الإعدادات)
  return {
    dailyCounts, slotCounts, maxOrdersPerDay, maxTeamsPerSlot: driverCount,
    // سقف المنطقة الخاص وعدّها: العميل يعدّ اليوم ممتلئاً إن بلغ أيّاً من السقفين.
    zoneMaxOrdersPerDay, zoneDailyCounts,
    scheduleEnabled: !!(zoneSchedule && zoneSchedule.enabled === true),
    openHours, closedDates, closedHours, defaultOpen: DEFAULT_OPEN,
  };
});

// Notify driver when they are assigned to an order
exports.notifyDriverOnAssignment = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;

      const beforeData = change.before.data();
      const afterData = change.after.data();
      const orderId = event.params.orderId;

      // Check if driver_id was changed and is not null
      if (afterData.driver_id && beforeData.driver_id !== afterData.driver_id) {
        const driverId = afterData.driver_id;

        // (تعليمات المنزل — شبكة أمان) بعض مسارات الإسناد تكتب driver_id مباشرةً من
        // لوحات الأدمن دون المرور بـ_assignDriverScheduled/approveAndAssignOrder؛
        // نستكمل نسخ house_rules من مستند العميل هنا كي تصل السائق في كل المسارات.
        if (afterData.house_rules === undefined && afterData.client_id) {
          try {
            const uSnap = await getFirestore()
                .collection("users").doc(afterData.client_id).get();
            const hr = uSnap.exists ? uSnap.data().house_rules : null;
            if (typeof hr === "string" && hr.trim()) {
              await change.after.ref.update({house_rules: hr.trim()});
            }
          } catch (e) {
            console.error("house_rules backfill:", e.message);
          }
        }

        const displayCode = afterData.code || orderId.substring(0, 6).toUpperCase();
        const title = "تم تعيين طلب جديد لك! 🚚";
        const body = `تم تعيينك للطلب #${displayCode}. يرجى التحقق من تفاصيل الرحلة في لوحة التحكم.`;

        // 1. Save to in-app notifications inbox
        await getFirestore().collection("notifications").add({
          userId: driverId,
          title: title,
          body: body,
          type: "order_assignment",
          relatedId: orderId,
          isRead: false,
          sentAt: FieldValue.serverTimestamp(),
        });

        // 2. Fetch driver's FCM token
        const tokenDoc = await getFirestore().collection("fcm_tokens").doc(driverId).get();
        if (tokenDoc.exists) {
          const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
          if (fcmToken) {
            const payload = {
              notification: {
                title: title,
                body: body,
              },
              data: {
                click_action: "FLUTTER_NOTIFICATION_CLICK",
                type: "order_assignment",
                orderId: orderId,
              },
              token: fcmToken,
            };
            try {
              await getMessaging().send(payload);
              console.log(`Assignment notification sent to driver ${driverId} for order ${orderId}`);
            } catch (error) {
              console.error("Error sending assignment FCM to driver:", error);
            }
          }
        }

        // 3. بريد للسائق (طلب المالك) — منفصل عن الوارد/الدفع أعلاه كي لا يتكرّرا:
        //    نوع "email" + toUid=null ⇒ بريد فقط (لا وارد لأن toUid فارغ، ولا دفع
        //    لأن النوع email). لا نُرسله إلا إن كان للسائق عنوانٌ مسجَّل — وإلّا لوقع
        //    البريد على العنوان الإداري الافتراضي بالخطأ.
        try {
          let driverEmail = "";
          const dv = await getFirestore().collection("drivers").doc(driverId).get();
          if (dv.exists && dv.data()?.email) {
            driverEmail = String(dv.data().email).trim();
          } else {
            const uv = await getFirestore().collection("users").doc(driverId).get();
            if (uv.exists && uv.data()?.email) driverEmail = String(uv.data().email).trim();
          }
          if (driverEmail) {
            await queuePush(
                null,
                title,
                `تم تعيينك للطلب #${displayCode}. افتح تطبيق زيارة لعرض تفاصيل ` +
                `الرحلة والموعد والموقع والتواصل مع العميل.`,
                "email",
                {orderId: orderId},
                null,
                driverEmail);
          }
        } catch (e) {
          console.error("Error queueing driver assignment email:", e.message);
        }
      }

      // إشعار السائق السابق عند سحب/إعادة إسناد المهمة (كان صامتاً — كان قد يذهب
      // لموعد لم يعد مُسنداً إليه). يشمل حالة التحرير (driver_id → null).
      if (beforeData.driver_id && beforeData.driver_id !== afterData.driver_id) {
        const displayCode = (beforeData.code || afterData.code ||
          orderId.substring(0, 6)).toString().toUpperCase();
        await queuePush(
            beforeData.driver_id,
            "تم سحب مهمة منك ℹ️",
            `لم تعد المهمة #${displayCode} مُسندة إليك. تحقّق من مهامك الحالية.`,
            "driver_task_removed", {orderId});
      }
      return null;
    });

// ── Moyasar Webhook ────────────────────────────────────────────────────────────
// Receives real-time payment events from Moyasar (payment_paid, payment_failed, etc.)
// Must return 2xx quickly. Moyasar retries up to 5 times over 2 hours on failure.
// Register this URL in Moyasar Dashboard → Webhooks → Add Webhook.
// Set events: payment_paid, payment_failed, payment_refunded
// Set shared_secret in Secret Manager as MOYASAR_WEBHOOK_SECRET.
exports.moyasarWebhook = onRequest(
    {secrets: ["MOYASAR_SECRET_KEY", "MOYASAR_WEBHOOK_SECRET"]},
    async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method not allowed"});
      }

      const event = req.body;

      // 1. Verify shared secret (set in Moyasar Dashboard → Webhooks)
      const webhookSecret = moyasarWebhookSecret.value();
      // رفض قاطع: إن لم يُضبط السرّ نرفض بدل القبول المفتوح (كان يمرّ أي POST بلا سرّ).
      if (!webhookSecret || event.secret_token !== webhookSecret) {
        console.error("moyasarWebhook: invalid/missing secret_token — rejecting");
        return res.status(401).json({error: "Invalid secret"});
      }

      // 2. Acknowledge immediately (Moyasar requires fast 2xx)
      res.status(200).json({received: true});

      // 3. Process event asynchronously (function stays alive until promise resolves)
      try {
        const eventType = event.type;
        const payment = event.data;

        if (!payment || !payment.id) {
          console.warn("moyasarWebhook: missing payment data in event", eventType);
          return;
        }

        const orderId = payment.metadata?.order_id;
        if (!orderId) {
          console.warn(`moyasarWebhook: no order_id in metadata for payment ${payment.id}`);
          return;
        }

        if (eventType === "payment_paid" || eventType === "payment_captured") {
          // Double-verify with Moyasar API using secret key (never trust webhook payload alone)
          const secret = moyasarSecretKey.value();

          const verified = await moyasar.getPayment(secret, payment.id);
          if (!verified.ok) {
            console.error(`moyasarWebhook: Moyasar API verify failed for payment ${payment.id}:`,
                verified.error ?? verified.raw);
            return;
          }

          const verifiedPayment = verified.raw;
          if (verifiedPayment.status !== "paid" && verifiedPayment.status !== "captured") {
            console.warn(`moyasarWebhook: payment ${payment.id} status is ${verifiedPayment.status} — skipping`);
            return;
          }

          // Find the order across all collections (idempotent update)
          const collections = [
            {col: "orders", amountField: "amount"},
            {col: "store_orders", amountField: "total_amount"},
            {col: "maintenance_requests", amountField: "amount"},
            {col: "contracts", amountField: "planPrice"},
          ];

          for (const {col, amountField} of collections) {
            const ref = getFirestore().collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists) {
              const data = doc.data();
              // (أمان C1) تحقّق أن المبلغ المدفوع فعلاً = مبلغ الطلب قبل تأكيده.
              // يمنع دفع مبلغ صغير (بمفتاح النشر) وربطه بطلب كبير لتأكيده مجاناً.
              // نُفضّل final_amount (السعر النهائي الذي قد تعدّله الإدارة لطلب متجر)
              // على المبلغ الأساسي — وإلا رُفضت دفعة حقيقية عند تعديل السعر.
              const expectedHalalas = amounts.toHalalas(
                  amounts.expectedAmount(data, amountField));
              if (expectedHalalas <= 0 || verifiedPayment.amount !== expectedHalalas) {
                console.error(
                    `moyasarWebhook: AMOUNT MISMATCH order ${orderId} in '${col}' — ` +
                    `paid ${verifiedPayment.amount} halalas, expected ${expectedHalalas}. NOT confirming.`);
                await ref.update({
                  payment_amount_mismatch: true,
                  updated_at: FieldValue.serverTimestamp(),
                }).catch(() => {});
                // أبلغ الإدارة — إشارة احتيال محتملة تحتاج مراجعة/تسوية يدوية.
                await queuePush(
                    "ADMIN_BROADCAST",
                    "تنبيه: عدم تطابق مبلغ دفع ⚠️",
                    `الطلب #${(data.code || orderId).toString()} استلم مبلغاً مختلفاً عن المطلوب — يحتاج مراجعة.`,
                    "admin_payment_alert", {orderId}, ["accountant_admin"]).catch(() => {});
                break;
              }
              if (data.is_paid) {
                console.log(`moyasarWebhook: Order ${orderId} already paid — skipping (idempotent)`);
              } else {
                // **تحقّقُ السعرِ الخادميُّ هنا أيضاً.** فحصُ المبلغِ أعلاه
                // يُقارنُ «المدفوعَ بالمُعلَن»، و`expectedAmount` كلُّ حقولِه
                // يَكتبها العميلُ عند الإنشاء — فمُعلِنُ ريالٍ يَدفعُ ريالاً
                // ويَمرّ. وإعادةُ التسعيرِ من مستندِ المنطقةِ كانت في
                // `verifyMoyasarPayment` وحدَه، وهو يَرتدُّ على `is_paid`
                // **قبلَ** فحصِه — فالويب هوكُ إن سَبَقَ (وتُطلقه ميسر من
                // خادمٍ إلى خادمٍ لحظةَ الدفع) استَهلكَ الفحصَ كلَّه، ومُتلاعبٌ
                // لا يُنادي النداءَ أصلاً.
                // طلبُ المتجر: سلّتُه تُعاد تسعيرُها من `products`. وسمٌ
                // وتنبيهٌ لا رفض — انظر ترويسةَ `_verifyStoreOrderPrice`.
                if (col === "store_orders") {
                  await _verifyStoreOrderPrice(getFirestore(), ref, orderId,
                      data, Number(verifiedPayment.amount) / 100, "webhook");
                }
                let tierB = null;
                if (col === "orders") {
                  const method = data.payment_method || "";
                  const paidSar = Number(verifiedPayment.amount) / 100;
                  const skipPv = data.server_created_from_payment === true ||
                    ["wallet", "subscription", "tamara", "tabby"]
                        .includes(method) || !(paidSar > 0);
                  if (!skipPv) {
                    tierB = await _verifyOrderPriceTierA(
                        getFirestore(), ref, orderId, data, paidSar, "webhook");
                  }
                }
                // **Tier A هنا، وTier B لا — وهذا قرارٌ لا سهو.** الوسمُ
                // والتنبيهُ بلا رجعةٍ ماليّة، فيَعملانِ على كلِّ مسلك (وهو
                // عينُ سياسةِ مسارِ المحفظة: «يَسِمُ ويَتّكلُ على المسحِ
                // الدوريّ»). أمّا Tier B فيُلغي أو يَستردُّ بطاقةَ عميلةٍ بلا
                // إنسانٍ في الحلقة، وسندُ تفعيلِه (رأسُ الملفّ: «صفرُ إنذارات
                // طوال فترة المراقبة») جُمع من مسارِ النداءِ وحدَه — وإن كان
                // الويب هوكُ يَسبقُه كثيراً فتلك العيّنةُ **لا تُغطّي سكّانَ
                // هذا المسلك أصلاً**. فتفعيلُه هنا قرارُ المالكِ بعد أن
                // تُظهرَ سجلّاتُ `[price-shadow:webhook]` أنّ السلوكَ واحد:
                // سطرٌ واحدٌ يُعيدُ النداءَ المحجوبَ أدناه.
                if (tierB) {
                  console.warn(`[price-shadow:webhook] TIER_B_WOULD_BLOCK ${orderId} — Tier A وُسم وأُنبِئ؛ الإنفاذُ من هذا المسلك مؤجَّلٌ بقرار`);
                }
                // (سباق) فحص + تحديث داخل Transaction لمنع معالجة الدفعة مرتين
                const flipped = await getFirestore().runTransaction(async (tx) => {
                  const snap = await tx.get(ref);
                  const cur = snap.data() || {};
                  if (cur.is_paid) return false;
                  // (#1) لا يُحيي الويب هوك طلباً حُجب لتلاعبٍ سعري أو استُرد/أُلغي.
                  if (cur.tamper_blocked === true ||
                      ["voided", "refunded", "payment_review"]
                          .includes(cur.payment_status)) {
                    return false;
                  }
                  tx.update(ref, {
                    payment_status: "paid",
                    is_paid: true,
                    moyasar_payment_id: payment.id,
                    moyasar_status: verifiedPayment.status,
                    updated_at: FieldValue.serverTimestamp(),
                    ...refunds.reopenFieldsIfSystemCancelled(snap.data()),
                  });
                  return true;
                });
                if (flipped) {
                  console.log(`moyasarWebhook: Order ${orderId} in '${col}' marked PAID via webhook`);
                  await notifyClientPaymentResult(col, orderId, data, true); // (F2)
                }
              }
              break;
            }
          }
        } else if (eventType === "payment_failed" || eventType === "payment_abandoned") {
          console.log(`moyasarWebhook: payment ${payment.id} for order ${orderId} — status: ${eventType}`);
          // (F2) أبلغ العميل بالفشل الفعلي فقط (لا عند مجرد المغادرة abandoned)
          if (eventType === "payment_failed") {
            const found = await _findOrder(orderId);
            if (found && !found.data.is_paid) {
              await notifyClientPaymentResult(found.col, orderId, found.data, false);
            }
          }
        } else if (eventType === "payment_refunded") {
          // Find and mark the order as refunded
          const collections = ["orders", "store_orders", "maintenance_requests", "contracts"];
          for (const col of collections) {
            const ref = getFirestore().collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists) {
              const rd = doc.data();
              // idempotent: مُسترَد سلفاً → لا تكرار (الاسترداد الجزئي يُرسل أحداثاً متعددة).
              if (rd.payment_status === "refunded") break;
              await ref.update({
                payment_status: "refunded",
                moyasar_status: "refunded",
                updated_at: FieldValue.serverTimestamp(),
              });
              console.log(`moyasarWebhook: Order ${orderId} marked REFUNDED via webhook`);
              // إشعار العميل باسترداد البطاقة (كان صامتاً — المحفظة فقط تُشعر).
              const rUid = rd.client_id || rd.userId;
              if (rUid) {
                await queuePush(rUid, "تم استرداد مبلغكِ 💳",
                    `أعدنا مبلغ الطلب #${(rd.code || orderId).toString()} إلى بطاقتكِ. قد يستغرق ظهوره أياماً وفق مصرفكِ.`,
                    "payment_update", {orderId}).catch(() => {});
              }
              break;
            }
          }
        } else {
          console.log(`moyasarWebhook: unhandled event type '${eventType}' — ignoring`);
        }
      } catch (error) {
        console.error("moyasarWebhook processing error:", error);
        // Do NOT re-throw — response already sent 200, Moyasar won't retry
      }
    },
);

// ── Moyasar Payment Operations (admin-only callable functions) ─────────────────
// These use the SECRET key and are only callable by authenticated admin users.
// Firestore rule: caller must have role == 'super_admin' or 'orders_manager'.
// النقل الخام (fetch/الترويسة/المسارات) في `moyasar_api.js`، وسياسةُ الاسترداد
// الآلي في `refund_engine.js`؛ ما يبقى هنا أغلفةُ onCall وحدها. (ثلاثةُ تعليقاتٍ
// كانت هنا تَصِف شيفرةً انتقلت في الشريحتين الأولى والثانية — أُزيلت.)


// حذف سائق نهائياً (بطلب المالك: أيقونة الحذف تحذف فعلاً ولا يبقى ظاهراً).
// خادمي إجبارياً: حذف مستند drivers من العميل يترك حساب Auth حيّاً، وبوّابة الطرد
// في لوحة السائق تشترط وجود المستند (`snapshot.data!.exists`) فتفشل مفتوحةً ويبقى
// المطرود داخلاً. حذف حساب Auth هو ما يُغلق الباب فعلاً، وهو حكر على Admin SDK.
/**
 * حذفُ كائنٍ من المخزنِ — إداريٌّ وخادميٌّ حصراً.
 *
 * **سببُ وجودِها.** `storage.rules` لا تَستطيعُ قراءةَ Firestore، فلا سبيلَ
 * فيها إلى معرفةِ الدور — وكانت قواعدُ `banners/` و`products/` و
 * `worker_photos/` تَقول `allow write/delete: if request.auth != null`:
 * **أيُّ عميلةٍ مسجَّلةٍ تَحذفُ كلَّ بنرٍ وكلَّ صورةِ منتجٍ في المتجر**،
 * وتَستبدلُها بما شاءت. وهي محتوًى إداريٌّ يُعرَضُ لكلِّ العملاء.
 *
 * والمخرجُ بلا «custom claims» (لا يَضبطُها المشروعُ اليوم، وإدخالُها
 * يَكسرُ حسابات الموظّفين القائمةَ حتى تُعادَ تهيئتُها) أن يَصيرَ الحذفُ
 * خادميّاً: القواعدُ تَمنعُ حذفَ العميلِ، وهذه الدالّةُ تَحذفُ بـAdmin SDK
 * بعدَ `_assertAdmin` — نفسُ نمطِ `deleteDriverAccount` (حذفُ Auth حكرٌ على
 * Admin SDK، فالزرُّ العميليُّ كان يَترُكُ الحسابَ حيّاً).
 *
 * والبادئاتُ **قائمةُ سماحٍ** لا منع: مسارُ الفواتيرِ ومسارُ إثباتِ الإكمالِ
 * خارجَها عمداً — لا مسوّغَ لحذفِهما من واجهةٍ، وفاتورةُ ZATCA مستندٌ ضريبيّ.
 */
exports.deleteStorageObject = onCall({cpu: 0.083}, async (request) => {
  await _assertAdmin(request);
  const raw = request.data && (request.data.url || request.data.path);
  if (!raw || typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "رابط الملف مطلوب");
  }
  // الرابطُ يُفكَّكُ بنفسِ حارسِ المرفقات (`attachments.js`) — فحصُ المضيفِ
  // والدلوِ مكتوبٌ هناك، ونسخةٌ ثانيةٌ منه هي ما يُحذّرُ منه هذا المستودع.
  const path = raw.startsWith("http") ?
    attachmentsGuard.storageObjectPath(raw, PROJECT_ID) :
    (raw.startsWith("/") || raw.includes("..") ? null : raw);
  if (!path) {
    throw new HttpsError("invalid-argument", "رابط غير صالح لمخزن المشروع");
  }
  const ALLOWED_PREFIXES = ["banners/", "products/", "worker_photos/"];
  if (!ALLOWED_PREFIXES.some((p) => path.startsWith(p))) {
    throw new HttpsError("permission-denied",
        "الحذف مسموح لصور البنرات والمنتجات والعاملات فقط");
  }
  try {
    await getStorage().bucket().file(path).delete();
  } catch (e) {
    // **عديمُ الأثرِ التكراريِّ**: كائنٌ غائبٌ ليس فشلاً — الشاشةُ تَحذفُ
    // مستندَ Firestore أوّلاً، فإعادةُ المحاولةِ بعد انقطاعٍ تَجدُ الكائنَ
    // محذوفاً سلفاً وكانت سَتُظهِرُ خطأً لا معنى له.
    if (e && (e.code === 404 || e.code === "404")) {
      return {deleted: false, missing: true};
    }
    console.error("[storage] delete failed:", path, e.message);
    throw new HttpsError("internal", "تعذّر حذف الملف من المخزن");
  }
  return {deleted: true, path};
});

exports.deleteDriverAccount = onCall({cpu: 0.083}, async (request) => {
  await _assertAdmin(request);
  const driverId = request.data && request.data.driverId;
  if (!driverId) {
    throw new HttpsError("invalid-argument", "معرّف السائق مطلوب");
  }
  const db = getFirestore();
  const driverRef = db.collection("drivers").doc(driverId);
  const driverSnap = await driverRef.get();
  if (!driverSnap.exists) {
    throw new HttpsError("not-found", "السائق غير موجود");
  }

  // حارس تكامل: حذف سائق وسط مهمة حيّة يترك الطلب بلا منفّذ والعميل يتتبّع
  // سائقاً غير موجود. نمنع الحذف ونطلب إعادة الإسناد أولاً — لا نحذف بصمت.
  const ACTIVE = ["assigned", "accepted", "on_the_way", "in_progress", "scheduled"];
  // الحارسُ نفسُه يَسألُ «> 0» فحسب، لكنّ **الرسالةَ تَطبعُ رقماً** — وكان
  // `limit(5)` لكلِّ مجموعةٍ يَسقُفُه عند عشرة: فسائقٌ عليه اثنتا عشرةَ مهمّةً
  // حيّةً يُقالُ للأدمنِ «لديه ١٠ طلب نشط»، فيُعيدُ إسنادَ عشرٍ ويَظنُّ أنّه
  // أفرغَه. وهي عائلةُ «لا رقمَ قبل أن نعرفه» بعينِها، فالعدُّ خادميٌّ الآن:
  // مساواةٌ + `in` بلا مدًى ⇒ لا فهرسَ مركَّب (كما كان الاستعلامُ المقصوص)،
  // وقراءةٌ واحدةٌ أرخصُ من خمسةِ مستندات.
  const activeCounts = await Promise.all(
      ["orders", "store_orders"].map((col) => db.collection(col)
          .where("driver_id", "==", driverId)
          .where("status", "in", ACTIVE)
          .count().get().then((a) => a.data().count)),
  );
  const activeCount = activeCounts.reduce((n, c) => n + c, 0);
  if (activeCount > 0) {
    throw new HttpsError("failed-precondition",
        `لا يمكن حذف السائق: لديه ${activeCount} طلب نشط — أعد إسنادها لسائق آخر أولاً.`);
  }

  const name = driverSnap.data().name || driverId;

  // 1) حساب Auth أولاً: لو فشل ما بعده نكون قد أغلقنا الدخول على أي حال.
  let authDeleted = true;
  try {
    await getAuth().deleteUser(driverId);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      // سائق قديم أُضيف من لوحة الويب قبل إصلاح التوفير: مستند بلا حساب Auth.
      authDeleted = false;
    } else {
      throw e;
    }
  }

  // 2) المستندات + رموز الإشعارات (اسمَا المجموعة القديم والجديد).
  await Promise.all([
    driverRef.delete(),
    db.collection("users").doc(driverId).delete().catch(() => {}),
    db.collection("fcm_tokens").doc(driverId).delete().catch(() => {}),
    db.collection("fcm_token").doc(driverId).delete().catch(() => {}),
  ]);

  // **مخطط السجل يجب أن يطابق كاتب العميل** (lib/services/audit_service.dart):
  // كان يُكتب `created_at` واسم إجراء بأحرف صغيرة، وشاشة السجل تُرتّب على
  // `timestamp` — وFirestore يستبعد المستندات التي لا تحمل حقل الترتيب، فكانت كل
  // عمليات الحذف الخادمية **لا تظهر في السجل إطلاقاً**، والاسم الصغير لا يطابق
  // مرشّحات الشاشة (تقارن بأحرف كبيرة) ولا خريطة تسمياتها العربية.
  const actorEmail = (request.auth.token && request.auth.token.email) || "Unknown Admin";
  await db.collection("audit_logs").add({
    action: "DELETE_DRIVER",
    admin_email: actorEmail,
    actor_id: request.auth.uid,
    target_id: driverId,
    details: {name, auth_deleted: authDeleted},
    timestamp: FieldValue.serverTimestamp(),
    platform: "Cloud Function (deleteDriverAccount)",
  }).catch(() => {});

  return {deleted: true, name, authDeleted};
});

// ─────────────────────────────────────────────────────────────────────────────
// حذفُ موظّفٍ كان ثلاثةَ مساراتٍ، ولا واحدٌ منها كاملاً — والنقصُ يَترك
// جهازَه مشتركاً في تنبيهاتِ الإدارةِ إلى الأبد (2026-10-05)
//
// `fcm_tokens/{uid}` يَحملُ **نسخةً** من `role` و`staff_role`، وتوجيهُ البثِّ
// وتنبيهاتِ `ADMIN_BROADCAST` يَستعلمُ عليها (`where("role","in",[…])` و
// `where("staff_role","in",…)`). وكاتبُ تلك النسخةِ **واحدٌ**: تطبيقُ
// المستخدمِ نفسِه عند الإقلاع أو الدخول أو تدويرِ الرمز.
//
// فحذفُ الموظّفِ كان:
//   • `admin_managers_screen`: يَحذفُ `admins/{id}` و`users/{id}` — ولا Auth
//     ولا رمزَ الإشعارات.
//   • `Admins.tsx`: يَحذفُ `users/{id}` وحدَه — ولا `admins` ولا Auth ولا رمز.
//   • `deleteDriverAccount` (السائق): يَحذفُ الأربعةَ كاملةً، وتعليقُه
//     يُسمّي تنظيفَ الرمزِ بالاسم.
//
// فالقاعدةُ مُنفَّذةٌ في واحدٍ من ثلاثة — شكلُ `isAssignableDriver` (اثنان من
// أربعة) ومفاتيحِ الإصدارِ بعينِه. والأثرُ **لا يُصحِّحُ نفسَه**: بزوالِ
// `users/{id}` تَرفضُ القواعدُ أيَّ تحديثٍ للرمزِ (الشرطُ يُقارِنُ بـ
// `getUserData()`، وقراءةُ مستندٍ غائبٍ تَرفضُ الكتابة)، فالرمزُ يَبقى
// موسوماً `admin` ما بقي الجهاز: كلُّ تنبيهٍ إداريٍّ — رقمُ طلبٍ، مبلغٌ، اسمُ
// عميلةٍ، فشلُ استردادٍ، عدمُ تطابقِ سعرٍ — يَصِلُ هاتفَ مَن أُقصي.
//
// وحسابُ Auth كان يَبقى حيّاً كذلك، فيَستطيعُ الدخولَ (ولا يَرى شيئاً:
// `users/{id}` غائبٌ فتَرفضُه القواعدُ وشاشةُ الدور) — لكنّ الإشعاراتَ تَصِل.
//
// **والحارسُ الحقيقيُّ هو المُشغّلُ أدناه لا هذا النداء**: ثلاثةُ مساراتٍ
// اليومَ وربعُها غداً، والكونسول رابعٌ لا شفرةَ فيه. فالنداءُ للاكتمالِ
// الفوريِّ (Auth + المستندات) والمُشغّلُ لئلّا يَبقى مسارٌ بلا تنظيف.
exports.deleteStaffAccount = onCall({cpu: 0.083}, async (request) => {
  // **مدير عام فقط** — القواعدُ تَحصرُ الكتابةَ على `admins` بـ`isSuperAdmin()`
  // (أي `getUserRole() in ['admin','super_admin']`)، و`_assertAdmin` يُجيزُ
  // `orders_manager` كذلك: فاستعمالُه هنا كان سيَمنحُ مديرَ الطلباتِ حذفَ
  // الموظّفين — أوسعَ من القواعد، وهو بعينُه ما يَمنعُه
  // `panel_role_rules_sync_test`.
  const {uid: actorUid, email: actorEmail} =
      await _assertSuperAdmin(request);
  const db = getFirestore();

  const staffId = request.data && request.data.staffId;
  if (!staffId) {
    throw new HttpsError("invalid-argument", "معرّف الموظّف مطلوب");
  }
  // حارسُ تكامل، نظيرُ «لديه طلبات نشطة» في مسارِ السائق: مديرٌ عامٌّ يَحذفُ
  // نفسَه يُقفلُ لوحةَ الإدارةِ على الجميع إن كان الأخير، ولا مسارَ استعادةٍ
  // في التطبيق — فلا نَحذفُ بصمتٍ ونَطلبُ حساباً آخر.
  if (staffId === actorUid) {
    throw new HttpsError("failed-precondition",
        "لا يمكنك حذف حسابك — اطلب من مدير عام آخر حذفه.");
  }

  const userRef = db.collection("users").doc(staffId);
  const [adminSnap, userSnap] = await Promise.all([
    db.collection("admins").doc(staffId).get(),
    userRef.get(),
  ]);
  if (!adminSnap.exists && !userSnap.exists) {
    throw new HttpsError("not-found", "الموظّف غير موجود");
  }
  const name = (adminSnap.exists && adminSnap.data().name) ||
      (userSnap.exists && userSnap.data().name) || staffId;

  // 1) Auth أوّلاً: لو فشلَ ما بعدَه نكونُ قد أغلقنا الدخولَ على أيِّ حال —
  //    نفسُ ترتيبِ مسارِ السائقِ ولنفسِ السبب.
  let authDeleted = true;
  try {
    await getAuth().deleteUser(staffId);
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      // موظّفٌ قديمٌ أُضيف قبل أن يُوفَّرَ الحسابُ عبر `createAccountViaAdmin`.
      authDeleted = false;
    } else {
      throw e;
    }
  }

  // 2) المستندات + رموزُ الإشعاراتِ (اسمَا المجموعةِ القديمُ والجديد).
  await Promise.all([
    db.collection("admins").doc(staffId).delete().catch(() => {}),
    userRef.delete().catch(() => {}),
    db.collection("fcm_tokens").doc(staffId).delete().catch(() => {}),
    db.collection("fcm_token").doc(staffId).delete().catch(() => {}),
  ]);

  // مخطّطُ السجلِّ يُطابقُ كاتبَ العميل (`lib/services/audit_service.dart`):
  // شاشةُ السجلِّ تُرتّبُ على `timestamp` وتُقارِنُ الإجراءَ بأحرفٍ كبيرة.
  await db.collection("audit_logs").add({
    action: "DELETE_STAFF",
    admin_email: actorEmail,
    actor_id: actorUid,
    target_id: staffId,
    details: {name, auth_deleted: authDeleted},
    timestamp: FieldValue.serverTimestamp(),
    platform: "Cloud Function (deleteStaffAccount)",
  }).catch(() => {});

  return {deleted: true, name, authDeleted};
});

// نسخةُ الدورِ على رمزِ الإشعاراتِ كان كاتبُها **واحداً**: تطبيقُ المستخدم.
// فترقيةُ عميلةٍ إلى مديرةِ طلباتٍ — أو تغييرُ دورٍ فرعيٍّ — لا تَبلغُ
// `fcm_tokens/{uid}` حتى يُعيدَ صاحبُها تشغيلَ التطبيق: فالمُرقَّى **لا
// تَصِلُه تنبيهاتُ الإدارةِ** (توجيهُ `ADMIN_BROADCAST` يُرشِّحُ على
// `staff_role`)، والمُنزَّلُ يَظلُّ يَستقبلُها. وهذا المُشغّلُ هو ما يُغني عن
// تذكّرِ كلِّ مسارٍ: يَغطّي الشاشةَ واللوحةَ والكونسولَ وما يُكتَبُ غداً.
//
// الحذفُ هنا شبكةُ أمانٍ لا بديلٌ عن `deleteStaffAccount`: ذاك يَحذفُ Auth
// (وهو ما لا يَقدِرُ عليه مُشغّلٌ أو عميل) ويُدوّنُ السجلّ.
/**
 * الحِمْلُ الذي يُوسَمُ به رمزُ الإشعاراتِ من مستندِ المستخدم — **موضعٌ
 * واحدٌ بمُنادِيَين**: المُشغّلُ عند تغييرِ الدور، ومكنسةُ الانحرافِ في
 * `opsHealthSweep`. كُتبَ مرّةً في كلٍّ منهما أوّلاً، وهو عينُ «قرارٌ
 * مكتوبٌ مرّتَين يَنحرِف» الذي يَتكرّرُ في هذا المستودع.
 * @param {Record<string, unknown>|null} u مستندُ `users/{uid}`.
 * @return {Record<string, unknown>} حِمْلُ الوسمِ.
 */
function _tokenRolePayload(u) {
  return {
    role: (u && u.role) || "client",
    staff_role: (u && u.staff_role) || null,
    role_synced_at: FieldValue.serverTimestamp(),
  };
}

/**
 * هل وسمُ الرمزِ يُخالِفُ مستندَ المستخدم.
 * @param {Record<string, unknown>} tok مستندُ `fcm_tokens/{uid}`.
 * @param {Record<string, unknown>|null} u مستندُ `users/{uid}`.
 * @return {boolean} صحيحٌ متى انحرفَ أحدُ الحقلَين.
 */
function _tokenRoleDrifted(tok, u) {
  const want = _tokenRolePayload(u);
  return (tok.role || null) !== want.role ||
    (tok.staff_role || null) !== want.staff_role;
}

exports.syncRoleToPushToken = onDocumentWritten(
    {document: "users/{uid}", cpu: 0.083},
    async (event) => {
      const uid = event.params.uid;
      const before = event.data && event.data.before &&
          event.data.before.exists ? event.data.before.data() : null;
      const after = event.data && event.data.after &&
          event.data.after.exists ? event.data.after.data() : null;
      const tokRef = getFirestore().collection("fcm_tokens").doc(uid);

      if (!after) {
        // زالَ المستخدم: الرمزُ لا يُصحَّحُ بعدها أبداً (القواعدُ تُقارِنُ
        // بـ`getUserData()`، وقراءةُ غائبٍ تَرفضُ الكتابة) فيَبقى موسوماً
        // بدورِه القديمِ ويَستقبلُ تنبيهاتَ الإدارة.
        await tokRef.delete().catch(() => {});
        return null;
      }
      if (!before) return null; // إنشاءٌ جديد: لا رمزَ بعد.

      const roleChanged = (before.role || null) !== (after.role || null);
      const staffChanged =
          (before.staff_role || null) !== (after.staff_role || null);
      if (!roleChanged && !staffChanged) return null;

      // لا نُنشئُ مستندَ رمزٍ لمن لا رمزَ له — الرمزُ نفسُه يَكتبُه الجهاز.
      const tokSnap = await tokRef.get();
      if (!tokSnap.exists) return null;
      await tokRef.set(_tokenRolePayload(after), {merge: true})
          .catch(() => {});
      return null;
    });

/** Helper: verify caller is admin (super_admin or orders_manager) */
async function _assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const userDoc = await getFirestore().collection("users").doc(uid).get();
  if (!userDoc.exists) {
    throw new HttpsError("permission-denied", "المستخدم غير موجود");
  }
  // Effective role mirrors the Firestore rules getUserRole(): staff_role is the real
  // role (staff carry role:'admin' + staff_role:'<subrole>'); fall back to role for
  // bootstrapped super admins. Checking only `role` previously rejected every
  // orders_manager (and any admin@ whose role wasn't literally 'super_admin').
  const data = userDoc.data();
  const role = data.staff_role || data.role;
  const allowedRoles = ["admin", "super_admin", "orders_manager"];
  if (!allowedRoles.includes(role)) {
    throw new HttpsError("permission-denied", "صلاحيات إدارية مطلوبة لهذه العملية");
  }
}

/**
 * **المدير العام وحده.** `_assertAdmin` يُجيزُ `orders_manager` كذلك، وبعضُ
 * العمليّاتِ تَحصرُها القواعدُ على `isSuperAdmin()` (مثلاً الكتابةُ على
 * `admins`) — فاستعمالُ الأوّلِ هناك يَمنحُ صلاحيّةً أوسعَ من القواعد، وهو
 * بعينُه ما يُراقبُه `panel_role_rules_sync_test`.
 *
 * والدورُ يُقرأُ **هنا** لا إنلاين عند كلِّ نداء: قاعدةٌ واحدةٌ في موضعٍ
 * واحدٍ (`staff_role` ثمّ `role`، مرآةً لـ`getUserRole()` في القواعد).
 * @param {object} request نداءُ onCall.
 * @return {Promise<{uid: string, email: string}>} هويّةُ الفاعل.
 */
async function _assertSuperAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const userDoc = await getFirestore().collection("users").doc(uid).get();
  if (!userDoc.exists) {
    throw new HttpsError("permission-denied", "المستخدم غير موجود");
  }
  const data = userDoc.data();
  const allowedRoles = ["admin", "super_admin"];
  if (!allowedRoles.includes(data.staff_role || data.role)) {
    throw new HttpsError("permission-denied",
        "هذه العملية للمدير العام فقط");
  }
  return {uid, email: (request.auth.token && request.auth.token.email) ||
      "Unknown Admin"};
}

/** Helper: find order across all collections, return {ref, col, data} or null */
async function _findOrder(orderId) {
  const collections = ["orders", "store_orders", "maintenance_requests", "contracts"];
  for (const col of collections) {
    const ref = getFirestore().collection(col).doc(orderId);
    const doc = await ref.get();
    if (doc.exists) return {ref, col, data: doc.data()};
  }
  return null;
}

// ── Refund ─────────────────────────────────────────────────────────────────────
// Refunds a paid or captured Moyasar payment. Supports full and partial refund.
// Required: paymentId (string), orderId (string)
// Optional: amountHalalas (int) — omit for full refund
exports.moyasarRefundPayment = onCall(
    {secrets: ["MOYASAR_SECRET_KEY"]},
    async (request) => {
      await _assertAdmin(request);

      const {paymentId, orderId, amountHalalas} = request.data;
      if (!paymentId || !orderId) {
        throw new HttpsError("invalid-argument", "paymentId و orderId مطلوبان");
      }

      const secret = moyasarSecretKey.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح Moyasar السري غير مهيأ");
      }

      // Guard against a DOUBLE refund: if this order was already refunded to the
      // wallet (onOrderRewards sets refund_credited) or already refunded via the
      // gateway, reject before hitting Moyasar again.
      // (سباق النقرتين) الفحص ثم النداء كان يسمح لأدمنَين متزامنَين بتمرير الفحص معاً
      // فيُردّ المبلغ مرتين — نطالب براية refund_claimed ذرّياً داخل معاملة قبل نداء
      // Moyasar (نفس نمط المطالبة الذرّية في generateSubscriptionVisits/onOrderRewards)،
      // ونحرّرها عند فشل البوابة كي تبقى إعادة المحاولة ممكنة.
      const existing = await _findOrder(orderId);
      if (existing) {
        await getFirestore().runTransaction(async (tx) => {
          const snap = await tx.get(existing.ref);
          const cur = snap.data() || {};
          if (cur.refund_credited === true) {
            throw new HttpsError("failed-precondition",
                "سبق ردّ هذا الطلب إلى محفظة العميل — لا يمكن ردّه عبر البوابة أيضاً");
          }
          if (cur.payment_status === "refunded" || cur.refund_claimed === true) {
            throw new HttpsError("failed-precondition",
                "سبق استرداد هذا الطلب (أو استردادٌ آخر قيد التنفيذ)");
          }
          tx.update(existing.ref, {
            refund_claimed: true,
            refund_claimed_at: FieldValue.serverTimestamp(),
          });
        });
      }

      // تحرير المطالبة عند أي فشل قبل/من البوابة — وإلا بقيت الراية عالقة وتعذّر
      // الاسترداد نهائياً.
      const releaseClaim = async () => {
        if (!existing) return;
        await existing.ref.update({refund_claimed: false})
            .catch((e) => console.error("moyasarRefund release claim:", e.message));
      };

      // النقل في moyasar_api؛ وعقدُ الخطأ يبقى هنا: نداءٌ من العميل يجب أن
      // يرمي HttpsError، وتحرير المطالبة قبل كل رمي حتى لا يبقى الطلب محجوزاً.
      let res;
      try {
        res = await moyasar.refund(secret, paymentId, amountHalalas);
      } catch (e) {
        await releaseClaim();
        console.error("moyasarRefund network error:", e.message);
        throw new HttpsError("internal", "تعذّر الاتصال ببوابة Moyasar — أعد المحاولة");
      }
      const result = res.result;

      if (!res.ok) {
        await releaseClaim();
        console.error(`moyasarRefund failed ${res.httpStatus}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل استرداد المبلغ من Moyasar");
      }

      // Update Firestore
      const order = await _findOrder(orderId);
      if (order) {
        const refundedAmount = amountHalalas ? amountHalalas / 100 :
          amounts.refundAmount(order.data);
        await order.ref.update({
          payment_status: "refunded",
          // نختم refund_credited أيضاً كي يمنع حارسُ onOrderRewards (refund_credited)
          // إيداعاً ثانياً في المحفظة — الطرفان الآن متماثلان ضدّ الاسترداد المزدوج.
          refund_credited: true,
          // كان الطلب يبقى «مدفوعاً وحيّاً» بعد الاسترداد: is_paid ظلّت true
          // فتَعِد التقارير بمالٍ رُدّ فعلاً، والحالة النشطة تُبقيه في لوحة السائق.
          is_paid: false,
          moyasar_status: result.status,
          refunded_at: FieldValue.serverTimestamp(),
          // المبلغ الحقيقي يختلف بالمجموعة: store=total_amount، عقد=planPrice، غيرها=amount.
          refunded_amount: refundedAmount,
        });
        // العميل كان لا يُشعر بشيء عند استرداد الأدمن من البوابة — بينما كل مسارات
        // الاسترداد الأخرى (webhook/الآلي) تُشعره. رسالة واحدة بنفس صيغتها.
        const clientId = order.data.client_id || order.data.userId;
        const code = order.data.code || orderId;
        if (clientId) {
          await queuePush(clientId, "تم استرداد مبلغك 💳",
              `أُعيد مبلغ ${refundedAmount.toFixed(2)} ر.س للطلب #${code} ` +
              "إلى وسيلة الدفع الأصلية. قد يستغرق الظهور 5-10 أيام عمل حسب البنك.",
              "order_refunded", {orderId}).catch(() => {});
        }
      }

      console.log(`moyasarRefund: payment ${paymentId} refunded — status: ${result.status}`);
      return {success: true, status: result.status, refundedAmount: result.amount};
    },
);

/**
 * (استرداد BNPL) مطالبة ذرّية بالاسترداد على مستند الطلب — نفس حرّاس
 * moyasarRefundPayment حرفياً (refund_credited/refunded/refund_claimed) كي يظلّ
 * منع الاسترداد المزدوج موحّداً عبر البوابات الثلاث، ونفس التحرير عند فشل البوابة.
 * @param {{ref: FirebaseFirestore.DocumentReference}} existing نتيجة _findOrder.
 * @return {Promise<void>} يرمي HttpsError عند استردادٍ سابق/جارٍ.
 */
async function _claimRefund(existing) {
  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(existing.ref);
    const cur = snap.data() || {};
    if (cur.refund_credited === true) {
      throw new HttpsError("failed-precondition",
          "سبق ردّ هذا الطلب إلى محفظة العميل — لا يمكن ردّه عبر البوابة أيضاً");
    }
    if (cur.payment_status === "refunded" || cur.refunded === true ||
        cur.refund_claimed === true) {
      throw new HttpsError("failed-precondition",
          "سبق استرداد هذا الطلب (أو استردادٌ آخر قيد التنفيذ)");
    }
    tx.update(existing.ref, {
      refund_claimed: true,
      refund_claimed_at: FieldValue.serverTimestamp(),
    });
  });
}

/**
 * يحلّ المبلغ الكامل المستحقّ للاسترداد من مستند الطلب — نفس ترتيب حقول
 * moyasarRefundPayment: store=final/total_amount، عقد=planPrice، غيرها=amount.
 * @param {object} data بيانات مستند الطلب.
 * @return {number} المبلغ بالريال (قد يكون 0 إن غابت الحقول).
 */
function _fullRefundAmount(data) {
  return amounts.refundAmount(data);
}

// ── Tamara Refund ──────────────────────────────────────────────────────────────
// استرداد كامل لدفعة تمارا (أقساط) — admin فقط. Required: order_id. Optional: reason.
// يخاطب تمارا بمعرّفها (tamara_order_id المخزَّن عند التأكيد)، مع احتياطي استحضاره
// بمرجعنا (طلبات أُكِّدت قبل تخزينه) — نفس نمط confirmPendingTamaraOrders، ونفس
// السرّ TAMARA_API_TOKEN والقاعدة https://api.tamara.co المستخدمَين فيه.
exports.tamaraRefundPayment = onCall(
    {secrets: ["TAMARA_API_TOKEN"]},
    async (request) => {
      await _assertAdmin(request);

      const orderId = request.data && request.data.order_id;
      const reason = (request.data && request.data.reason) || "استرداد من إدارة زيارة";
      if (!orderId) {
        throw new HttpsError("invalid-argument", "order_id مطلوب");
      }

      const token = tamaraApiToken.value();
      if (!token) {
        throw new HttpsError("failed-precondition", "رمز تمارا غير مهيأ في الخادم");
      }

      const existing = await _findOrder(orderId);
      if (!existing) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب");
      }
      const isTamara = existing.data.payment_method === "tamara" ||
        !!existing.data.tamara_status || !!existing.data.tamara_order_id;
      if (!isTamara) {
        throw new HttpsError("failed-precondition", "هذا الطلب لم يُدفع عبر تمارا");
      }
      const refundAmount = _fullRefundAmount(existing.data);
      if (!(refundAmount > 0)) {
        throw new HttpsError("failed-precondition", "لا مبلغ صالحاً على هذا الطلب لاسترداده");
      }

      // (سباق النقرتين) مطالبة ذرّية قبل نداء البوابة — كما في moyasarRefundPayment.
      await _claimRefund(existing);
      const releaseClaim = async () => {
        await existing.ref.update({refund_claimed: false})
            .catch((e) => console.error("tamaraRefund release claim:", e.message));
      };

      // معرّف تمارا: المخزَّن أولاً، وإلا نستحضره بمرجعنا (طلبات ما قبل التخزين).
      let tamaraOrderId = existing.data.tamara_order_id;
      if (!tamaraOrderId) {
        try {
          const r = await tamara.getOrderByReference(token, orderId);
          if (r.ok) tamaraOrderId = r.order.order_id;
        } catch (e) {
          console.error("tamaraRefund lookup:", e.message);
        }
      }
      if (!tamaraOrderId) {
        await releaseClaim();
        throw new HttpsError("not-found",
            "تعذّر العثور على معرّف طلب تمارا لهذا الطلب — تحقّق من لوحة تمارا");
      }

      // النقل في tamara_api؛ وعقدُ الخطأ يبقى هنا: تحرير المطالبة قبل كل رمي
      // حتى لا يبقى الطلب محجوزاً بلا استرداد.
      let res;
      try {
        res = await tamara.refund(token, tamaraOrderId, refundAmount, reason);
      } catch (e) {
        await releaseClaim();
        console.error("tamaraRefund network error:", e.message);
        throw new HttpsError("internal", "تعذّر الاتصال ببوابة تمارا — أعد المحاولة");
      }
      const result = res.result;

      if (!res.ok) {
        await releaseClaim();
        console.error(`tamaraRefund failed ${res.httpStatus}:`, result);
        const msg = (res.httpStatus === 401 || res.httpStatus === 403) ?
          "رفضت تمارا الاعتماد — تحقّق من رمز TAMARA_API_TOKEN" :
          res.httpStatus === 409 ?
          "ترفض تمارا الاسترداد — يبدو أنه سبق استرداد هذه الدفعة لديها" :
          (result && result.message) ||
            "فشل استرداد المبلغ من تمارا — تحقّق من حالة الطلب في لوحة تمارا";
        throw new HttpsError("internal", msg);
      }

      const refundId = (result && result.refund_id) ||
        (Array.isArray(result && result.refunds) && result.refunds[0] &&
          result.refunds[0].refund_id) || null;
      await existing.ref.update({
        payment_status: "refunded",
        // نختم refund_credited كي يمنع حارسُ onOrderRewards إيداعاً ثانياً في
        // المحفظة — كما في moyasarRefundPayment تماماً.
        refund_credited: true,
        is_paid: false,
        refunded: true,
        tamara_status: "refunded",
        refund_provider: "tamara",
        ...(refundId ? {refund_id: refundId} : {}),
        refund_reason: reason,
        refunded_at: FieldValue.serverTimestamp(),
        refunded_amount: refundAmount,
      });

      const clientId = existing.data.client_id || existing.data.userId;
      const code = existing.data.code || orderId;
      if (clientId) {
        await queuePush(clientId, "تم استرداد مبلغك 💳",
            `أُعيد مبلغ ${refundAmount.toFixed(2)} ر.س للطلب #${code} ` +
            "إلى وسيلة الدفع الأصلية. قد يستغرق الظهور 5-10 أيام عمل حسب البنك.",
            "order_refunded", {orderId}).catch(() => {});
      }

      console.log(`tamaraRefund: order ${orderId} (tamara ${tamaraOrderId}) refunded ${refundAmount} SAR`);
      return {success: true, refundedAmount: refundAmount,
        ...(refundId ? {refundId} : {})};
    },
);

// ── Tabby Refund ───────────────────────────────────────────────────────────────
// استرداد كامل لدفعة تابي — admin فقط. Required: order_id. Optional: reason.
// يعتمد tabby_payment_id الذي يخزّنه tabbyWebhook عند التأكيد، ونفس سرّ تابي
// الوحيد المُهيّأ (TABBY_WEBHOOK_SECRET) والقاعدة https://api.tabby.ai.
exports.tabbyRefundPayment = onCall(
    {secrets: ["TABBY_WEBHOOK_SECRET"]},
    async (request) => {
      await _assertAdmin(request);

      const orderId = request.data && request.data.order_id;
      const reason = (request.data && request.data.reason) || "استرداد من إدارة زيارة";
      if (!orderId) {
        throw new HttpsError("invalid-argument", "order_id مطلوب");
      }

      const secret = tabbyWebhookSecret.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح تابي غير مهيأ في الخادم");
      }

      const existing = await _findOrder(orderId);
      if (!existing) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب");
      }
      const tabbyPaymentId = existing.data.tabby_payment_id;
      if (!tabbyPaymentId) {
        throw new HttpsError("failed-precondition",
            "هذا الطلب لم يُدفع عبر تابي (لا معرّف دفعة تابي عليه)");
      }
      const refundAmount = _fullRefundAmount(existing.data);
      if (!(refundAmount > 0)) {
        throw new HttpsError("failed-precondition", "لا مبلغ صالحاً على هذا الطلب لاسترداده");
      }

      // (سباق النقرتين) مطالبة ذرّية قبل نداء البوابة — كما في moyasarRefundPayment.
      await _claimRefund(existing);
      const releaseClaim = async () => {
        await existing.ref.update({refund_claimed: false})
            .catch((e) => console.error("tabbyRefund release claim:", e.message));
      };

      // تابي: المرتجع وحده — قرار المالك 2026-09-30 (انظر no_tabby_test.dart).
      let res;
      try {
        res = await tamara.tabbyRefund(secret, tabbyPaymentId, refundAmount, reason);
      } catch (e) {
        await releaseClaim();
        console.error("tabbyRefund network error:", e.message);
        throw new HttpsError("internal", "تعذّر الاتصال ببوابة تابي — أعد المحاولة");
      }
      const result = res.result;

      if (!res.ok) {
        await releaseClaim();
        console.error(`tabbyRefund failed ${res.httpStatus}:`, result);
        const msg = (res.httpStatus === 401 || res.httpStatus === 403) ?
          "رفضت تابي الاعتماد — تحقّق من مفتاح تابي في الخادم" :
          res.httpStatus === 409 ?
          "ترفض تابي الاسترداد — يبدو أنه سبق استرداد هذه الدفعة لديها" :
          (result && (result.error || result.message)) ||
            "فشل استرداد المبلغ من تابي — تحقّق من حالة الدفعة في لوحة تابي";
        throw new HttpsError("internal", msg);
      }

      const refunds = Array.isArray(result && result.refunds) ? result.refunds : [];
      const refundId = (refunds.length && refunds[refunds.length - 1].id) || null;
      await existing.ref.update({
        payment_status: "refunded",
        // نختم refund_credited كي يمنع حارسُ onOrderRewards إيداعاً ثانياً في
        // المحفظة — كما في moyasarRefundPayment تماماً.
        refund_credited: true,
        is_paid: false,
        refunded: true,
        tabby_status: "refunded",
        refund_provider: "tabby",
        ...(refundId ? {refund_id: refundId} : {}),
        refund_reason: reason,
        refunded_at: FieldValue.serverTimestamp(),
        refunded_amount: refundAmount,
      });

      const clientId = existing.data.client_id || existing.data.userId;
      const code = existing.data.code || orderId;
      if (clientId) {
        await queuePush(clientId, "تم استرداد مبلغك 💳",
            `أُعيد مبلغ ${refundAmount.toFixed(2)} ر.س للطلب #${code} ` +
            "إلى وسيلة الدفع الأصلية. قد يستغرق الظهور 5-10 أيام عمل حسب البنك.",
            "order_refunded", {orderId}).catch(() => {});
      }

      console.log(`tabbyRefund: order ${orderId} (payment ${tabbyPaymentId}) refunded ${refundAmount} SAR`);
      return {success: true, refundedAmount: refundAmount,
        ...(refundId ? {refundId} : {})};
    },
);

// ── Void ───────────────────────────────────────────────────────────────────────
// Voids an authorized, paid, or captured payment (within the void window).
// Required: paymentId (string), orderId (string)
exports.moyasarVoidPayment = onCall(
    {secrets: ["MOYASAR_SECRET_KEY"]},
    async (request) => {
      await _assertAdmin(request);

      const {paymentId, orderId} = request.data;
      if (!paymentId || !orderId) {
        throw new HttpsError("invalid-argument", "paymentId و orderId مطلوبان");
      }

      const secret = moyasarSecretKey.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح Moyasar السري غير مهيأ");
      }

      // كان `await response.json()` عارياً هنا: ردٌّ غير JSON من وسيطٍ يرمي
      // خطأً خامّاً بدل الرسالة العربية. التحليل في الوحدة متسامح، فيصل
      // `result = {}` و`ok = false` فتُرمى الرسالة المقصودة.
      const res = await moyasar.voidPayment(secret, paymentId);
      const result = res.result;

      if (!res.ok) {
        console.error(`moyasarVoid failed ${res.httpStatus}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل إلغاء عملية الدفع من Moyasar");
      }

      const order = await _findOrder(orderId);
      if (order) {
        await order.ref.update({
          payment_status: "voided",
          moyasar_status: result.status,
          voided_at: FieldValue.serverTimestamp(),
          is_paid: false,
        });
      }

      console.log(`moyasarVoid: payment ${paymentId} voided — status: ${result.status}`);
      return {success: true, status: result.status};
    },
);

// ── Capture ────────────────────────────────────────────────────────────────────
// Captures an authorized (manual: true) Moyasar payment.
// Required: paymentId (string), orderId (string)
// Optional: amountHalalas (int) — omit for full capture
exports.moyasarCapturePayment = onCall(
    {secrets: ["MOYASAR_SECRET_KEY"]},
    async (request) => {
      await _assertAdmin(request);

      const {paymentId, orderId, amountHalalas} = request.data;
      if (!paymentId || !orderId) {
        throw new HttpsError("invalid-argument", "paymentId و orderId مطلوبان");
      }

      const secret = moyasarSecretKey.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح Moyasar السري غير مهيأ");
      }

      // نفس ملاحظة الإلغاء: كان التحليل عارياً.
      const res = await moyasar.capture(secret, paymentId, amountHalalas);
      const result = res.result;

      if (!res.ok) {
        console.error(`moyasarCapture failed ${res.httpStatus}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل تحصيل المبلغ المحجوز من Moyasar");
      }

      const order = await _findOrder(orderId);
      if (order) {
        await order.ref.update({
          payment_status: "captured",
          is_paid: true,
          moyasar_status: result.status,
          captured_at: FieldValue.serverTimestamp(),
        });
      }

      console.log(`moyasarCapture: payment ${paymentId} captured — status: ${result.status}`);
      return {success: true, status: result.status, capturedAmount: result.amount};
    },
);

// ── Tabby Webhook ──────────────────────────────────────────────────────────────
// Receives real-time payment events from Tabby (payment.authorized, payment.captured, etc.)
// Closes the Single Point of Failure where SDK callback could be lost due to:
//   - Network drop after payment and before app receives 'authorized' result
//   - User closing the app from Task Manager while WebView is still open
//   - OS killing the app in the background (screen lock / low memory)
//
// Register this URL in Tabby Merchant Dashboard → Webhooks → Add Webhook.
// Set events: payment.authorized, payment.captured, payment.rejected, payment.expired
// Set the Webhook Secret in Firebase Secret Manager as TABBY_WEBHOOK_SECRET.
//
// Idempotency: if both the SDK callback AND this webhook fire for the same payment,
// the Firestore Transaction (is_paid check) ensures the order is only created once.
exports.tabbyWebhook = onRequest(
    {secrets: ["TABBY_WEBHOOK_SECRET"], cpu: 0.083},
    async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method not allowed"});
      }

      // 1. Verify HMAC-SHA256 signature from x-tabby-signature header
      const crypto = require("crypto");
      const signature = req.headers["x-tabby-signature"] || req.headers["tabby-signature"];
      const secret = tabbyWebhookSecret.value();

      if (!signature) {
        console.warn("tabbyWebhook: rejected — missing signature header");
        return res.status(401).json({error: "Missing signature"});
      }

      // **التوقيعُ على البايتاتِ الخامّةِ لا على إعادةِ تسلسلِها.**
      // `JSON.stringify(req.body)` ليس الجسمَ الذي وقّعه تابي: الجسمُ يُحلَّلُ
      // ثم يُعادُ بناؤه، فتَختلفُ المسافاتُ وتهريبُ اليونيكود وصياغةُ الأرقام
      // — فيَفشلُ HMAC على إشعارٍ شرعيٍّ ويُرَدُّ 401. و`req.rawBody` هو ما
      // تُوفّره Firebase لهذا الغرضِ بعينِه (Buffer بالبايتاتِ كما وصلت).
      // الاحتياطُ باقٍ كي لا يَسوءَ السلوكُ حيث لا يُوفَّرُ الخامّ.
      const rawBody = req.rawBody || JSON.stringify(req.body);
      const expectedSig = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");

      const sigBuf = Buffer.from(String(signature));
      const expBuf = Buffer.from(expectedSig);
      if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
        console.warn("tabbyWebhook: rejected — invalid HMAC signature");
        return res.status(401).json({error: "Invalid signature"});
      }

      // 2. Acknowledge immediately (Tabby expects fast 2xx)
      res.status(200).json({received: true});

      // 3. Process event asynchronously
      try {
        const event = req.body;
        const eventType = event.type; // e.g. "payment.authorized", "payment.captured"
        const payment = event.data?.payment || event.payment || event.data;

        if (!payment || !payment.id) {
          console.warn("tabbyWebhook: missing payment object in event", JSON.stringify(event));
          return;
        }

        const paymentId = payment.id;
        // Tabby stores our reference in order.reference_id
        const orderId = payment.order?.reference_id || payment.reference_id;

        console.log(`tabbyWebhook: event=${eventType} paymentId=${paymentId} orderId=${orderId}`);

        if (!orderId) {
          console.warn(`tabbyWebhook: no reference_id found for payment ${paymentId}`);
          return;
        }

        if (eventType === "payment.authorized" || eventType === "payment.captured") {
          // Idempotent update — check is_paid first inside a Transaction to prevent
          // duplicate order creation if SDK callback and webhook arrive simultaneously
          const db = getFirestore();
          const collections = [
            "orders",
            "maintenance_requests",
            "contracts",
          ];

          for (const col of collections) {
            const ref = db.collection(col).doc(orderId);
            const doc = await ref.get();

            if (doc.exists) {
              const data = doc.data();

              if (data.is_paid) {
                // SDK callback already processed this payment — safe to skip
                console.log(`tabbyWebhook: ${col}/${orderId} already paid — skipping (idempotent)`);
              } else {
                const result = await db.runTransaction(async (tx) => {
                  const snap = await tx.get(ref);
                  const cur = snap.data() || {};
                  if (cur.is_paid) return "already";
                  // (أمان) جلسة تابي تُنشأ من العميل بمبلغ يتحكّم فيه، فنتحقّق أن المبلغ
                  // المدفوع = مبلغ الطلب الحقيقي قبل التأكيد (كما يفعل moyasarWebhook) —
                  // وإلا دفع 1ر.س لطلب كبير وأكّده مجاناً.
                  const expected = amounts.expectedAmount(cur);
                  const paid = Number(payment.amount || 0);
                  if (expected <= 0 || Math.abs(paid - expected) > 0.01) {
                    tx.update(ref, {
                      payment_amount_mismatch: true,
                      updated_at: FieldValue.serverTimestamp(),
                    });
                    return "mismatch";
                  }
                  tx.update(ref, {
                    payment_status: "paid",
                    is_paid: true,
                    tabby_payment_id: paymentId,
                    tabby_status: eventType,
                    updated_at: FieldValue.serverTimestamp(),
                  });
                  return "paid";
                });
                if (result === "paid") {
                  console.log(`tabbyWebhook: ${col}/${orderId} marked PAID via webhook (${eventType})`);
                  await notifyClientPaymentResult(col, orderId, data, true);
                } else if (result === "mismatch") {
                  console.error(`tabbyWebhook: AMOUNT MISMATCH ${col}/${orderId} — NOT confirming.`);
                  await queuePush("ADMIN_BROADCAST", "تنبيه: عدم تطابق مبلغ (تابي) ⚠️",
                      `الطلب #${(data.code || orderId).toString()} استلم مبلغاً مختلفاً عبر تابي — يحتاج مراجعة.`,
                      "admin_payment_alert", {orderId}, ["accountant_admin"]).catch(() => {});
                }
              }
              break; // Found the document — stop searching collections
            }
          }
        } else if (eventType === "payment.rejected" || eventType === "payment.expired" || eventType === "payment.cancelled") {
          // فشل — يشمل كل المجموعات (كان يبحث في orders فقط فتفوت الصيانة/العقد).
          const db = getFirestore();
          for (const col of ["orders", "maintenance_requests", "contracts"]) {
            const ref = db.collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists && !doc.data().is_paid) {
              await ref.update({
                payment_status: "failed",
                tabby_status: eventType,
                updated_at: FieldValue.serverTimestamp(),
              });
              console.log(`tabbyWebhook: ${col}/${orderId} marked FAILED (${eventType})`);
              await notifyClientPaymentResult(col, orderId, doc.data(), false);
              break;
            }
          }
        } else {
          console.log(`tabbyWebhook: unhandled event type '${eventType}' — ignoring`);
        }
      } catch (error) {
        console.error("tabbyWebhook processing error:", error);
        // Do NOT re-throw — response already sent 200, Tabby won't retry on our fault
      }
    },
);
