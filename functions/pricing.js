"use strict";

// تسعير خادمي مرجعي — دوال نقيّة بلا تبعيات (قابلة للاختبار عبر `node test/pricing.test.js`).
// تُعيد حساب «الأساس» (قبل الضريبة) من كمّيات الطلب الموثوقة × أسعار مستند المنطقة،
// متجاهلةً أي سعر مكتوب على الطلب/الـ service_meta (يكتبه العميل، غير موثوق).
// الإجمالي المتوقَّع الذي يُخزَّن في حقل amount = الأساس × 1.15 (النموذج: الضريبة فوق السعر).

// الأنواعُ التي تُعيدُ [computeExpectedBasePrice] حسابَ سعرِها. مُصدَّرةٌ كي
// لا تُعدَّ بيدها في موضعٍ آخر: كانت `_isPriceableKind` في `index.js` تُعدِّدُ
// أربعةً وتُغفلُ `event_workers`، فطلبُ عاملاتِ مناسباتٍ بلا منطقةٍ يَتهرّبُ من
// التحقّقِ بصمت. `price_verify.test.js` يُقارنُ كلَّ فرعِ `kind` هنا بالقائمة.
const PRICEABLE_KINDS = [
  "sofa_rug_sqm",
  "ac_service",
  "car_interior",
  "event_workers",
  "home_package",
];

function acPriceField(job, type) {
  const j = job === "maintenance" ? "Maint" : job === "wash" ? "Wash" : null;
  const t = type === "window" ? "Window" : type === "split" ? "Split" : null;
  if (!j || !t) return null;
  return `ac${j}${t}Price`;
}

function carPriceField(size) {
  const s = size === "small" ? "Small" :
    size === "medium" ? "Medium" :
    size === "large" ? "Large" : null;
  return s ? `car${s}Price` : null;
}

// يُعيد الأساس (قبل الضريبة) أو null إن تعذّر التحقق الموثوق: بندٌ غير مسعّر في المنطقة،
// أو نوعٌ لا يُعاد تسعيره خادمياً بعد (طلبات المتجر — عناصرها بلا معرّف منتج).
function computeExpectedBasePrice(order, zone) {
  if (!order || !zone) return null;
  const meta = order.service_meta;

  // بالساعة: لا service_meta؛ zone.prices خريطة {ساعات→سعر المدّة}، × عدد العاملات.
  if (!meta || !meta.kind) {
    const prices = zone.prices || {};
    const hp = Number(prices[String(order.hours_contracted)]);
    if (!hp || isNaN(hp)) return null;
    const workers = Number(order.worker_count) || 1;
    return hp * workers;
  }

  const kind = meta.kind;

  if (kind === "sofa_rug_sqm") {
    const pieces = Array.isArray(meta.pieces) ? meta.pieces : [];
    let base = 0;
    for (const p of pieces) {
      const isRug = p.kind === "rug";
      const rate = Number(isRug ? zone.rugSqmPrice : zone.sofaSqmPrice);
      if (!rate || isNaN(rate)) return null;
      const len = Number(p.length_m) || 0;
      const wid = Number(p.width_m) || 0;
      const measure = isRug ? len * wid : len; // الكنب: طولي (الطول)؛ السجاد: مساحي
      base += measure * rate;
    }
    return base > 0 ? base : null;
  }

  if (kind === "ac_service") {
    const lines = Array.isArray(meta.lines) ? meta.lines : [];
    let base = 0;
    for (const l of lines) {
      const field = acPriceField(l.job, l.type);
      const rate = field ? Number(zone[field]) : NaN;
      if (!rate || isNaN(rate)) return null;
      base += (Number(l.count) || 0) * rate;
    }
    return base > 0 ? base : null;
  }

  if (kind === "car_interior") {
    const lines = Array.isArray(meta.lines) ? meta.lines : [];
    let base = 0;
    for (const l of lines) {
      const field = carPriceField(l.size);
      const rate = field ? Number(zone[field]) : NaN;
      if (!rate || isNaN(rate)) return null;
      base += (Number(l.count) || 0) * rate;
    }
    return base > 0 ? base : null;
  }

  // (عاملات المناسبات) الأساس = العدد × الساعات × سعر ساعة العاملة في المنطقة.
  // الكمّيات من الطلب والسعر من وثيقة المنطقة — لا يُقرأ meta.hour_rate إطلاقاً
  // (يكتبه العميل). حدود مطابقة للشاشة تمنع طلباً مُلفَّقاً بساعات خيالية.
  if (kind === "event_workers") {
    const rate = Number(zone.eventWorkerHourPrice);
    if (!rate || isNaN(rate) || rate <= 0) return null;
    const workers = Number(meta.workers);
    const hours = Number(meta.event_hours);
    if (!workers || workers < 1 || workers > 10) return null;
    if (!hours || hours < 2 || hours > 12) return null;
    return workers * hours * rate;
  }

  // (باقات السكن) السعر من zone.packages[نوع السكن].crews[عدد الكوادر] الموثوق —
  // يشمل الكوادر سلفاً فلا يُضرب بأي عدد. خيارٌ معطَّل/غير مسعَّر = يتعذّر التحقق (null)
  // فلا يُقبل سعرُ عميلٍ لخيارٍ أطفأه الأدمن لمنطقته.
  if (kind === "home_package") {
    const pkgs = zone.packages || {};
    const pkg = pkgs[String(meta.homeType)] || {};
    const crews = pkg.crews || {};
    const opt = crews[String(meta.crewCount)];
    if (!opt || opt.enabled !== true) return null;
    const price = Number(opt.price);
    if (!price || isNaN(price) || price <= 0) return null;
    // مواد التنظيف المضافة داخل الطلب نفسه (فاتورة واحدة بطلب واحد — طلب المالك):
    // أسعارها تأتي محلولةً من `products` عبر resolveMaterialsBase قبل النداء،
    // لأن هذه الدالة نقيّة بلا وصول لقاعدة البيانات. غيابها = صفر (طلب بلا مواد).
    const materialsBase = Number(order.materials_base_resolved) || 0;
    return price + materialsBase;
  }

  // store_products: عناصر service_meta بلا معرّف منتج → يتعذّر إعادة التسعير الموثوق.
  // (متجر الشركات المباشر آمن أصلاً: createStoreOrder يُعيد قراءة السعر من products.)
  return null;
}

// مواد التنظيف داخل طلب التنظيف المنزلي: تُسعَّر من مستندات `products` الموثوقة
// لا من السلة التي يكتبها العميل. تُعيد الأساس (قبل الضريبة)، أو null إن تعذّر
// التحقق (منتج مفقود/بلا سعر) كي لا يمرّ سعرٌ غير قابل لإعادة الحساب.
// مفصولة عن computeExpectedBasePrice لأن تلك نقيّة بلا تبعيات؛ هذه تقرأ Firestore.
async function resolveMaterialsBase(db, meta) {
  const items = meta && Array.isArray(meta.materials) ? meta.materials : [];
  if (items.length === 0) return 0;
  let base = 0;
  for (const it of items) {
    const id = it && it.product_id;
    const qty = Number(it && it.quantity) || 0;
    if (!id || qty <= 0) return null;
    const snap = await db.collection("products").doc(String(id)).get();
    if (!snap.exists) return null;
    const price = Number(snap.data().price);
    if (!price || isNaN(price) || price <= 0) return null;
    base += price * qty;
  }
  return base;
}

/**
 * أساسُ سلّةِ المتجرِ من `products` — **إعادةُ تسعيرٍ خادميّةٌ لم تكن موجودة.**
 *
 * `store_service.dart` يُسعّرُ السلّةَ من `products` داخلَ معامَلةٍ ويَكتبُ
 * `total_amount` و`items` بـ`{id, name, quantity, price}` — لكنّه يَفعلُ ذلك
 * **في العميل**. ومُتلاعبٌ يَكتبُ مستندَ `store_orders` من الـSDK مباشرةً
 * يُعلِنُ ما شاء: القواعدُ تَشترطُ `is_paid: false` و`client_id` ولا تَفحصُ
 * المبلغ، وفحصُ `moyasarWebhook` الوحيدُ «المدفوعُ = المُعلَن»
 * (`expectedAmount`)، وكلُّ حقولِ ذلك التدرّجِ يَكتبُها هو. فسلّةٌ بخمسِ مئةٍ
 * تُعلَنُ بريالٍ وتُدفَعُ بريالٍ وتُشحَن.
 *
 * ولا تحقّقَ خادميّاً للمتجرِ من أيِّ نوع: `computeExpectedBasePrice` تُعيدُ
 * `null` له (عناصرُه ليست خدمةً في منطقة)، فسلسلةُ Tier A كلُّها مقصورةٌ على
 * `orders`. والبياناتُ اللازمةُ موجودةٌ في المستندِ نفسِه، والدالّةُ التي
 * تَفعلُ هذا بالضبط موجودةٌ مجموعةً واحدةً بعيداً: `resolveMaterialsBase`.
 *
 * **نفسُ عقدِ `resolveMaterialsBase`**: `null` تعني «تعذّر التسعير» — عنصرٌ بلا
 * معرّفٍ أو بكمّيّةٍ غيرِ موجبةٍ أو منتجٌ محذوفٌ أو سعرٌ غيرُ صالح — ولا يُرفَضُ
 * دفعٌ بلا يقين. وسلّةٌ فارغةٌ تُعيدُ `0`.
 *
 * @param {object} db Firestore
 * @param {Array} items مصفوفةُ `store_orders.items`
 * @return {Promise<?number>} الأساسُ قبل الضريبة، أو `null` إن تعذّر
 */
async function resolveStoreCartBase(db, items) {
  const list = Array.isArray(items) ? items : [];
  if (list.length === 0) return 0;
  let base = 0;
  for (const it of list) {
    // `store_service` يَكتبُ المعرّفَ في `id`؛ ونَقبلُ `product_id` كذلك
    // لأنّه اسمُ الحقلِ في موادِّ التنظيفِ داخلَ طلبِ الخدمة.
    const id = it && (it.id || it.product_id);
    const qty = Number(it && it.quantity) || 0;
    if (!id || qty <= 0) return null;
    const snap = await db.collection("products").doc(String(id)).get();
    if (!snap.exists) return null;
    const price = Number(snap.data().price);
    if (!price || isNaN(price) || price <= 0) return null;
    base += price * qty;
  }
  return base;
}

// رسوم الوعورة (قرار المالك 2026-09-16 — تسعير القرى والوعورة): نسبة مئوية على
// الأساس قبل الضريبة لطلبات القرى الجبلية/الوعرة. تُقرأ من مستند المنطقة الموثوق
// فقط (terrain_surcharge_percent) — ما يكتبه الطلب/العميل لا يُقرأ. 0..100،
// وغير الرقمي/السالب = 0 (لا رسوم). لا تُطبَّق على الأسعار الثابتة (العقود) لأن
// تلك لا تمرّ بهذا المسار أصلاً (activateContractOnPaid يطابق planPrice حرفياً).
function terrainSurchargePercent(zone) {
  const n = Number(zone && zone.terrain_surcharge_percent);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.min(100, n);
}

// الأساس بعد الوعورة (قبل الضريبة والذروة والخصم) — null/0 يمرّان كما هما.
function applyTerrainSurcharge(base, zone) {
  if (!base || base <= 0) return base;
  return base * (1 + terrainSurchargePercent(zone) / 100);
}

module.exports = {
  PRICEABLE_KINDS,
  computeExpectedBasePrice,
  resolveMaterialsBase,
  resolveStoreCartBase,
  acPriceField,
  carPriceField,
  terrainSurchargePercent,
  applyTerrainSurcharge,
};
