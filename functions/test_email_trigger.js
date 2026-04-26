const admin = require("firebase-admin");
admin.initializeApp({
  projectId: "zyiarah-app",
});
const db = admin.firestore();

/** Creates a diagnostic notification trigger document for testing. */
async function testTrigger() {
  console.log("Creating a TEST trigger in Firestore...");
  const res = await db.collection("notification_triggers").add({
    toUid: "TEST_USER",
    recipientEmail: "admin@zyiarah.com",
    title: "إيميل تجريبي - Test Email",
    body: "<h1>أهلاً بك</h1><p>هذا إيميل تجريبي لاختبار المحرك السحابي.</p>",
    type: "email",
    processed: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    app: "DIAGNOSTIC_TOOL",
  });
  console.log(`✅ Trigger created with ID: ${res.id}`);
  console.log("Now wait 10 seconds and check logs...");
  process.exit(0);
}

testTrigger().catch((err) => {
  console.error(err);
  process.exit(1);
});
