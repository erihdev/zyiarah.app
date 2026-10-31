"use strict";

// نقلُ العاملاتِ إلى العميلةِ وعودتُهنّ — **السياسةُ** (متى تُطلَبُ رحلةٌ،
// ومتى تُلغى، وما يُكتَبُ على الطلب). النقلُ الفعليُّ (HTTP) في
// `mowasalat_api.js`، والمحاكي هنا للتجربةِ بلا شريك.
//
// ═══ لماذا ═══
//
// المالكُ تعاقدَ مع «مواصلات»: سائقوهم يَنقلون عاملاتِنا من مقرِّ المؤسّسةِ
// إلى بيتِ العميلةِ ويُعيدونهنّ (2026-10-31). ما كان يَفعلُه موظّفٌ بيدِه
// (رسالةٌ بالموعدِ والموقع) يَفعلُه الخادمُ الآن لحظةَ الإسنادِ ولحظةَ
// الإنجاز، ويُبلِّغُ الإدارةَ إن لم تُقبَلِ الرحلةُ قبلَ الموعدِ بوقتٍ كافٍ.
//
// ═══ الشكلُ على مستندِ الطلب ═══
//
//   transport: {
//     outbound: {state, gen, provider, provider_ride_id, reference,
//                requested_at, pickup_at, driver:{name,phone,plate},
//                eta_minutes, error, last_event_at, alerted_unaccepted},
//     return:   {... الشكلُ نفسُه ...},
//   }
//
// `state` ∈ LIVE ∪ FINAL أدناه. `gen` عدّادُ أجيالٍ: كلُّ إعادةِ طلبٍ (تغيُّرُ
// الموعد، تغيُّرُ العاملة، إعادةٌ يدويّةٌ من الإدارة) تَزيدُه، والمرجعُ
// `orderId:leg:gen` يُرسَلُ للشريك ويَعودُ في حدثِه — فحدثٌ عن جيلٍ قديمٍ
// يُهمَل بدلَ أن يَطمسَ الجيلَ الحيّ.
//
// ═══ لماذا مُشغّلٌ لا نداءٌ داخلَ المُسنِد ═══
//
// `driver_id` يُكتَبُ من سبعةِ مساراتٍ (`_assignDriverScheduled` ومُنادوه،
// و`approveAndAssignOrder`، و`rescheduleAssignedOrder`)، والموعدُ يُغيَّرُ من
// مسارَين، والإلغاءُ من أربعة. نداءٌ داخلَ كلِّ واحدٍ هو النمطُ الذي يَتكرّرُ
// هنا باسمِ «قاعدةٌ عامّةٌ مُنفَّذةٌ في بعضِ المواضع». المُشغّلُ على مستندِ
// الطلبِ يَرى الكتابةَ كيفما جاءت — ومَن يُكتَبُ غداً كذلك.
//
// ═══ التطبيقُ هو المنسّق (قرارُ المالك 2026-10-31، «الآليّ») ═══
//
// لا سائقَ للمؤسّسةِ يَضغطُ الأزرارَ الثلاثة. فحالةُ الطلبِ تَتحرّكُ من
// أحداثِ رحلةِ **الذهاب**: السيارةُ انطلقت بالعاملاتِ ⇒ `on_the_way`
// (فتَصِلُ العميلةَ دفعةُ «سائقكِ في الطريق» من مُشغّلِها القائم)، ووصلت
// ⇒ `in_progress`. والإنجازُ **بالوقت**: مدّةُ الطلبِ (`slots.orderHours`)
// من لحظةِ الوصولِ ⇒ `completed` من المكنسةِ، وهو ما يُطلِقُ رحلةَ العودةِ
// والجوائزَ وخصمَ الزيارةِ عبرَ المُشغّلاتِ القائمة (`rewards_handled_by:
// "server"` هو مفتاحُها). الاختيارُ المرفوضُ كان «ضغطةُ الإدارة» لكلِّ
// طلب. وكلُّ تقدّمٍ **إلى الأمامِ فقط** وعلى طلبٍ تَقودُه رحلةٌ (ساقُ
// الذهابِ وصلت) — فطلبٌ يُنفّذُه سائقٌ بشريٌّ بلا رحلةٍ لا تَمَسُّه المكنسة.
//
// ═══ العرف ═══
//
// الوحدةُ تَستقبلُ `db` وسيطاً ولا تَستوردُه (قاعدةُ `refund_engine.js`)،
// و`queuePush` والمزوّدُ والساعةُ تُحقَنُ — فتُختبَرُ بلا محاكٍ ولا شبكة.
// المدّةُ وخريطةُ الحالاتِ النشطةِ من `slots.js` لا تُكتَبُ هنا بيدٍ.

const slots = require("./slots");
const mowasalat = require("./mowasalat_api");

/** مستندُ الإعداداتِ (مقروءٌ لكلِّ مسجَّل — لا أسرارَ فيه). */
const CONFIG_DOC = "system_configs/transport";

const LEGS = Object.freeze(["outbound", "return"]);
const LIVE_STATES = Object.freeze(["requesting", "requested", "accepted", "driving", "arrived"]);
const FINAL_STATES = Object.freeze(["completed", "cancelled", "failed"]);
/** ترتيبُ التقدّم: حدثٌ أدنى رتبةً من المكتوبِ لا يَرجِعُ به (وصولُ الأحداثِ غيرُ مرتَّب). */
const STATE_RANK = Object.freeze({
  requesting: 0, requested: 1, accepted: 2, driving: 3, arrived: 4,
  completed: 5, cancelled: 5, failed: 5,
});
/** الحالاتُ التي يَجوزُ فيها طلبُ رحلةِ الذهاب: قبلَ أن تَتحرّكَ العاملة. */
const PRE_TRIP_STATUSES = Object.freeze(["scheduled", "assigned", "accepted"]);
const DEFAULT_LEAD_MINUTES = 45;
const UNACCEPTED_ALERT_MINUTES = 60;
const ADMIN_ROLES = Object.freeze(["super_admin", "orders_manager"]);
/**
 * حالةُ الطلبِ التي تَستدعيها حالةُ رحلةِ **الذهاب** — والانتقالُ إلى الأمامِ
 * فقط، ومن الحالاتِ المذكورةِ في `from` وحدَها (مرآةُ تسلسلِ
 * `order_service.updateOrderStatus`: لا `in_progress` من `completed`).
 * `completed` للرحلةِ = أُنزِلت العاملاتُ عند العميلة، فهو وصولٌ كذلك.
 */
const ORDER_PROGRESS_BY_RIDE = Object.freeze({
  driving: {to: "on_the_way", from: PRE_TRIP_STATUSES},
  arrived: {to: "in_progress", from: [...PRE_TRIP_STATUSES, "on_the_way"]},
  completed: {to: "in_progress", from: [...PRE_TRIP_STATUSES, "on_the_way"]},
});
/** قيمةُ `completed_by` التي تَكتبُها المكنسةُ — لتمييزِ الإنجازِ الآليِّ في السجلّ. */
const AUTO_COMPLETED_BY = "transport_auto";

/**
 * المزوّدُ التجريبيُّ: يَقبلُ فوراً بسائقٍ وهميٍّ ولا يَلمسُ شبكة. يُفعَّلُ
 * بـ`provider: "simulator"` في مستندِ الإعدادات — لبيئةِ التجربةِ ولاختبارِ
 * المسارِ كلِّه قبلَ أن يَصِلَ من مواصلات شيء.
 */
const simulatorProvider = {
  name: "simulator",
  createRide: async (_cfg, req) => ({
    ok: true, httpStatus: 200,
    rideId: `sim_${String(req.reference).replace(/[^A-Za-z0-9_-]/g, "_")}`,
    status: "accepted",
    result: {driver: {name: "سائق تجريبي", phone: "0500000000", plate: "تجريبي"}},
  }),
  cancelRide: async () => ({ok: true, httpStatus: 200, status: "cancelled", result: {}}),
  getRide: async () => ({ok: true, httpStatus: 200, status: "accepted", result: {}}),
};

/** المزوّدُ الحقيقيّ — نقلُ `mowasalat_api.js` كما هو. */
const mowasalatProvider = {
  name: "mowasalat",
  createRide: mowasalat.createRide,
  cancelRide: mowasalat.cancelRide,
  getRide: mowasalat.getRide,
};

/**
 * قراءةُ الإعداداتِ إلى شكلٍ مُطبَّع. غيابُ المستندِ أو `enabled !== true`
 * يَعني **لا نقلَ** — فالنشرُ آمنٌ قبلَ أن يَقرّرَ المالكُ التفعيل.
 * @param {object|null|undefined} raw بياناتُ `system_configs/transport`
 * @return {{enabled:boolean, provider:string, hq:{lat:number,lng:number,label:string}|null,
 *   leadMinutes:number, baseUrl:string}}
 */
function normalizeConfig(raw) {
  const d = raw && typeof raw === "object" ? raw : {};
  const loc = d.hq_location;
  const hq = loc && typeof loc.latitude === "number" && typeof loc.longitude === "number" ?
    {lat: loc.latitude, lng: loc.longitude, label: String(d.hq_label || "مقر المؤسسة")} :
    null;
  const lead = Number(d.lead_minutes);
  return {
    enabled: d.enabled === true,
    provider: d.provider === "simulator" ? "simulator" : "mowasalat",
    hq,
    leadMinutes: Number.isFinite(lead) && lead > 0 ? lead : DEFAULT_LEAD_MINUTES,
    baseUrl: String(d.api_base_url || ""),
  };
}

/**
 * @param {object} db
 * @return {Promise<object>} إعداداتٌ مُطبَّعة
 */
async function readConfig(db) {
  const [col, id] = CONFIG_DOC.split("/");
  const snap = await db.collection(col).doc(id).get();
  return normalizeConfig(snap.exists ? snap.data() : null);
}

/**
 * اختيارُ المزوّد. مواصلات بلا مفتاحٍ أو عنوانٍ ⇒ `null` (مُعطَّل عمليّاً
 * ويُقالُ ذلك في السجلّ) — لا سقوطَ صامتاً إلى المحاكي.
 * @param {object} cfg إعداداتٌ مُطبَّعة
 * @param {{apiKey?:string}} secrets
 * @return {{name:string, api:object, cfg:object}|null}
 */
function selectProvider(cfg, secrets) {
  if (cfg.provider === "simulator") return {name: "simulator", api: simulatorProvider, cfg: {}};
  const apiKey = secrets && secrets.apiKey;
  if (!apiKey || !cfg.baseUrl) return null;
  return {name: "mowasalat", api: mowasalatProvider, cfg: {baseUrl: cfg.baseUrl, apiKey}};
}

/**
 * @param {object} order
 * @param {string} leg
 * @return {object|null}
 */
function legOf(order, leg) {
  const t = order && order.transport;
  return t && t[leg] && typeof t[leg] === "object" ? t[leg] : null;
}

/**
 * @param {object|null} l
 * @return {boolean}
 */
function isLive(l) {
  return !!l && LIVE_STATES.includes(l.state);
}

/**
 * @param {object} order
 * @return {number|null} لحظةُ الموعدِ بالمللي، أو null
 */
function serviceMs(order) {
  const sd = order && order.service_date;
  if (!sd) return null;
  if (typeof sd.toMillis === "function") return sd.toMillis();
  if (typeof sd.getTime === "function") return sd.getTime();
  return null;
}

/**
 * القرارُ الصِّرف: ما الذي يَستدعيه تغيُّرُ الطلب؟ نقيٌّ ليُختبَرَ جدولاً.
 * @param {object|null} before
 * @param {object|null} after
 * @param {number} nowMs
 * @return {Array<{type:string, leg?:string, replace?:boolean, legs?:string[]}>}
 */
function decide(before, after, nowMs) {
  const b = before || {};
  const liveLegsOf = (o) => LEGS.filter((l) => isLive(legOf(o, l)));
  if (!after) {
    const legs = liveLegsOf(b);
    return legs.length ? [{type: "cancel", legs}] : [];
  }
  const a = after;
  const hadDriver = !!b.driver_id;
  const hasDriver = !!a.driver_id;
  const driverChanged = hasDriver && (b.driver_id || null) !== a.driver_id;
  const bMs = serviceMs(b);
  const aMs = serviceMs(a);
  const dateChanged = bMs !== null && aMs !== null && bMs !== aMs;
  const cancelledNow = b.status !== "cancelled" && a.status === "cancelled";
  const driverRemoved = hadDriver && !hasDriver;
  const completedNow = b.status !== "completed" && a.status === "completed";

  // إلغاءٌ أو فكُّ إسناد: كلُّ رحلةٍ حيّةٍ تُلغى.
  if (cancelledNow || driverRemoved) {
    const legs = liveLegsOf(a);
    return legs.length ? [{type: "cancel", legs}] : [];
  }

  // إنجازٌ: رحلةُ عودةٍ واحدةٌ، إن كانت هناك عاملةٌ أصلاً.
  if (completedNow && hasDriver) {
    const ret = legOf(a, "return");
    if (!ret) return [{type: "request", leg: "return", replace: false}];
    return [];
  }

  // قبلَ التحرّك: ذهابٌ لطلبٍ مدفوعٍ مُسنَدٍ ذي موعد.
  if (hasDriver && a.is_paid === true && PRE_TRIP_STATUSES.includes(a.status) && aMs !== null) {
    const out = legOf(a, "outbound");
    const pickupMs = aMs; // الحدُّ الأدنى: لا نَطلبُ رحلةً لموعدٍ مضى
    if (pickupMs <= nowMs) return [];
    // لا رحلةَ أصلاً ⇒ تُطلَب (يَشملُ طلباً أُسنِدَ قبلَ تفعيلِ الميزة: أوّلُ
    // كتابةٍ بعدَ التفعيلِ تَطلبُها — المُشغّلُ يُصحّحُ نفسَه).
    if (!out) return [{type: "request", leg: "outbound", replace: false}];
    // هل تَغيّرَ ما بُنيت عليه الرحلة؟ يُقارَنُ بما سُجّل على الساقِ وقتَ
    // حجزِها، لا بقبلَ/بعدَ المُشغّل: إعادةُ تسليمِ الحدثِ نفسِه (قبلَ بلا
    // عاملة ⇒ بعدَ بعاملة) تَقعُ على ساقٍ حُجزت لهذه العاملةِ وهذا الموعدِ
    // فلا تُستبدَل. والساقُ القديمةُ بلا هذَين الحقلَين تَسقطُ إلى الفرق.
    const rebuilt = "for_driver_id" in out || "for_service_ms" in out ?
      (out.for_driver_id || null) !== a.driver_id || Number(out.for_service_ms) !== aMs :
      (driverChanged || dateChanged);
    // رحلةٌ انتهت (أُلغيت/فشلت) ثمّ تَغيّرَ ما بُنيت عليه ⇒ جيلٌ جديد.
    if (FINAL_STATES.includes(out.state) && rebuilt) {
      return [{type: "request", leg: "outbound", replace: false}];
    }
    // رحلةٌ حيّةٌ وتَغيّرَ ما بُنيت عليه ⇒ تُلغى وتُطلَبُ بديلتُها.
    if (isLive(out) && rebuilt) {
      return [{type: "request", leg: "outbound", replace: true}];
    }
  }
  return [];
}

/**
 * بناءُ طلبِ الرحلةِ بشكلِنا الداخليّ.
 * @param {object} order
 * @param {object} cfg إعداداتٌ مُطبَّعة (فيها hq)
 * @param {string} leg
 * @param {number} gen
 * @param {string} orderId
 * @param {number} nowMs
 * @return {object|null} null إن غابَ شرطٌ (مقرٌّ، موقعٌ، موعد)
 */
function buildRideRequest(order, cfg, leg, gen, orderId, nowMs) {
  if (!cfg.hq) return null;
  const loc = order.location;
  if (!loc || typeof loc.latitude !== "number" || typeof loc.longitude !== "number") return null;
  const code = order.code || orderId;
  const client = {lat: loc.latitude, lng: loc.longitude,
    label: `عميلة ${order.client_name || ""} — طلب #${code}`.replace(/\s+—/, " —")};
  const hq = {lat: cfg.hq.lat, lng: cfg.hq.lng, label: cfg.hq.label};
  let pickupMs;
  if (leg === "outbound") {
    const sMs = serviceMs(order);
    if (sMs === null) return null;
    pickupMs = sMs - cfg.leadMinutes * 60 * 1000;
  } else {
    pickupMs = nowMs;
  }
  const count = workerCount(order);
  return {
    reference: `${orderId}:${leg}:${gen}`,
    pickup: leg === "outbound" ? hq : client,
    dropoff: leg === "outbound" ? client : hq,
    pickupAt: new Date(pickupMs).toISOString(),
    pickupMs,
    // قرارُ المالكِ (2026-10-31): لا اسمَ ولا جوّالَ للعاملة يَخرجُ إلى مواصلات —
    // العددُ وحدَه. العاملةُ لا دورَ لها في المسار ولا حسابَ تَستعمله.
    passengerCount: count,
    notes: `طلب زيارة #${code} — ${leg === "outbound" ? "ذهاب" : "عودة"}` +
      ` — ${count} ${count === 1 ? "عاملة" : "عاملات"} (${slots.orderHours(order)} س)`,
  };
}

/**
 * عددُ العاملاتِ في الطلب، من بياناتِ الخدمةِ التي حجزتها العميلة:
 * باقاتُ السكن `crewCount`، وعاملاتُ المناسبات `workers`. غيرُهما أو قيمةٌ
 * فاسدةٌ ⇒ ١ (لا رحلةَ بلا راكبة، والصفرُ ليس عدداً هنا).
 * @param {object} order
 * @return {number}
 */
function workerCount(order) {
  const meta = (order && order.service_meta) || {};
  const raw = Number(meta.crewCount !== undefined ? meta.crewCount : meta.workers);
  return Number.isInteger(raw) && raw >= 1 && raw <= 20 ? raw : 1;
}

/**
 * حجزُ الجيلِ ذرّيّاً: يَكتبُ `requesting` ويُعيدُ الجيلَ الجديدَ والسابقَ،
 * أو null إن كانت رحلةٌ حيّةٌ قائمةً و`replace` كاذب (المُشغّلُ يُعادُ
 * إطلاقُه على كتاباتِنا نفسِها — فهذا ما يَمنعُ طلبَ الرحلةِ مرّتَين).
 * @param {object} db
 * @param {string} orderId
 * @param {string} leg
 * @param {boolean} replace
 * @param {string} providerName
 * @param {Date} now
 * @return {Promise<{gen:number, previous:object|null, order:object}|null>}
 */
async function claimLeg(db, orderId, leg, replace, providerName, now) {
  const ref = db.collection("orders").doc(orderId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const order = snap.data();
    const prev = legOf(order, leg);
    if (isLive(prev) && !replace) return null;
    const gen = ((prev && Number(prev.gen)) || 0) + 1;
    tx.update(ref, {
      [`transport.${leg}`]: {
        state: "requesting", gen, provider: providerName,
        reference: `${orderId}:${leg}:${gen}`, requested_at: now,
        // ما بُنيت عليه الرحلة — `decide` يُقارنُ بهما لا بقبلَ/بعدَ المُشغّل،
        // فإعادةُ تسليمِ حدثٍ قديمٍ لا تُولّدُ جيلاً جديداً.
        for_driver_id: order.driver_id || null,
        for_service_ms: serviceMs(order),
      },
    });
    return {gen, previous: prev, order};
  });
}

/**
 * كتابةُ نتيجةٍ على جيلٍ بعينِه — إن تَغيّرَ الجيلُ في الأثناءِ لا يُكتَبُ شيء.
 * @param {object} db
 * @param {string} orderId
 * @param {string} leg
 * @param {number} gen
 * @param {object} patch حقولٌ داخلَ `transport.{leg}`
 * @return {Promise<boolean>} هل كُتب
 */
async function patchLeg(db, orderId, leg, gen, patch) {
  const ref = db.collection("orders").doc(orderId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const cur = legOf(snap.data(), leg);
    if (!cur || Number(cur.gen) !== gen) return false;
    const upd = {};
    for (const [k, v] of Object.entries(patch)) upd[`transport.${leg}.${k}`] = v;
    tx.update(ref, upd);
    return true;
  });
}

/**
 * طلبُ رحلةٍ لساقٍ: حجزٌ ثمّ إلغاءُ السابقةِ (إن حيّة) ثمّ النداء. الفشلُ
 * يُكتَبُ `failed` **ويُنبَّهُ عنه** — لا دفنَ صامتاً (قاعدةُ `refund_engine`).
 * @param {object} db
 * @param {string} orderId
 * @param {string} leg
 * @param {boolean} replace
 * @param {{cfg:object, provider:object, queuePush:Function, now:Date}} deps
 * @return {Promise<{outcome:string, gen?:number}>}
 */
async function requestLeg(db, orderId, leg, replace, deps) {
  const {cfg, provider, queuePush, now} = deps;
  const claim = await claimLeg(db, orderId, leg, replace, provider.name, now);
  if (!claim) return {outcome: "noop"};
  const {gen, previous, order} = claim;
  const code = order.code || orderId;

  if (previous && isLive(previous) && previous.provider_ride_id) {
    try {
      await provider.api.cancelRide(provider.cfg, previous.provider_ride_id);
    } catch (e) {
      console.warn(`[transport] cancel of superseded ride failed ${orderId}/${leg}: ${e.message}`);
    }
  }

  const req = buildRideRequest(order, cfg, leg, gen, orderId, now.getTime());
  if (!req) {
    const why = !cfg.hq ? "لا موقعَ مقرٍّ في الإعدادات" :
      (!order.location ? "الطلب بلا موقع" : "الطلب بلا موعد");
    await patchLeg(db, orderId, leg, gen, {state: "failed", error: why, last_event_at: now});
    await queuePush("ADMIN_BROADCAST", "تعذّر طلب رحلة التوصيل 🚐",
        `الطلب #${code}: لم تُطلب رحلة ${leg === "outbound" ? "الذهاب" : "العودة"} — ${why}.`,
        "admin_transport_alert", {orderId, leg}, ADMIN_ROLES).catch(() => {});
    return {outcome: "failed", gen};
  }

  let res;
  try {
    res = await provider.api.createRide(provider.cfg, req);
  } catch (e) {
    res = {ok: false, httpStatus: 0, rideId: null, status: null, result: {error: e.message}};
  }
  if (!res.ok) {
    const err = `HTTP ${res.httpStatus}: ${(res.result && (res.result.message || res.result.error)) || "رفض المزوّد"}`;
    await patchLeg(db, orderId, leg, gen, {
      state: "failed", error: String(err).slice(0, 300), pickup_at: new Date(req.pickupMs),
      last_event_at: now,
    });
    await queuePush("ADMIN_BROADCAST", "تعذّر طلب رحلة التوصيل 🚐",
        `الطلب #${code}: رفض «${provider.name}» رحلة ${leg === "outbound" ? "الذهاب" : "العودة"}` +
        ` — ${err}. احجزها يدويّاً أو أعد المحاولة من تفاصيل الطلب.`,
        "admin_transport_alert", {orderId, leg}, ADMIN_ROLES).catch(() => {});
    return {outcome: "failed", gen};
  }
  const d = res.result && res.result.driver;
  await patchLeg(db, orderId, leg, gen, {
    state: res.status || "requested",
    provider_ride_id: res.rideId,
    pickup_at: new Date(req.pickupMs),
    error: null,
    last_event_at: now,
    ...(d ? {driver: {name: String(d.name || ""), phone: String(d.phone || ""),
      plate: String(d.plate || "")}} : {}),
  });
  return {outcome: "requested", gen};
}

/**
 * إلغاءُ السيقانِ الحيّة — تُكتَبُ `cancelled` حتى لو فشلَ النداء (الطلبُ
 * نفسُه أُلغي، فلا معنى لرحلةٍ «حيّة» عليه)، ويُنبَّهُ عن الفشل.
 * @param {object} db
 * @param {string} orderId
 * @param {string[]} legs
 * @param {{provider:object|null, queuePush:Function, now:Date}} deps
 * @return {Promise<void>}
 */
async function cancelLegs(db, orderId, legs, deps) {
  const {provider, queuePush, now} = deps;
  const ref = db.collection("orders").doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const order = snap.data();
  for (const leg of legs) {
    const l = legOf(order, leg);
    if (!isLive(l)) continue;
    let ok = true;
    if (l.provider_ride_id && provider) {
      try {
        const r = await provider.api.cancelRide(provider.cfg, l.provider_ride_id);
        ok = r.ok;
      } catch {
        ok = false;
      }
    }
    await patchLeg(db, orderId, leg, Number(l.gen), {state: "cancelled", last_event_at: now,
      ...(ok ? {} : {error: "تعذّر إبلاغ المزوّد بالإلغاء"})});
    if (!ok) {
      await queuePush("ADMIN_BROADCAST", "تعذّر إلغاء رحلة التوصيل 🚐",
          `الطلب #${order.code || orderId}: لم يَقبل المزوّد إلغاء رحلة ` +
          `${leg === "outbound" ? "الذهاب" : "العودة"} — ألغِها يدويّاً.`,
          "admin_transport_alert", {orderId, leg}, ADMIN_ROLES).catch(() => {});
    }
  }
}

/**
 * نقطةُ دخولِ المُشغّل.
 * @param {object} db
 * @param {{orderId:string, before:object|null, after:object|null}} change
 * @param {{cfg:object, provider:object|null, queuePush:Function, now:Date}} deps
 * @return {Promise<Array<object>>} ما نُفِّذ (للسجلّ وللاختبار)
 */
async function handleOrderChange(db, change, deps) {
  const {orderId, before, after} = change;
  const actions = decide(before, after, deps.now.getTime());
  const done = [];
  for (const act of actions) {
    if (act.type === "cancel") {
      await cancelLegs(db, orderId, act.legs, deps);
      done.push({...act});
    } else if (act.type === "request") {
      if (!deps.cfg.enabled || !deps.provider) {
        done.push({...act, outcome: "disabled"});
        continue;
      }
      const r = await requestLeg(db, orderId, act.leg, act.replace, deps);
      done.push({...act, ...r});
    }
  }
  return done;
}

/**
 * تطبيقُ حدثٍ من الشريك (ويب هوك). المرجعُ يَحملُ الجيلَ، فحدثٌ عن جيلٍ
 * غيرِ الحيّ يُهمَل؛ وحدثٌ أدنى رتبةً من المكتوبِ لا يَرجِعُ به.
 * @param {object} db
 * @param {object} ev ناتجُ `mowasalat.parseWebhookEvent`
 * @param {{queuePush:Function, now:Date, GeoPoint?:Function}} deps
 * @return {Promise<{applied:boolean, reason?:string, orderId?:string, leg?:string, state?:string,
 *   orderStatusTo?:string|null}>}
 */
async function applyRideEvent(db, ev, deps) {
  const {queuePush, now, GeoPoint} = deps;
  if (!ev || !ev.reference) return {applied: false, reason: "no_reference"};
  const parts = String(ev.reference).split(":");
  if (parts.length !== 3) return {applied: false, reason: "bad_reference"};
  const [orderId, leg, genStr] = parts;
  const gen = Number(genStr);
  if (!LEGS.includes(leg) || !Number.isInteger(gen)) return {applied: false, reason: "bad_reference"};
  if (!ev.status) return {applied: false, reason: "unknown_status"};

  const ref = db.collection("orders").doc(orderId);
  const out = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return {applied: false, reason: "no_order"};
    const order = snap.data();
    const cur = legOf(order, leg);
    if (!cur || Number(cur.gen) !== gen) return {applied: false, reason: "stale_gen"};
    if (cur.provider_ride_id && ev.rideId && cur.provider_ride_id !== ev.rideId) {
      return {applied: false, reason: "ride_mismatch"};
    }
    if (FINAL_STATES.includes(cur.state)) return {applied: false, reason: "already_final"};
    if ((STATE_RANK[ev.status] || 0) < (STATE_RANK[cur.state] || 0)) {
      return {applied: false, reason: "regress"};
    }
    const prevState = cur.state;
    const upd = {
      [`transport.${leg}.state`]: ev.status,
      [`transport.${leg}.last_event_at`]: now,
    };
    if (ev.driver && (ev.driver.name || ev.driver.phone)) upd[`transport.${leg}.driver`] = ev.driver;
    if (ev.etaMinutes !== null && ev.etaMinutes !== undefined) {
      upd[`transport.${leg}.eta_minutes`] = ev.etaMinutes;
    }
    if (!cur.provider_ride_id && ev.rideId) upd[`transport.${leg}.provider_ride_id`] = ev.rideId;
    // موقعُ السيارةِ ⇒ `driver_location` الذي تَقرؤه خريطةُ تتبّعِ العميلة —
    // على ساقِ الذهابِ الحيّةِ وحدَها (سيارةُ العودةِ لا تَعنيها).
    if (ev.location && leg === "outbound" && LIVE_STATES.includes(ev.status) && GeoPoint) {
      upd.driver_location = new GeoPoint(ev.location.lat, ev.location.lng);
      upd[`transport.${leg}.location`] = ev.location;
    }
    // التطبيقُ هو المنسّق: رحلةُ الذهابِ تُحرّكُ حالةَ الطلبِ إلى الأمام.
    const prog = leg === "outbound" ? ORDER_PROGRESS_BY_RIDE[ev.status] : null;
    const orderStatusTo = prog && prog.from.includes(order.status) ? prog.to : null;
    if (orderStatusTo) {
      upd.status = orderStatusTo;
      upd.status_source = "transport";
      if (orderStatusTo === "on_the_way") upd.on_the_way_at = now;
      if (orderStatusTo === "in_progress") {
        upd.arrived_at = now;
        upd.start_time = now;
      }
    }
    tx.update(ref, upd);
    return {applied: true, orderId, leg, state: ev.status, prevState, orderStatusTo,
      driverUid: order.driver_id || null, code: order.code || orderId};
  });
  if (!out.applied) return out;

  // إبلاغُ العاملةِ (حسابُ «السائق» في زيارة) بما يَعنيها، والإدارةِ بما يُعطّل.
  const legAr = leg === "outbound" ? "الذهاب" : "العودة";
  if (out.driverUid && ev.status === "accepted" && out.prevState !== "accepted") {
    const dn = ev.driver && ev.driver.name ? ` (${ev.driver.name}${ev.driver.plate ? " — " + ev.driver.plate : ""})` : "";
    await queuePush(out.driverUid, "تأكّدت رحلة " + legAr + " 🚐",
        `سيارة التوصيل لطلب #${out.code} مؤكّدة${dn}.`,
        "driver_transport", {orderId, leg}).catch(() => {});
  } else if (out.driverUid && ev.status === "arrived") {
    await queuePush(out.driverUid, "وصلت سيارة التوصيل 🚐",
        `سيارة ${legAr} لطلب #${out.code} بانتظارك الآن.`,
        "driver_transport", {orderId, leg}).catch(() => {});
  }
  if (ev.status === "cancelled") {
    await queuePush("ADMIN_BROADCAST", "ألغى المزوّد رحلة التوصيل ⚠️",
        `الطلب #${out.code}: أُلغيت رحلة ${legAr} من جهة المزوّد — احجز بديلاً أو أعد المحاولة من تفاصيل الطلب.`,
        "admin_transport_alert", {orderId, leg}, ADMIN_ROLES).catch(() => {});
  }
  return {applied: true, orderId, leg, state: ev.status, orderStatusTo: out.orderStatusTo || null};
}

/**
 * مكنسةٌ: رحلةُ ذهابٍ لم تُقبَل والموعدُ على بُعدِ أقلَّ من ساعة ⇒ تنبيهٌ
 * إداريٌّ واحد. الاستعلامُ مدًى واحدٌ على `service_date` ثمّ ترشيحٌ محلّيٌّ
 * (لا فهرسَ مركَّباً — قاعدةُ المستودع)، والنافذةُ قصيرةٌ فلا تَمتلئ.
 * @param {object} db
 * @param {{queuePush:Function, now:Date, Timestamp:object}} deps
 * @return {Promise<number>} عددُ التنبيهات
 */
async function sweepUnacceptedRides(db, deps) {
  const {queuePush, now, Timestamp} = deps;
  const nowMs = now.getTime();
  const from = Timestamp.fromDate(new Date(nowMs - 60 * 60 * 1000));
  const to = Timestamp.fromDate(new Date(nowMs + 3 * 60 * 60 * 1000));
  const snap = await db.collection("orders")
      .where("service_date", ">=", from)
      .where("service_date", "<", to)
      .limit(200).get();
  let alerts = 0;
  for (const doc of snap.docs) {
    const o = doc.data();
    const out = legOf(o, "outbound");
    if (!out || !["requesting", "requested"].includes(out.state)) continue;
    if (out.alerted_unaccepted === true) continue;
    if (!PRE_TRIP_STATUSES.includes(o.status)) continue;
    const pickupMs = out.pickup_at && typeof out.pickup_at.toMillis === "function" ?
      out.pickup_at.toMillis() : (serviceMs(o) || 0);
    if (pickupMs - nowMs > UNACCEPTED_ALERT_MINUTES * 60 * 1000) continue;
    const okWrite = await patchLeg(db, doc.id, "outbound", Number(out.gen), {alerted_unaccepted: true});
    if (!okWrite) continue;
    await queuePush("ADMIN_BROADCAST", "رحلة توصيل لم تُقبل بعد ⏳",
        `الطلب #${o.code || doc.id}: رحلة الذهاب ما زالت بلا سائق والموعد قريب — تابع مع المزوّد أو احجز بديلاً.`,
        "admin_transport_alert", {orderId: doc.id, leg: "outbound"}, ADMIN_ROLES).catch(() => {});
    alerts++;
  }
  return alerts;
}

/**
 * الإنجازُ الآليُّ بالوقت: طلبٌ `in_progress` وصلت رحلةُ ذهابِه ومضت مدّتُه
 * من لحظةِ الوصولِ ⇒ `completed`. الكتابةُ تُحاكي ما يَكتبُه إكمالُ السائقِ
 * في `order_service.updateOrderStatus` (الحالةُ، `end_time`،
 * `rewards_handled_by: "server"` — مفتاحُ الجوائزِ وخصمِ الزيارة — وتحريرُ
 * مستندِ السائقِ بحارسِ المِلكيّةِ نفسِه)، فتَسري عليه المُشغّلاتُ القائمةُ
 * كلُّها بلا استثناء، ومنها `onOrderTransport` الذي يَطلبُ رحلةَ العودة.
 *
 * الاستعلامُ مساواةٌ واحدةٌ على `status` (لا فهرسَ مركَّباً) ثمّ ترشيحٌ
 * محلّيّ. مجموعةُ `in_progress` جمهورُ لحظةٍ لا تراكُم، فلا تَزدحمُ النافذة.
 * والشرطُ «ساقُ الذهابِ وصلت» هو ما يَحصُرُ الأثرَ في الطلباتِ التي يَقودُها
 * النقلُ: طلبٌ يُنفّذُه سائقٌ بشريٌّ بلا رحلةٍ لا تَمَسُّه.
 * @param {object} db
 * @param {{now:Date, Timestamp:object, FieldValue?:object}} deps
 * @return {Promise<number>} عددُ ما أُنجِز
 */
async function sweepAutoComplete(db, deps) {
  const {now, FieldValue} = deps;
  const nowMs = now.getTime();
  const snap = await db.collection("orders")
      .where("status", "==", "in_progress")
      .limit(200).get();
  let done = 0;
  for (const doc of snap.docs) {
    const o = doc.data();
    const out = legOf(o, "outbound");
    if (!out || !["arrived", "completed"].includes(out.state)) continue;
    if (o.is_paid !== true) continue;
    const arrived = o.arrived_at || o.start_time;
    const arrivedMs = arrived && typeof arrived.toMillis === "function" ? arrived.toMillis() :
      (arrived && typeof arrived.getTime === "function" ? arrived.getTime() : null);
    if (arrivedMs === null) continue;
    const dueMs = arrivedMs + slots.orderHours(o) * 60 * 60 * 1000;
    if (dueMs > nowMs) continue;

    const ref = db.collection("orders").doc(doc.id);
    const driverId = o.driver_id || null;
    const okWrite = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      if (!fresh.exists || fresh.data().status !== "in_progress") return false;
      const driverRef = driverId ? db.collection("drivers").doc(driverId) : null;
      const driverSnap = driverRef ? await tx.get(driverRef) : null;
      tx.update(ref, {
        status: "completed",
        end_time: now,
        completed_at: now,
        rewards_handled_by: "server",
        completed_by: AUTO_COMPLETED_BY,
        status_source: "transport",
      });
      if (driverSnap && driverSnap.exists) {
        const dCur = driverSnap.data().current_order_id;
        const owns = dCur === null || dCur === undefined || dCur === "" || dCur === doc.id;
        const du = {};
        if (owns) {
          du.current_order_id = null;
          du.is_available = true;
        }
        if (FieldValue) du.completed_orders_count = FieldValue.increment(1);
        if (Object.keys(du).length) tx.update(driverRef, du);
      }
      return true;
    });
    if (okWrite) done++;
  }
  return done;
}

module.exports = {
  CONFIG_DOC,
  LEGS,
  LIVE_STATES,
  FINAL_STATES,
  PRE_TRIP_STATUSES,
  DEFAULT_LEAD_MINUTES,
  UNACCEPTED_ALERT_MINUTES,
  ADMIN_ROLES,
  ORDER_PROGRESS_BY_RIDE,
  AUTO_COMPLETED_BY,
  simulatorProvider,
  mowasalatProvider,
  normalizeConfig,
  readConfig,
  selectProvider,
  legOf,
  isLive,
  decide,
  buildRideRequest,
  workerCount,
  claimLeg,
  requestLeg,
  cancelLegs,
  handleOrderChange,
  applyRideEvent,
  sweepUnacceptedRides,
  sweepAutoComplete,
};
