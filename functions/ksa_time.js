"use strict";

// توقيتُ الرياض — دوالٌ نقيّةٌ بلا تبعيات (`node test/ksa_time.test.js`).
//
// الدوالُ الخادميّةُ تعملُ بـUTC: لا `TZ` مضبوطةٌ في `firebase.json` ولا في
// `functions/package.json`، وخيارُ `timeZone: "Asia/Riyadh"` في `onSchedule`
// يحكمُ **موعدَ الكرون** لا منطقةَ العمليّة. فقراءةُ مكوّناتٍ محلّيّةٍ
// (`getHours()`) من **لحظةٍ زمنيّة** تُعيدُ ساعةَ UTC — أي ساعةَ الرياضِ
// ناقصةً ثلاثاً، و«أمس» قبلَ الثالثةِ فجراً.
//
// تمييزٌ لازمٌ وإلّا بدا كلُّ `getHours()` عطلاً: قراءةُ مكوّناتٍ محلّيّةٍ من
// تاريخٍ **بُني من مكوّنات** — `new Date(y, m - 1, d)` ثمّ `getFullYear()` —
// صحيحةٌ لأنّها ذهابٌ وعودةٌ في المنطقةِ نفسِها، وهي كذلك في ثلاثةِ مواضعَ
// باقيةٍ في `index.js` (توليدُ زياراتِ العقد، ومَسحُ أيّامِ الجدول). الخطأُ
// هو قراءتُها من لحظةٍ مطلقة.
//
// كُتبت الصيغةُ يدويّاً في **سبعةِ** مواضعَ واختلفت: خمسةٌ تُزيحُ ثلاثاً،
// وموضعا الإنشاءِ الخادميِّ للطلب — `verifyMoyasarPayment` حين يُنشئ الطلبَ من
// بيانات الدفع (مسارُ Apple Pay / الدفعِ الأصيل)، و`reconcileOrphanPayments`
// حين يستعيدُ دفعةً يتيمة — لا يُزيحان، فكانا يَكتبان `booking_time_slot`
// أبكرَ بثلاثِ ساعاتٍ من موعدِ العميلة. ولم يكن ذلك عرضاً فقط:
// `capacity.js` يَعدُّ السائقَ مشغولاً من `booking_time_slot` طولَ المدّة، فكان
// يَحجزُ ثلاثَ ساعاتٍ خاطئةً ويَترُكُ ساعاتِ الموعدِ الحقيقيّةِ فارغةً
// (ازدواجُ حجز)، ولوحةُ السائقِ وتذكيرُ العميلةِ والفاتورةُ تُعلن الساعةَ
// الخاطئة.

/** إزاحةُ السعوديّة عن UTC — ثابتةٌ على مدار السنة (لا توقيتَ صيفيّاً). */
const KSA_OFFSET_MS = 3 * 60 * 60 * 1000;

const _pad2 = (n) => String(n).padStart(2, "0");

/**
 * يفكّ ISO قادماً من العملاء إلى **لحظةٍ زمنيّةٍ صحيحة**: سلسلةُ Dart المحلّيّةُ
 * بلا لاحقةِ منطقة (`2026-07-30T14:00:00.000`) قصدُ مرسِلِها توقيتُ الرياض.
 * سلاسلُ الويب بـ`Z` أو بإزاحةٍ صريحةٍ تمرُّ كما هي.
 *
 * ⚠️ **لا يُترَكُ للمحرّكِ أن يَختارَ المنطقة (2026-10-10).** كان التعليقُ هنا
 * يَقول «يفسّرُها Node كـUTC»، وذلك صحيحٌ **في عمليّةٍ منطقتُها UTC وحدَها**:
 * ECMAScript تَقرأُ صيغةَ «تاريخٍ وساعةٍ» بلا إزاحةٍ **بمنطقةِ العمليّة**
 * (والتاريخَ وحدَه بـUTC). فكانت صحّةُ كلِّ موعدٍ يَبنيه الخادمُ — مسارُ Apple
 * Pay، واستعادةُ الدفعةِ اليتيمة، والإسنادُ وإعادةُ الجدولة — معلَّقةً على أنّ
 * `TZ` غيرُ مضبوطٍ في بيئةِ الدوال. ومقيسٌ: في عمليّةٍ بتوقيتِ الرياضِ يُخزَّنُ
 * موعدُ 14:00 لحظةَ `08:00Z` (ستُّ ساعاتٍ مبكّراً، لأنّ المحرّكَ أزاحَ ثلاثاً
 * ثمّ أزاحت الدالّةُ ثلاثاً أخرى) — وهو ما يَحدثُ في المُحاكي وفي `npm test`
 * على جهازِ المطوّرِ بالسعوديّة. فالساعةُ تُقرأُ الآن **بـUTC صراحةً**
 * (`Z` تُلحَقُ قبلَ الفكّ) ثمّ تُطرَحُ الإزاحة: النتيجةُ واحدةٌ أيّاً كانت
 * منطقةُ العمليّة، ومطابقةٌ بالضبطِ لِما كانت تُعطيه في UTC.
 * والغيابُ غياب: `null`/`undefined` يُعطيانِ `Invalid Date` (عبرَ `String()`)
 * لا لحظةَ ١٩٧٠ التي كان `new Date(null)` يُعطيها فتُطرَحُ منها الإزاحة.
 * @param {string} s سلسلة ISO
 * @return {Date} لحظةٌ زمنيّة (أو `Invalid Date` إن تعذّر الفكّ)
 */
function parseKsaIso(s) {
  const str = String(s).trim();
  if (/(?:Z|[+-]\d{2}:?\d{2})$/.test(str)) return new Date(str);
  // تاريخٌ وساعة ⇒ تُقرأُ بـUTC صراحةً؛ والتاريخُ وحدَه تَقرؤه ECMAScript بـUTC أصلاً.
  // (V8 يَقبلُ `2026-10-07Z` كذلك، لكنّها ليست صيغةً معياريّة — فلا يُبنى عليها.)
  const hasTime = /\d[T ]\d{1,2}:\d{2}/.test(str);
  const d = new Date(hasTime ? `${str}Z` : str);
  if (isNaN(d.getTime())) return d;
  return new Date(d.getTime() - KSA_OFFSET_MS);
}

/**
 * حقلا الحجزِ المحلّيّان كما يَقرؤهما `capacity.js` ولوحةُ السائقِ والفاتورة:
 * `booking_date` بصيغة `YYYY-MM-DD` و`booking_time_slot` بصيغة `HH:00`
 * (24 ساعة — قاعدةٌ صارمةٌ يعتمدُها `lib/utils/time_format.dart`).
 * @param {number|Date} ms اللحظةُ الزمنيّة (ميلي ثانية أو `Date`)
 * @return {{bookingDate: ?string, bookingTimeSlot: ?string}} أو `null`ان للحظةٍ غيرِ صالحة
 */
function riyadhBookingFields(ms) {
  // الغيابُ غيابٌ: `Number(null)` صفرٌ لا `NaN`، فـ`null` كان يُنتج
  // `1970-01-01 03:00` — تاريخاً مُلفَّقاً يُكتب على الطلبِ بدل لا شيء.
  if (ms === null || ms === undefined) {
    return {bookingDate: null, bookingTimeSlot: null};
  }
  const t = ms instanceof Date ? ms.getTime() : Number(ms);
  if (!Number.isFinite(t)) return {bookingDate: null, bookingTimeSlot: null};
  const r = new Date(t + KSA_OFFSET_MS);
  if (isNaN(r.getTime())) return {bookingDate: null, bookingTimeSlot: null};
  return {
    bookingDate: `${r.getUTCFullYear()}-${_pad2(r.getUTCMonth() + 1)}-` +
      `${_pad2(r.getUTCDate())}`,
    bookingTimeSlot: `${_pad2(r.getUTCHours())}:00`,
  };
}

/**
 * تاريخُ الرياضِ المحلّيُّ وحدَه (`YYYY-MM-DD`).
 * @param {number|Date} ms اللحظةُ الزمنيّة
 * @return {?string} التاريخ
 */
function riyadhLocalDate(ms) {
  return riyadhBookingFields(ms).bookingDate;
}

/**
 * خانةُ ساعةِ الرياضِ المحلّيّةُ وحدَها (`HH:00`).
 * @param {number|Date} ms اللحظةُ الزمنيّة
 * @return {?string} الخانة
 */
function riyadhLocalSlot(ms) {
  return riyadhBookingFields(ms).bookingTimeSlot;
}

/**
 * **بدايةُ يومِ الرياضِ** الذي تَقعُ فيه [ms] — لحظةٌ زمنيّةٌ (ميلي ثانية).
 *
 * تُقاسُ بها «أموعدٌ في الماضي؟»: الحدُّ **بدايةُ اليومِ** لا «ليس قبلَ الآن»،
 * لأنّ مُنتقي التاريخِ في سطحَي الإدارةِ دقّتُه يومٌ — ولأنّ ساعةً مضت **من
 * اليومِ نفسِه** موعدٌ مشروعٌ يُسجّلُه الأدمنُ لزيارةٍ تأخّرَ إدخالُها، وهي
 * داخلَ نافذةِ `sweepUnassignedPaidOrders` (‎−١٣س) فتَبقى قابلةً للاستعادة.
 *
 * حسابٌ صِرفٌ على الإزاحةِ لا قراءةُ مكوّناتٍ محلّيّة: الدوالُ تَعملُ بـUTC
 * (انظر رأسَ الملفّ)، و`riyadhLocalDate` مشدودةٌ بها في فحصِها.
 * @param {number|Date} ms اللحظةُ الزمنيّة
 * @return {?number} بدايةُ اليومِ بالميلي، أو `null` للحظةٍ غيرِ صالحة
 */
function riyadhDayStartMs(ms) {
  if (ms === null || ms === undefined) return null;
  const t = ms instanceof Date ? ms.getTime() : Number(ms);
  if (!Number.isFinite(t)) return null;
  const DAY = 24 * 60 * 60 * 1000;
  return Math.floor((t + KSA_OFFSET_MS) / DAY) * DAY - KSA_OFFSET_MS;
}

/**
 * ختمٌ للعرضِ في الإشعارات: `YYYY-MM-DD HH:00` بتوقيتِ الرياض.
 * @param {number|Date} ms اللحظةُ الزمنيّة
 * @return {?string} الختم
 */
function riyadhStamp(ms) {
  const f = riyadhBookingFields(ms);
  return f.bookingDate === null ?
    null : `${f.bookingDate} ${f.bookingTimeSlot}`;
}

module.exports = {
  KSA_OFFSET_MS,
  parseKsaIso,
  riyadhBookingFields,
  riyadhLocalDate,
  riyadhLocalSlot,
  riyadhStamp,
  riyadhDayStartMs,
};
