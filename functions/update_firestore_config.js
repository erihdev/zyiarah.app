const admin = require("firebase-admin");
const { getFirestore } = require("firebase-admin/firestore");

if (!admin.apps.length) {
  admin.initializeApp();
}

async function updateConfig() {
  const db = getFirestore();
  const resendApiKey = "re_bAMv2HPK_B1o5dFNf25VupqRhGRpPp1Jy";
  
  await db.collection("system_configs").doc("email_settings").set({
    resendApiKey: resendApiKey,
    fromEmail: "admin@zyiarah.com",
    fromName: "Zyiarah | زيارة",
    // Keep old SMTP settings as fallback
    host: "smtp.resend.com",
    port: 465,
    user: "resend",
    pass: resendApiKey,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, { merge: true });
  
  console.log("Firestore configuration updated successfully.");
  process.exit(0);
}

updateConfig().catch(err => {
  console.error(err);
  process.exit(1);
});
