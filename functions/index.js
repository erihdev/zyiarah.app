/* eslint-disable max-len */
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
admin.initializeApp();

// Secrets — stored in Firebase Secret Manager, never in source code
const tamaraApiToken = defineSecret("TAMARA_API_TOKEN");
const resendApiKeySecret = defineSecret("RESEND_API_KEY");

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
exports.notifyAvailableDriversOnNewOrder = onDocumentCreated("orders/{orderId}",
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
exports.notifyClientOnOrderCancellation = onDocumentUpdated("orders/{orderId}",
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
exports.manualSendNotification = onCall(async (request) => {
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
    {secrets: ["TAMARA_API_TOKEN"]},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً");
      }

      const {orderId, amount, customerPhone, customerName} = request.data;

      if (!orderId || !amount || !customerPhone || !customerName) {
        throw new HttpsError("invalid-argument", "بيانات الطلب ناقصة");
      }
      if (typeof amount !== "number" || amount <= 0) {
        throw new HttpsError("invalid-argument", "المبلغ غير صالح");
      }

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
exports.tamaraWebhook = onRequest(
    {secrets: ["TAMARA_API_TOKEN"]},
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

      if (signature !== expectedSig && !signature.includes(expectedSig)) {
        console.warn("Tamara webhook rejected: invalid signature");
        res.status(401).send("Invalid signature");
        return;
      }

      const notification = req.body;
      console.log("Verified Tamara Webhook:", JSON.stringify(notification));

      const {order_id: orderId, status} = notification;

      if (status === "authorised" || status === "captured") {
        try {
          // FIX: only update payment fields — do NOT set status to 'accepted'
          // The order stays 'pending' until a driver accepts it manually
          await admin.firestore().collection("orders").doc(orderId).update({
            payment_status: "paid",
            is_paid: true,
            tamara_status: status,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`Order ${orderId} marked as PAID via Tamara Webhook`);
        } catch (error) {
          console.error("Error updating order from Tamara webhook:", error);
        }
      } else if (status === "declined" || status === "expired") {
        try {
          await admin.firestore().collection("orders").doc(orderId).update({
            payment_status: "failed",
            tamara_status: status,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        } catch (error) {
          console.error("Error updating failed Tamara order:", error);
        }
      }
      res.status(200).send("OK");
    });

const {Resend} = require("resend");

// 6. Unified Notification Trigger Processor
exports.processNotificationTriggers = onDocumentCreated(
    {document: "notification_triggers/{id}", secrets: ["RESEND_API_KEY"]},
    async (event) => {
      const snap = event.data;
      if (!snap) return;

      const trigger = snap.data();
      if (!trigger || trigger.processed === true) return;

      const {toUid, title, body, type, template, data = {}, attachmentUrls = []} = trigger;
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
