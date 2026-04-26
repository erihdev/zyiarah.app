const admin = require("firebase-admin");
const {getFirestore} = require("firebase-admin/firestore");

if (!admin.apps.length) {
  admin.initializeApp();
}

/** Reads and logs the email_settings config document from Firestore. */
async function checkConfig() {
  const db = getFirestore();
  const doc = await db.collection("system_configs").doc("email_settings").get();
  if (doc.exists) {
    console.log("Config exists:", JSON.stringify(doc.data(), null, 2));
  } else {
    console.log("Config does not exist.");
  }
  process.exit(0);
}

checkConfig().catch((err) => {
  console.error(err);
  process.exit(1);
});
