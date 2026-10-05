"use strict";

// أهليّةُ الكوبونِ وقيمتُه — دوالٌ نقيّةٌ بلا تبعيات (`node test/coupons.test.js`).
//
// ═══ ما كان مكسوراً ═══
//
// `_computeTrustedDiscount` في `index.js` وُضع ليُجيب «كم يستحقُّ هذا الكوبون؟»
// من مستندِ `promo_codes` لا من `discount_amount` الذي يَكتبه العميل. وكان
// يُجيبُ **المقدار** ولا يُجيبُ **الأهليّة**: يَفحصُ `status` و`expiry` فقط،
// ويُغفل ثلاثةً يَفحصُها العميلُ كلَّها في `order_service.validateCoupon`:
//
//   `target_user_id` ..... كوبونُ إحالةٍ موجَّهٌ لعميلةٍ بعينها. وكودُه حتميّ
//                          (`REF` + ستُّ محارفَ من المعرّف + `10`) ويُرسَل في
//                          إشعارٍ نصّيّ. فعميلةٌ أخرى تَصرفُه، والخادمُ يَقبل.
//   `restricted_zones` ... كوبونُ منطقةٍ يَعملُ في كلِّ منطقة.
//   `uses`/`maxUses` ..... بلا سقف. وتعليقُ `countCouponUseOnOrderCreate` يقول
//                          «والمنعُ النهائيُّ جزءٌ من التسعيرِ الخادميّ» —
//                          وعدٌ بمنعٍ لم يكن موجوداً في التسعيرِ الخادميّ.
//
// فالخادمُ يَثِقُ بالعميلِ في الأهليّةِ وحدَه — وهو عينُ ما وُجدت الدالّةُ
// لتمنعه. وطلبُ العميلِ يُكتب من جهازه بـ`coupon_code` و`discount_amount`،
// فالمسارُ مُتاحٌ لا نظريّ.
//
// ═══ و`expiry` بنوعَين: المحرّران لا يَكتبان الشيءَ نفسَه ═══
//
// محرّرُ Flutter يَكتب `Timestamp.fromDate(...)`، ولوحةُ الويب
// (`Marketing.tsx`) كانت تَكتبُ **نصَّ الحقلِ خاماً** (`"2026-12-31"`).
// وفحصُ الخادمِ كان `typeof c.expiry.toMillis === "function"` — فالنصُّ لا
// يَملكُ `toMillis` و**الفحصُ يُتخطّى كلَّه**: كلُّ كوبونٍ أُنشئ من لوحةِ
// الويبِ كان بلا انتهاءٍ خادميّاً. والعميلُ يَفحصُ النوعَين (`Timestamp` و
// `String`) فيَحجبُه — فكانت الواجهةُ أصرمَ من الخادم. اللوحةُ أُصلحت لتَكتبَ
// `Timestamp`، وهذه الوحدةُ تَقرأُ النوعَين لأنّ وثائقَ النصِّ قائمةٌ فعلاً في
// قاعدةِ البيانات.
//
// ═══ ولمَ الرفضُ وحدَه لا يَكفي ═══
//
// رفضُ الخصمِ يَرفعُ «المتوقَّع»، و`verifyMoyasarPayment` لا يَسِمُ ولا يُنبّهُ
// إلّا عند `ratio < 0.5`. فكوبونُ 10% غيرُ مؤهَّلٍ يُنتج `ratio = 0.9` —
// **فلا وسمَ ولا تنبيهَ ولا أثر**، وهو بالضبط نسبةُ كوبونِ الإحالةِ الذي
// يُولّده المحرّك. فالإنفاذُ بلا وسمٍ تجميليّ. لذا تُصنّفُ الأسبابُ هنا:
// `ESCALATED_PROBLEMS` ما لا تَبلغُه عميلةٌ صادقة (كوبونُ غيرِها، منطقةٌ
// أخرى) فيُنبَّهُ الأدمن؛ وما سواه (نَفاد، انتهاء، تعطيل) يُسَمُ بلا تنبيه
// لأنّ سباقاً بين لحظةِ التطبيقِ ولحظةِ الدفعِ يَبلغُه حسنُ النيّة.

/** الأسبابُ التي لا تَبلغُها عميلةٌ صادقةٌ — تُنبِّه الأدمن. */
const ESCALATED_PROBLEMS = new Set(["other_user", "other_zone"]);

/**
 * انتهاءُ الكوبونِ بالميلي-ثانية، من `Timestamp` أو من نصِّ ISO — النوعان
 * موجودان في الإنتاج. `null` = بلا انتهاء (أو قيمةٌ لا تُفكّ).
 * @param {object|undefined} coupon مستندُ الكوبون
 * @return {?number} الميلي-ثانية
 */
function couponExpiryMs(coupon) {
  const raw = coupon && coupon.expiry;
  if (raw === null || raw === undefined || raw === "") return null;
  if (typeof raw.toMillis === "function") {
    const ms = raw.toMillis();
    return Number.isFinite(ms) ? ms : null;
  }
  if (raw instanceof Date) {
    return Number.isFinite(raw.getTime()) ? raw.getTime() : null;
  }
  if (typeof raw === "number") return Number.isFinite(raw) ? raw : null;
  if (typeof raw === "string") {
    const ms = Date.parse(raw);
    return Number.isFinite(ms) ? ms : null;
  }
  return null;
}

/**
 * **لماذا لا يُطبَّق هذا الكوبون؟** — `null` = مؤهَّل. الأسبابُ بترتيبِ
 * الفحص: `not_found` ← `inactive` ← `expired` ← `exhausted` ← `other_user`
 * ← `other_zone`. تُطابقُ حرفيّاً ما يَفحصه `order_service.validateCoupon`
 * في العميل، وهذا هو المقصود: جهةٌ واحدةٌ تَقرّرُ والطرفان يَسألانها.
 * @param {object|null|undefined} coupon مستندُ الكوبون (أو `null` إن لم يُوجد)
 * @param {{uid?: ?string, zoneName?: ?string, nowMs?: number}} ctx سياقُ الطلب
 * @return {?string} السببُ أو `null`
 */
function couponProblem(coupon, {uid = null, zoneName = null,
  nowMs = Date.now()} = {}) {
  if (!coupon) return "not_found";
  // الغيابُ يُقبَل: وثائقُ قديمةٌ بلا `status` (نفسُ تسامحِ العميل).
  if (coupon.status && coupon.status !== "active") return "inactive";
  const exp = couponExpiryMs(coupon);
  if (exp !== null && exp < nowMs) return "expired";
  const maxUses = Number(coupon.maxUses) || 0;
  const uses = Number(coupon.uses) || 0;
  if (maxUses > 0 && uses >= maxUses) return "exhausted";
  const target = coupon.target_user_id;
  if (typeof target === "string" && target !== "" && target !== uid) {
    return "other_user";
  }
  const zones = coupon.restricted_zones;
  if (Array.isArray(zones) && zones.length > 0) {
    const allowed = zones.map((z) => String(z));
    if (!zoneName || !allowed.includes(String(zoneName))) return "other_zone";
  }
  return null;
}

/**
 * قيمةُ الخصمِ الخادميّةُ بالريال — الحسابُ كما كان حرفيّاً: نسبةٌ على
 * المشحونِ المُذرَّى (`chargedGross × surge`)، أو مبلغٌ ثابت، بسقفِ
 * `max_discount` إن وُجد. لا تَفحصُ الأهليّة — `couponProblem` تَفعل.
 * @param {object} coupon مستندُ الكوبون
 * @param {{chargedGross: number, surge?: number}} ctx الأساسُ المشحونُ والذروة
 * @return {number} الخصمُ (≥ 0)
 */
function couponDiscount(coupon, {chargedGross, surge = 1}) {
  const value = Number(coupon && coupon.value) || 0;
  let d = coupon && coupon.type === "percentage" ?
    chargedGross * surge * (value / 100) : value;
  if (coupon && coupon.max_discount) {
    d = Math.min(d, Number(coupon.max_discount) || d);
  }
  return Math.max(0, Number.isFinite(d) ? d : 0);
}

/**
 * الخصمُ الموثوقُ أخيراً: لا يَتجاوزُ الخادميَّ، ويَحترمُ خصمَ العميلِ الأقلّ.
 * صفرُ العميلِ **ليس** قراراً هنا (حقلٌ غائبٌ أو لم يُحسَب) فيُؤخذ الخادميّ —
 * وهذا ما كان، ونُبقيه كما هو.
 * @param {number} clientDiscount ما كَتبه العميلُ على الطلب
 * @param {number} serverDiscount ما حَسبه الخادم
 * @return {number} الأصغرُ منهما (≥ 0)
 */
function trustedDiscount(clientDiscount, serverDiscount) {
  const c = Number(clientDiscount) || 0;
  const s = Number(serverDiscount) || 0;
  return Math.max(0, c > 0 ? Math.min(c, s) : s);
}

module.exports = {
  ESCALATED_PROBLEMS,
  couponExpiryMs,
  couponProblem,
  couponDiscount,
  trustedDiscount,
};
