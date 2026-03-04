const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// 1. Notify user when admin replies to a support ticket
exports.sendNotificationOnTicketReply = functions.firestore
    .document("support_tickets/{ticketId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
      const newMessage = snap.data();

      // We only want to notify the user if the admin replied
      if (newMessage.senderId !== "admin") return null;

      const ticketId = context.params.ticketId;
      const ticketRef = admin.firestore()
          .collection("support_tickets").doc(ticketId);
      const ticketDoc = await ticketRef.get();

      if (!ticketDoc.exists) return null;

      const ticketData = ticketDoc.data();
      const userId = ticketData.userId;

      // Get user's FCM token
      const tokenDoc = await admin.firestore()
          .collection("fcm_tokens").doc(userId).get();
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
        console.log(
            `Notification sent to user ${userId} for ticket ${ticketId}`,
        );
      } catch (error) {
        console.error("Error sending notification:", error);
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

      const tokenDoc = await admin.firestore()
          .collection("fcm_tokens").doc(targetUserId).get();
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
        console.log(
            `Notification sent to ${targetUserId} for order ${orderId}`,
        );
      } catch (error) {
        console.error("Error sending order notification:", error);
      }

      return null;
    });

// 3. Global Notification from Admin Panel
exports.sendGlobalNotification = functions.firestore
    .document("notifications/{notificationId}")
    .onCreate(async (snap, context) => {
      const data = snap.data();
      const title = data.title;
      const body = data.body;
      const target = data.target || "all"; // "all", "customers", "drivers"

      const tokens = [];

      if (target === "all") {
        const tokensSnap = await admin.firestore()
            .collection("fcm_tokens").get();
        tokensSnap.forEach((doc) => {
          if (doc.data().fcmToken) tokens.push(doc.data().fcmToken);
        });
      } else {
        // Find users matching the target role
        const usersSnap = await admin.firestore()
            .collection("users").where("role", "==", target).get();
        const userIds = usersSnap.docs.map((doc) => doc.id);

        // Get tokens for those specific users
        if (userIds.length > 0) {
          for (const uid of userIds) {
            const tDoc = await admin.firestore()
                .collection("fcm_tokens").doc(uid).get();
            if (tDoc.exists && tDoc.data().fcmToken) {
              tokens.push(tDoc.data().fcmToken);
            }
          }
        }
      }

      if (tokens.length === 0) {
        console.log("No users found to send the notification to.");
        return null;
      }

      // Firebase limits multicast to 500 tokens at a time.
      // For large apps, chunking array into 500 is needed.
      const chunks = [];
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        chunks.push(tokens.slice(i, i + chunkSize));
      }

      for (const chunk of chunks) {
        const payload = {
          notification: {
            title: title,
            body: body,
          },
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            type: "global",
          },
          tokens: chunk,
        };

        try {
          const response = await admin.messaging()
              .sendEachForMulticast(payload);
          console.log(
              `Success: ${response.successCount}, Failed: ${response.failureCount}`,
          );
        } catch (error) {
          console.error("Error sending bulk notifications:", error);
        }
      }

      return null;
    });
