"use strict";
// حارس واجهة firebase-admin المعيارية (modular) — تشغيل: node test/admin_modular_api.test.js (ضمن npm test).
//
// التاريخ: كان index.js يستدعي admin.firestore()‎ وadmin.firestore.FieldValue وadmin.messaging()‎
// داخل المعالجات، أي بعد النشر لا قبله. firebase-admin 14 حذف هذه الواجهة المُسمّاة كلّها
// (كلّها undefined)، فيسقط كل معالج وقت التشغيل — بينما npm test وnpm run lint وتحميل
// index.js تمرّ خضراء لأن النداء لا يُنفَّذ في أيّها. رُفضت الترقية ثلاث مرّات بالدليل
// نفسه: #198، #202/#211، و#215 (14.4.0)، ثم أُضيف في #244 حارسٌ يُثبت وجود الواجهة
// المُسمّاة (test/admin_namespace.test.js) كي يصير السقوط الصامت فشلاً في CI.
//
// ثم هاجر index.js وdiagnose_email.js وcheck_firestore_config.js إلى الواجهة المعيارية
// (firebase-admin/app | firestore | messaging | auth) وارتقى firebase-admin إلى 14، فانقلب
// الحارس: يُثبت الآن نقاط الدخول المعيارية التي يعتمدها الكود المُهاجر، ويرفض أيّ عودة إلى
// الواجهة المُسمّاة. صنف العطب الأصلي باقٍ شكلاً: النداءات ما زالت تعيش داخل المعالجات،
// فتصديرٌ مفقود (FieldValue مثلاً بعد ترقية كبرى قادمة) يصبح undefined عند التحميل ولا
// يسقط إلا وقت التشغيل. لذا لا يكتفي الحارس بـtypeof بل يُنفِّذ كل مُصدَّر فعلاً — بلا شبكة.
//
// اقرأ هذا الرأس قبل تغيير ما يحميه: خفض firebase-admin دون 14 أو إعادة require("firebase-admin")
// المُسمّاة يُفشِل الحارس عن قصد.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {initializeApp, getApps, deleteApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp, GeoPoint} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getAuth} = require("firebase-admin/auth");

const root = path.join(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(root, rel), "utf8");

let passed = 0;
/**
 * مُشغّل اختبار مصغّر بنمط pricing.test.js.
 * @param {string} name اسم الاختبار.
 * @param {Function} fn جسم الاختبار (قد يكون async).
 */
async function t(name, fn) {
  await fn();
  passed++;
  console.log("  ok -", name);
}

(async () => {
  await t("(أ) firebase-admin/firestore: FieldValue وTimestamp وGeoPoint تُنفَّذ فعلاً لا typeof فقط", async () => {
    assert.strictEqual(typeof getFirestore, "function", "getFirestore ليست دالة");
    // القيم الحسّاسة (sentinels) التي تُكتب في كل مستند تقريباً.
    for (const k of ["serverTimestamp", "increment", "delete"]) {
      assert.strictEqual(typeof FieldValue[k], "function", `FieldValue.${k} ليست دالة`);
    }
    assert.ok(FieldValue.serverTimestamp(), "serverTimestamp() لم تُعِد قيمة");
    assert.ok(FieldValue.increment(1), "increment(1) لم تُعِد قيمة");
    assert.ok(FieldValue.delete(), "delete() لم تُعِد قيمة");
    // الطوابع الزمنية: المنشئات الثلاث التي يستعملها index.js.
    assert.strictEqual(typeof Timestamp.now().toMillis(), "number");
    assert.strictEqual(Timestamp.fromDate(new Date(1000)).toMillis(), 1000);
    assert.strictEqual(Timestamp.fromMillis(2500).toMillis(), 2500);
    // موقع الزيارة الملتقَط.
    const gp = new GeoPoint(16.8892, 42.5511);
    assert.strictEqual(gp.latitude, 16.8892);
    assert.strictEqual(gp.longitude, 42.5511);
  });

  await t("(ب) firebase-admin/app: initializeApp وgetApps وdeleteApp دوالّ", async () => {
    for (const [k, f] of Object.entries({initializeApp, getApps, deleteApp})) {
      assert.strictEqual(typeof f, "function", `${k} ليست دالة`);
    }
    assert.ok(Array.isArray(getApps()), "getApps() لا تُعيد مصفوفة");
  });

  await t("(ج) getFirestore/getMessaging/getAuth تُعيد عملاء بالواجهات المستعملة — بلا شبكة", async () => {
    // تطبيق خاص بالحارس (لا يحمّل index.js ولا يتصل بشيء: إنشاء العملاء كسول).
    const app = initializeApp({projectId: "demo-zyiarah-guard"}, "modular-api-guard");
    try {
      const db = getFirestore(app);
      for (const k of ["collection", "batch", "runTransaction"]) {
        assert.strictEqual(typeof db[k], "function", `Firestore.${k} ليست دالة`);
      }
      assert.strictEqual(db.collection("orders").doc("o1").id, "o1");
      const messaging = getMessaging(app);
      for (const k of ["send", "sendEachForMulticast"]) {
        assert.strictEqual(typeof messaging[k], "function", `Messaging.${k} ليست دالة`);
      }
      assert.strictEqual(typeof getAuth(app).deleteUser, "function", "Auth.deleteUser ليست دالة");
    } finally {
      await deleteApp(app);
    }
  });

  await t("(د) لا ملف في functions/ يعود إلى الواجهة المُسمّاة admin.* أو require(\"firebase-admin\")", async () => {
    const self = path.basename(__filename);
    const files = [
      ...fs.readdirSync(root).filter((f) => f.endsWith(".js")),
      ...fs.readdirSync(path.join(root, "test")).filter((f) => f.endsWith(".js") && f !== self)
          .map((f) => path.join("test", f)),
    ];
    assert.ok(files.includes("index.js") && files.includes("diagnose_email.js"),
        "قائمة الملفات المفحوصة لا تضمّ index.js/diagnose_email.js");
    const namespaced = /\badmin\.(firestore|messaging|auth|storage|initializeApp|apps|app|credential|database)\b/;
    for (const f of files) {
      const src = read(f);
      const m = namespaced.exec(src);
      assert.ok(m === null,
          `${f} يستعمل الواجهة المُسمّاة «${m && m[0]}» — غير موجودة في firebase-admin 14`);
      assert.ok(!/require\(\s*["']firebase-admin["']\s*\)/.test(src),
          `${f} يستورد firebase-admin المُسمّاة — استورد firebase-admin/<module> بدلاً منها`);
    }
  });

  await t("(هـ) index.js يعتمد الواجهة المعيارية فعلاً (وإلا فالحارس بلا موضوع)", async () => {
    const src = read("index.js");
    for (const mod of ["app", "firestore", "messaging", "auth"]) {
      assert.ok(src.includes(`require("firebase-admin/${mod}")`),
          `index.js لا يستورد firebase-admin/${mod}`);
    }
    for (const call of ["initializeApp()", "getFirestore()", "FieldValue.serverTimestamp()",
      "Timestamp.fromDate(", "new GeoPoint(", "getMessaging().send", "getAuth().deleteUser"]) {
      assert.ok(src.includes(call), `index.js لم يعد يستعمل ${call}`);
    }
    const diag = read("diagnose_email.js");
    assert.ok(diag.includes(`require("firebase-admin/firestore")`) && diag.includes("getFirestore()"),
        "diagnose_email.js لا يستعمل getFirestore() من firebase-admin/firestore");
  });

  await t("(و) package.json يثبّت firebase-admin على 14 فأعلى (الواجهة المُسمّاة انتهت هنا)", async () => {
    const range = String(JSON.parse(read("package.json")).dependencies["firebase-admin"] || "");
    const major = Number((/(\d+)/.exec(range) || [])[1]);
    assert.ok(major >= 14,
        `firebase-admin "${range}" — أُبقيت الترقية دون 14 ثلاث مرّات بسبب الواجهة المُسمّاة، وقد أُزيلت الآن`);
  });

  console.log(`admin_modular_api: ${passed} passed`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
