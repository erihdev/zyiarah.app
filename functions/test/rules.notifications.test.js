// قواعدُ طابورَي الإشعارات — ثُغرةُ انتحالِ «server» وإغلاقُها.
//
// `processNotificationTriggers` كان يَحسبُ الثقةَ من
// `trigger.createdBy === "server"`، و`notification_triggers` قاعدتُها
// `allow create: if isLoggedIn()` **بلا أيِّ قيدٍ على الحقول** — فأيُّ مستخدمٍ
// مسجَّلٍ يَكتب `createdBy: "server"` فيُعَدُّ موثوقاً ويَتخطّى حارسَ مكافحةِ
// الترحيلِ كلَّه: إشعارُ Push وسجلٌّ داخلَ التطبيقِ بعنوانٍ ونصٍّ من اختيارِه
// إلى **أيِّ ضحيّة**، أو بثٌّ إداريٌّ مزيَّف، أو بريدٌ من نطاقِ المنشأةِ إلى
// أيِّ عنوان (`recipientEmail` يأتي من المستند).
//
// الإصلاحُ الحاملُ للوزنِ خادميٌّ ولا يَنتظر نشرَ القواعد: الدفعُ الخادميُّ
// انتقلَ إلى `notification_queue` — **بلا قاعدةِ مطابقةٍ** — فالعميلُ ممنوعٌ
// منها بالافتراضِ المُغلَق، وAdmin SDK يَتخطّى القواعد. وهذا الملفُّ يُثبّت
// الشِّقَّين: أنّ `notification_queue` مُغلَقةٌ على العميل، وأنّ القيدَ الجديدَ
// يَمنعُ انتحالَ `createdBy`.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {setDoc, doc, addDoc, collection, getDocs} =
  require("firebase/firestore");

(async () => {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-zyiarah-notifications",
    firestore: {
      rules: fs.readFileSync(
          path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/client1"), {role: "client"});
    await setDoc(doc(db, "users/victim"), {role: "client"});
    await setDoc(doc(db, "users/adminA"), {role: "admin"});
  });

  const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
  const anon = testEnv.unauthenticatedContext().firestore();

  let pass = 0; let fail = 0;
  const check = async (name, promise, shouldSucceed) => {
    try {
      await (shouldSucceed ? assertSucceeds(promise) : assertFails(promise));
      console.log(`  ✓ ${name}`); pass++;
    } catch (e) {
      console.error(`  ✗ ${name} — ${e.message}`); fail++;
    }
  };

  const trigger = (extra) => ({
    toUid: "victim",
    title: "تنبيه",
    body: "نصّ",
    type: "generic",
    processed: false,
    ...extra,
  });

  console.log("\nnotification queues — rules");

  // ── الثغرةُ بعينها ──
  await check(
      "عميلٌ لا يستطيع انتحالَ createdBy:'server' (الثغرةُ بعينها)",
      addDoc(collection(asUser("client1"), "notification_triggers"),
          trigger({createdBy: "server"})),
      false);

  await check(
      "ولا انتحالَ معرّفِ مستخدمٍ آخر (انتحالُ موظّف)",
      addDoc(collection(asUser("client1"), "notification_triggers"),
          trigger({createdBy: "adminA"})),
      false);

  await check(
      "ولا كتابةَ بلا createdBy إطلاقاً",
      addDoc(collection(asUser("client1"), "notification_triggers"),
          trigger({})),
      false);

  await check(
      "ويَكتبُ بمعرّفِه هو (المسارُ الشرعيّ)",
      addDoc(collection(asUser("client1"), "notification_triggers"),
          trigger({createdBy: "client1"})),
      true);

  // ── الطابورُ الخادميُّ مُغلَقٌ تماماً ──
  for (const [who, db] of [["عميل", asUser("client1")],
    ["أدمن", asUser("adminA")], ["غيرُ مسجَّل", anon]]) {
    await check(
        `${who} لا يَكتبُ في notification_queue (لا قاعدةَ مطابقةٍ لها)`,
        addDoc(collection(db, "notification_queue"), trigger({})),
        false);
  }
  await check(
      "ولا يَقرؤها أحد",
      getDocs(collection(asUser("adminA"), "notification_queue")),
      false);

  await check(
      "وغيرُ المسجَّلِ لا يَكتبُ طابورَ العميلِ أصلاً",
      addDoc(collection(anon, "notification_triggers"), trigger({})),
      false);

  console.log(`\nnotification rules: ${pass} passed, ${fail} failed`);
  await testEnv.cleanup();
  process.exit(fail > 0 ? 1 : 0);
})();
