/* eslint-disable max-len */
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onTaskDispatched} = require("firebase-functions/v2/tasks");
const {getFunctions} = require("firebase-admin/functions");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const geofire = require("geofire-common");
admin.initializeApp();

// Secrets — stored in Firebase Secret Manager, never in source code
const tamaraApiToken = defineSecret("TAMARA_API_TOKEN");
// رمز الإشعارات (Notification Token) — يوقّع به تمارا الـ webhook (JWT/HS256).
// منفصل عن رمز API؛ يُجلب من لوحة تمارا (API keys) ويُضبط بـ functions:secrets:set.
const tamaraNotificationToken = defineSecret("TAMARA_NOTIFICATION_TOKEN");
const resendApiKeySecret = defineSecret("RESEND_API_KEY");
const moyasarSecretKey = defineSecret("MOYASAR_SECRET_KEY");
const moyasarWebhookSecret = defineSecret("MOYASAR_WEBHOOK_SECRET");
const tabbyWebhookSecret = defineSecret("TABBY_WEBHOOK_SECRET");

// 1. Notify user when admin replies to a support ticket
exports.sendNotificationOnTicketReply = onDocumentCreated({document: "support_tickets/{ticketId}/messages/{messageId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const newMessage = snap.data();
      const ticketId = event.params.ticketId;
      const ticketDoc = await admin.firestore().collection("support_tickets")
          .doc(ticketId).get();
      if (!ticketDoc.exists) return null;
      const ticketData = ticketDoc.data();

      // كشف رد الإدارة: تطبيق الأدمن يكتب senderRole:'admin' فقط، ولوحة الويب تكتب
      // senderId:'admin' أيضاً — كان الفحص القديم على senderId فقط يفوّت ردود تطبيق الأدمن
      // فلا يصل العميل إشعار «تم الرد على تذكرتك».
      if (newMessage.senderRole === "admin" || newMessage.senderId === "admin") {
        // رد الدعم → أشعِر صاحب التذكرة (push + سجل داخل التطبيق).
        await queuePush(
            ticketData.userId,
            "تم الرد على تذكرتك 💬",
            "قام الدعم الفني بالرد على تذكرتك للتو.",
            "support_ticket", {ticketId});
      } else {
        // رد العميل → أشعِر الإدارة. لكن تخطَّ الرسالة الأولى (نصّ التذكرة عند إنشائها)
        // لأن sendNotificationToAdminsOnNewTicket يُشعر الإدارة بها أصلاً — منعاً لتنبيهٍ مزدوج.
        const msgs = await admin.firestore().collection("support_tickets")
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

      const rawName = (afterData.client_name || "").trim();
      const greet = ["", "عميل", "عميلة", "عميل زيارة", "عميلة زيارة"]
          .includes(rawName) ? "" : `${rawName}، `;

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
        targetUserId = afterData.client_id;
        title = "تم تأكيد حجزكِ 🎉";
        body = `${greet}دفعتكِ مؤكّدة وحُدِّد موعد خدمتكِ — فريق زيارة سيصلكِ في وقته.`;
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
        targetUserId = afterData.client_id;
        title = "تم إلغاء طلبكِ ⚠️";
        body = `${greet}أُلغي طلبكِ. لأي استفسار نحن بخدمتكِ.`;
      }

      if (!targetUserId) return null;

      // سجلّ الإشعارات داخل التطبيق يُكتب **دائماً وأولاً** — كان بعد فحص التوكن
      // وداخل try الإرسال: عميل بلا توكن FCM (ويب/جهاز جديد/رفض الإذن) لم يكن
      // يفقد الدفعة فحسب بل حتى أثرها في صندوق إشعاراته (كشفته المسرحية: صفر
      // إشعارات سيارات لدى عميل الويب).
      await admin.firestore().collection("notifications").add({
        userId: targetUserId,
        title: title,
        body: body,
        type: "order_update",
        relatedId: orderId,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const tokenDoc = await admin.firestore().collection("fcm_tokens")
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
        await admin.messaging().send(payload);
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
exports.notifyClientOnOrderCancellation = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async () => null);

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
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
      // إيميل + إشعار لكل نقلة (طلبها المالك): تحت المراجعة ⇒ جاري التوصيل ⇒ تم التسليم.
      // بريد العميل من الطلب (يُكتب عند الإنشاء) أو من users كاحتياط للطلبات القديمة؛
      // النوع store_update ضمن wantsEmail فيُرسَل الإيميل مع الإشعار.
      let clientEmail = after.client_email;
      if (!clientEmail) {
        try {
          const u = await admin.firestore().collection("users").doc(clientId).get();
          clientEmail = u.exists ? (u.data() && u.data().email) : null;
        } catch (_) { clientEmail = null; }
      }
      await queuePush(clientId, m.t, `${m.b} (#${code})`, "store_update",
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
 * Deliver a broadcast: push to the target topic + fan out to the `notifications`
 * collection for in-app viewing. Shared by the create-trigger and the scheduler.
 * @param {FirebaseFirestore.DocumentReference} docRef notifications_log doc ref.
 * @param {Object} data Notification payload (title, body, target).
 * @return {Promise<void>}
 */
async function _deliverBroadcast(docRef, data) {
  const {title, body, target = "all"} = data;
  const payload = {
    notification: {title, body},
    data: {click_action: "FLUTTER_NOTIFICATION_CLICK", type: "global_broadcast"},
  };
  try {
    // إرسال لرموز الأجهزة مباشرةً بدل topic — أوثق بكثير: لا يعتمد على اشتراك المواضيع
    // ولا على تأخّر انتشارها (كان سبب عدم وصول البثّ لبعض الأجهزة رغم تسجيلها).
    let tokQuery = admin.firestore().collection("fcm_tokens");
    if (target === "clients") {
      tokQuery = tokQuery.where("role", "==", "client");
    } else if (target === "drivers") {
      tokQuery = tokQuery.where("role", "==", "driver");
    } else if (target === "admins") {
      tokQuery = tokQuery.where("role", "in", ["admin", "super_admin"]);
    }
    const tokSnap = await tokQuery.get();
    const uniqTokens = [...new Set(
        tokSnap.docs.map((d) => d.data().token || d.data().fcmToken).filter(Boolean))];
    let sent = 0; let failed = 0; const invalid = [];
    for (let i = 0; i < uniqTokens.length; i += 500) {
      const chunk = uniqTokens.slice(i, i + 500);
      const resp = await admin.messaging().sendEachForMulticast({
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
    for (const bad of invalid) {
      const q = await admin.firestore().collection("fcm_tokens").where("token", "==", bad).limit(5).get();
      for (const dd of q.docs) await dd.ref.delete().catch(() => {});
    }
    console.log(`broadcast(${target}) tokens: sent=${sent} failed=${failed} cleaned=${invalid.length}`);

    let query = admin.firestore().collection("users");
    if (target === "clients") {
      query = query.where("role", "==", "client");
    } else if (target === "drivers") {
      query = query.where("role", "==", "driver");
    }
    const usersSnap = await query.get();
    let batch = admin.firestore().batch();
    let count = 0;
    for (const userDoc of usersSnap.docs) {
      const notifRef = admin.firestore().collection("notifications").doc();
      batch.set(notifRef, {
        userId: userDoc.id, title, body,
        type: "global_broadcast", isRead: false,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      count++;
      if (count === 400) {
        await batch.commit();
        batch = admin.firestore().batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();

    await docRef.update({
      processed: true, status: "sent",
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Notification delivered for target: ${target}`);
  } catch (error) {
    console.error("Error sending push notification:", error);
    await docRef.update({
      processed: true, status: "error",
      error: error.message || "Unknown error",
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
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
      const db = admin.firestore();
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
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();
      // Single-inequality query (auto-indexed); status is filtered in code so a
      // delivered doc (status:'sent') is never re-sent.
      const due = await db.collection("notifications_log")
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

  const userDoc = await admin.firestore()
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
    await admin.messaging().send({...payload, topic});
    return {success: true, topic, sentAt: new Date().toISOString()};
  } catch (error) {
    throw new HttpsError("internal", error.message);
  }
});

// 4.5 Create Tamara checkout session (server-side — token never exposed to client)
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
      const orderDoc = await admin.firestore().collection("orders").doc(orderId).get();
      if (orderDoc.exists) {
        info = orderDoc.data();
        trueAmount = Number(info.amount);
      } else {
        const storeOrderDoc = await admin.firestore().collection("store_orders").doc(orderId).get();
        if (storeOrderDoc.exists) {
          info = storeOrderDoc.data();
          // final_amount = السعر النهائي بعد تعديل الإدارة (رسوم توصيل مثلاً). كان
          // Tamara تشحن total_amount (سعر السلة) فتُحصّل مبلغاً مختلفاً عمّا وافق عليه العميل.
          trueAmount = Number(info.final_amount ?? info.total_amount);
        } else {
          // العقد/الاشتراك: يُمرَّر معرّفه كـ orderId ويعيش في contracts (planPrice شامل
          // الضريبة). بدون هذا الفرع كان دفع الاشتراك عبر تمارا يفشل بـ not-found — بينما
          // verifyMoyasarPayment و tamaraWebhook يعالجان العقود أصلاً (كان تناقضاً).
          const contractDoc = await admin.firestore().collection("contracts").doc(orderId).get();
          if (contractDoc.exists) {
            info = contractDoc.data();
            trueAmount = Number(info.planPrice);
          }
        }
      }

      if (trueAmount === null || isNaN(trueAmount) || trueAmount <= 0) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب أو أن قيمة المبلغ غير صالحة في السيرفر");
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
        const response = await fetch("https://api.tamara.co/checkout", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
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
          }),
        });

        if (!response.ok) {
          const errText = await response.text();
          console.error(`Tamara API error ${response.status}: ${errText}`);
          throw new HttpsError(
              "internal", "فشل إنشاء جلسة الدفع — تحقق من بيانات الطلب");
        }

        const data = await response.json();
        return {checkoutUrl: data.checkout_url};
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message);
      }
    });

// 5. Tamara Webhook Handler
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

    const code = data?.code || orderId;
    const rawName = (data?.client_name || "").trim();
    const greet = ["", "عميل", "عميلة", "عميل زيارة", "عميلة زيارة"]
        .includes(rawName) ? "" : `${rawName}، `;
    const title = success ? "تم تأكيد دفعتكِ ✅" : "تعذّر إتمام الدفع ⚠️";
    const body = success ?
      `${greet}استلمنا دفعتكِ بنجاح ونبدأ بتجهيز طلبكِ فوراً 🌿` :
      `${greet}لم تكتمل عملية الدفع. يمكنكِ إعادة المحاولة من التطبيق.`;

    // 1) إشعار داخل التطبيق (سجل)
    await admin.firestore().collection("notifications").add({
      userId: clientUid,
      title: title,
      body: body,
      type: "payment_update",
      relatedId: orderId,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 2) Push عبر FCM
    const tokenDoc = await admin.firestore().collection("fcm_tokens")
        .doc(clientUid).get();
    if (!tokenDoc.exists) return;
    const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
    if (!fcmToken) return;

    await admin.messaging().send({
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
async function _tamaraFlipPaid(db, orderRef, eventType) {
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
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (flipped === null) continue;
    if (flipped) {
      console.log(`tamaraWebhook: ${col}/${orderRef} marked PAID (${eventType})`);
      await notifyClientPaymentResult(col, orderRef, data, true);
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

      const db = admin.firestore();
      try {
        if (eventType === "order_approved") {
          // إلزامي: نقل approved→authorised عبر Authorize API، وإلا يبقى الطلب
          // معلّقاً ولا يدخل دورة التسوية (لا نُقبض).
          const authRes = await fetch(
              `https://api.tamara.co/orders/${tamaraOrderId}/authorise`,
              {method: "POST", headers: {
                "Authorization": `Bearer ${tamaraApiToken.value()}`,
                "Content-Type": "application/json",
              }});
          if (!authRes.ok) {
            console.error(`tamaraWebhook: authorise failed ${authRes.status}: ${await authRes.text()}`);
          } else {
            console.log(`tamaraWebhook: order ${tamaraOrderId} authorised`);
            await _tamaraFlipPaid(db, orderRef, eventType);
          }
        } else if (eventType === "order_authorised" || eventType === "order_captured") {
          await _tamaraFlipPaid(db, orderRef, eventType);
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
                  updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const cfg = await admin.firestore().collection("system_configs").doc("main_settings").get();
    const adminEmail = (cfg.exists && cfg.data()?.admin_email ? String(cfg.data().admin_email) : "").toLowerCase();
    if (lower === adminEmail || lower === "admin@zyiarah.com" || lower === "no-reply@zyiarah.com") return true;
  } catch (e) {
    // fall through to user/driver lookups
  }
  const u = await admin.firestore().collection("users").where("email", "==", email).limit(1).get();
  if (!u.empty) return true;
  const d = await admin.firestore().collection("drivers").where("email", "==", email).limit(1).get();
  if (!d.empty) return true;
  return false;
}

// يبني بريد HTML منسّقاً لتنبيهات الإدارة بتفاصيل الطلب/العميل بدل نصّ عارٍ.
// يُرجع null إن لم يكن النوع تنبيهاً إدارياً معروفاً → يُستخدم النص العادي.
async function _buildAdminAlertHtml(type, data) {
  const db = admin.firestore();
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
      } catch (_) { /* التفاصيل الأساسية تكفي إن تعذّر جلب الزيارات */ }
    } else {
      return null;
    }
  } catch (e) {
    console.error("[EMAIL] admin alert html failed:", e.message);
    return null;
  }
  const rowsHtml = rows.map(([k, v]) =>
    `<tr><td style="padding:11px 10px;color:#64748b;font-size:14px;border-bottom:1px solid #f1f5f9">${k}</td>` +
    `<td style="padding:11px 10px;font-weight:bold;color:#1e293b;text-align:left;border-bottom:1px solid #f1f5f9">${v}</td></tr>`).join("");
  return `<div dir="rtl" style="font-family:Tajawal,Arial,sans-serif;max-width:600px;margin:auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0">
  <div style="background:linear-gradient(135deg,#5D1B5E,#8B3D8C);padding:28px;text-align:center">
    <h1 style="color:#fff;margin:0;font-size:22px">${heading} 🔔</h1>
    <p style="color:#e9d5ea;margin:6px 0 0">لوحة إدارة زيارة</p>
  </div>
  <div style="padding:28px">
    <p style="font-size:15px;color:#475569;margin:0 0 8px">وصلك طلب جديد يحتاج مراجعتك — التفاصيل:</p>
    <table style="width:100%;border-collapse:collapse">${rowsHtml}</table>
  </div>
  <div style="background:#f8fafc;padding:14px;text-align:center;color:#94a3b8;font-size:12px">زيارة — إشعار إداري آلي</div>
</div>`;
}

exports.processNotificationTriggers = onDocumentCreated(
    // retry: إعادة المحاولة عند فشل عابر (Resend/FCM) بدل فقد الإشعار للأبد. سجلّ
    // الصندوق (step 1) بمعرّف حتمي كي لا يتكرّر عند الإعادة.
    {document: "notification_triggers/{id}", secrets: ["RESEND_API_KEY"], cpu: 0.25, retry: true},
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const trigger = snap.data();
      if (!trigger || trigger.processed === true) return;

      const {toUid, title, body, type, template, data = {}, targetRoles} = trigger;
      const attachmentUrls = Array.isArray(trigger.attachmentUrls) ? trigger.attachmentUrls : [];
      let recipientEmail =
        trigger.recipientEmail || data.customerEmail || "admin@zyiarah.com";
      // تنبيهات الإدارة تذهب لبريد الإدارة المُهيّأ (admin_email) لا لبريد العميل —
      // كان data.customerEmail قد يوجّه «تنبيه الإدارة» لبريد العميل بالخطأ.
      if (toUid === "ADMIN_BROADCAST") {
        try {
          const cfgA = await admin.firestore()
              .collection("system_configs").doc("main_settings").get();
          const ae = (cfgA.exists && cfgA.data()?.admin_email) ?
            String(cfgA.data().admin_email).trim() : "";
          recipientEmail = ae || "admin@zyiarah.com";
        } catch (_) { recipientEmail = "admin@zyiarah.com"; }
      }

      console.log(`Processing trigger ${event.params.id}`);

      try {
        // SECURITY: notification_triggers قابلة للكتابة من أي عميل (firestore.rules).
        // العميل غير الموثوق لا يجوز أن يخاطب **مستخدماً آخر** — كان بإمكانه انتحال إشعار
        // Push + سجلّ داخل التطبيق باسم زيارة لأي ضحية (تصيّد). نحسب ثقة المُرسِل مرّة
        // (server أو موظّف بدور != client) ونرفض أي trigger موجَّه لغير مُنشئه.
        // (تصلّب ADMIN_BROADCAST يُعالَج على حدة — تدفّقات إدارية شرعية تكتبه.)
        let senderIsTrusted = trigger.createdBy === "server";
        if (!senderIsTrusted && trigger.createdBy) {
          try {
            const cu = await admin.firestore().collection("users")
                .doc(String(trigger.createdBy)).get();
            const r = cu.exists ? cu.data().role : null;
            senderIsTrusted = r != null && r !== "client";
          } catch (_) { senderIsTrusted = false; }
        }
        const targetsOtherUser = toUid && toUid !== "ADMIN_BROADCAST" &&
          toUid !== trigger.createdBy;
        if (!senderIsTrusted && targetsOtherUser) {
          console.warn(`[NOTIF] Refused untrusted trigger from ${trigger.createdBy} to ${toUid}`);
          await snap.ref.update({processed: true, status: "refused_untrusted_recipient"});
          return;
        }

        // 1. Sync to In-App Notification History
        if (toUid && toUid !== "ADMIN_BROADCAST") {
          await admin.firestore().collection("notifications")
              .doc(`trig_${event.params.id}`).set({
                userId: toUid,
                title: title,
                body: (body || "").replace(/<[^>]*>?/gm, ""),
                type: type,
                relatedId: data.orderId || data.code || event.params.id,
                isRead: false,
                sentAt: admin.firestore.FieldValue.serverTimestamp(),
              });
        }
        // 1b. سجلّ تنبيهات الإدارة — تستمع إليه لوحة الويب لحظيّاً (لا FCM/VAPID).
        if (toUid === "ADMIN_BROADCAST") {
          // معرّف حتمي (بدل add): إعادة المحاولة تكتب فوق نفس المستند بدل تكرار التنبيه.
          await admin.firestore().collection("admin_notifications")
              .doc(`admin_trig_${event.params.id}`).set({
                title: title,
                body: (body || "").replace(/<[^>]*>?/gm, ""),
                type: type,
                data: data || {},
                targetRoles: Array.isArray(targetRoles) ? targetRoles : null,
                relatedId: data.orderId || data.ticketId || data.code || event.params.id,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
              const cu = await admin.firestore().collection("users").doc(String(cb)).get();
              const r = cu.exists ? cu.data().role : null;
              emailSenderOk = r != null && r !== "client";
            } catch (_) {
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
          const configDoc = await admin.firestore()
              .collection("system_configs").doc("email_settings").get();
          if (configDoc.exists) {
            fromName = configDoc.data()?.fromName || fromName;
            fromEmail = configDoc.data()?.fromEmail || fromEmail;
          }

          const fromString = `"${fromName}" <${fromEmail}>`;
          const resend = new Resend(resendKey);

          const attachments = [];
          for (const url of attachmentUrls) {
            try {
              const res = await fetch(url);
              if (res.ok) {
                const buf = await res.arrayBuffer();
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

          const {data: resendData, error: resendError} = await resend.emails.send(emailPayload);
          if (resendError) {
            throw new Error(`Resend Error: ${resendError.message}`);
          }
          await snap.ref.update({
            emailStatus: "sent",
            messageId: resendData.id,
            provider: "resend",
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`[EMAIL] Sent. Message ID: ${resendData.id}`);
        }

        // 3. Push Notification via FCM (حارس pushSent يمنع تكرار الدفع عند إعادة المحاولة)
        if (type !== "email" && trigger.pushSent !== true) {
          let targetTokens = [];
          if (toUid === "ADMIN_BROADCAST") {
            const allAdminRoles = ["admin", "super_admin", "orders_manager", "accountant_admin", "marketing_admin"];
            if (Array.isArray(targetRoles) && targetRoles.length > 0) {
              // توجيه فعلي حسب الدور الفرعي: نصفّي بـ staff_role (الدور الحقيقي على
              // التوكن) — الحقل role دائماً 'admin' للموظّفين فلا يصلح للتصفية. نضمّ
              // دائماً المدراء الكبار (role admin/super بلا staff_role) عبر استعلام ثانٍ.
              const [byStaff, bySuper] = await Promise.all([
                admin.firestore().collection("fcm_tokens").where("staff_role", "in", targetRoles).get(),
                admin.firestore().collection("fcm_tokens").where("role", "in", ["admin", "super_admin"]).get(),
              ]);
              const seen = new Set();
              for (const d of [...byStaff.docs, ...bySuper.docs]) {
                const t = d.data()?.fcmToken || d.data()?.token;
                if (t && !seen.has(t)) { seen.add(t); targetTokens.push(t); }
              }
            } else {
              const snap2 = await admin.firestore()
                  .collection("fcm_tokens").where("role", "in", allAdminRoles).get();
              targetTokens = snap2.docs
                  .map((d) => d.data()?.fcmToken || d.data()?.token)
                  .filter((t) => !!t);
            }
          } else if (toUid) {
            const tokenDoc = await admin.firestore()
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
              await admin.messaging().send({...pushMsg, token: targetTokens[0]});
            } else {
              await admin.messaging().sendEachForMulticast({
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
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error(`Error processing trigger ${event.params.id}:`, error);
        const attempts = Number(trigger.attempts || 0) + 1;
        await snap.ref.update({
          processed: false,
          attempts,
          error: error.message,
          lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        // إعادة محاولة محدودة: كل الخطوات أعلاه حتمية/محروسة (in-app بمعرّف حتمي،
        // admin_notifications بمعرّف حتمي، البريد بحارس emailStatus، الدفع بحارس
        // pushSent) — فإعادة التشغيل لا تُكرّر شيئاً. نتوقّف بعد 3 محاولات لمنع
        // عاصفة إعادة المحاولات على فشل دائم (بريد غير صالح مثلاً).
        if (attempts < 3) throw error;
        await snap.ref.update({giveUp: true});
        console.error(`Trigger ${event.params.id} gave up after ${attempts} attempts`);
      }
    });

// 6b. Secure wallet — redeem Qatrat points for balance (server-authoritative).
// The wallet is (currently) client-writable, so this onCall is the trusted path:
// it validates the points server-side and performs the conversion atomically.
// Pairs with the deferred lockdown of the wallets write rule.
exports.redeemQatratPoints = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const pointsToRedeem = Number(request.data && request.data.pointsToRedeem);
  if (!Number.isInteger(pointsToRedeem) || pointsToRedeem < 50) {
    throw new HttpsError("invalid-argument", "الحد الأدنى للاستبدال 50 نقطة");
  }

  const walletRef = admin.firestore().collection("wallets").doc(uid);
  const txRef = walletRef.collection("transactions").doc();

  const result = await admin.firestore().runTransaction(async (t) => {
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
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(txRef, {
      amount: financialCredit,
      points: -pointsToRedeem,
      type: "qatrat_redeem",
      description: `استبدال ${pointsToRedeem} نقطة زيارة برصيد مالي`,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
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
  } catch (_) {
    return null;
  }
}

async function queuePush(toUid, title, body, type, data, targetRoles, recipientEmail) {
  await admin.firestore().collection("notification_triggers").add({
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
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    processed: false,
  });
}

/**
 * Race-safe first-completed-order referral payout. The referral doc's
 * pending->rewarded flip inside the transaction is the single-winner mutex;
 * the referrer credit, ledger row and coupon are all written in the SAME
 * transaction so a crash cannot leave a half-paid referral, and deterministic
 * ids make a redelivery a no-op.
 * @param {string} refereeUid The referee (new user) uid.
 * @param {string} orderId The completed order id.
 * @param {string} orderCode Human order code for messages.
 * @return {Promise<void>}
 */
async function processReferralRewardServer(refereeUid, orderId, orderCode) {
  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);

  // Resolve the referral: deterministic id first, query fallback for legacy
  // random-id docs created before applyReferralCode switched to a fixed id.
  let referralRef = db.collection("referrals").doc(refereeUid);
  if (!(await referralRef.get()).exists) {
    const q = await db.collection("referrals")
        .where("referee_id", "==", refereeUid)
        .where("status", "==", "pending").limit(1).get();
    if (q.empty) return;
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
        rewarded_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      t.update(orderRef, {referral_processed: true});
      t.set(referrerWallet, {
        balance: admin.firestore.FieldValue.increment(REFERRER_REWARD),
        last_updated: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      t.create(bonusTx, {
        amount: REFERRER_REWARD, points: 0, type: "referral_reward",
        description: "مكافأة إحالة صديق أتمّ أول طلب",
        order_id: orderId,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
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
        expiry: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
        target_user_id: refereeUid,
        description: "خصم الإحالة 10% — مكافأة الانضمام",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      return {referrerId, couponCode};
    });
  } catch (e) {
    console.error(`[referral] payout txn failed for ${refereeUid}:`, e.message);
    return;
  }
  if (!payout) return;

  await queuePush(payout.referrerId, "🎁 مكافأة إحالتك وصلت!",
      `أُضيفت ${REFERRER_REWARD} ر.س لمحفظتك مكافأة لإحالة صديق أتمّ أول طلب.`,
      "referral_reward", {orderId: orderId});
  await queuePush(refereeUid, "🎉 كوبون الإحالة جاهز!",
      `حصلت على كوبون خصم 10% على طلبك القادم. الكود: ${payout.couponCode}`,
      "referral_coupon", {coupon_code: payout.couponCode});
}

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

      const db = admin.firestore();
      const orderRef = db.collection("orders").doc(orderId);
      const clientId = after.client_id;
      const amount = Number(after.amount || 0);
      const code = after.code || orderId;

      // ── COMPLETION: Qatrat points (+ referral) ──
      if (completed) {
        if (clientId && amount > 0) {
          const points = Math.round(amount);
          const walletRef = db.collection("wallets").doc(clientId);
          const txRef = walletRef.collection("transactions").doc(`qatrat_${orderId}`);
          let didFlip = false;
          try {
            await db.runTransaction(async (t) => {
              const oSnap = await t.get(orderRef);
              if (oSnap.get("qatrat_granted") === true) return;
              t.set(walletRef, {
                qatrat_points: admin.firestore.FieldValue.increment(points),
                last_updated: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
              t.create(txRef, {
                amount: 0, points: points, type: "qatrat_reward",
                description: `نقاط زيارة مكتسبة من الطلب المكتمل #${code}`,
                order_id: orderId,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
              });
              t.update(orderRef, {
                qatrat_granted: true,
                qatrat_granted_at: admin.firestore.FieldValue.serverTimestamp(),
              });
              didFlip = true;
            });
          } catch (e) {
            console.error(`[rewards] qatrat txn failed for ${orderId}:`, e.message);
          }
          if (didFlip) {
            await queuePush(clientId, "حصلت على نقاط زيارة جديدة! ✨🎈",
                `أضيفت ${points} نقطة زيارة لرصيدك مكافأة على الطلب #${code}.`,
                "qatrat_credit", {orderId: orderId});
          }
        }
        if (clientId) {
          await processReferralRewardServer(clientId, orderId, code);
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
          const walletRef = db.collection("wallets").doc(clientId);
          const txRef = walletRef.collection("transactions").doc(`refund_${orderId}`);
          let didFlip = false;
          try {
            await db.runTransaction(async (t) => {
              const oSnap = await t.get(orderRef);
              // قراءة طازجة داخل المعاملة: إن سبق إيداع المحفظة أو ردّت البوابة الدفعة
              // (payment_status='refunded')، لا نودِع ثانيةً — يمنع استرداداً مزدوجاً
              // (بطاقة + محفظة) حين يسبق ردُّ البوابة تنفيذَ هذه المعاملة. الفحص الخارجي
              // كان يعتمد لقطة حدثٍ قديمة قد تسبق كتابة payment_status='refunded'.
              if (oSnap.get("refund_credited") === true ||
                  oSnap.get("payment_status") === "refunded") return;
              t.set(walletRef, {
                balance: admin.firestore.FieldValue.increment(amount),
                last_updated: admin.firestore.FieldValue.serverTimestamp(),
              }, {merge: true});
              t.create(txRef, {
                amount: amount, points: 0, type: "refund",
                description: `إعادة رصيد للطلب الملغي رقم #${code}`,
                order_id: orderId,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
              });
              t.update(orderRef, {refund_credited: true});
              didFlip = true;
            });
          } catch (e) {
            console.error(`[rewards] refund txn failed for ${orderId}:`, e.message);
          }
          if (didFlip) {
            await queuePush(clientId, "تم إعادة رصيد لمحفظتك 💰",
                `تم إيداع مبلغ ${amount} ر.س في محفظتك للطلب الملغي #${code}.`,
                "wallet_credit", {orderId: orderId});
          }
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

      const db = admin.firestore();
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
              startedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          } else if (afterStatus === "completed") {
            await db.collection("maintenance_requests").doc(maintenanceId).set({
              status: "completed",
              completedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, {merge: true});
          }
        } catch (e) {
          console.error(`[linked] maintenance sync failed for ${orderId}:`, e.message);
        }
      }

      // 2. Subscription visit accounting
      if (isSubscription && clientId) {
        const userRef = db.collection("users").doc(clientId);
        try {
          if (afterStatus === "completed") {
            await db.runTransaction(async (t) => {
              const oSnap = await t.get(orderRef);
              if (oSnap.get("visit_counted") === true) return; // already counted
              const cId = oSnap.get("contract_id");
              t.set(userRef, {
                visits_remaining: admin.firestore.FieldValue.increment(-1),
              }, {merge: true});
              // اخصم من عدّاد العقد نفسه أيضاً كي تعكس بطاقة الباقة رصيدها الفعلي
              if (cId) {
                t.set(db.collection("contracts").doc(cId), {
                  visits_remaining: admin.firestore.FieldValue.increment(-1),
                }, {merge: true});
              }
              t.update(orderRef, {visit_counted: true});
            });
          } else if (afterStatus === "cancelled") {
            await db.runTransaction(async (t) => {
              const oSnap = await t.get(orderRef);
              // Restore ONLY a visit that was actually consumed; a never-completed
              // visit was part of the prepaid batch and must not mint a free visit.
              if (oSnap.get("visit_counted") !== true) return;
              const cId = oSnap.get("contract_id");
              t.set(userRef, {
                visits_remaining: admin.firestore.FieldValue.increment(1),
              }, {merge: true});
              if (cId) {
                t.set(db.collection("contracts").doc(cId), {
                  visits_remaining: admin.firestore.FieldValue.increment(1),
                }, {merge: true});
              }
              t.update(orderRef, {visit_counted: false});
            });
          }
        } catch (e) {
          console.error(`[linked] visit accounting failed for ${orderId}:`, e.message);
        }
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

      const db = admin.firestore();
      const orderRef = change.after.ref;
      const q = await db.collection("promo_codes")
          .where("code", "==", code.toUpperCase()).limit(1).get();
      if (q.empty) return null;
      const promoRef = q.docs[0].ref;

      try {
        await db.runTransaction(async (t) => {
          const oSnap = await t.get(orderRef);
          if (oSnap.get("coupon_counted") === true) return; // already counted
          t.update(promoRef, {uses: admin.firestore.FieldValue.increment(1)});
          t.update(orderRef, {coupon_counted: true});
        });
      } catch (e) {
        console.error(`[coupon] use-count failed for order ${event.params.orderId}:`, e.message);
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

  const db = admin.firestore();
  const walletRef = db.collection("wallets").doc(uid);
  const txRef = orderId ?
    walletRef.collection("transactions").doc(`wallet_pay_${orderId}`) :
    walletRef.collection("transactions").doc();
  const orderRef = orderId ? db.collection("orders").doc(orderId) : null;

  const result = await db.runTransaction(async (t) => {
    const wSnap = await t.get(walletRef);
    if (orderRef) {
      const oSnap = await t.get(orderRef);
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
      last_updated: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    t.set(txRef, {
      amount: -amount, points: 0, type: "payment",
      description: note,
      ...(orderId ? {order_id: orderId} : {}),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (orderRef) {
      t.update(orderRef, {
        is_paid: true,
        payment_status: "paid",
        payment_method: "wallet",
        paid_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return {success: true, newBalance: balance - amount};
  });

  // إشعار العميل بتأكيد الدفع بالمحفظة (كان صامتاً) — بعد نجاح المعاملة، وأول مرّة فقط.
  if (orderId && !result.alreadyPaid) {
    admin.firestore().collection("orders").doc(orderId).get()
        .then((s) => s.exists &&
          notifyClientPaymentResult("orders", orderId, s.data(), true))
        .catch((e) => console.error("notify after wallet pay:", e));
  }
  return result;
});

// 7. Secure Moyasar payment verification on Call function
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
      const authHeader = `Basic ${Buffer.from(secret + ":").toString("base64")}`;

      // نجلب الدفعة من Moyasar أولاً — نحتاج metadata لإنشاء الطلب خادميّاً إن غاب.
      let paymentData;
      try {
        const response = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}`, {
          method: "GET", headers: {"Authorization": authHeader},
        });
        if (!response.ok) {
          const errText = await response.text();
          console.error(`Moyasar API response error ${response.status}: ${errText}`);
          throw new HttpsError("internal", "فشل التحقق من الدفع مع بوابة Moyasar");
        }
        paymentData = await response.json();
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message);
      }
      if (paymentData.status !== "paid") {
        throw new HttpsError("failed-precondition", `حالة عملية الدفع ليست مدفوعة: ${paymentData.status}`);
      }

      const db = admin.firestore();
      const FieldValue = admin.firestore.FieldValue;

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
              const uDoc = await admin.firestore().collection("users")
                  .doc(md.client_id || request.auth.uid).get();
              if (uDoc.exists) clientName = (uDoc.data().name || "").trim();
            } catch (_) {}
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
            hours_contracted: Number(md.hours || 4),
            worker_count: Number(md.worker_count || 1),
            zone_name: md.zone_name || null,
            location: (!isNaN(lat) && !isNaN(lng)) ?
              new admin.firestore.GeoPoint(lat, lng) :
              new admin.firestore.GeoPoint(24.7136, 46.6753),
            created_at: FieldValue.serverTimestamp(),
            server_created_from_payment: true,
            // أعِد بناء تفصيل الخدمة من الـ metadata (وإلّا فُقِد على طلب Apple Pay).
            ...(_parseServiceMeta(md.service_meta_json) ?
              {service_meta: _parseServiceMeta(md.service_meta_json)} : {}),
          };
          if (md.service_date) {
            const sd = new Date(md.service_date);
            if (!isNaN(sd.getTime())) {
              payload.service_date = admin.firestore.Timestamp.fromDate(sd);
              if (isHourly) {
                const pad = (n) => String(n).padStart(2, "0");
                payload.booking_date = `${sd.getFullYear()}-${pad(sd.getMonth() + 1)}-${pad(sd.getDate())}`;
                payload.booking_time_slot = `${pad(sd.getHours())}:00`;
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
      const owner = orderDoc.data().client_id || orderDoc.data().userId;
      if (owner && owner !== request.auth.uid) {
        throw new HttpsError("permission-denied", "لا يمكن تأكيد دفع طلب مستخدم آخر");
      }
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

      // قلب is_paid داخل معامَلة: إشعار مرّة واحدة عند الانتقال false→true.
      const flipped = await db.runTransaction(async (tx) => {
        const snap = await tx.get(orderRef);
        if (snap.data()?.is_paid === true) return false;
        tx.update(orderRef, {
          payment_status: "paid",
          is_paid: true,
          moyasar_payment_id: paymentId,
          moyasar_status: paymentData.status,
          updated_at: FieldValue.serverTimestamp(),
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
    // 1. Delete user from Firebase Auth
    try {
      await admin.auth().deleteUser(uid);
      console.log(`Successfully deleted auth user: ${uid}`);
    } catch (authErr) {
      if (authErr.code === "auth/user-not-found") {
        console.warn(`User ${uid} not found in Firebase Auth`);
      } else {
        throw authErr;
      }
    }

    // 2. Delete user's document from users collection
    await admin.firestore().collection("users").doc(uid).delete();
    console.log(`Successfully deleted users/${uid} document`);

    // 3. Clean up associated FCM tokens (both legacy collection names)
    await admin.firestore().collection("fcm_tokens").doc(uid).delete().catch(() => {});
    await admin.firestore().collection("fcm_token").doc(uid).delete().catch(() => {});

    // 4. Mark the request fully processed
    await admin.firestore().collection("account_deletions").doc(uid).update({
      completed_at: admin.firestore.FieldValue.serverTimestamp(),
      status: "deleted_fully_processed",
    });
    console.log(`Successfully completed deletion workflow for ${uid}`);
  } catch (error) {
    console.error(`Error processing account deletion for user ${uid}:`, error);
    // Record the failure so it can be retried/inspected by an admin
    await admin.firestore().collection("account_deletions").doc(uid).update({
      error: error.message || "Unknown error",
      status: "failed_deletion",
      failed_at: admin.firestore.FieldValue.serverTimestamp(),
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
      const db = admin.firestore();
      const start = afterData.service_date.toDate();
      const hours = Number(afterData.hours_contracted || 4);
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
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
    const ACTIVE_WITH_DRIVER = ["scheduled", "accepted", "on_the_way", "in_progress"];
    const driverFreed = beforeData && afterData &&
        beforeData.driver_id && ACTIVE_WITH_DRIVER.includes(beforeData.status) &&
        (afterData.status === "cancelled" || afterData.status === "completed");
    if (driverFreed) {
      const db = admin.firestore();
      const cutoff = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 60 * 60 * 1000));
      // نفس شكل استعلام المكنسة (فهرس status+service_date قائم).
      const snap = await db.collection("orders")
          .where("status", "==", "pending")
          .where("service_date", ">=", cutoff)
          .limit(25).get();
      const waiting = snap.docs.filter((d) => {
        const o = d.data();
        return o.is_paid === true && !o.driver_id && o.service_date;
      }).slice(0, 5);
      // كل مسار يسجّل — الاختبار الحيّ الأول فشل صامتاً ولم نعرف أي فرع ابتلعه.
      console.log(`onOrderWritten: driver freed by ${event.params.orderId} — ` +
          `${snap.size} pending, ${waiting.length} paid+unassigned`);
      for (const doc of waiting) {
        const o = doc.data();
        const start = o.service_date.toDate();
        const hours = Number(o.hours_contracted || 4);
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
  const summaryRef = admin.firestore().collection("metadata").doc("analytics_summary");

  const updates = {};
  if (deltaRevenue !== 0) updates.total_revenue = admin.firestore.FieldValue.increment(deltaRevenue);
  if (deltaActive !== 0) updates.active_orders = admin.firestore.FieldValue.increment(deltaActive);
  if (deltaCompleted !== 0) updates.completed_orders = admin.firestore.FieldValue.increment(deltaCompleted);

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
    const cfg = await admin.firestore()
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
    const q = admin.firestore().collection("users")
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
 * يجد سائقاً حرّاً لفترة زمنية.
 * - **بلا مناطق**: قرار المالك — السائق يقبل أي طلب يُسنَد إليه، والسعة تُضبط بالسقف
 *   اليومي المتفق عليه مسبقاً (max_orders_per_day) وبعدد السائقين، لا بالجغرافيا.
 *   (وواقعاً لم تُسنَد منطقة لسائق قط: zone_name غائب عن كل السائقين، و assigned_zones
 *   لم يُكتب في أي مكان — كان الترشيح يعمل دائماً على مسار «بلا منطقة».)
 * - الانشغال: السائق مشغول إن كان لديه طلب يتقاطع زمنياً بحالة
 *   scheduled/on_the_way/in_progress/accepted (لا يُحسب الانشغال "الآني" بل تقاطع الفترة).
 * @param {admin.firestore.Firestore} db
 * @param {object} opts {startDateTime, endDateTime}
 * @return {Promise<FirebaseFirestore.QueryDocumentSnapshot|null>}
 */
async function _findFreeDriverForSlot(db, {startDateTime, endDateTime}) {
  // نافذة الانشغال [البداية−24س، النهاية): تلتقط أي مهمة قد تتقاطع زمنياً، بما
  // فيها العابرة لمنتصف ليل UTC. كانت حدود اليوم التقويمي (getFullYear/Month/Date
  // بتوقيت UTC للخادم) تُفوّت مهمة سائقٍ في اليوم السابق UTC (سلوت الرياض
  // 00:00–02:59 = اليوم UTC السابق)، فيُعاد اختيار السائق نفسه ويرفضه الفحص الذرّي
  // فيبقى الطلب المدفوع عالقاً بلا سائق أبداً. (24س تغطي أي مدة مهمة ≤ يوم.)
  const winStart = new Date(startDateTime.getTime() - 24 * 60 * 60 * 1000);

  const driversSnap = await db.collection("drivers").get();
  const eligible = driversSnap.docs.filter((doc) => doc.data().is_active !== false);
  if (eligible.length === 0) return null;

  // بناء مجموعة السائقين المشغولين بطلبات متقاطعة زمنياً
  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", admin.firestore.Timestamp.fromDate(winStart))
      .where("service_date", "<", admin.firestore.Timestamp.fromDate(endDateTime))
      .where("status", "in", ["scheduled", "on_the_way", "in_progress", "accepted"])
      .get();

  const busy = new Set();
  for (const doc of ordersSnap.docs) {
    const data = doc.data();
    if (!data.service_date || !data.driver_id) continue;
    const oStart = data.service_date.toDate();
    const oHours = Number(data.hours_contracted || 4);
    const oEnd = new Date(oStart.getTime() + oHours * 60 * 60 * 1000);
    if (startDateTime < oEnd && oStart < endDateTime) busy.add(data.driver_id);
  }

  for (const doc of eligible) {
    if (busy.has(doc.id)) continue;
    // (H3) تأكّد أن معرّف مستند السائق حساب حقيقي (users/{id} بدور driver).
    // مستند drivers قد يكون مسودّة id ليست uid → إسناده يترك الطلب عالقاً بلا
    // من يراه (تطبيق السائق والقواعد يعتمدان على auth.uid == driver_id).
    const userSnap = await db.collection("users").doc(doc.id).get();
    const role = userSnap.exists ?
      (userSnap.data().staff_role || userSnap.data().role) : null;
    if (role !== "driver") continue;
    return doc;
  }
  return null;
}

/**
 * يتحقق هل سائق محدد حرّ في فترة زمنية (لا يتقاطع مع مهمة أخرى له).
 * يستخدم نفس فهرس مُحدِّد التوفّر (service_date + status) ويصفّي السائق في JS.
 * @param {admin.firestore.Firestore} db
 * @param {string} driverId
 * @param {Date} startDateTime
 * @param {Date} endDateTime
 * @return {Promise<boolean>}
 */
async function _isDriverFreeForSlot(db, driverId, startDateTime, endDateTime) {
  // نفس نافذة _findFreeDriverForSlot: [البداية−24س، النهاية) تلتقط العابر لمنتصف الليل.
  const winStart = new Date(startDateTime.getTime() - 24 * 60 * 60 * 1000);

  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", admin.firestore.Timestamp.fromDate(winStart))
      .where("service_date", "<", admin.firestore.Timestamp.fromDate(endDateTime))
      .where("status", "in", ["scheduled", "on_the_way", "in_progress", "accepted"])
      .get();

  for (const doc of ordersSnap.docs) {
    const data = doc.data();
    if (data.driver_id !== driverId || !data.service_date) continue;
    const oStart = data.service_date.toDate();
    const oEnd = new Date(oStart.getTime() + Number(data.hours_contracted || 4) * 60 * 60 * 1000);
    if (startDateTime < oEnd && oStart < endDateTime) return false; // مشغول
  }
  return true;
}

/**
 * يُسنِد طلباً لسائق بحالة scheduled (التوجيه المباشر).
 * لا يُعدّ السائق مشغولاً الآن — يصبح مشغولاً فقط عند انتقاله إلى on_the_way.
 * @param {admin.firestore.Firestore} db
 * @param {string} orderId
 * @param {FirebaseFirestore.DocumentSnapshot} driverDoc
 * @param {Date} startDateTime
 * @return {Promise<{driverId:string, driverName:string}>}
 */
async function _assignDriverScheduled(db, orderId, driverDoc, startDateTime) {
  const d = driverDoc.data();
  // موعد الرياض (UTC+3): الدوال تعمل بـUTC، فحساب المكوّنات مباشرةً كان يعطي ساعة
  // ناقصة 3 (07:00 بدل 10:00) → تذكير بوقت خاطئ + عدم احتساب الفترة في السعة.
  const riyadh = new Date(startDateTime.getTime() + 3 * 60 * 60 * 1000);
  const bookingDate = `${riyadh.getUTCFullYear()}-` +
    `${String(riyadh.getUTCMonth() + 1).padStart(2, "0")}-` +
    `${String(riyadh.getUTCDate()).padStart(2, "0")}`;
  const timeSlot = `${String(riyadh.getUTCHours()).padStart(2, "0")}:00`;
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
    const slotHours = Number(cur.hours_contracted || 4);
    const slotEnd = new Date(startDateTime.getTime() + slotHours * 60 * 60 * 1000);
    // نافذة [البداية−24س، النهاية): تلتقط مهمّة عابرة لمنتصف ليل UTC، وأيضاً مهمة
    // طويلة (hours_contracted > 8) تبدأ قبل السلوت بأكثر من 8 ساعات (كانت −8 تُفوّتها).
    const winStart = new Date(startDateTime.getTime() - 24 * 60 * 60 * 1000);
    const dayQ = db.collection("orders")
        .where("service_date", ">=", admin.firestore.Timestamp.fromDate(winStart))
        .where("service_date", "<", admin.firestore.Timestamp.fromDate(slotEnd))
        .where("status", "in", ["scheduled", "on_the_way", "in_progress", "accepted"]);
    const daySnap = await tx.get(dayQ);
    for (const d2 of daySnap.docs) {
      const od = d2.data();
      if (od.driver_id !== driverDoc.id || !od.service_date) continue;
      const oStart = od.service_date.toDate();
      const oEnd = new Date(oStart.getTime() + Number(od.hours_contracted || 4) * 60 * 60 * 1000);
      if (startDateTime < oEnd && oStart < slotEnd) return false; // تعارض زمني — لا تُسنِد
    }

    tx.update(orderRef, {
      status: "scheduled",
      driver_id: driverDoc.id,
      driver_name: d.name || "سائق",
      // assigned_driver: شاشات تتبّع العميل تقرأ هذا الحقل — لولاه تُظهر «جاري
      // تعيين سائق» للأبد رغم إسناد السائق.
      assigned_driver: d.name || "سائق",
      driver_phone: d.phone || "000000000",
      assigned_at: admin.firestore.FieldValue.serverTimestamp(),
      scheduled_at: admin.firestore.Timestamp.fromDate(startDateTime),
      // service_date مطلوب حتى يحتسب مُحدِّد التوفّر هذه المهمة ضمن انشغال السائق
      service_date: admin.firestore.Timestamp.fromDate(startDateTime),
      booking_date: bookingDate,
      booking_time_slot: timeSlot,
    });
    return true;
  });
  return {driverId: driverDoc.id, driverName: d.name || "سائق", assigned};
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
  const db = admin.firestore();

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
    tx.update(contractRef, {
      visits_generated: true,
      visits_generated_at: admin.firestore.FieldValue.serverTimestamp(),
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
  const location = c.location || new admin.firestore.GeoPoint(24.7136, 46.6753);
  const hours = Number(c.hours || 4);
  const planName = c.planName || "باقة اشتراك";
  const results = [];

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
      location: location,
      zone_name: zoneName,
      hours_contracted: hours,
      service_date: admin.firestore.Timestamp.fromDate(startDateTime),
      booking_date: v.date,
      booking_time_slot: v.slot,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      reminder_sent: false,
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

  return {generated: schedule.length, results};
});

// ════════════════════════════════════════════════════════════════════════
// Server-side subscription activation — يحلّ محلّ التفعيل العميلي الذي منعته
// قواعد Stage-C (العميل كان يكتب status='active' + visits_remaining بلا تحقّق دفع).
// ════════════════════════════════════════════════════════════════════════

/**
 * يولّد زيارات العقد (طلبات + إسناد سائقين). مشترك؛ لا يرمي — يُعيد {skipped}.
 * @param {admin.firestore.Firestore} db
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
  const location = c.location || new admin.firestore.GeoPoint(24.7136, 46.6753);
  const hours = Number(c.hours || 4);
  const planName = c.planName || "باقة اشتراك";
  const results = [];
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
      location: location,
      zone_name: zoneName,
      hours_contracted: hours,
      service_date: admin.firestore.Timestamp.fromDate(startDateTime),
      booking_date: v.date,
      booking_time_slot: v.slot,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      reminder_sent: false,
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
exports.activateContractOnPaid = onDocumentUpdated({document: "contracts/{contractId}", cpu: 0.25},
    async (event) => {
      const change = event.data;
      if (!change) return null;
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (before.is_paid === true || after.is_paid !== true) return null;
      const db = admin.firestore();
      const contractRef = change.after.ref;
      // مطالبة ذرّية (idempotent) بالتفعيل + التوليد
      const claim = await db.runTransaction(async (tx) => {
        const s = await tx.get(contractRef);
        const c = s.data() || {};
        if (c.visits_generated === true) return null;
        tx.update(contractRef, {
          status: "active",
          activated_at: admin.firestore.FieldValue.serverTimestamp(),
          visits_generated: true,
          visits_generated_at: admin.firestore.FieldValue.serverTimestamp(),
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
            visits_remaining: admin.firestore.FieldValue.increment(pv),
            has_active_subscription: true,
            subscription_total_visits: pv,
            subscription_type: c.planName || "باقة زيارة",
            subscription_expiry: admin.firestore.Timestamp.fromMillis(expiryMs),
          }, {merge: true});
          // عدّادات مستقلّة لكل عقد — كي تعرض الرئيسية بطاقة منفصلة لكل باقة نشطة
          // (الشهرية + الأسبوعية معاً) بدل طمس حقول المستخدم المجمّعة بعضها بعضاً.
          tx.set(contractRef, {
            visits_remaining: pv,
            visits_total: pv,
            expiry: admin.firestore.Timestamp.fromMillis(expiryMs),
          }, {merge: true});
        }
        return c;
      });
      if (!claim) return null;
      // المعرّفات حتمية فإعادة التوليد idempotent. لا نُعيد راية visits_generated عند
      // الفشل حتى لا يتكرّر منح الزيارات — أي نقص يُكمِله مسار إداري.
      try {
        await _generateContractVisits(db, contractRef, claim);
      } catch (e) {
        console.error("activateContractOnPaid generate:", e);
      }
      // إشعار إداري موحّد واحد لكل اشتراك (أسبوعي/شهري) — بريده يسرد جدول كل الزيارات
      // (يُبنى في _buildAdminAlertHtml). داخل الـ claim الذرّي فيُرسل مرة واحدة لكل عقد،
      // ويحلّ محلّ إشعارات «طلب خدمة جديد» المكتومة لكل زيارة.
      await queuePush("ADMIN_BROADCAST", "اشتراك جديد! 📄",
          `اشتراك جديد في (${claim.planName || "باقة"}) — ${Number(claim.planVisits || 0)} ` +
          `زيارة. تفاصيل الجدول في البريد.`,
          "new_contract_admin", {contractId: event.params.contractId},
          ["orders_manager"]).catch(() => {});
      if (claim.userId) {
        await queuePush(claim.userId, "تم تفعيل باقتكِ ✨",
            `فُعِّل اشتراككِ وأُضيفت ${Number(claim.planVisits || 0)} زيارة لحسابكِ.`,
            "contract_activated", {contractId: event.params.contractId}).catch(() => {});
      }
      return null;
    });

// دفع باقة اشتراك بالمحفظة (خادميّاً) — يخصم planPrice ذرّياً ويقلب is_paid على
// العقد، فيُشغّل activateContractOnPaid. القواعد تمنع العميل من فعل ذلك بنفسه.
exports.payContractWithWallet = onCall({cpu: 0.083}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  const uid = request.auth.uid;
  const contractId = request.data && request.data.contractId;
  if (!contractId) throw new HttpsError("invalid-argument", "معرف العقد مطلوب");
  const db = admin.firestore();
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
      last_updated: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    t.set(txRef, {amount: -price, points: 0, type: "payment",
      description: "دفع باقة اشتراك", contract_id: contractId,
      created_at: admin.firestore.FieldValue.serverTimestamp()});
    t.update(contractRef, {is_paid: true, payment_method: "wallet",
      paid_at: admin.firestore.FieldValue.serverTimestamp()});
    return {success: true, newBalance: balance - price};
  });
});

// ════════════════════════════════════════════════════════════════════════
// Admin approve + assign (المسار الثاني: الكنب/المكيفات/المتجر)
// ════════════════════════════════════════════════════════════════════════
exports.approveAndAssignOrder = onCall({cpu: 0.25}, async (request) => {
  await _assertAdmin(request); // super_admin أو orders_manager
  const {orderId, driverId, scheduledIso} = request.data;
  if (!orderId || !driverId || !scheduledIso) {
    throw new HttpsError("invalid-argument", "البيانات ناقصة (الطلب/السائق/الموعد)");
  }
  const startDateTime = new Date(scheduledIso);
  if (isNaN(startDateTime.getTime())) {
    throw new HttpsError("invalid-argument", "موعد غير صالح");
  }
  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);

  const [orderSnap, driverSnap] = await Promise.all([
    orderRef.get(),
    db.collection("drivers").doc(driverId).get(),
  ]);
  if (!orderSnap.exists) throw new HttpsError("not-found", "الطلب غير موجود");
  if (!driverSnap.exists) throw new HttpsError("not-found", "السائق غير موجود");

  const orderData = orderSnap.data();
  if (orderData.status !== "pending") {
    throw new HttpsError("failed-precondition", "لا يمكن اعتماد الطلب بحالته الحالية");
  }
  if (driverSnap.data().is_active === false) {
    throw new HttpsError("failed-precondition", "السائق غير نشط");
  }

  // (الثغرة #2) تأكّد أن السائق المختار حرّ فعلاً في الفترة المطلوبة
  const hours = Number(orderData.hours_contracted || 4);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
  const free = await _isDriverFreeForSlot(db, driverId, startDateTime, endDateTime);
  if (!free) {
    throw new HttpsError(
        "failed-precondition",
        "السائق مشغول بمهمة أخرى في هذا الوقت — اختر سائقاً أو موعداً آخر");
  }

  // (الثغرة #2) Transaction ذرّي: يُعيد فحص حالة الطلب قبل الإسناد لمنع التعيين
  // المزدوج عند موافقة مديرَين على نفس الطلب معاً.
  const d = driverSnap.data();
  // موعد الرياض (UTC+3) — انظر _assignDriverScheduled: حساب المكوّنات بـUTC مباشرةً
  // كان يخزّن ساعة/يوماً خاطئاً في booking_time_slot/booking_date.
  const riyadh = new Date(startDateTime.getTime() + 3 * 60 * 60 * 1000);
  const bookingDate = `${riyadh.getUTCFullYear()}-` +
    `${String(riyadh.getUTCMonth() + 1).padStart(2, "0")}-` +
    `${String(riyadh.getUTCDate()).padStart(2, "0")}`;
  const timeSlot = `${String(riyadh.getUTCHours()).padStart(2, "0")}:00`;

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(orderRef);
    const st = fresh.data()?.status;
    if (st !== "pending") {
      throw new HttpsError("failed-precondition", "تم اعتماد الطلب بالفعل من مدير آخر");
    }
    // (منع الحجز المزدوج) إعادة فحص حرّية السائق ذرّياً داخل المعاملة — الفحص أعلاه
    // خارج المعاملة كان يسمح لموافقتين متزامنتين على طلبين مختلفين بإسناد نفس السائق
    // لفترة متداخلة. النافذة تمتدّ 8س للخلف لالتقاط مهمّة تعبر منتصف ليل UTC.
    const slotEnd = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
    const winStart = new Date(startDateTime.getTime() - 8 * 60 * 60 * 1000);
    const conflictQ = db.collection("orders")
        .where("service_date", ">=", admin.firestore.Timestamp.fromDate(winStart))
        .where("service_date", "<", admin.firestore.Timestamp.fromDate(slotEnd))
        .where("status", "in", ["scheduled", "on_the_way", "in_progress", "accepted"]);
    const conflictSnap = await tx.get(conflictQ);
    for (const d2 of conflictSnap.docs) {
      const od = d2.data();
      if (od.driver_id !== driverId || !od.service_date) continue;
      const oStart = od.service_date.toDate();
      const oEnd = new Date(oStart.getTime() + Number(od.hours_contracted || 4) * 60 * 60 * 1000);
      if (startDateTime < oEnd && oStart < slotEnd) {
        throw new HttpsError("failed-precondition",
            "السائق مشغول بمهمة أخرى في هذا الوقت — اختر سائقاً أو موعداً آخر");
      }
    }
    tx.update(orderRef, {
      status: "scheduled",
      driver_id: driverId,
      driver_name: d.name || "سائق",
      // assigned_driver: شاشات التتبّع تقرأ هذا الحقل — بدونه يعلق العميل على «جاري
      // تعيين سائق» للأبد في مسار الاعتماد اليدوي (كنب/مكيفات/متجر).
      assigned_driver: d.name || "سائق",
      driver_phone: d.phone || "000000000",
      assigned_at: admin.firestore.FieldValue.serverTimestamp(),
      scheduled_at: admin.firestore.Timestamp.fromDate(startDateTime),
      service_date: admin.firestore.Timestamp.fromDate(startDateTime),
      booking_date: bookingDate,
      booking_time_slot: timeSlot,
    });
  });

  return {assigned: true, driverId: driverId, driverName: d.name || "سائق"};
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

      const db = admin.firestore();
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
      const db = admin.firestore();
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
      const db = admin.firestore();
      const now = Date.now();
      const windowStart = new Date(now + 60 * 60 * 1000); // +1h
      const windowEnd = new Date(now + 75 * 60 * 1000); // +1h15m

      const snap = await db.collection("orders")
          .where("status", "==", "scheduled")
          .where("scheduled_at", ">=", admin.firestore.Timestamp.fromDate(windowStart))
          .where("scheduled_at", "<", admin.firestore.Timestamp.fromDate(windowEnd))
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
const _pad2 = (n) => String(n).padStart(2, "0");
// إزاحة +3 ساعات ثم قراءة مكوّنات UTC = توقيت الرياض المحلي.
const _riyadhLocalDate = (ms) => {
  const r = new Date(ms + 3 * 60 * 60 * 1000);
  return `${r.getUTCFullYear()}-${_pad2(r.getUTCMonth() + 1)}-${_pad2(r.getUTCDate())}`;
};

exports.remindClientsUpcomingAppointments = onSchedule(
    {schedule: "every 30 minutes", timeZone: "Asia/Riyadh"},
    async () => {
      const db = admin.firestore();
      const now = Date.now();
      const in24h = new Date(now + 24 * 60 * 60 * 1000);
      // نطاق مفرد على service_date (مُفهرَس تلقائياً) — الحالة تُصفّى في الكود.
      const snap = await db.collection("orders")
          .where("service_date", ">=", admin.firestore.Timestamp.fromDate(new Date(now)))
          .where("service_date", "<=", admin.firestore.Timestamp.fromDate(in24h))
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
        // مناداة العميلة باسمها المسجّل (إن لم يكن اسماً افتراضياً).
        const rawName = (d.client_name || "").trim();
        const greet = ["", "عميل", "عميلة", "عميل زيارة", "عميلة زيارة"]
            .includes(rawName) ? "" : `${rawName}، `;
        const timeStr = d.booking_time_slot ||
          `${_pad2(new Date(apptMs + 3 * 60 * 60 * 1000).getUTCHours())}:00`;

        // وسم اليوم (اليوم/غداً/بعد N أيام) بالتقويم المحلي.
        const apptDateStr = d.booking_date || _riyadhLocalDate(apptMs);
        const dDiff = Math.round(
            (new Date(`${apptDateStr}T00:00:00Z`).getTime() -
             new Date(`${_riyadhLocalDate(now)}T00:00:00Z`).getTime()) / 86400000);
        const dayLabel = dDiff <= 0 ? "اليوم" : dDiff === 1 ? "غداً" : `بعد ${dDiff} أيام`;

        if (hoursUntil > 2.5 && d.client_reminder_24h_sent !== true) {
          // queuePush: يكتب صندوق الوارد دائماً — كان _pushToUid يضبط علم الإرسال
          // ثم يتخطّى بصمت العميل بلا توكن، فيفقد التذكير للأبد ولا يُعاد.
          await queuePush(
              d.client_id,
              "موعد زيارتكِ اقترب 🏡",
              `${greet}موعد «${serviceName}» ${dayLabel} الساعة ${timeStr}. بانتظاركِ 🌿`,
              "appointment_reminder",
              {orderId: doc.id},
          );
          await doc.ref.update({client_reminder_24h_sent: true});
          sent++;
        } else if (hoursUntil > 0 && hoursUntil <= 2.5 &&
                   d.client_reminder_soon_sent !== true) {
          await queuePush(
              d.client_id,
              "اقترب موعد زيارتكِ ⏰",
              `${greet}«${serviceName}» بعد ساعتين (الساعة ${timeStr}). فريقنا في الطريق إليكِ 🚗`,
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
    {schedule: "every 5 minutes", timeZone: "Asia/Riyadh"},
    async () => {
      const db = admin.firestore();
      const now = Date.now();
      const cutoff = admin.firestore.Timestamp.fromDate(new Date(now - 60 * 60 * 1000));
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
        const hours = Number(d.hours_contracted || 4);
        const end = new Date(start.getTime() + hours * 60 * 60 * 1000);
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
      const strandFloor = admin.firestore.Timestamp.fromDate(
          new Date(now - 24 * 60 * 60 * 1000));
      const strandCeil = admin.firestore.Timestamp.fromDate(
          new Date(now - 60 * 60 * 1000));
      const strandSnap = await db.collection("orders")
          .where("status", "==", "pending")
          .where("service_date", ">=", strandFloor)
          .where("service_date", "<", strandCeil).get();
      let alerted = 0;
      for (const doc of strandSnap.docs) {
        const d = doc.data();
        if (d.driver_id || d.is_paid !== true || d.stranded_alerted === true) continue;
        await queuePush(
            "ADMIN_BROADCAST",
            "طلب مدفوع بلا سائق ⚠️",
            `الطلب #${d.code || doc.id} مدفوع وفات موعده بلا إسناد سائق — يلزم تدخّل يدوي.`,
            "admin_order_alert",
            {orderId: doc.id, code: d.code || doc.id});
        await doc.ref.update({stranded_alerted: true});
        alerted++;
      }
      if (alerted) console.warn(`sweepUnassignedPaidOrders: ${alerted} stranded paid order(s) escalated to admin`);
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
      const authHeader = `Basic ${Buffer.from(secret + ":").toString("base64")}`;
      const db = admin.firestore();
      let recovered = 0;
      try {
        const resp = await fetch("https://api.moyasar.com/v1/payments?per=25",
            {method: "GET", headers: {Authorization: authHeader}});
        if (!resp.ok) { console.error("[reconcile] list failed", resp.status); return null; }
        const data = await resp.json();
        // حدّ تجاهل: مدفوعات تجريبية/قديمة تمّ تنظيف طلباتها لا تُعاد مطابقتها أبداً.
        // يُضبط في system_configs/reconcile.ignore_before (ISO). بلا إعداد = السلوك السابق.
        let ignoreBeforeMs = 0;
        try {
          const rc = await db.collection("system_configs").doc("reconcile").get();
          const v = rc.exists ? rc.data().ignore_before : null;
          if (v) ignoreBeforeMs = new Date(v).getTime();
        } catch (e) { /* افتراضياً بلا حدّ */ }
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
            if (foundData.is_paid !== true) {
              const paidH = Math.round(Number(p.amount));
              const expected = Number(
                  foundData.amount ?? foundData.final_amount ??
                  foundData.total_amount ?? foundData.planPrice ?? 0);
              const expectedH = Math.round(expected * 100);
              if (expectedH > 0 && paidH >= expectedH) {
                await foundRef.update({
                  is_paid: true, payment_status: "paid",
                  moyasar_payment_id: p.id, moyasar_status: "paid",
                  updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
              const uDoc = await admin.firestore().collection("users").doc(md.client_id).get();
              if (uDoc.exists) clientName = (uDoc.data().name || "").trim();
            } catch (_) {}
          }
          const payload = {
            code, client_id: md.client_id, client_name: clientName || "عميل زيارة", client_phone: md.client_phone || "",
            service_type: md.service_name || "خدمة زيارة", service_name: md.service_name || "خدمة زيارة",
            amount: amountSar, is_paid: true, payment_status: "paid",
            moyasar_payment_id: p.id, moyasar_status: "paid",
            status: "pending",
            payment_method: (p.source && p.source.type) || "applepay",
            hours_contracted: Number(md.hours || 4), worker_count: Number(md.worker_count || 1),
            zone_name: md.zone_name || null,
            location: (!isNaN(lat) && !isNaN(lng)) ?
              new admin.firestore.GeoPoint(lat, lng) : new admin.firestore.GeoPoint(24.7136, 46.6753),
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            server_created_from_payment: true, reconciled: true,
            // أعِد بناء تفصيل الخدمة من الـ metadata (وإلّا فُقِد على طلب Apple Pay).
            ...(_parseServiceMeta(md.service_meta_json) ?
              {service_meta: _parseServiceMeta(md.service_meta_json)} : {}),
          };
          if (md.service_date) {
            const sd = new Date(md.service_date);
            if (!isNaN(sd.getTime())) {
              payload.service_date = admin.firestore.Timestamp.fromDate(sd);
              if (isHourly) {
                const pad = (n) => String(n).padStart(2, "0");
                payload.booking_date = `${sd.getFullYear()}-${pad(sd.getMonth() + 1)}-${pad(sd.getDate())}`;
                payload.booking_time_slot = `${pad(sd.getHours())}:00`;
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
      const db = admin.firestore();
      const since = admin.firestore.Timestamp.fromDate(
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
          const r = await fetch(
              `https://api.tamara.co/merchants/orders/reference-id/${doc.id}`,
              {headers: {Authorization: `Bearer ${apiToken}`}});
          if (!r.ok) continue;
          const to = await r.json();
          const st = to.status;
          let justConfirmed = false;
          if (st === "approved") {
            const a = await fetch(
                `https://api.tamara.co/orders/${to.order_id}/authorise`,
                {method: "POST", headers: {
                  Authorization: `Bearer ${apiToken}`,
                  "Content-Type": "application/json",
                }});
            if (a.ok) {
              await _tamaraFlipPaid(db, doc.id, "order_authorised");
              justConfirmed = true;
            }
          } else if (["authorised", "captured", "fully_captured",
            "partially_captured"].includes(st)) {
            await _tamaraFlipPaid(db, doc.id, "order_" + st);
            justConfirmed = true;
          } else if (["declined", "expired", "canceled"].includes(st)) {
            // نُلغي الطلب (لا نتركه pending) كي يحرّر خانة الحجز ويُصحّح العدّاد — كان
            // يبقى pending فيستهلك السعة أبداً رغم فشل الدفع.
            await doc.ref.update({
              status: "cancelled",
              payment_status: "failed",
              cancel_reason: "tamara_" + st,
              tamara_status: "order_" + st,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
          if (justConfirmed) {
            confirmed++;
            // إسناد فوري للساعة بعد التأكيد (بدل انتظار الـ sweep 15 دقيقة).
            if (d.service_date && !d.driver_id && d.status === "pending") {
              try {
                const start = d.service_date.toDate();
                const hours = Number(d.hours_contracted || 4);
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
        const sinceC = admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 6 * 60 * 60 * 1000));
        const csnap = await db.collection("contracts")
            .where("createdAt", ">=", sinceC).get();
        for (const cdoc of csnap.docs) {
          const cd = cdoc.data();
          if (cd.is_paid === true) continue;
          try {
            const r = await fetch(
                `https://api.tamara.co/merchants/orders/reference-id/${cdoc.id}`,
                {headers: {Authorization: `Bearer ${apiToken}`}});
            if (!r.ok) continue;
            const to = await r.json();
            const st = to.status;
            if (st === "approved") {
              const a = await fetch(
                  `https://api.tamara.co/orders/${to.order_id}/authorise`,
                  {method: "POST", headers: {
                    Authorization: `Bearer ${apiToken}`,
                    "Content-Type": "application/json",
                  }});
              if (a.ok) {
                await _tamaraFlipPaid(db, cdoc.id, "order_authorised");
                confirmed++;
              }
            } else if (["authorised", "captured", "fully_captured",
              "partially_captured"].includes(st)) {
              await _tamaraFlipPaid(db, cdoc.id, "order_" + st);
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
      const db = admin.firestore();
      const cutoffMs = Date.now() - 30 * 60 * 1000;
      // استعلام أحادي الحقل (status) تفادياً لفهرس مركّب؛ نُرشّح is_paid+created_at كوداً.
      const snap = await db.collection("orders")
          .where("status", "==", "pending").get();
      let cancelled = 0;
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.is_paid === true) continue;
        const c = d.created_at;
        if (!c || typeof c.toMillis !== "function") continue;
        if (c.toMillis() > cutoffMs) continue; // أحدث من 30 دقيقة — قد يكون دفعاً جارياً
        try {
          await doc.ref.update({
            status: "cancelled",
            cancel_reason: "unpaid_expired",
            cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
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

      const rawName = (after.client_name || "").trim();
      const greet = ["", "عميل", "عميلة", "عميل زيارة", "عميلة زيارة"]
          .includes(rawName) ? "" : `${rawName}، `;
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
exports.applyReferralCode = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }
  const uid = request.auth.uid;
  const code = String(request.data && request.data.code || "").trim().toUpperCase();
  if (!code) throw new HttpsError("invalid-argument", "كود الإحالة مطلوب");
  const db = admin.firestore();

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
      created_at: admin.firestore.FieldValue.serverTimestamp(),
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

  const db = admin.firestore();

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
  const hours = Number(durationHours || orderData.hours_contracted || 4);
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
  const db = admin.firestore();

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
 * ساعات فتح المنطقة في تاريخ محدد، أو null إن كانت مغلقة.
 * @param {object|undefined} schedule
 * @param {string} dateStr yyyy-MM-dd
 * @return {number[]|null} [startHour, endHour] أو null (مغلق)
 */
function zoneOpenHoursForDate(schedule, dateStr) {
  if (!schedule || schedule.enabled !== true) return DEFAULT_OPEN;

  const blackouts = Array.isArray(schedule.blackouts) ? schedule.blackouts : [];
  if (blackouts.includes(dateStr)) return null; // إغلاق صريح يتقدّم كل شيء

  // فتح استثنائي: تاريخ ضمن نافذة يتجاوز الأسبوعي.
  const windows = Array.isArray(schedule.windows) ? schedule.windows : [];
  for (const w of windows) {
    if (w && w.from && w.to && dateStr >= w.from && dateStr <= w.to) {
      const s = Number(w.start); const e = Number(w.end);
      if (Number.isInteger(s) && Number.isInteger(e) && e > s) return [s, e];
    }
  }

  // الجدول الأسبوعي.
  const weekday = new Date(`${dateStr}T00:00:00`).getDay(); // 0=الأحد..6=السبت
  const wk = schedule.weekly && schedule.weekly[String(weekday)];
  if (wk && wk.open === true) {
    const s = Number(wk.start); const e = Number(wk.end);
    if (Number.isInteger(s) && Number.isInteger(e) && e > s) return [s, e];
  }
  return null; // جدولٌ مُفعَّل وهذا اليوم غير مشمول => مغلق
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

  const db = admin.firestore();

  // 0. جدول فتح المنطقة (إن وُجدت منطقة باسم zoneName ولها schedule).
  let zoneSchedule = null;
  if (zoneName) {
    try {
      const zq = await db.collection("service_zones")
          .where("name", "==", zoneName).limit(1).get();
      if (!zq.empty) zoneSchedule = zq.docs[0].data().schedule || null;
    } catch (_) {}
  }

  // 1. السعة الحقيقية للفترة = عدد السائقين النشطين. **بلا مناطق** (قرار المالك):
  // السائق يقبل أي طلب، فالسعة رقم واحد للنشاط كلّه لا لكل منطقة.
  const driversSnap = await db.collection("drivers").get();
  const eligible = driversSnap.docs.filter((doc) => doc.data().is_active !== false);
  const driverCount = eligible.length;

  // 2. السعة اليومية تبقى من الإعدادات (سقف إضافي)
  let maxOrdersPerDay = 10;
  try {
    const hourlySnap = await db.collection("system_configs")
        .doc("hourly_settings").get();
    if (hourlySnap.exists) {
      maxOrdersPerDay = hourlySnap.data().max_orders_per_day ?? 10;
    }
  } catch (_) {}

  // 3. عدّ الطلبات التي تستهلك سائقاً في كل فترة (غير الملغاة)
  const snap = await db.collection("orders")
      .where("booking_date", ">=", startDate)
      .where("booking_date", "<=", endDate)
      .get();

  const dailyCounts = {};
  const slotCounts = {};
  for (const doc of snap.docs) {
    const d = doc.data();
    if (d.status === "cancelled" || d.status === "rejected") continue;
    // لا نعدّ الطلبات غير المدفوعة: يُنشأ الطلب is_paid=false قبل بوابة الدفع، والمهجور
    // منها (لم يُكمَل دفعه) كان يبقى pending أبداً فيستهلك سعة الخانة/اليوم ويحجب عملاء
    // حقيقيين بلا خدمة فعلية. نعدّ فقط ما أكّده الخادم (is_paid===true).
    if (d.is_paid !== true) continue;
    // **نعدّ طلبات كل المناطق.** كان العدّ مقصوراً على منطقة الطلب بينما driverCount
    // يشمل كل السائقين (لأنهم بلا مناطق) — فيُقاس بسطٌ منطقةٍ واحدة على مقامٍ عالمي:
    // سائقان مشغولان بطلبَي «الدائر» الساعة 10، وعميلة «أبو السلع» ترى عدّادها صفراً
    // فتحجز نفس الساعة ⇒ ثلاثة طلبات وسائقان ⇒ طلبٌ مدفوع بلا سائق. البسط والمقام
    // يجب أن يكونا من العالم نفسه.
    const bDate = d.booking_date;
    if (!bDate) continue;
    dailyCounts[bDate] = (dailyCounts[bDate] || 0) + 1;
    const ts = d.booking_time_slot;
    if (ts) {
      // الطلب يشغل سائقاً طوال مدته — نعدّه في كل ساعة يشغلها كي يعكس التلوين
      // الانشغال الحقيقي (كان يُعدّ في ساعة البدء فقط فتظهر ساعات لاحقة متاحة زوراً).
      const startH = parseInt(String(ts).split(":")[0], 10);
      const hrs = Number(d.hours_contracted || 4);
      if (!isNaN(startH)) {
        for (let h = startH; h < startH + hrs; h++) {
          const key = `${bDate}_${String(h).padStart(2, "0")}:00`;
          slotCounts[key] = (slotCounts[key] || 0) + 1;
        }
      }
    }
  }

  // 4. اشتقاق جدول الفتح لكل يوم في المدى — مرجعيّ، يرسم منه العميل ويفرضه الدفع.
  const openHours = {};   // "yyyy-MM-dd" -> [start, end]
  const closedDates = []; // أيام مغلقة كلياً بالجدول
  const start = new Date(`${startDate}T00:00:00`);
  const end = new Date(`${endDate}T00:00:00`);
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    const ds = `${y}-${m}-${day}`;
    const hrs = zoneOpenHoursForDate(zoneSchedule, ds);
    if (hrs === null) closedDates.push(ds);
    else openHours[ds] = hrs;
  }

  // maxTeamsPerSlot يعكس الآن عدد السائقين الحقيقي (لا قيمة ثابتة من الإعدادات)
  return {
    dailyCounts, slotCounts, maxOrdersPerDay, maxTeamsPerSlot: driverCount,
    scheduleEnabled: !!(zoneSchedule && zoneSchedule.enabled === true),
    openHours, closedDates, defaultOpen: DEFAULT_OPEN,
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
        const displayCode = afterData.code || orderId.substring(0, 6).toUpperCase();
        const title = "تم تعيين طلب جديد لك! 🚚";
        const body = `تم تعيينك للطلب #${displayCode}. يرجى التحقق من تفاصيل الرحلة في لوحة التحكم.`;

        // 1. Save to in-app notifications inbox
        await admin.firestore().collection("notifications").add({
          userId: driverId,
          title: title,
          body: body,
          type: "order_assignment",
          relatedId: orderId,
          isRead: false,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 2. Fetch driver's FCM token
        const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(driverId).get();
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
              await admin.messaging().send(payload);
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
          const dv = await admin.firestore().collection("drivers").doc(driverId).get();
          if (dv.exists && dv.data()?.email) {
            driverEmail = String(dv.data().email).trim();
          } else {
            const uv = await admin.firestore().collection("users").doc(driverId).get();
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
          const authHeader = `Basic ${Buffer.from(secret + ":").toString("base64")}`;

          const verifyResponse = await fetch(`https://api.moyasar.com/v1/payments/${payment.id}`, {
            headers: {"Authorization": authHeader},
          });

          if (!verifyResponse.ok) {
            console.error(`moyasarWebhook: Moyasar API verify failed ${verifyResponse.status} for payment ${payment.id}`);
            return;
          }

          const verifiedPayment = await verifyResponse.json();
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
            const ref = admin.firestore().collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists) {
              const data = doc.data();
              // (أمان C1) تحقّق أن المبلغ المدفوع فعلاً = مبلغ الطلب قبل تأكيده.
              // يمنع دفع مبلغ صغير (بمفتاح النشر) وربطه بطلب كبير لتأكيده مجاناً.
              // نُفضّل final_amount (السعر النهائي الذي قد تعدّله الإدارة لطلب متجر)
              // على المبلغ الأساسي — وإلا رُفضت دفعة حقيقية عند تعديل السعر.
              const expectedHalalas = Math.round(
                  Number(data.final_amount ?? data[amountField] ?? 0) * 100);
              if (expectedHalalas <= 0 || verifiedPayment.amount !== expectedHalalas) {
                console.error(
                    `moyasarWebhook: AMOUNT MISMATCH order ${orderId} in '${col}' — ` +
                    `paid ${verifiedPayment.amount} halalas, expected ${expectedHalalas}. NOT confirming.`);
                await ref.update({
                  payment_amount_mismatch: true,
                  updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
                // (سباق) فحص + تحديث داخل Transaction لمنع معالجة الدفعة مرتين
                const flipped = await admin.firestore().runTransaction(async (tx) => {
                  const snap = await tx.get(ref);
                  if (snap.data()?.is_paid) return false;
                  tx.update(ref, {
                    payment_status: "paid",
                    is_paid: true,
                    moyasar_payment_id: payment.id,
                    moyasar_status: verifiedPayment.status,
                    updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
            const ref = admin.firestore().collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists) {
              const rd = doc.data();
              // idempotent: مُسترَد سلفاً → لا تكرار (الاسترداد الجزئي يُرسل أحداثاً متعددة).
              if (rd.payment_status === "refunded") break;
              await ref.update({
                payment_status: "refunded",
                moyasar_status: "refunded",
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
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

/** Helper: build Moyasar auth header from secret */
function _moyasarAuthHeader(secret) {
  return `Basic ${Buffer.from(secret + ":").toString("base64")}`;
}

/** Helper: verify caller is admin (super_admin or orders_manager) */
async function _assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
  }
  const uid = request.auth.uid;
  const userDoc = await admin.firestore().collection("users").doc(uid).get();
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

/** Helper: find order across all collections, return {ref, col, data} or null */
async function _findOrder(orderId) {
  const collections = ["orders", "store_orders", "maintenance_requests", "contracts"];
  for (const col of collections) {
    const ref = admin.firestore().collection(col).doc(orderId);
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
      const existing = await _findOrder(orderId);
      if (existing) {
        if (existing.data.refund_credited === true) {
          throw new HttpsError("failed-precondition",
              "سبق ردّ هذا الطلب إلى محفظة العميل — لا يمكن ردّه عبر البوابة أيضاً");
        }
        if (existing.data.payment_status === "refunded") {
          throw new HttpsError("failed-precondition", "سبق استرداد هذا الطلب");
        }
      }

      const body = amountHalalas ? JSON.stringify({amount: amountHalalas}) : undefined;

      const response = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}/refund`, {
        method: "POST",
        headers: {
          "Authorization": _moyasarAuthHeader(secret),
          ...(body ? {"Content-Type": "application/json"} : {}),
        },
        ...(body ? {body} : {}),
      });

      const result = await response.json();

      if (!response.ok) {
        console.error(`moyasarRefund failed ${response.status}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل استرداد المبلغ من Moyasar");
      }

      // Update Firestore
      const order = await _findOrder(orderId);
      if (order) {
        await order.ref.update({
          payment_status: "refunded",
          // نختم refund_credited أيضاً كي يمنع حارسُ onOrderRewards (refund_credited)
          // إيداعاً ثانياً في المحفظة — الطرفان الآن متماثلان ضدّ الاسترداد المزدوج.
          refund_credited: true,
          moyasar_status: result.status,
          refunded_at: admin.firestore.FieldValue.serverTimestamp(),
          // المبلغ الحقيقي يختلف بالمجموعة: store=total_amount، عقد=planPrice، غيرها=amount.
          refunded_amount: amountHalalas ? amountHalalas / 100 :
            Number(order.data.final_amount ?? order.data.total_amount ??
              order.data.planPrice ?? order.data.amount ?? 0),
        });
      }

      console.log(`moyasarRefund: payment ${paymentId} refunded — status: ${result.status}`);
      return {success: true, status: result.status, refundedAmount: result.amount};
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

      const response = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}/void`, {
        method: "POST",
        headers: {"Authorization": _moyasarAuthHeader(secret)},
      });

      const result = await response.json();

      if (!response.ok) {
        console.error(`moyasarVoid failed ${response.status}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل إلغاء عملية الدفع من Moyasar");
      }

      const order = await _findOrder(orderId);
      if (order) {
        await order.ref.update({
          payment_status: "voided",
          moyasar_status: result.status,
          voided_at: admin.firestore.FieldValue.serverTimestamp(),
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

      const body = amountHalalas ? JSON.stringify({amount: amountHalalas}) : undefined;

      const response = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}/capture`, {
        method: "POST",
        headers: {
          "Authorization": _moyasarAuthHeader(secret),
          ...(body ? {"Content-Type": "application/json"} : {}),
        },
        ...(body ? {body} : {}),
      });

      const result = await response.json();

      if (!response.ok) {
        console.error(`moyasarCapture failed ${response.status}:`, result);
        throw new HttpsError("internal", result.message ?? "فشل تحصيل المبلغ المحجوز من Moyasar");
      }

      const order = await _findOrder(orderId);
      if (order) {
        await order.ref.update({
          payment_status: "captured",
          is_paid: true,
          moyasar_status: result.status,
          captured_at: admin.firestore.FieldValue.serverTimestamp(),
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

      const rawBody = JSON.stringify(req.body);
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
          const db = admin.firestore();
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
                  const expected = Number(
                      cur.final_amount ?? cur.total_amount ?? cur.planPrice ?? cur.amount ?? 0);
                  const paid = Number(payment.amount || 0);
                  if (expected <= 0 || Math.abs(paid - expected) > 0.01) {
                    tx.update(ref, {
                      payment_amount_mismatch: true,
                      updated_at: admin.firestore.FieldValue.serverTimestamp(),
                    });
                    return "mismatch";
                  }
                  tx.update(ref, {
                    payment_status: "paid",
                    is_paid: true,
                    tabby_payment_id: paymentId,
                    tabby_status: eventType,
                    updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
          const db = admin.firestore();
          for (const col of ["orders", "maintenance_requests", "contracts"]) {
            const ref = db.collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists && !doc.data().is_paid) {
              await ref.update({
                payment_status: "failed",
                tabby_status: eventType,
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
