/**
 * تصفيرُ بياناتِ التجاربِ قبلَ الإطلاق — **يُشغّلُه المالكُ بيدِه**، لا الأتمتة.
 *
 * حذفُ بياناتٍ لا رجعةَ فيه، فالسكربتُ:
 *   1. **تجربةٌ جافّةٌ افتراضاً** (`--dry-run` ضمنيّ): يَعُدُّ ما سيُحذَفُ ولا
 *      يَلمسُ شيئاً. الحذفُ يَلزمُه `--execute` صراحةً.
 *   2. **نسخةٌ احتياطيّةٌ قبلَ أيِّ حذف**: كلُّ مستندٍ يُكتَبُ JSON في
 *      `backups/reset_<timestamp>/<collection>.json` قبلَ أن يُمسّ — فالفواتيرُ
 *      الضريبيّةُ (ZATCA) للطلباتِ المدفوعةِ تَبقى محفوظةً خارجَ القاعدة، وهو
 *      الاحتفاظُ الذي تَشترطُه لائحةُ ضريبةِ القيمةِ المضافة لو كانَ بينَ
 *      التجاربِ طلبٌ حقيقيٌّ مدفوع.
 *   3. **النطاقُ الافتراضيُّ الطلباتُ وما يَتبعُها فقط**: `orders`،
 *      `store_orders`، `contracts`، وصناديقُ الإشعاراتِ وطوابيرُها، وعدّادُ
 *      أرقامِ الطلبات. ما يَمسُّ المالَ أو الحساباتِ **اختياريٌّ بعلمٍ صريح**:
 *        `--wallets`   تصفيرُ أرصدةِ المحافظِ وسجلِّ الحركاتِ والإحالات.
 *        `--drivers`   تحريرُ السائقينَ (المهمّةُ الجارية، التوفّر، عدّادُ
 *                      الإنجاز، التقييمُ المجمَّع).
 *        `--tickets`   حذفُ تذاكرِ الدعمِ ورسائلِها.
 *        `--audit`     حذفُ سجلِّ التدقيقِ الإداريّ.
 *        `--storage`   حذفُ ملفّاتِ الفواتيرِ (`invoices/`) وصورِ إثباتِ
 *                      التقييم (`order_feedback/`) من التخزين.
 *      الحساباتُ (`users`/`admins`/`drivers` كمستندات) والمناطقُ والباقاتُ
 *      والمنتجاتُ والكوبوناتُ والإعداداتُ **لا تُمَسُّ أبداً** — ليست طلبات.
 *
 * التشغيل (من مجلّدِ `functions/` بعد `npm ci`):
 *   # اعتمادُ حسابِ خدمةٍ له Firestore + (اختياريّاً) Storage
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node reset_test_data.js                       # عَدٌّ فقط
 *   node reset_test_data.js --execute             # الطلباتُ وما يَتبعُها
 *   node reset_test_data.js --execute --drivers --wallets --storage
 *
 * لماذا ليس دالّةً سحابيّةً: حذفٌ شاملٌ لا رجعةَ فيه يَجبُ أن يَكونَ فعلاً
 * بشريّاً واحداً له نسخةٌ احتياطيّةٌ على جهازِ مَن نفّذَه — لا نقطةً قابلةً
 * للنداءِ من أيِّ سطح.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const {initializeApp, getApps} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

if (!getApps().length) {
  initializeApp();
}

const args = new Set(process.argv.slice(2));
const EXECUTE = args.has("--execute");
const WITH = {
  wallets: args.has("--wallets"),
  drivers: args.has("--drivers"),
  tickets: args.has("--tickets"),
  audit: args.has("--audit"),
  storage: args.has("--storage"),
};

/** المجموعاتُ التي تُحذَفُ كاملةً في النطاقِ الافتراضيّ. */
const ORDER_COLLECTIONS = [
  "orders",
  "store_orders",
  "contracts",
  "notifications",
  "notification_queue",
  "notification_triggers",
];

const BATCH = 400; // دونَ سقفِ Firestore (500) بهامش.

const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const backupDir = path.join(__dirname, "backups", `reset_${stamp}`);

/**
 * يُحوّلُ قيمَ Firestore غيرَ القابلةِ للتسلسلِ (Timestamp/GeoPoint/مرجع)
 * إلى JSON قابلٍ للقراءة.
 * @param {*} v القيمة.
 * @return {*} القيمةُ القابلةُ للتسلسل.
 */
function plain(v) {
  if (v === null || v === undefined) return v;
  if (typeof v.toDate === "function") return {__timestamp: v.toDate().toISOString()};
  if (typeof v.latitude === "number" && typeof v.longitude === "number") {
    return {__geopoint: [v.latitude, v.longitude]};
  }
  if (typeof v.path === "string" && typeof v.id === "string" && v.firestore) {
    return {__ref: v.path};
  }
  if (Array.isArray(v)) return v.map(plain);
  if (typeof v === "object") {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k] = plain(x);
    return out;
  }
  return v;
}

/**
 * يَكتبُ لقطةَ مجموعةٍ (ومجموعاتِها الفرعيّةِ) إلى ملفِّ النسخةِ الاحتياطيّة.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} name اسمُ المجموعة.
 * @return {Promise<FirebaseFirestore.DocumentReference[]>} مراجعُ كلِّ ما
 *   سيُحذَف، مرتَّبةً بحيث تَسبقُ المجموعاتُ الفرعيّةُ آباءَها.
 */
async function snapshotCollection(db, name) {
  const refs = [];
  const rows = [];
  const snap = await db.collection(name).get();
  for (const doc of snap.docs) {
    const row = {id: doc.id, data: plain(doc.data()), subcollections: {}};
    const subs = await doc.ref.listCollections();
    for (const sub of subs) {
      const subSnap = await sub.get();
      row.subcollections[sub.id] = subSnap.docs.map((d) => ({id: d.id, data: plain(d.data())}));
      for (const d of subSnap.docs) refs.push(d.ref);
    }
    refs.push(doc.ref);
    rows.push(row);
  }
  if (EXECUTE) {
    fs.mkdirSync(backupDir, {recursive: true});
    fs.writeFileSync(path.join(backupDir, `${name}.json`), JSON.stringify(rows, null, 1));
  }
  return refs;
}

/**
 * يَحذفُ المراجعَ على دفعاتٍ.
 * @param {FirebaseFirestore.Firestore} db
 * @param {FirebaseFirestore.DocumentReference[]} refs
 */
async function deleteRefs(db, refs) {
  for (let i = 0; i < refs.length; i += BATCH) {
    const b = db.batch();
    for (const r of refs.slice(i, i + BATCH)) b.delete(r);
    await b.commit();
  }
}

/**
 * يُطبّقُ تحديثاً واحداً على كلِّ مستندٍ في مجموعة، على دفعات.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} name
 * @param {Object} patch
 * @return {Promise<number>} عددُ المستندات.
 */
async function patchCollection(db, name, patch) {
  const snap = await db.collection(name).get();
  if (EXECUTE) {
    fs.mkdirSync(backupDir, {recursive: true});
    fs.writeFileSync(path.join(backupDir, `${name}.before.json`),
        JSON.stringify(snap.docs.map((d) => ({id: d.id, data: plain(d.data())})), null, 1));
    for (let i = 0; i < snap.docs.length; i += BATCH) {
      const b = db.batch();
      for (const d of snap.docs.slice(i, i + BATCH)) b.update(d.ref, patch);
      await b.commit();
    }
  }
  return snap.size;
}

/**
 * يَحذفُ ملفّاتِ بادئةٍ من مخزنِ المشروع.
 * @param {string} prefix
 * @return {Promise<number>} عددُ الملفّات.
 */
async function wipeStoragePrefix(prefix) {
  const {getStorage} = require("firebase-admin/storage");
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles({prefix});
  if (EXECUTE) {
    for (const f of files) await f.delete({ignoreNotFound: true});
  }
  return files.length;
}

/** نقطةُ الدخول. */
async function main() {
  const db = getFirestore();
  const mode = EXECUTE ? "تنفيذٌ فعليّ" : "تجربةٌ جافّة (لا حذف)";
  console.log(`== تصفيرُ بياناتِ التجارب — ${mode} ==`);
  if (EXECUTE) console.log(`النسخةُ الاحتياطيّة: ${backupDir}`);

  const report = [];

  // ١) الطلباتُ وما يَتبعُها.
  for (const name of ORDER_COLLECTIONS) {
    const refs = await snapshotCollection(db, name);
    if (EXECUTE) await deleteRefs(db, refs);
    report.push([name, refs.length, "حُذف" ]);
  }

  // ٢) عدّادُ أرقامِ الطلبات (`ZY-…`): يَبدأُ من ١٠١ من جديد.
  if (EXECUTE) await db.collection("metadata").doc("order_counter").delete();
  report.push(["metadata/order_counter", 1, "صُفِّر"]);

  // ٣) الاختياريّ.
  if (WITH.tickets) {
    const refs = await snapshotCollection(db, "support_tickets");
    if (EXECUTE) await deleteRefs(db, refs);
    report.push(["support_tickets (+messages)", refs.length, "حُذف"]);
  }
  if (WITH.audit) {
    const refs = await snapshotCollection(db, "audit_logs");
    if (EXECUTE) await deleteRefs(db, refs);
    report.push(["audit_logs", refs.length, "حُذف"]);
  }
  if (WITH.wallets) {
    for (const name of ["transactions", "referrals", "wallet_transactions"]) {
      const refs = await snapshotCollection(db, name);
      if (EXECUTE) await deleteRefs(db, refs);
      report.push([name, refs.length, "حُذف"]);
    }
    const n = await patchCollection(db, "wallets", {
      balance: 0,
      qatrat_points: 0,
      updated_at: FieldValue.serverTimestamp(),
    });
    report.push(["wallets (الرصيدُ والنقاط ← ٠)", n, "صُفِّر"]);
    const promo = await db.collection("promo_codes").where("target_user_id", "!=", null).get();
    if (EXECUTE) {
      fs.writeFileSync(path.join(backupDir, "promo_codes.referral.json"),
          JSON.stringify(promo.docs.map((d) => ({id: d.id, data: plain(d.data())})), null, 1));
      await deleteRefs(db, promo.docs.map((d) => d.ref));
    }
    report.push(["promo_codes (كوبوناتُ الإحالةِ الموجَّهة)", promo.size, "حُذف"]);
  }
  if (WITH.drivers) {
    const n = await patchCollection(db, "drivers", {
      current_order_id: null,
      is_available: true,
      completed_orders_count: 0,
      rating_avg: FieldValue.delete(),
      rating_count: FieldValue.delete(),
    });
    report.push(["drivers (تحريرٌ وتصفيرُ العدّاداتِ والتقييم)", n, "صُفِّر"]);
  }
  if (WITH.storage) {
    for (const prefix of ["invoices/", "order_feedback/"]) {
      const n = await wipeStoragePrefix(prefix);
      report.push([`storage:${prefix}`, n, "حُذف"]);
    }
  }

  console.log("");
  for (const [what, n, verb] of report) {
    console.log(`${EXECUTE ? verb : "سيُحذَف/يُصفَّر"}  ${String(n).padStart(6)}  ${what}`);
  }
  if (!EXECUTE) {
    console.log("\nلم يُحذَف شيء. للتنفيذ: node reset_test_data.js --execute [--drivers --wallets --tickets --audit --storage]");
  } else {
    console.log(`\nتمّ. النسخةُ الاحتياطيّةُ في: ${backupDir}`);
  }
}

main().then(() => process.exit(0)).catch((err) => {
  console.error("فشلَ التصفير:", err);
  process.exit(1);
});
