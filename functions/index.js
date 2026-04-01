const functions = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
admin.initializeApp();

// 1. Notify user when admin replies to a support ticket
exports.sendNotificationOnTicketReply = functions.firestore
    .document("support_tickets/{ticketId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const newMessage = snap.data();
      if (newMessage.senderId !== "admin") return null;

      const ticketId = context.params.ticketId;
      const ticketRef = admin.firestore().collection("support_tickets")
          .doc(ticketId);
      const ticketDoc = await ticketRef.get();

      if (!ticketDoc.exists) return null;

      const ticketData = ticketDoc.data();
      const userId = ticketData.userId;

      const tokenDoc = await admin.firestore().collection("fcm_tokens")
          .doc(userId).get();
      if (!tokenDoc.exists) return null;

      const fcmToken = tokenDoc.data().fcmToken;
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
        console.log(`Notification sent to user ${userId} ` +
            `for ticket ${ticketId}`);

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

// 1.5 Notify Admins on New Order
exports.sendNotificationToAdminsOnNewOrder = functions.firestore
    .document("orders/{orderId}")
    .onCreate(async (snap, context) => {
      const newOrder = snap.data();
      const orderId = context.params.orderId;

      const payload = {
        notification: {
          title: "طلب جديد! 🚨",
          body: `وصلك طلب تنظيف جديد من العميل. رقم الطلب: ${orderId.substring(0, 6)}`,
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

// 2. Notify driver/client when order status changes
exports.sendNotificationOnOrderStatusChange = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change, context) => {
      const beforeData = change.before.data();
      const afterData = change.after.data();
      const orderId = context.params.orderId;

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

      const fcmToken = tokenDoc.data().fcmToken;
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
        console.log(`Notification sent to ${targetUserId} ` +
            `for order ${orderId}`);

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
exports.manualSendNotification = functions.https.onCall(
    async (data, _context) => {
      const {title, body, target = "all"} = data;

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
        throw new functions.https.HttpsError("internal", error.message);
      }
    });

// 5. Tamara Webhook Handler (Security/Reliability Fix)
exports.tamaraWebhook = functions.https.onRequest(async (req, res) => {
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

  res.status(200).send("OK");
});
