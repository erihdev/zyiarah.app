"use strict";
// تحقّق _validateContractPlan لمسار عاملات المناسبات (event_workers) —
// تشغيل: node test/event_worker_contract_validation.test.js (ضمن npm test).
//
// _validateContractPlan داخلية (غير exports.) ولا تُستدعى دوال Firestore حقيقية
// هنا (بلا محاكي) — بنمط notification_dedup.test.js نقرأ نص index.js، لكن بدل
// فحص نصي فقط، نقتطع جسم الدالة بعدّ الأقواس ونبنيها دالة async حقيقية عبر
// AsyncFunction ونُشغّلها بـdb وهمي. هذا يمنحنا تحقّقاً سلوكياً فعلياً (يمرّ/يُرفض)
// دون تعديل سلوك الإنتاج ودون الحاجة لمحاكي Firestore.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {HttpsError} = require("firebase-functions/v2/https");

const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

/**
 * يقتطع نص دالة async باسم معطى من index.js بعدّ الأقواس (يدعم القوالب
 * ${...} لأنها متوازنة الأقواس أصلاً)، ويبنيها دالة قابلة للتشغيل مباشرة.
 * @param {string} name اسم الدالة (بلا "async function").
 * @param {string[]} params أسماء معاملات الدالة كما وردت في تعريفها.
 * @return {Function} دالة async حقيقية.
 */
function extractAsyncFn(name, params) {
  const sig = `async function ${name}(`;
  const start = src.indexOf(sig);
  assert.ok(start >= 0, `${name} غير موجودة في index.js`);
  const braceStart = src.indexOf("{", start);
  let depth = 0;
  let end = braceStart;
  for (; end < src.length; end++) {
    if (src[end] === "{") depth++;
    else if (src[end] === "}") {
      depth--;
      if (depth === 0) break;
    }
  }
  assert.ok(depth === 0, `أقواس غير متوازنة عند اقتطاع ${name}`);
  const body = src.slice(braceStart + 1, end);
  // HttpsError حرّة في نص الدالة الأصلية (مستوردة أعلى index.js) — نمرّرها
  // كمعامل إضافي هنا بدل استيراد كامل index.js (يتجنّب admin.initializeApp
  // وأسرار defineSecret وغيرها من التهيئة الثقيلة غير اللازمة لهذا الاختبار).
  const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
  return new AsyncFunction(...params, "HttpsError", body);
}

const validateContractPlan = extractAsyncFn(
    "_validateContractPlan", ["db", "c", "tx"]);

/**
 * db وهمي بحدّ أدنى: يدعم فقط .collection(name).where(f,"==",v).limit(n).get()
 * كما يستخدمها _validateContractPlan فعلياً (بلا تحويل، بلا محاكي حقيقي).
 * @param {object} collections {اسم_المجموعة: [مستندات...]}
 * @return {object} db وهمي.
 */
function fakeDb(collections) {
  return {
    collection(name) {
      return {
        where(field, op, value) {
          assert.strictEqual(op, "==", "المحاكي يدعم == فقط");
          const all = (collections[name] || []).filter((d) => d[field] === value);
          return {
            limit(n) {
              const docs = all.slice(0, n).map((d) => ({data: () => d}));
              return {get: async () => ({empty: docs.length === 0, docs})};
            },
          };
        },
      };
    },
  };
}

let passed = 0;
/**
 * مُشغّل اختبار مصغّر بنمط pricing.test.js/notification_dedup.test.js.
 * @param {string} name اسم الاختبار.
 * @param {Function} f جسم الاختبار (قد يكون async).
 */
async function t(name, f) {
  await f();
  passed++;
  console.log("  ok -", name);
}

const evPkg = {
  title: "باقة استقبال VIP", subtitle: "", price: 100, visits: 3,
  hours: 4, workers: 4, features: [],
};
const subPkg = {
  title: "الباقة الأسبوعية", subtitle: "", price: 200, visits: 4, features: [],
};
const evPrice = Math.round(evPkg.price * 1.15 * 100) / 100; // 115
const subPrice = Math.round(subPkg.price * 1.15 * 100) / 100; // 230

const db = fakeDb({
  event_worker_packages: [evPkg],
  subscription_packages: [subPkg],
});

(async () => {
  await t("(a) مطابقة صحيحة (سعر + زيارات + عاملات) تمرّ بلا رمي", async () => {
    await validateContractPlan(db, {
      contract_kind: "event_workers", planName: evPkg.title,
      planPrice: evPrice, planVisits: evPkg.visits, workers: evPkg.workers,
    }, undefined, HttpsError);
  });

  await t("(b) سعر مُتلاعَب به يُرفض", async () => {
    await assert.rejects(
        () => validateContractPlan(db, {
          contract_kind: "event_workers", planName: evPkg.title,
          planPrice: 1, planVisits: evPkg.visits, workers: evPkg.workers,
        }, undefined, HttpsError),
        (e) => e instanceof HttpsError && e.code === "failed-precondition");
  });

  await t("(c) عدد عاملات مُتلاعَب به يُرفض", async () => {
    await assert.rejects(
        () => validateContractPlan(db, {
          contract_kind: "event_workers", planName: evPkg.title,
          planPrice: evPrice, planVisits: evPkg.visits, workers: 999,
        }, undefined, HttpsError),
        (e) => e instanceof HttpsError && e.code === "failed-precondition" &&
          /عاملات/.test(e.message));
  });

  await t("(d) غياب contract_kind يسقط افتراضياً إلى subscription_packages", async () => {
    // planName يطابق باقة الاشتراك فقط (غير موجود بهذا الاسم في event_worker_packages)
    // — نجاح هذا الاختبار يثبت أن الاستعلام ذهب فعلاً إلى المجموعة الصحيحة.
    await validateContractPlan(db, {
      planName: subPkg.title, planPrice: subPrice, planVisits: subPkg.visits,
    }, undefined, HttpsError);
    // ولا يُرفض حتى مع وجود حقل workers طارئ — المسار الافتراضي لا يفحصه إطلاقاً.
    await validateContractPlan(db, {
      planName: subPkg.title, planPrice: subPrice, planVisits: subPkg.visits,
      workers: 999,
    }, undefined, HttpsError);
  });

  await t("(e) باقة event_workers بلا حقل workers لا تفرض تحقّق العدد (تراجعية)", async () => {
    const dbNoWorkers = fakeDb({event_worker_packages: [
      {title: "باقة قديمة", price: 100, visits: 2, features: []},
    ]});
    const price = Math.round(100 * 1.15 * 100) / 100;
    await validateContractPlan(dbNoWorkers, {
      contract_kind: "event_workers", planName: "باقة قديمة",
      planPrice: price, planVisits: 2, workers: 12345, // أي رقم — لا يُفحص
    }, undefined, HttpsError);
  });

  console.log(`\nevent_worker_contract_validation: ${passed} passed`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
