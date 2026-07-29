"use strict";

// تسعير خادمي مرجعي — دوال نقيّة بلا تبعيات (قابلة للاختبار عبر `node test/pricing.test.js`).
// تُعيد حساب «الأساس» (قبل الضريبة) من كمّيات الطلب الموثوقة × أسعار مستند المنطقة،
// متجاهلةً أي سعر مكتوب على الطلب/الـ service_meta (يكتبه العميل، غير موثوق).
// الإجمالي المتوقَّع الذي يُخزَّن في حقل amount = الأساس × 1.15 (النموذج: الضريبة فوق السعر).

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
    return price;
  }

  // store_products: عناصر service_meta بلا معرّف منتج → يتعذّر إعادة التسعير الموثوق.
  // (متجر الشركات المباشر آمن أصلاً: createStoreOrder يُعيد قراءة السعر من products.)
  return null;
}

module.exports = { computeExpectedBasePrice, acPriceField, carPriceField };
