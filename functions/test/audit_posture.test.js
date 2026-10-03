"use strict";

// حارس دائم: **ما يصرخ به `npm audit` ليس ما يُستغَلّ فعلاً** — ولا يُعالَج بـ--force.
//
// `npm audit` في functions/ يُبلّغ عن ثماني ثغرات (ستّ عالية واثنتان متوسّطتان).
// فُحصت كلها مسارَ مسارٍ في 2026-10-03، والنتيجة أن **لا واحدة منها قابلة
// للاستغلال في الإنتاج**:
//
//   الستّ العالية — سلسلة Firebase JS SDK كاملة
//     @grpc/grpc-js@1.9.16 (الثغرة <=1.13.5) يأتي من @firebase/rules-unit-testing
//     وهي devDependency للمحاكي وحده. وفي **شجرة الإنتاج** نسخةٌ أخرى تماماً:
//     firebase-admin → @google-cloud/firestore → google-gax → @grpc/grpc-js@1.14.5
//     وهي **خارج نطاق الثغرة**. فالعاليات كلها في شجرة الاختبار لا في المنشور.
//
//   المتوسّطتان — uuid@9.0.1 عبر gaxios@6.7.1 عبر @google-cloud/storage@8.2.0
//     هذه **في شجرة الإنتاج فعلاً**، لكنها غير قابلة للوصول: الثغرة في
//     v3/v5/v6 عند تمرير وسيط `buf`، وgaxios ينادي `uuid.v4()` وحدها (نداءٌ
//     واحد لحدود multipart في gaxios.js)، وشفرتنا لا تستورد uuid إطلاقاً.
//     ولا سبيل لإصلاحها عندنا: @google-cloud/storage@8.2.0 أحدثُ ما صدر ويقيّد
//     gaxios ^6.0.2، وgaxios 6.7.1 آخر 6.x، وfirebase-admin@14.5.0 أحدثُ ما
//     صدر. فالإصلاح عند Google لا عندنا.
//
// **والخطر الحقيقي ليس الثغرات — بل `npm audit fix --force`.** فـnpm يقترح
// «إصلاح» السلسلة العالية بإنزال @firebase/rules-unit-testing من ^5 إلى 2.0.7
// (isSemVerMajor)، وهو هبوطٌ بثلاث نسخات رئيسية يكسر اختبارات القواعد في
// المحاكي — نفس هراء نطاقات نسخ Firebase الذي ظهر في لوحة الإدارة. فالفحوص
// أدناه تمنع ذلك: إن هبطت الحزمة أو تلوّث grpc-js الإنتاجي، يسقط الحارس.

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  fn();
  console.log(`  ok - ${name}`);
  passed++;
}

/**
 * @param {string} p مسار الحزمة داخل node_modules
 * @return {string|null} نسختها أو null
 */
function ver(p) {
  try {
    return JSON.parse(
        fs.readFileSync(path.join(root, "node_modules", p, "package.json"),
            "utf8")).version;
  } catch {
    return null;
  }
}

/**
 * @param {string} v نسخة دلالية
 * @return {number[]} [major, minor, patch]
 */
function parts(v) {
  return v.split("-")[0].split(".").map(Number);
}

t("grpc-js الذي يحلّه الإنتاج خارج نطاق الثغرة (<=1.13.5)", () => {
  // **لا تفحص node_modules/@grpc/grpc-js المرفوع إلى الأعلى.** npm يرفع هناك
  // نسخة **التطوير** 1.9.16 (من Firebase JS SDK) ويعشّش نسخة الإنتاج تحت
  // google-gax. فالفحص الصحيح أن نحلّ الحزمة **كما يحلّها مستهلكها الإنتاجي**:
  // google-gax هو من ينادي grpc فعلاً في مسار firebase-admin.
  const gaxPath = require.resolve("google-gax", {paths: [root]});
  const resolved = require.resolve("@grpc/grpc-js/package.json",
      {paths: [path.dirname(gaxPath)]});
  const v = JSON.parse(fs.readFileSync(resolved, "utf8")).version;

  const [a, b, c] = parts(v);
  const vulnerable = a < 1 || (a === 1 && b < 13) ||
    (a === 1 && b === 13 && c <= 5);
  assert.ok(
      !vulnerable,
      `grpc-js الذي يراه google-gax = ${v} وهو داخل نطاق الثغرة. هذا مسار ` +
      "الإنتاج (firebase-admin → @google-cloud/firestore → google-gax)، " +
      "فالثغرة حقيقية وتستحقّ ترقية firebase-admin لا تجاهلاً.");

  // والنسخة المصابة مسموحة في شجرة التطوير وحدها — نثبّت أنها هناك فعلاً كي
  // لا يُقرأ نجاح الفحص أعلاه كأن 1.9.16 اختفت.
  const hoisted = ver("@grpc/grpc-js");
  if (hoisted) {
    const [x, y, z] = parts(hoisted);
    const hoistedVuln = x < 1 || (x === 1 && y < 13) ||
      (x === 1 && y === 13 && z <= 5);
    assert.ok(
        !hoistedVuln || ver("@firebase/rules-unit-testing"),
        `النسخة المرفوعة ${hoisted} مصابة ولا @firebase/rules-unit-testing ` +
        "في الشجرة لتفسّرها — من أين جاءت؟ افحص الشجرة قبل التجاهل.");
  }
});

t("@firebase/rules-unit-testing لم تُنزَل إلى 2.x بـaudit fix --force", () => {
  const pkg = JSON.parse(
      fs.readFileSync(path.join(root, "package.json"), "utf8"));
  const dev = pkg.devDependencies || {};
  const range = dev["@firebase/rules-unit-testing"];
  assert.ok(range, "اختفت الحزمة — اختبارات قواعد المحاكي تعتمد عليها");
  const major = Number(range.replace(/^[^\d]*/, "").split(".")[0]);
  assert.ok(
      major >= 5,
      `النسخة ${range}: npm audit fix --force يقترح إنزالها إلى 2.0.7 ` +
      "«إصلاحاً» للسلسلة العالية. ذلك هبوطٌ بثلاث نسخات رئيسية يكسر " +
      "اختبارات القواعد، والسلسلة كلها في شجرة التطوير لا الإنتاج. " +
      "لا تُنزَّل — راجِع رأس هذا الملف.");
});

t("حزمة الإنتاج لا تضمّ @firebase/rules-unit-testing", () => {
  const pkg = JSON.parse(
      fs.readFileSync(path.join(root, "package.json"), "utf8"));
  assert.ok(
      !(pkg.dependencies || {})["@firebase/rules-unit-testing"],
      "حزمة اختبارٍ انتقلت إلى dependencies — فتُنشَر مع الدوال وتصير " +
      "سلسلتها العالية ثغراتَ إنتاج فعلية.");
});

t("شفرتنا لا تستورد uuid مباشرةً (لو فعلت لصارت الثغرة قابلة للوصول)", () => {
  const offenders = fs.readdirSync(root)
      .filter((f) => f.endsWith(".js"))
      .filter((f) => /require\(["']uuid["']\)|from ["']uuid["']/
          .test(fs.readFileSync(path.join(root, f), "utf8")));
  assert.deepStrictEqual(
      offenders, [],
      "استيراد uuid مباشرةً يجعل ثغرة v3/v5/v6 قابلة للوصول: " +
      offenders.join(", "));
});

console.log(`${passed} audit posture tests passed.`);
