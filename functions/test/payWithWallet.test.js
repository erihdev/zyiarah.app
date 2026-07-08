/* eslint-disable */
// Emulator function test: payWithWallet flips is_paid atomically, is idempotent,
// and rejects cross-user / underfunded / amount-mismatch payments.
// Run: firestore emulator on :8080, then `node test/payWithWallet.test.js`.
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = "demo-zyiarah-rules";

const fft = require("firebase-functions-test")({projectId: "demo-zyiarah-rules"});
const myFns = require("../index.js"); // initialises admin.initializeApp()
const admin = require("firebase-admin");
const db = admin.firestore();
const payWithWallet = fft.wrap(myFns.payWithWallet);

let pass = 0; let fail = 0;
const ok = (name, cond) => {
  if (cond) {
    console.log(`  ✓ ${name}`); pass++;
  } else {
    console.error(`  ✗ ${name}`); fail++;
  }
};
const expectThrow = async (name, fn) => {
  try {
    await fn(); console.error(`  ✗ ${name} (expected throw)`); fail++;
  } catch (e) {
    console.log(`  ✓ ${name} (${e.code || e.message})`); pass++;
  }
};

(async () => {
  const uid = "u_wallet";
  const other = "u_other";
  await db.collection("wallets").doc(uid).set({balance: 500});
  await db.collection("orders").doc("o_pay").set({
    client_id: uid, amount: 200, is_paid: false, status: "pending",
  });

  console.log("payWithWallet — server-side confirmation:");

  // 1. Happy path: pays, flips is_paid, debits wallet.
  const r1 = await payWithWallet({data: {amount: 200, orderId: "o_pay"}, auth: {uid}});
  ok("returns success", r1 && r1.success === true);
  ok("wallet debited 500->300", (await db.collection("wallets").doc(uid).get()).get("balance") === 300);
  const o1 = await db.collection("orders").doc("o_pay").get();
  ok("order is_paid=true (server)", o1.get("is_paid") === true);
  ok("order payment_method=wallet", o1.get("payment_method") === "wallet");
  const txs = await db.collection("wallets").doc(uid).collection("transactions").get();
  ok("one debit tx linked to order", txs.size === 1 && txs.docs[0].get("order_id") === "o_pay");

  // 2. Idempotent: second call does not double-charge.
  const r2 = await payWithWallet({data: {amount: 200, orderId: "o_pay"}, auth: {uid}});
  ok("idempotent alreadyPaid", r2 && r2.alreadyPaid === true);
  ok("wallet still 300 (no double debit)", (await db.collection("wallets").doc(uid).get()).get("balance") === 300);

  // 3. Cross-user order rejected.
  await db.collection("orders").doc("o_other").set({client_id: other, amount: 100, is_paid: false});
  await expectThrow("rejects other user's order", () =>
    payWithWallet({data: {amount: 100, orderId: "o_other"}, auth: {uid}}));

  // 4. Amount mismatch rejected (order is 200, try to pay 50).
  await db.collection("orders").doc("o_mm").set({client_id: uid, amount: 200, is_paid: false});
  await expectThrow("rejects amount mismatch", () =>
    payWithWallet({data: {amount: 50, orderId: "o_mm"}, auth: {uid}}));

  // 5. Insufficient balance rejected.
  await db.collection("wallets").doc("u_poor").set({balance: 10});
  await db.collection("orders").doc("o_poor").set({client_id: "u_poor", amount: 200, is_paid: false});
  await expectThrow("rejects insufficient balance", () =>
    payWithWallet({data: {amount: 200, orderId: "o_poor"}, auth: {uid: "u_poor"}}));

  console.log(`\npayWithWallet test: ${pass} passed, ${fail} failed`);
  await fft.cleanup();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e); process.exit(1);
});
