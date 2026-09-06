/* eslint-disable */
// Emulator rules test: proves the Stage-C order-create rule closes wallet minting.
// Run: firestore emulator on :8080, then `node test/rules.orders.test.js`.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {setDoc, doc} = require("firebase/firestore");

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-zyiarah-rules",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const uid = "client_abc";
  const db = testEnv.authenticatedContext(uid).firestore();

  let pass = 0; let fail = 0;
  const check = async (name, promise, shouldSucceed) => {
    try {
      await (shouldSucceed ? assertSucceeds(promise) : assertFails(promise));
      console.log(`  ✓ ${name}`);
      pass++;
    } catch (e) {
      console.error(`  ✗ ${name} — ${e.message}`);
      fail++;
    }
  };

  console.log("Stage-C order-create rule — wallet-minting closure:");

  // The actual mint vector: forge a PAID order -> now DENIED at create.
  await check("mint: create is_paid=true -> DENIED",
      setDoc(doc(db, "orders/mint1"),
          {client_id: uid, status: "pending", is_paid: true, amount: 5000}),
      false);

  // Server trust fields cannot be seeded at create.
  await check("trust: needs_refund at create -> DENIED",
      setDoc(doc(db, "orders/t1"),
          {client_id: uid, status: "pending", needs_refund: true, amount: 200}),
      false);
  await check("trust: rewards_handled_by at create -> DENIED",
      setDoc(doc(db, "orders/t2"),
          {client_id: uid, status: "pending", rewards_handled_by: "server", amount: 200}),
      false);
  await check("trust: refund_credited at create -> DENIED",
      setDoc(doc(db, "orders/t3"),
          {client_id: uid, status: "pending", refund_credited: true, amount: 200}),
      false);

  // Legit new-flow creates (is_paid false / absent) still work.
  await check("legit: is_paid=false -> ALLOWED",
      setDoc(doc(db, "orders/ok1"),
          {client_id: uid, status: "pending", is_paid: false, amount: 200}),
      true);
  // awaiting_payment هي حالة الدخول الثانية المسموحة (يكتبها متجرُ العميل في
  // store_service.dart). كانت هنا pending_admin_approval — وهي حالة ميتة حُذفت
  // من الجذور، فكان الإنشاء يُرفض على الحالة لا على is_paid، ولم يُختبر الغياب أبداً.
  await check("legit: is_paid absent -> ALLOWED",
      setDoc(doc(db, "orders/ok2"),
          {client_id: uid, status: "awaiting_payment", amount: 200}),
      true);

  // Existing protections still hold.
  await check("spoof: client_id != uid -> DENIED",
      setDoc(doc(db, "orders/spoof1"),
          {client_id: "someone_else", status: "pending", is_paid: false, amount: 200}),
      false);
  await check("status: bad initial status -> DENIED",
      setDoc(doc(db, "orders/bad1"),
          {client_id: uid, status: "completed", is_paid: false, amount: 200}),
      false);

  await testEnv.cleanup();
  console.log(`\nRules test: ${pass} passed, ${fail} failed`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
