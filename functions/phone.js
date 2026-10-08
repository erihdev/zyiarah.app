/**
 * رقمُ الجوالِ السعوديُّ: صيغةٌ واحدةٌ — مرآةُ `saudiMobile`/`saudiE164` في
 * `lib/utils/phone_format.dart`، وجدولُ الحالاتِ مشترَكٌ بين اللغتَين
 * (`functions/test/phone.test.js` يَملكُه و`test/saudi_mobile_test.dart`
 * يَقرؤه).
 *
 * **ولمَ الخادمُ أيضاً وليس الكاتبُ وحدَه:** `createTamaraCheckout` كان يَفعلُ
 * `customerPhone.startsWith("+") ? customerPhone : "+966" + customerPhone`،
 * والرقمُ يَأتيه من `users/{uid}.phone` عبرَ شاشةِ الدفع — وذلك الحقلُ
 * يَحملُ في الإنتاجِ خمسَ صِيَغ، لأنّ محرِّرَ التسجيلِ كان يُخزّنُ النصَّ
 * الخامَّ. فـ`0501234567` تُصبِحُ `+9660501234567` و`966501234567` تُصبِحُ
 * `+966966501234567`. وإصلاحُ الكاتبِ وحدَه لا يُعيدُ كتابةَ ما كُتب — قرارُ
 * احتياطِ `latest_build` و`couponExpiryMs` ولنفسِ السبب.
 *
 * وحدةٌ نقيّةٌ: لا `getFirestore()` ولا `getApp()` ولا `initializeApp()`.
 */

/**
 * تطبيعُ الأرقامِ العربيّةِ-الهنديّةِ (٠..٩) والفارسيّةِ (۰..۹) إلى لاتينيّة،
 * وإسقاطُ علاماتِ الاتّجاهِ غيرِ المرئيّة. مرآةُ `normalizeDigits` في
 * `lib/utils/catalog_number.dart` — لازمةٌ هنا لأنّ نسخةً أقدمَ من التطبيقِ
 * تُرسِلُ ما كَتبَته العميلةُ كما هو.
 */
function normalizeDigits(input) {
  let out = "";
  for (const ch of String(input)) {
    const c = ch.codePointAt(0);
    if (c >= 0x0660 && c <= 0x0669) {
      out += String.fromCharCode(0x30 + (c - 0x0660));
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      out += String.fromCharCode(0x30 + (c - 0x06F0));
    } else if (c === 0x066B) {
      out += ".";
    } else if (c === 0x066C || c === 0x200E || c === 0x200F || c === 0x061C) {
      // فاصلُ الآلافِ وعلاماتُ الاتّجاه: تُحذَف
    } else {
      out += ch;
    }
  }
  return out.trim();
}

/** الصيغةُ المحلّيّةُ القانونيّةُ `05XXXXXXXX`، أو `null` حين لا تَنحلّ. */
function saudiMobile(raw) {
  if (raw === null || raw === undefined) return null;
  let d = normalizeDigits(raw).replace(/[^0-9]/g, "");
  if (d === "") return null;
  // `00966` صراحةً **قبلَ** `966`: بالترتيبِ المعاكسِ يَبقى صفرٌ في الأوّل.
  if (d.startsWith("00966")) {
    d = d.slice(5);
  } else if (d.startsWith("966")) {
    d = d.slice(3);
  }
  if (d.startsWith("0")) d = d.slice(1);
  // صارِمٌ لا «آخرُ تسعةِ أرقام»: الأخيرُ يَقبلُ `99999501234567` بقصِّه.
  if (!/^5\d{8}$/.test(d)) return null;
  return "0" + d;
}

/** الصيغةُ الدوليّةُ `+9665XXXXXXXX` لبوّاباتِ الدفع، أو `null`. */
function saudiE164(raw) {
  const local = saudiMobile(raw);
  return local === null ? null : "+966" + local.slice(1);
}

module.exports = {normalizeDigits, saudiMobile, saudiE164};
