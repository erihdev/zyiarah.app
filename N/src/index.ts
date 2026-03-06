import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

export const onNotificationCreated = onDocumentCreated("notifications_log/{id}", async (event) => {
  const snap = event.data;
  if (!snap) {
    console.log("No data associated with the event");
    return;
  }
  const newValue = snap.data();

  if (!newValue || !newValue.title || !newValue.body) {
    console.log("Missing data in notification log doc:", event.params.id);
    return;
  }

  const title = newValue.title;
  const body = newValue.body;
  const target = newValue.target || "all"; // 'all', 'clients', 'drivers'

  const payload = {
    notification: {
      title: title,
      body: body,
    },
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
  };

  try {
    if (target === "all") {
      await admin.messaging().send({...payload, topic: "all_users"});
      console.log("Successfully sent message to topic: all_users");

      await admin.messaging().send({...payload, topic: "clients"});
      await admin.messaging().send({...payload, topic: "drivers"});
    } else if (target === "clients") {
      await admin.messaging().send({...payload, topic: "clients"});
      console.log("Successfully sent message to topic: clients");
    } else if (target === "drivers") {
      await admin.messaging().send({...payload, topic: "drivers"});
      console.log("Successfully sent message to topic: drivers");
    }

    // Update the document to show it was successfully processed
    await snap.ref.update({
      processed: true,
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return;
  } catch (error: any) {
    console.error("Error sending push notification:", error);

    // Mark as failed
    await snap.ref.update({
      processed: true,
      error: error.message || "Unknown error",
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return;
  }
});
