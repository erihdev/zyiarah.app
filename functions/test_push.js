const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");

if (!admin.apps.length) {
  admin.initializeApp();
}

async function sendTestPush() {
  const db = getFirestore();
  console.log("Triggering Test Push Notification...");
  
  await db.collection("notifications_log").add({
    title: "تجربة الإشعارات - تطبيق زيارة 🚀",
    body: "مرحباً بك! الإشعارات الآن تعمل بنجاح وبسرعة البرق.",
    target: "all",
    created_at: admin.firestore.FieldValue.serverTimestamp()
  });

  console.log("✅ Trigger document added to notifications_log successfully.");
  console.log("The Cloud Function will process this and dispatch the FCM push shortly.");
  process.exit(0);
}

sendTestPush().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
