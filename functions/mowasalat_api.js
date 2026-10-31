"use strict";

// نقلُ العاملاتِ عبر «مواصلات» — **النقلُ (HTTP) وحدَه**، لا السياسة.
//
// ═══ لماذا وحدةٌ مستقلّة ═══
//
// على نسقِ `moyasar_api.js` و`tamara_api.js`: كلُّ نداءِ HTTP إلى مواصلات
// يَمُرُّ من هنا، فلا يُكتَبُ عنوانٌ ولا ترويسةُ مصادقةٍ بيدٍ في موضعٍ آخر
// (العلّةُ الموثَّقةُ: أربعُ نسخٍ من ترويسةِ ميسر، تسعٌ من ترويسةِ تمارا، ولا
// نسختانِ متطابقتان). أمّا **متى** تُطلَبُ الرحلةُ ومتى تُلغى فذاك في
// `transport.js`.
//
// ═══ العقدُ افتراضيٌّ حتى تَصِلَ وثائقُ مواصلات ═══
//
// لا واجهةَ معلَنةً على muasalat.net (2026-10-31). الشكلُ المكتوبُ هنا هو
// **ما نُراسِلُهم به وما سنُعدِّلُه عند وصولِ وثائقِهم**، وقد كُتب بحيث يكونَ
// التعديلُ محصوراً في هذا الملفِّ: الطلبُ (`createRide`) والإلغاءُ
// (`cancelRide`) والاستعلامُ (`getRide`) وتوقيعُ الويب هوك
// (`verifySignature`) وخريطةُ الحالاتِ (`normalizeStatus`). ما وراءَ ذلك
// (`transport.js` والمُشغّلاتُ والشاشات) لا يَعرفُ شكلَ مواصلات أصلاً.
//
// ═══ عقدُ الخطأ ═══
//
// كعقدِ ميسر: **لا رميَ على حالةِ HTTP** — تُعادُ `{ok, httpStatus, rideId,
// status, result}` ويُقرّرُ المُنادي. أخطاءُ الشبكةِ تَنتشرُ (المُنادي في
// `transport.js` يَلتقطُها ويَكتبُ `failed` ويُنبّه). والتحليلُ متسامحٌ: جسمٌ
// ليس JSON يَصيرُ `{}` لا استثناءً خامّاً.

/** ترويسةُ التوقيعِ المتوقَّعةُ في الويب هوك (افتراضيّة — تُعدَّلُ مع الوثائق). */
const SIGNATURE_HEADER = "x-mowasalat-signature";

/**
 * حالاتُ مواصلات → حالاتُنا الداخليّة (`transport.js`). ما لم يُعرَف يُعادُ
 * `null` فيُهمَلُ الحدثُ بدلَ أن يُكتَبَ شيءٌ غيرُ مفهومٍ على الطلب.
 */
const STATUS_MAP = Object.freeze({
  requested: "requested",
  pending: "requested",
  accepted: "accepted",
  assigned: "accepted",
  driver_assigned: "accepted",
  en_route: "en_route",
  on_the_way: "en_route",
  started: "en_route",
  arrived: "arrived",
  picked_up: "en_route",
  completed: "completed",
  finished: "completed",
  cancelled: "cancelled",
  canceled: "cancelled",
  rejected: "cancelled",
  no_driver: "cancelled",
});

/**
 * @param {string|undefined} s حالةُ مواصلات كما وصلت
 * @return {string|null} حالتُنا، أو null إن لم تُعرَف
 */
function normalizeStatus(s) {
  if (typeof s !== "string") return null;
  return STATUS_MAP[s.trim().toLowerCase()] || null;
}

/**
 * ترويساتُ النداء — مفتاحٌ واحدٌ حاملٌ (افتراضيّ: `Authorization: Bearer`).
 * @param {string} apiKey
 * @return {object}
 */
function authHeaders(apiKey) {
  return {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
}

/**
 * تحليلٌ متسامحٌ للردّ.
 * @param {Response} r
 * @return {Promise<object>}
 */
async function parseJson(r) {
  try {
    const text = await r.text();
    if (!text) return {};
    return JSON.parse(text);
  } catch {
    return {};
  }
}

/**
 * @param {string} baseUrl
 * @param {string} p
 * @return {string}
 */
function urlOf(baseUrl, p) {
  return `${String(baseUrl || "").replace(/\/+$/, "")}${p}`;
}

/**
 * إنشاءُ رحلةٍ محجوزةٍ مسبقاً.
 *
 * `req` بشكلِنا الداخليّ (يَبنيه `transport.buildRideRequest`):
 *   {reference, pickup:{lat,lng,label}, dropoff:{lat,lng,label},
 *    pickupAt: ISO, passenger:{name, phone}, notes}
 * @param {{baseUrl:string, apiKey:string}} cfg
 * @param {object} req
 * @return {Promise<{ok:boolean, httpStatus:number, rideId:string|null,
 *   status:string|null, result:object}>}
 */
async function createRide(cfg, req) {
  const body = {
    reference: req.reference,
    scheduled_at: req.pickupAt,
    pickup: {lat: req.pickup.lat, lng: req.pickup.lng, label: req.pickup.label},
    dropoff: {lat: req.dropoff.lat, lng: req.dropoff.lng, label: req.dropoff.label},
    passenger: {name: req.passenger.name, phone: req.passenger.phone},
    notes: req.notes || "",
  };
  const r = await fetch(urlOf(cfg.baseUrl, "/v1/rides"), {
    method: "POST",
    headers: authHeaders(cfg.apiKey),
    body: JSON.stringify(body),
  });
  const result = await parseJson(r);
  const rideId = result.id || result.ride_id || null;
  return {
    ok: r.ok && !!rideId,
    httpStatus: r.status,
    rideId: rideId ? String(rideId) : null,
    status: normalizeStatus(result.status) || (r.ok ? "requested" : null),
    result,
  };
}

/**
 * إلغاءُ رحلة. 404 يُعادُ `ok: true` مع `status: "cancelled"`: رحلةٌ لا
 * يَعرفُها مواصلاتُ هي رحلةٌ لا تَحدثُ، والمُنادي يُريدُ ذلك بعينِه.
 * @param {{baseUrl:string, apiKey:string}} cfg
 * @param {string} rideId
 * @return {Promise<{ok:boolean, httpStatus:number, status:string|null, result:object}>}
 */
async function cancelRide(cfg, rideId) {
  const r = await fetch(urlOf(cfg.baseUrl, `/v1/rides/${encodeURIComponent(rideId)}/cancel`), {
    method: "POST",
    headers: authHeaders(cfg.apiKey),
    body: "{}",
  });
  const result = await parseJson(r);
  const ok = r.ok || r.status === 404;
  return {
    ok,
    httpStatus: r.status,
    status: ok ? "cancelled" : normalizeStatus(result.status),
    result,
  };
}

/**
 * استعلامُ حالةِ رحلة (للمكنسةِ عند غيابِ الويب هوك). أخطاءُ الشبكةِ
 * تُبتلَعُ كـ`moyasar.getPayment`: «لم نَستطع السؤال» يُقرَأُ «لا نَعرف».
 * @param {{baseUrl:string, apiKey:string}} cfg
 * @param {string} rideId
 * @return {Promise<{ok:boolean, httpStatus:number, status:string|null, result:object}>}
 */
async function getRide(cfg, rideId) {
  try {
    const r = await fetch(urlOf(cfg.baseUrl, `/v1/rides/${encodeURIComponent(rideId)}`), {
      method: "GET",
      headers: authHeaders(cfg.apiKey),
    });
    const result = await parseJson(r);
    return {ok: r.ok, httpStatus: r.status, status: normalizeStatus(result.status), result};
  } catch (e) {
    return {ok: false, httpStatus: 0, status: null, result: {error: e.message}};
  }
}

/**
 * توقيعُ الويب هوك: HMAC-SHA256 (hex) على **البايتاتِ الخامّة** — الدرسُ
 * الموثَّقُ في `tabbyWebhook`: `JSON.stringify(req.body)` ليس ما وُقِّع.
 * مقارنةٌ بزمنٍ ثابتٍ بعد فحصِ الطول (timingSafeEqual يَرمي على طولَين
 * مختلفَين). سرٌّ غائبٌ أو ترويسةٌ غائبةٌ ⇒ رفض — يَفشلُ مُغلَقاً.
 * @param {string} secret
 * @param {Buffer|string} rawBody
 * @param {string|undefined} signature
 * @return {boolean}
 */
function verifySignature(secret, rawBody, signature) {
  if (!secret || !signature) return false;
  const crypto = require("crypto");
  const expected = crypto.createHmac("sha256", secret).update(rawBody).digest("hex");
  const sigBuf = Buffer.from(String(signature).trim().toLowerCase());
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length) return false;
  return crypto.timingSafeEqual(sigBuf, expBuf);
}

/**
 * قراءةُ حدثِ ويب هوك إلى شكلِنا الداخليّ (`transport.applyRideEvent`).
 * @param {object} body
 * @return {{rideId:string|null, reference:string|null, status:string|null,
 *   driver:{name:string,phone:string,plate:string}|null, etaMinutes:number|null}}
 */
function parseWebhookEvent(body) {
  const b = body && typeof body === "object" ? body : {};
  const ride = b.ride && typeof b.ride === "object" ? b.ride : b;
  const d = ride.driver && typeof ride.driver === "object" ? ride.driver : null;
  const eta = Number(ride.eta_minutes);
  return {
    rideId: ride.id || ride.ride_id ? String(ride.id || ride.ride_id) : null,
    reference: ride.reference ? String(ride.reference) : null,
    status: normalizeStatus(ride.status || b.event),
    driver: d ? {
      name: String(d.name || ""),
      phone: String(d.phone || ""),
      plate: String(d.plate || d.vehicle_plate || ""),
    } : null,
    etaMinutes: Number.isFinite(eta) ? eta : null,
  };
}

module.exports = {
  SIGNATURE_HEADER,
  STATUS_MAP,
  normalizeStatus,
  createRide,
  cancelRide,
  getRide,
  verifySignature,
  parseWebhookEvent,
};
