const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
initializeApp({
  projectId: "zyiarah-app", // Ensure this is correct
});
const db = getFirestore();

/** Diagnoses email settings and notification trigger documents in Firestore. */
async function diagnose() {
  console.log("Checking Email Settings...");
  const settingsRef = db.collection("system_configs").doc("email_settings");
  const config = await settingsRef.get();
  if (config.exists) {
    console.log("✅ Email Settings Found");
    const data = config.data();
    console.log("From:", data.fromEmail);
    console.log("Resend Key Present:", !!data.resendApiKey);
  } else {
    console.log("❌ Email Settings MISSING");
  }

  // **الطابوران.** الدفعُ الخادميُّ (`queuePush`) انتقل إلى
  // `notification_queue` — بلا قاعدةِ مطابقةٍ في firestore.rules فلا يَكتبه
  // عميل — وبقي `notification_triggers` لكتابةِ التطبيقِ واللوحة. وهذا
  // التشخيصُ هو ما يُشغَّلُ حين يَتعطّلُ البريد، فقراءةُ طابورٍ واحدٍ تَقولُ
  // «صفرٌ معلَّق» بينما الطابورُ الآخرُ مُتراكم: تشخيصٌ يُطمئنُ على عطل.
  for (const col of ["notification_queue", "notification_triggers"]) {
    console.log(`\nChecking ${col}...`);
    const pending = await db.collection(col)
        .where("processed", "==", false)
        .orderBy("createdAt", "desc")
        .limit(5)
        .get();

    console.log(`Found ${pending.size} pending triggers.`);

    pending.forEach((doc) => {
      const data = doc.data();
      const errMsg = data.error || "None";
      console.log(`- ID: ${doc.id} | Type: ${data.type} | Error: ${errMsg}`);
    });

    const failed = await db.collection(col)
        .where("error", "!=", null)
        .limit(5)
        .get();

    console.log(`Found ${failed.size} triggers with errors.`);
    failed.forEach((doc) => {
      console.log(`- ID: ${doc.id} | Error: ${doc.data().error}`);
    });
  }

  process.exit(0);
}

diagnose().catch((err) => {
  console.error(err);
  process.exit(1);
});
