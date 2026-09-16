// قواعد service_policies: قراءة عامّة (شاشة الشروط تُفتح قبل الدخول)، وكتابة
// للسوبر وحده. يعمل ضمن test:emulator كبقيّة فحوص القواعد.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {setDoc, doc, updateDoc, getDoc, deleteDoc} = require("firebase/firestore");

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-zyiarah-policies",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/superA"), {role: "admin"});
    await setDoc(doc(db, "users/ordersMgr"), {role: "admin", staff_role: "orders_manager"});
    await setDoc(doc(db, "users/marketer"), {role: "admin", staff_role: "marketing_admin"});
    await setDoc(doc(db, "users/client1"), {role: "client"});
    await setDoc(doc(db, "service_policies/p1"), {
      title: "اشتراطات السلامة", body: "…", category: "privacy_safety",
      enabled: true, mandatory_before_booking: true, order: 0,
    });
  });

  const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
  const anon = testEnv.unauthenticatedContext().firestore();
  const policy = {title: "t", body: "b", category: "contracts", enabled: true,
    mandatory_before_booking: false, order: 1};

  let pass = 0; let fail = 0;
  const check = async (name, promise, shouldSucceed) => {
    try {
      await (shouldSucceed ? assertSucceeds(promise) : assertFails(promise));
      console.log(`  ✓ ${name}`); pass++;
    } catch (e) {
      console.error(`  ✗ ${name} — ${e.message}`); fail++;
    }
  };

  console.log("service_policies rules:");

  // القراءة عامّة — شاشة الشروط تُفتح من التسجيل قبل أي دخول.
  await check("anonymous CAN read a policy",
      getDoc(doc(anon, "service_policies/p1")), true);
  await check("client CAN read a policy",
      getDoc(doc(asUser("client1"), "service_policies/p1")), true);

  // الكتابة للسوبر وحده.
  await check("anonymous CANNOT create",
      setDoc(doc(anon, "service_policies/x"), policy), false);
  await check("client CANNOT create",
      setDoc(doc(asUser("client1"), "service_policies/x"), policy), false);
  await check("client CANNOT toggle enabled",
      updateDoc(doc(asUser("client1"), "service_policies/p1"), {enabled: false}), false);
  await check("orders_manager CANNOT create (super only)",
      setDoc(doc(asUser("ordersMgr"), "service_policies/x"), policy), false);
  await check("marketing_admin CANNOT create (super only)",
      setDoc(doc(asUser("marketer"), "service_policies/x"), policy), false);
  await check("super_admin CAN create",
      setDoc(doc(asUser("superA"), "service_policies/p2"), policy), true);
  await check("super_admin CAN toggle enabled",
      updateDoc(doc(asUser("superA"), "service_policies/p1"), {enabled: false}), true);
  await check("super_admin CAN delete",
      deleteDoc(doc(asUser("superA"), "service_policies/p2")), true);

  console.log(`\nservice_policies test: ${pass} passed, ${fail} failed`);
  await testEnv.cleanup();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
