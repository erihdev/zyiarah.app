const admin = require("firebase-admin");
admin.initializeApp({
    projectId: "zyiarah-app" // Ensure this is correct
});
const db = admin.firestore();

async function diagnose() {
  console.log("Checking Email Settings...");
  const config = await db.collection("system_configs").doc("email_settings").get();
  if (config.exists) {
    console.log("✅ Email Settings Found");
    const data = config.data();
    console.log("From:", data.fromEmail);
    console.log("Resend Key Present:", !!data.resendApiKey);
  } else {
    console.log("❌ Email Settings MISSING");
  }

  console.log("\nChecking Notification Triggers...");
  const pending = await db.collection("notification_triggers")
    .where("processed", "==", false)
    .orderBy("createdAt", "desc")
    .limit(5)
    .get();

  console.log(`Found ${pending.size} pending triggers.`);
  
  pending.forEach(doc => {
    const data = doc.data();
    console.log(`- ID: ${doc.id} | Type: ${data.type} | Error: ${data.error || 'None'}`);
  });

  const failed = await db.collection("notification_triggers")
    .where("error", "!=", null)
    .limit(5)
    .get();
    
  console.log(`\nFound ${failed.size} triggers with errors.`);
  failed.forEach(doc => {
    console.log(`- ID: ${doc.id} | Error: ${doc.data().error}`);
  });

  process.exit(0);
}

diagnose().catch(err => {
  console.error(err);
  process.exit(1);
});
