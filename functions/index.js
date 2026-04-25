/* eslint-disable max-len */
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
admin.initializeApp();
// const functions = require("firebase-functions");

// 1. Notify user when admin replies to a support ticket
exports.sendNotificationOnTicketReply = onDocumentCreated("support_tickets/{ticketId}/messages/{messageId}",
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
exports.sendNotificationToAdminsOnNewOrder = onDocumentCreated("orders/{orderId}",
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
exports.sendNotificationToAdminsOnNewStoreOrder = onDocumentCreated("store_orders/{orderId}",
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
exports.sendNotificationToAdminsOnNewMaintenance = onDocumentCreated("maintenance_requests/{requestId}",
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
exports.sendNotificationToAdminsOnNewContract = onDocumentCreated("contracts/{contractId}",
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
exports.sendNotificationOnOrderStatusChange = onDocumentUpdated("orders/{orderId}",
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

      if (afterData.status === "accepted") {
        targetUserId = afterData.clientId;
        title = "تم قبول طلبك!";
        body = "لقد تم قبول طلبك وجارٍ تجهيزه.";
      } else if (afterData.status === "in_progress") {
        targetUserId = afterData.clientId;
        title = "سائقك في الطريق";
        body = "السائق متجه إليك الآن.";
      } else if (afterData.status === "completed") {
        targetUserId = afterData.clientId;
        title = "تم إكمال الطلب";
        body = "نشكرك لاستخدام تطبيق زيارة.";
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

// 3. Unified Global Notification Trigger
exports.onNotificationCreated = onDocumentCreated("notifications_log/{id}",
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
        if (target === "all") {
          await admin.messaging().send({...payload, topic: "all_users"});
          await admin.messaging().send({...payload, topic: "clients"});
          await admin.messaging().send({...payload, topic: "drivers"});
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

// 4. Callable function for direct sending
exports.manualSendNotification = onCall(async (request) => {
  const {title, body, target = "all"} = request.data;

  const payload = {
    notification: {title, body},
    data: {click_action: "FLUTTER_NOTIFICATION_CLICK"},
  };

  try {
    if (target === "all") {
      await admin.messaging().send({...payload, topic: "all_users"});
    } else {
      await admin.messaging().send({...payload, topic: target});
    }
    return {success: true};
  } catch (error) {
    throw new HttpsError("internal", error.message);
  }
});

// 5. Tamara Webhook Handler (Security/Reliability Fix)
exports.tamaraWebhook = onRequest(async (req, res) => {
  // ⚠️ IMPORTANT: In production, verify the Tamara signature header!
  const notification = req.body;
  console.log("Received Tamara Webhook:", JSON.stringify(notification));

  const {order_id: orderId, status} = notification;

  if (status === "authorised" || status === "captured") {
    try {
      await admin.firestore().collection("orders").doc(orderId).update({
        payment_status: "paid",
        status: "accepted",
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Order ${orderId} marked as PAID via Tamara Webhook`);
    } catch (error) {
      console.error("Error updating order from Tamara webhook:", error);
    }
  }
  res.status(200).send("Webhook received");
});

const nodemailer = require("nodemailer");
const { Resend } = require("resend");

// 6. Unified Notification Trigger Processor (THE BEST: DIRECT MAIL + ATTACHMENTS + IN-APP SYNC)
exports.processNotificationTriggers = onDocumentCreated("notification_triggers/{id}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const trigger = snap.data();
  if (!trigger || trigger.processed === true) return;

  const {toUid, title, body, type, template, data = {}, attachmentUrls = []} = trigger;
  const recipientEmail = trigger.recipientEmail || data.customerEmail || "admin@zyiarah.com";

  console.log(`Processing trigger ${event.params.id} via Advanced Communications Pipeline`);

  try {
    // ------------------------------------------------------------
    // 1. Sync to In-App Notification History (Universal)
    // ------------------------------------------------------------
    if (toUid && toUid !== "ADMIN_BROADCAST") {
      await admin.firestore().collection("notifications").add({
        userId: toUid,
        title: title,
        body: body.replace(/<[^>]*>?/gm, ""), // Clean text for UI
        type: type,
        relatedId: data.orderId || data.code || event.params.id,
        isRead: false,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // ------------------------------------------------------------
    // 2. Handle Email Logic (Resend / SMTP)
    // ------------------------------------------------------------
    if (type === "email" || type === "hybrid" || type === "admin_order_alert") {
      console.log(`[EMAIL_WORKER] Starting email task for: ${recipientEmail} with type: ${type}`);
      const configDoc = await admin.firestore().collection("system_configs").doc("email_settings").get();
      if (!configDoc.exists) {
        console.error("[EMAIL_WORKER] CRITICAL: system_configs/email_settings document is MISSING");
        throw new Error("Email settings missing");
      }

      const {fromName, fromEmail, resendApiKey} = configDoc.data();
      console.log(`[EMAIL_WORKER] Config loaded. From: ${fromEmail}, Key Present: ${!!resendApiKey}`);
      
      const fromString = `"${fromName || "Zyiarah | زيارة"}" <${fromEmail || "no-reply@zyiarah.com"}>`;

      if (resendApiKey) {
        const resend = new Resend(resendApiKey);

        // 2a. Process Attachments
        const attachments = [];
        if (attachmentUrls && attachmentUrls.length > 0) {
          console.log(`[EMAIL_WORKER] Processing ${attachmentUrls.length} attachments...`);
          for (const url of attachmentUrls) {
            try {
              const response = await fetch(url);
              if (response.ok) {
                const arrayBuffer = await response.arrayBuffer();
                const filename = url.split("/").pop().split("?")[0] || "invoice.pdf";
                attachments.push({
                  filename: filename,
                  content: Buffer.from(arrayBuffer),
                });
              }
            } catch (attError) {
              console.error(`[EMAIL_WORKER] Attachment download failed for ${url}:`, attError);
            }
          }
        }

        const emailPayload = {
          from: fromString,
          to: recipientEmail,
          subject: title,
          attachments: attachments.length > 0 ? attachments : undefined,
        };

        if (template && template.id) {
          console.log(`[EMAIL_WORKER] Sending TEMPLATED email: ${template.id}`);
          emailPayload.template = {
            id: template.id,
            variables: template.variables || {},
          };
        } else {
          console.log("[EMAIL_WORKER] Sending HTML email (no template)");
          emailPayload.html = body;
        }

        console.log("[EMAIL_WORKER] Dispatching to Resend API...");
        const {data: resendData, error: resendError} = await resend.emails.send(emailPayload);
        
        if (resendError) {
          console.error("[EMAIL_WORKER] RESEND API ERROR:", JSON.stringify(resendError));
          throw new Error(`Resend Error: ${resendError.message}`);
        }

        console.log(`[EMAIL_WORKER] SUCCESS! Message ID: ${resendData.id}`);
        await snap.ref.update({
          emailStatus: "sent",
          messageId: resendData.id,
          provider: "resend",
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } else {
        console.error("[EMAIL_WORKER] Skipping email: resendApiKey is empty in settings");
      }
    }

    // ------------------------------------------------------------
    // 3. Handle Push Notification Logic (FCM)
    // ------------------------------------------------------------
    if (type !== "email") {
      let targetTokens = [];

      if (toUid === "ADMIN_BROADCAST") {
        const adminTokensSnap = await admin.firestore().collection("fcm_tokens").where("role", "==", "admin").get();
        targetTokens = adminTokensSnap.docs.map((doc) => doc.data()?.fcmToken || doc.data()?.token).filter((t) => !!t);
      } else if (toUid) {
        const tokenDoc = await admin.firestore().collection("fcm_tokens").doc(toUid).get();
        if (tokenDoc.exists) {
          const t = tokenDoc.data()?.fcmToken || tokenDoc.data()?.token;
          if (t) targetTokens = [t];
        }
      }

      if (targetTokens.length > 0) {
        const message = {
          notification: {title, body: body.replace(/<[^>]*>?/gm, "")},
          data: {...data, click_action: "FLUTTER_NOTIFICATION_CLICK"},
          tokens: targetTokens.length === 1 ? undefined : targetTokens,
          token: targetTokens.length === 1 ? targetTokens[0] : undefined,
        };

        if (targetTokens.length === 1) {
          await admin.messaging().send(message);
        } else {
          await admin.messaging().sendEachForMulticast({
            tokens: targetTokens,
            notification: message.notification,
            data: message.data,
          });
        }
        console.log(`Push sent to ${targetTokens.length} devices`);
      }
    }

    // Final signature
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
