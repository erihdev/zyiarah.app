"use strict";
// حارس واجهة firebase-admin المُسمّاة — تشغيل: node test/admin_namespace.test.js (ضمن npm test).
//
// index.js يستدعي admin.firestore()‎ وadmin.firestore.FieldValue وadmin.messaging()‎
// داخل المعالجات، أي بعد النشر لا قبله. الترقية إلى firebase-admin 14 تحذف هذه
// الواجهة كلّها (كلّها undefined)، فيسقط كل معالج وقت التشغيل — بينما npm test
// وnpm run lint وتحميل index.js تمرّ خضراء لأن النداء لا يُنفَّذ في أيّها.
// رُفضت الترقية ثلاث مرّات بالدليل نفسه: #198، #202/#211، و#215 (14.4.0).
// هذا الحارس يحوّل ذلك السقوط الصامت إلى فشل في CI.
const assert = require("assert");
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

let passed = 0;
function t(name, fn) {
  fn();
  passed++;
  console.log("  ok -", name);
}

t("(أ) admin.firestore دالة، وFieldValue متاح عليها", () => {
  assert.strictEqual(typeof admin.firestore, "function",
      "admin.firestore ليس دالة — firebase-admin 14 يحذف الواجهة المُسمّاة");
  assert.ok(admin.firestore.FieldValue,
      "admin.firestore.FieldValue غير معرَّف — serverTimestamp() يسقط في كل كتابة");
  assert.strictEqual(typeof admin.firestore.FieldValue.serverTimestamp, "function");
});

t("(ب) admin.messaging وadmin.auth وadmin.storage دوالّ", () => {
  for (const key of ["messaging", "auth", "storage"]) {
    assert.strictEqual(typeof admin[key], "function",
        `admin.${key} ليس دالة — الإشعارات/الحسابات/الملفات تسقط وقت التشغيل`);
  }
});

t("(ج) index.js ما زال يعتمد الواجهة المُسمّاة (وإلا فالحارس بلا موضوع)", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  assert.ok(src.includes("admin.firestore()"), "index.js لم يعد ينادي admin.firestore()");
  assert.ok(src.includes("admin.firestore.FieldValue"), "index.js لم يعد يستعمل FieldValue");
});

console.log(`admin_namespace: ${passed} passed`);
