/* eslint-disable max-len */
const {onDocumentCreated, onDocumentUpdated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const geofire = require("geofire-common");
admin.initializeApp();

// Secrets — stored in Firebase Secret Manager, never in source code
const tamaraApiToken = defineSecret("TAMARA_API_TOKEN");
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
      if (newMessage.senderId !== "admin") return null;

      const ticketId = event.params.ticketId;
      const ticketRef = admin.firestore().collection("support_tickets")
          .doc(ticketId);
      const ticketDoc = await ticketRef.get();

      if (!ticketDoc.exists) return null;

      const ticketData = ticketDoc.data();
      const userId = ticketData.userId;

      const tokenDoc = await admin.firestore().collection("fcm_tokens")
          .doc(userId).get();
      if (!tokenDoc.exists) return null;

      const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
      if (!fcmToken) return null;

      const payload = {
        notification: {
          title: "تم الرد على تذكرتك",
          body: "قام الدعم الفني بالرد على تذكرة الدعم الخاصة بك للتو.",
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "support_ticket",
          ticketId: ticketId,
        },
        token: fcmToken,
      };

      try {
        await admin.messaging().send(payload);
        console.log(`Notification sent to user ${userId} for ticket ${ticketId}`);

        // Save to notifications collection for in-app history
        await admin.firestore().collection("notifications").add({
          userId: userId,
          title: payload.notification.title,
          body: payload.notification.body,
          type: "support_ticket",
          relatedId: ticketId,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error("Error sending notification:", error);
      }
      return null;
    });

// 1.5 Notify Admins on New Order (Services)
exports.sendNotificationToAdminsOnNewOrder = onDocumentCreated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const orderId = event.params.orderId;
      const orderData = snap.data();
      const displayCode = orderData.code || orderId.substring(0, 6);

      const payload = {
        notification: {
          title: "طلب خدمات جديد! 🚨",
          body: `وصلك طلب تنظيف جديد من العميل. رقم الطلب: ${displayCode}`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "new_order_admin",
          orderId: orderId,
        },
      };

      try {
        await admin.messaging().send({...payload, topic: "admins"});
        console.log(`Admin notification sent for new order: ${orderId}`);
      } catch (error) {
        console.error("Error sending admin notification for new order:", error);
      }
      return null;
    });

// 1.6 Notify Admins on New Store Order
exports.sendNotificationToAdminsOnNewStoreOrder = onDocumentCreated({document: "store_orders/{orderId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const orderData = snap.data();
      const displayCode = orderData.code || event.params.orderId.substring(0, 6);

      const payload = {
        notification: {
          title: "طلب متجر جديد! 🛒",
          body: `وصلك طلب منتجات من المتجر. رقم الطلب: ${displayCode}`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "new_store_order_admin",
          orderId: event.params.orderId,
        },
      };

      try {
        await admin.messaging().send({...payload, topic: "admins"});
      } catch (error) {
        console.error("Error sending store order alert:", error);
      }
      return null;
    });

// 1.7 Notify Admins on New Maintenance Request
exports.sendNotificationToAdminsOnNewMaintenance = onDocumentCreated({document: "maintenance_requests/{requestId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const payload = {
        notification: {
          title: "طلب صيانة جديد! 🛠️",
          body: `وصلك طلب صيانة جديد من عميل.`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "new_maintenance_admin",
          requestId: event.params.requestId,
        },
      };

      try {
        await admin.messaging().send({...payload, topic: "admins"});
      } catch (error) {
        console.error("Error sending maintenance alert:", error);
      }
      return null;
    });

// 1.8 Notify Admins on New Contract (Pending Approval)
exports.sendNotificationToAdminsOnNewContract = onDocumentCreated({document: "contracts/{contractId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const contractData = snap.data();
      const planName = contractData.planName || "باقة غير محددة";

      const payload = {
        notification: {
          title: "طلب تعاقد جديد! 📄",
          body: `هناك طلب اشتراك في (${planName}) ينتظر موافقتك.`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "new_contract_admin",
          contractId: event.params.contractId,
        },
      };

      try {
        await admin.messaging().send({...payload, topic: "admins"});
        console.log(`Admin alert sent for contract: ${event.params.contractId}`);
      } catch (error) {
        console.error("Error sending contract alert:", error);
      }
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
      let title = "تحديث مبدئي للطلب";
      let body = "حدث تغيير في حالة طلبك للتطبيق.";

      // FIX: field is `client_id` (snake_case) not `clientId`
      if (afterData.status === "accepted") {
        targetUserId = afterData.client_id;
        title = "تم قبول طلبك! 🚚";
        body = `السائق ${afterData.assigned_driver || "فريق زيارة"} في الطريق إليك.`;
      } else if (afterData.status === "arrived") {
        targetUserId = afterData.client_id;
        title = "وصل السائق! 🏠";
        body = "السائق متواجد الآن عند موقعك، استعد لاستقباله.";
      } else if (afterData.status === "in_progress") {
        targetUserId = afterData.client_id;
        title = "بدأ العمل 🛠️";
        body = "فريق زيارة بدأ في تنفيذ خدمتك.";
      } else if (afterData.status === "completed") {
        targetUserId = afterData.client_id;
        title = "تم الإنجاز! ✨";
        body = "انتهى العمل بنجاح. شكراً لثقتك بزيارة، ننتظر تقييمك.";
      } else if (afterData.status === "cancelled") {
        targetUserId = afterData.client_id;
        title = "تم إلغاء الطلب ⚠️";
        body = `تم إلغاء الطلب #${afterData.code || ""}. تواصل معنا لمزيد من التفاصيل.`;
      }

      if (!targetUserId) return null;

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

        // Save to notifications collection for in-app history
        await admin.firestore().collection("notifications").add({
          userId: targetUserId,
          title: title,
          body: body,
          type: "order_update",
          relatedId: orderId,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error("Error sending order notification:", error);
      }
      return null;
    });

// 2.5 Notify all available drivers when a new pending order is created
exports.notifyAvailableDriversOnNewOrder = onDocumentCreated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return null;

      const orderData = snap.data();
      if (orderData.status !== "pending") return null;

      const displayCode = orderData.code || event.params.orderId.substring(0, 6);
      const serviceType = orderData.service_type || "خدمة";
      const zoneName = orderData.zone_name || "";

      const payload = {
        notification: {
          title: "طلب جديد متاح 🚀",
          body: `طلب ${serviceType} جديد${zoneName ? " في " + zoneName : ""}. رقم #${displayCode} — اضغط للقبول.`,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "new_order_driver",
          orderId: event.params.orderId,
          code: displayCode,
        },
      };

      try {
        await admin.messaging().send({...payload, topic: "drivers"});
        console.log(`Available drivers notified for order: ${displayCode}`);
      } catch (error) {
        console.error("Error notifying drivers:", error);
      }
      return null;
    });

// 2.6 Notify client when their order is cancelled by admin
exports.notifyClientOnOrderCancellation = onDocumentUpdated({document: "orders/{orderId}", cpu: 0.083},
    async (event) => {
      const change = event.data;
      if (!change) return null;

      const before = change.before.data();
      const after = change.after.data();

      if (before.status === after.status || after.status !== "cancelled") return null;
      if (after.cancelled_by === "client") return null; // Client already knows

      const clientId = after.client_id;
      if (!clientId) return null;

      const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(clientId).get();
      if (!tokenDoc.exists) return null;

      const fcmToken = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
      if (!fcmToken) return null;

      const displayCode = after.code || event.params.orderId.substring(0, 6);

      try {
        await admin.messaging().send({
          notification: {
            title: "تم إلغاء طلبك ⚠️",
            body: `تم إلغاء الطلب #${displayCode} من قبل الإدارة. تواصل معنا لمزيد من التفاصيل.`,
          },
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            type: "order_cancelled",
            orderId: event.params.orderId,
          },
          token: fcmToken,
        });
        console.log(`Cancellation notification sent to client ${clientId}`);
      } catch (error) {
        console.error("Error sending cancellation notification:", error);
      }
      return null;
    });

// 3. Unified Global Notification Trigger
exports.onNotificationCreated = onDocumentCreated({document: "notifications_log/{id}", cpu: 0.083},
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const newValue = snap.data();
      if (!newValue || !newValue.title || !newValue.body) {
        console.log("Missing data in notification log doc:", event.params.id);
        return;
      }

      const {title, body, target = "all"} = newValue;

      const payload = {
        notification: {title, body},
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          type: "global_broadcast",
        },
      };

      try {
        // FIX: use single `all_users` topic to avoid double-delivery to clients/drivers
        if (target === "all") {
          await admin.messaging().send({...payload, topic: "all_users"});
        } else if (target === "clients" || target === "drivers") {
          await admin.messaging().send({...payload, topic: target});
        }

        // --- Save notifications to Firestore for in-app viewing ---
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
            userId: userDoc.id,
            title: title,
            body: body,
            type: "global_broadcast",
            isRead: false,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          count++;
          if (count === 400) {
            await batch.commit();
            batch = admin.firestore().batch();
            count = 0;
          }
        }
        if (count > 0) {
          await batch.commit();
        }
        // ------------------------------------------------------------

        await snap.ref.update({
          processed: true,
          processed_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`Notification processed for target: ${target}`);
      } catch (error) {
        console.error("Error sending push notification:", error);
        await snap.ref.update({
          processed: true,
          error: error.message || "Unknown error",
          processed_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
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

      // Fetch the true price from Firestore to prevent client-side tampering
      let trueAmount = null;

      const orderDoc = await admin.firestore().collection("orders").doc(orderId).get();
      if (orderDoc.exists) {
        const orderData = orderDoc.data();
        trueAmount = Number(orderData.amount);
      } else {
        const storeOrderDoc = await admin.firestore().collection("store_orders").doc(orderId).get();
        if (storeOrderDoc.exists) {
          const storeOrderData = storeOrderDoc.data();
          trueAmount = Number(storeOrderData.total_amount);
        }
      }

      if (trueAmount === null || isNaN(trueAmount) || trueAmount <= 0) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب أو أن قيمة المبلغ غير صالحة في السيرفر");
      }

      const amount = trueAmount;
      const token = tamaraApiToken.value();
      const phone = customerPhone.startsWith("+") ?
        customerPhone : `+966${customerPhone}`;

      try {
        const response = await fetch("https://api.tamara.co/checkout", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            order_reference_id: orderId,
            total_amount: {amount, currency: "SAR"},
            consumer: {first_name: customerName, phone_number: phone},
            merchant_url: {
              success: "https://zyiarah.com/payment-success",
              failure: "https://zyiarah.com/payment-failure",
              cancel: "https://zyiarah.com/payment-cancel",
            },
            description: "خدمات منزلية - مؤسسة معاذ يحي محمد المالكي",
          }),
        });

        if (response.status !== 201) {
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
    const title = success ? "تم تأكيد الدفع ✅" : "تعذّر إتمام الدفع ⚠️";
    const body = success ?
      `تم استلام دفعتك للطلب #${code} بنجاح، وسنبدأ بتجهيزه فوراً.` :
      `لم تكتمل عملية الدفع للطلب #${code}. يمكنك إعادة المحاولة من التطبيق.`;

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

exports.tamaraWebhook = onRequest(
    {secrets: ["TAMARA_API_TOKEN"], cpu: 0.083},
    async (req, res) => {
      // Verify Tamara signature to prevent spoofed payment events
      const signature = req.headers["tamara-signature"] || req.headers["x-tamara-signature"];
      if (!signature) {
        console.warn("Tamara webhook rejected: missing signature header");
        res.status(401).send("Unauthorized");
        return;
      }

      const crypto = require("crypto");
      const secret = tamaraApiToken.value();
      const rawBody = JSON.stringify(req.body);
      const expectedSig = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");

      const sigBuf = Buffer.from(String(signature));
      const expBuf = Buffer.from(expectedSig);
      if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
        console.warn("Tamara webhook rejected: invalid signature");
        res.status(401).send("Invalid signature");
        return;
      }

      const notification = req.body;
      console.log("Verified Tamara Webhook:", JSON.stringify(notification));

      const {order_id: orderId, status} = notification;

      if (status === "authorised" || status === "captured") {
        try {
          // فحص + تحديث داخل Transaction (idempotent) لمنع تكرار المعالجة/الإشعار
          const ref = admin.firestore().collection("orders").doc(orderId);
          let orderData = null;
          const flipped = await admin.firestore().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (!snap.exists) return false;
            orderData = snap.data();
            if (orderData.is_paid) return false; // سبق معالجته
            // FIX: تحديث حقول الدفع فقط — الطلب يبقى 'pending' حتى يقبله سائق
            tx.update(ref, {
              payment_status: "paid",
              is_paid: true,
              tamara_status: status,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            return true;
          });
          if (flipped) {
            console.log(`Order ${orderId} marked as PAID via Tamara Webhook`);
            await notifyClientPaymentResult("orders", orderId, orderData, true); // (F2)
          }
        } catch (error) {
          console.error("Error updating order from Tamara webhook:", error);
        }
      } else if (status === "declined" || status === "expired") {
        try {
          const ref = admin.firestore().collection("orders").doc(orderId);
          const doc = await ref.get();
          if (doc.exists && !doc.data().is_paid) {
            await ref.update({
              payment_status: "failed",
              tamara_status: status,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            await notifyClientPaymentResult("orders", orderId, doc.data(), false); // (F2)
          }
        } catch (error) {
          console.error("Error updating failed Tamara order:", error);
        }
      }
      res.status(200).send("OK");
    });

const {Resend} = require("resend");

// 6. Unified Notification Trigger Processor
exports.processNotificationTriggers = onDocumentCreated(
    {document: "notification_triggers/{id}", secrets: ["RESEND_API_KEY"], cpu: 0.25},
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const trigger = snap.data();
      if (!trigger || trigger.processed === true) return;

      const {toUid, title, body, type, template, data = {}} = trigger;
      const attachmentUrls = Array.isArray(trigger.attachmentUrls) ? trigger.attachmentUrls : [];
      const recipientEmail =
        trigger.recipientEmail || data.customerEmail || "admin@zyiarah.com";

      console.log(`Processing trigger ${event.params.id}`);

      try {
        // 1. Sync to In-App Notification History
        if (toUid && toUid !== "ADMIN_BROADCAST") {
          await admin.firestore().collection("notifications").add({
            userId: toUid,
            title: title,
            body: body.replace(/<[^>]*>?/gm, ""),
            type: type,
            relatedId: data.orderId || data.code || event.params.id,
            isRead: false,
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }

        // 2. Email via Resend (key from Secret Manager)
        if (type === "email" || type === "hybrid" || type === "admin_order_alert") {
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
            emailPayload.html = body;
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

        // 3. Push Notification via FCM
        if (type !== "email") {
          let targetTokens = [];
          if (toUid === "ADMIN_BROADCAST") {
            // FIX: include all admin role variants, not just 'admin'
            const adminRoles = ["admin", "super_admin", "orders_manager", "accountant_admin", "marketing_admin"];
            const snap2 = await admin.firestore()
                .collection("fcm_tokens").where("role", "in", adminRoles).get();
            targetTokens = snap2.docs
                .map((d) => d.data()?.fcmToken || d.data()?.token)
                .filter((t) => !!t);
          } else if (toUid) {
            const tokenDoc = await admin.firestore()
                .collection("fcm_tokens").doc(toUid).get();
            if (tokenDoc.exists) {
              const t = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
              if (t) targetTokens = [t];
            }
          }

          if (targetTokens.length > 0) {
            const pushMsg = {
              notification: {title, body: body.replace(/<[^>]*>?/gm, "")},
              data: {...data, click_action: "FLUTTER_NOTIFICATION_CLICK"},
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
          }
        }

        await snap.ref.update({
          processed: true,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (error) {
        console.error(`Error processing trigger ${event.params.id}:`, error);
        await snap.ref.update({
          processed: false,
          error: error.message,
          lastAttemptAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
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

      // Fetch the true amount from Firestore (orders, store_orders, maintenance_requests, or contracts) to prevent tampering
      let trueAmount = null;
      let orderRef = admin.firestore().collection("orders").doc(orderId);

      let orderDoc = await orderRef.get();
      if (orderDoc.exists) {
        trueAmount = Number(orderDoc.data().amount);
      } else {
        orderRef = admin.firestore().collection("store_orders").doc(orderId);
        orderDoc = await orderRef.get();
        if (orderDoc.exists) {
          trueAmount = Number(orderDoc.data().total_amount);
        } else {
          orderRef = admin.firestore().collection("maintenance_requests").doc(orderId);
          orderDoc = await orderRef.get();
          if (orderDoc.exists) {
            trueAmount = Number(orderDoc.data().amount);
          } else {
            orderRef = admin.firestore().collection("contracts").doc(orderId);
            orderDoc = await orderRef.get();
            if (orderDoc.exists) {
              trueAmount = Number(orderDoc.data().planPrice);
            }
          }
        }
      }

      if (trueAmount === null || isNaN(trueAmount) || trueAmount <= 0) {
        throw new HttpsError("not-found", "لم يتم العثور على الطلب في السيرفر أو أن المبلغ غير صالح");
      }

      const trueAmountHalalas = Math.round(trueAmount * 100);

      // Verify payment details with Moyasar API
      const secret = moyasarSecretKey.value();
      if (!secret) {
        throw new HttpsError("failed-precondition", "مفتاح Moyasar السري غير مهيأ في الخادم");
      }

      const authHeader = `Basic ${Buffer.from(secret + ":").toString("base64")}`;

      try {
        const response = await fetch(`https://api.moyasar.com/v1/payments/${paymentId}`, {
          method: "GET",
          headers: {
            "Authorization": authHeader,
          },
        });

        if (!response.ok) {
          const errText = await response.text();
          console.error(`Moyasar API response error ${response.status}: ${errText}`);
          throw new HttpsError("internal", "فشل التحقق من الدفع مع بوابة Moyasar");
        }

        const paymentData = await response.json();

        // Perform validations:
        // 1. Paid amount matches order amount (in Halalas)
        // 2. Status is 'paid'
        if (paymentData.status !== "paid") {
          throw new HttpsError("failed-precondition", `حالة عملية الدفع ليست مدفوعة: ${paymentData.status}`);
        }

        const paidAmountHalalas = Number(paymentData.amount);
        if (paidAmountHalalas !== trueAmountHalalas) {
          console.error(`Amount mismatch. Paid: ${paidAmountHalalas}, expected: ${trueAmountHalalas}`);
          throw new HttpsError("failed-precondition", "مبلغ الدفع لا يتطابق مع مبلغ الطلب");
        }

        // Atomically update payment status in Firestore
        await orderRef.update({
          payment_status: "paid",
          is_paid: true,
          moyasar_payment_id: paymentId,
          moyasar_status: paymentData.status,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Order ${orderId} successfully verified and marked as PAID via Moyasar.`);
        return {success: true};
      } catch (error) {
        if (error instanceof HttpsError) throw error;
        throw new HttpsError("internal", error.message);
      }
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
exports.getSurgePricingFactor = onCall({cpu: 0.083}, async (request) => {
  // if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

  const driversRef = admin.firestore().collection("users").where("role", "==", "driver");
  const snap = await driversRef.get();

  if (snap.empty) {
    return {surgeFactor: 1.0};
  }

  let totalActive = 0;
  let availableCount = 0;

  snap.forEach((doc) => {
    const data = doc.data();
    // Assuming active drivers are those who are not banned or deactivated
    if (data.isActive !== false) {
      totalActive++;
      if (data.status === "available" || data.status === "online") {
        availableCount++;
      }
    }
  });

  if (totalActive === 0) return {surgeFactor: 1.0};

  const availablePercentage = availableCount / totalActive;
  if (availablePercentage < 0.20) {
    return {surgeFactor: 1.15};
  }

  return {surgeFactor: 1.0};
});

// 9. Smart Dispatch Core: findNearestDrivers
exports.findNearestDrivers = onCall({cpu: 0.25}, async (request) => {
  // if (!request.auth) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");

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
 * يجد سائقاً مؤهلاً وحرّاً لفترة زمنية في منطقة محددة.
 * - المنطقة: يُفضَّل السائق الذي zone_name == منطقة الطلب أو assigned_zones تحتويها.
 *   السائق بلا منطقة مُسجَّلة يُعامَل مؤقتاً كمن يخدم كل المناطق (fallback أثناء الإطلاق
 *   حتى تُسنِد الإدارة المناطق للسائقين).
 * - الانشغال: السائق مشغول إن كان لديه طلب يتقاطع زمنياً بحالة
 *   scheduled/on_the_way/in_progress/accepted (لا يُحسب الانشغال "الآني" بل تقاطع الفترة).
 * @param {admin.firestore.Firestore} db
 * @param {object} opts {zoneName, startDateTime, endDateTime}
 * @return {Promise<FirebaseFirestore.QueryDocumentSnapshot|null>}
 */
async function _findFreeDriverForSlot(db, {zoneName, startDateTime, endDateTime}) {
  const dayStart = new Date(
      startDateTime.getFullYear(), startDateTime.getMonth(), startDateTime.getDate());
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

  const driversSnap = await db.collection("drivers").get();
  let eligible = driversSnap.docs.filter((doc) => doc.data().is_active !== false);

  if (zoneName) {
    eligible = eligible.filter((doc) => {
      const d = doc.data();
      const dz = d.zone_name;
      const zones = Array.isArray(d.assigned_zones) ? d.assigned_zones : [];
      const unzoned = (!dz || dz === "") && zones.length === 0;
      return unzoned || dz === zoneName || zones.includes(zoneName);
    });
  }
  if (eligible.length === 0) return null;

  // بناء مجموعة السائقين المشغولين بطلبات متقاطعة في نفس اليوم
  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", admin.firestore.Timestamp.fromDate(dayStart))
      .where("service_date", "<", admin.firestore.Timestamp.fromDate(dayEnd))
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
    if (!busy.has(doc.id)) return doc;
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
  const dayStart = new Date(
      startDateTime.getFullYear(), startDateTime.getMonth(), startDateTime.getDate());
  const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

  const ordersSnap = await db.collection("orders")
      .where("service_date", ">=", admin.firestore.Timestamp.fromDate(dayStart))
      .where("service_date", "<", admin.firestore.Timestamp.fromDate(dayEnd))
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
  const bookingDate = `${startDateTime.getFullYear()}-` +
    `${String(startDateTime.getMonth() + 1).padStart(2, "0")}-` +
    `${String(startDateTime.getDate()).padStart(2, "0")}`;
  const timeSlot = `${String(startDateTime.getHours()).padStart(2, "0")}:00`;

  await db.collection("orders").doc(orderId).update({
    status: "scheduled",
    driver_id: driverDoc.id,
    driver_name: d.name || "سائق",
    driver_phone: d.phone || "000000000",
    assigned_at: admin.firestore.FieldValue.serverTimestamp(),
    scheduled_at: admin.firestore.Timestamp.fromDate(startDateTime),
    // service_date مطلوب حتى يحتسب مُحدِّد التوفّر هذه المهمة ضمن انشغال السائق
    service_date: admin.firestore.Timestamp.fromDate(startDateTime),
    booking_date: bookingDate,
    booking_time_slot: timeSlot,
  });
  return {driverId: driverDoc.id, driverName: d.name || "سائق"};
}

// ════════════════════════════════════════════════════════════════════════
// Subscription Visit Generator — pre-generate & auto-assign all contract visits
// ════════════════════════════════════════════════════════════════════════
exports.generateSubscriptionVisits = onCall({cpu: 0.5}, async (request) => {
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
    const startDateTime = new Date(dp[0], dp[1] - 1, dp[2], hr, 0, 0);
    const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);

    const orderRef = db.collection("orders").doc();
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
      status: "pending_admin_approval", // تُرفَع إلى scheduled عند توفّر سائق
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
    const driver = await _findFreeDriverForSlot(db, {zoneName, startDateTime, endDateTime});
    if (driver) {
      const r = await _assignDriverScheduled(db, orderRef.id, driver, startDateTime);
      results.push({visit: i + 1, assigned: true, driverId: r.driverId});
    } else {
      results.push({visit: i + 1, assigned: false});
    }
  }

  return {generated: schedule.length, results};
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
  if (orderData.status !== "pending_admin_approval" && orderData.status !== "pending") {
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
  const bookingDate = `${startDateTime.getFullYear()}-` +
    `${String(startDateTime.getMonth() + 1).padStart(2, "0")}-` +
    `${String(startDateTime.getDate()).padStart(2, "0")}`;
  const timeSlot = `${String(startDateTime.getHours()).padStart(2, "0")}:00`;

  await db.runTransaction(async (tx) => {
    const fresh = await tx.get(orderRef);
    const st = fresh.data()?.status;
    if (st !== "pending_admin_approval" && st !== "pending") {
      throw new HttpsError("failed-precondition", "تم اعتماد الطلب بالفعل من مدير آخر");
    }
    tx.update(orderRef, {
      status: "scheduled",
      driver_id: driverId,
      driver_name: d.name || "سائق",
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

      console.log(
          `freeDriverOnOrderCancel: freed driver ${driverId} ` +
          `(order ${event.params.orderId} cancelled)`);
    },
);

/**
 * (2c) إرسال Push لمستخدم عبر توكنه في fcm_tokens.
 * @param {string} uid
 * @param {string} title
 * @param {string} body
 * @param {object} data
 */
async function _pushToUid(uid, title, body, data) {
  if (!uid) return;
  try {
    const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(uid).get();
    if (!tokenDoc.exists) return;
    const token = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
    if (!token) return;
    await admin.messaging().send({
      notification: {title, body},
      data: {click_action: "FLUTTER_NOTIFICATION_CLICK", ...data},
      token,
    });
  } catch (e) {
    console.error("_pushToUid error:", e);
  }
}

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
        await _pushToUid(
            d.driver_id,
            "تذكير: مهمتك بعد ساعة ⏰",
            `لديك مهمة (#${code}) تبدأ خلال ساعة تقريباً — استعد للانطلاق.`,
            {type: "task_reminder", orderId: doc.id},
        );
        await doc.ref.update({reminder_sent: true});
        sent++;
      }
      console.log(`remindDriversUpcomingTasks: sent ${sent} reminder(s)`);
    },
);

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

      const code = after.code || event.params.orderId;
      await _pushToUid(
          after.client_id,
          "سائقك في الطريق إليك 🚗",
          `انطلق السائق لتنفيذ طلبك (#${code}) — يرجى الاستعداد لاستقباله.`,
          {type: "order_update", orderId: event.params.orderId},
      );
    },
);

// 10. Auto Assign Driver Directly (No acceptance required)
exports.autoAssignDriverDirectly = onCall({cpu: 0.25}, async (request) => {
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
  if (!orderData.service_date) {
    throw new HttpsError("failed-precondition", "تاريخ الخدمة غير محدد");
  }

  const startDateTime = orderData.service_date.toDate();
  const hours = Number(durationHours || orderData.hours_contracted || 4);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);

  // (Direct Dispatch) اختيار سائق متاح في نفس المنطقة والفترة ثم إسناده بحالة scheduled
  const driver = await _findFreeDriverForSlot(db, {
    zoneName: orderData.zone_name || null,
    startDateTime,
    endDateTime,
  });
  if (!driver) {
    return {assigned: false, error: "no_available_drivers"};
  }

  const r = await _assignDriverScheduled(db, orderId, driver, startDateTime);
  return {
    assigned: true,
    driverId: r.driverId,
    driverName: r.driverName,
    driverEmail: driver.data().email || null,
  };
});

// 11. Check hourly slot availability securely (server-side)
exports.checkHourlySlotAvailability = onCall({cpu: 0.25}, async (request) => {
  const {startDateTimeIso, durationHours} = request.data;
  if (!startDateTimeIso) {
    throw new HttpsError("invalid-argument", "تاريخ البداية مطلوب");
  }

  const startDateTime = new Date(startDateTimeIso);
  const hours = Number(durationHours || 4);
  const endDateTime = new Date(startDateTime.getTime() + hours * 60 * 60 * 1000);
  const db = admin.firestore();

  // (Direct Dispatch) التوفّر = وجود سائق حرّ في نفس المنطقة والفترة عبر نفس مُحدِّد الإسناد
  const driver = await _findFreeDriverForSlot(db, {
    zoneName: request.data.zoneName || null,
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
    driverEmail: driverData.email || null,
  };
});

// 12. Hourly slot availability for client UI — server-side to bypass Firestore rules.
// Returns daily order counts + per-slot counts for the requested date range.
// The client app uses these to colour date cells and slot buttons without
// needing read access to other users' orders.
exports.getHourlyAvailability = onCall({cpu: 0.25}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "يجب تسجيل الدخول");
  }

  const {startDate, endDate, zoneName} = request.data;
  if (!startDate || !endDate) {
    throw new HttpsError("invalid-argument", "startDate و endDate مطلوبان");
  }

  const db = admin.firestore();

  // 1. السعة الحقيقية للفترة = عدد السائقين الحرّين القابلين للإسناد في المنطقة.
  // (Direct Dispatch / قرار 4) — الفترة حمراء إذا بلغ عدد الطلبات عدد السائقين.
  const driversSnap = await db.collection("drivers").get();
  let eligible = driversSnap.docs.filter((doc) => doc.data().is_active !== false);
  if (zoneName) {
    eligible = eligible.filter((doc) => {
      const d = doc.data();
      const zones = Array.isArray(d.assigned_zones) ? d.assigned_zones : [];
      const unzoned = (!d.zone_name) && zones.length === 0;
      return unzoned || d.zone_name === zoneName || zones.includes(zoneName);
    });
  }
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
    const bDate = d.booking_date;
    if (!bDate) continue;
    dailyCounts[bDate] = (dailyCounts[bDate] || 0) + 1;
    const ts = d.booking_time_slot;
    if (ts) {
      const key = `${bDate}_${ts}`;
      slotCounts[key] = (slotCounts[key] || 0) + 1;
    }
  }

  // maxTeamsPerSlot يعكس الآن عدد السائقين الحقيقي (لا قيمة ثابتة من الإعدادات)
  return {dailyCounts, slotCounts, maxOrdersPerDay, maxTeamsPerSlot: driverCount};
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
      if (webhookSecret && event.secret_token !== webhookSecret) {
        console.error("moyasarWebhook: invalid secret_token — possible spoofed request");
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

          for (const {col} of collections) {
            const ref = admin.firestore().collection(col).doc(orderId);
            const doc = await ref.get();
            if (doc.exists) {
              const data = doc.data();
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
              await ref.update({
                payment_status: "refunded",
                moyasar_status: "refunded",
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(`moyasarWebhook: Order ${orderId} marked REFUNDED via webhook`);
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
  const role = userDoc.data().role;
  const allowedRoles = ["super_admin", "orders_manager"];
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
          moyasar_status: result.status,
          refunded_at: admin.firestore.FieldValue.serverTimestamp(),
          refunded_amount: amountHalalas ? amountHalalas / 100 : (order.data.amount ?? 0),
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
                await db.runTransaction(async (tx) => {
                  const snap = await tx.get(ref);
                  if (snap.data()?.is_paid) {
                    // Another write beat us to it (race between webhook + SDK callback)
                    console.log(`tabbyWebhook: ${col}/${orderId} was paid mid-transaction — aborting (idempotent)`);
                    return;
                  }
                  tx.update(ref, {
                    payment_status: "paid",
                    is_paid: true,
                    tabby_payment_id: paymentId,
                    tabby_status: eventType,
                    updated_at: admin.firestore.FieldValue.serverTimestamp(),
                  });
                });
                console.log(`tabbyWebhook: ${col}/${orderId} marked PAID via webhook (${eventType})`);
                await notifyClientPaymentResult(col, orderId, data, true); // (F2)
              }
              break; // Found the document — stop searching collections
            }
          }
        } else if (eventType === "payment.rejected" || eventType === "payment.expired" || eventType === "payment.cancelled") {
          // Mark as failed — no refund needed (payment was never captured)
          const db = admin.firestore();
          const ref = db.collection("orders").doc(orderId);
          const doc = await ref.get();
          if (doc.exists && !doc.data().is_paid) {
            await ref.update({
              payment_status: "failed",
              tabby_status: eventType,
              updated_at: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`tabbyWebhook: order ${orderId} marked FAILED (${eventType})`);
            await notifyClientPaymentResult("orders", orderId, doc.data(), false); // (F2)
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
