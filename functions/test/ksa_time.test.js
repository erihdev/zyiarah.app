"use strict";

// توقيتُ الرياضِ الخادميّ — تشغيل: node test/ksa_time.test.js (ضمن npm test).
//
// ═══ العطلُ الحيُّ الذي أوجد الوحدة ═══
//
// الدوالُ تعملُ بـUTC. فصيغةُ «حقلَي الحجزِ المحلّيَّين» — إزاحةُ ثلاثِ ساعاتٍ
// ثمّ قراءةُ مكوّناتِ UTC — كُتبت يدويّاً في **سبعةِ** مواضع، و**موضعان لم
// يُزيحا**: المُنشئانِ الخادميّانِ للطلبِ من بيانات الدفع —
// `verifyMoyasarPayment` (مسارُ Apple Pay / الدفعِ الأصيل، حين لا وثيقةَ طلبٍ
// فتُبنى من `metadata`) و`reconcileOrphanPayments` (استعادةُ دفعةٍ يتيمة) —
// فكانا يَكتبان:
//
//     payload.booking_time_slot = `${pad(sd.getHours())}:00`;
//
// و`sd` **لحظةٌ زمنيّةٌ مطلقة** آتيةٌ من `parseKsaIso`. فـ`getHours()` تُعيدُ
// ساعةَ UTC: موعدُ 14:00 بالرياضِ يُخزَّن `"11:00"`.
//
// ولم يكن ذلك عرضاً فحسب. الأثرُ المرتَّب:
//
//   ١. `capacity.js` يَعدُّ السائقَ مشغولاً **من `booking_time_slot`** طولَ
//      `hours_contracted`. فحُجزت 11:00–15:00 وبقيت 14:00–18:00 فارغةً:
//      ساعاتٌ حقيقيّةٌ تُرفَض، وساعاتُ الموعدِ تُباع مرّةً أخرى — **ازدواجُ
//      حجزٍ لسائقٍ واحد**.
//   ٢. لوحةُ السائق (`driver_dashboard`) تُعلن الساعةَ الخاطئة.
//   ٣. تذكيرُ العميلةِ يَقرأ `d.booking_time_slot ||` بديلاً **صحيحاً**، فحين
//      يوجدُ الحقلُ الخاطئُ يُتخطّى البديلُ الصحيح.
//   ٤. الفاتورةُ/العقدُ (`zyiarah_pdf_service`) يطبعان الساعةَ الخاطئة.
//   ٥. `booking_date` يَنزلقُ يوماً كاملاً لموعدٍ بين 00:00 و02:59 بالرياض.
//
// وهو **انحدارٌ أحدثَه إصلاحٌ سابق**: قبلَ `parseKsaIso` كانت السلسلةُ الساذجةُ
// تُفسَّر كـUTC، فـ`getHours()` تُعيدُ أرقامَ ساعةِ الرياضِ **صحيحةً بالخطأ**
// بينما `service_date` يُخزَّن متأخّراً ثلاثاً. أُصلحت اللحظةُ ولم يُصلَح
// المشتَقّ — وتعليقُ `parseKsaIso` نفسُه كان يذكرُ المشتقّ ولا يَمسّه.
//
// ═══ تمييزٌ لازمٌ وإلّا بدا كلُّ getHours() عطلاً ═══
//
// قراءةُ مكوّناتٍ محلّيّةٍ من تاريخٍ **بُني من مكوّنات** — `new Date(y, m-1, d)`
// ثمّ `getFullYear()` — صحيحةٌ: ذهابٌ وعودةٌ في المنطقةِ نفسِها. وهي كذلك في
// ثلاثةِ مواضعَ باقيةٍ في `index.js` (توليدُ زياراتِ العقدِ مرّتين، ومَسحُ
// أيّامِ الجدول). فالحارسُ يُثبّتُ **مصدرَ حقلَي الحجز** لا يَمنعُ `getHours`.
//
// ═══ وفخُّ الحرفِ نفسِه بمعنيَين ═══
//
// `3 * 60 * 60 * 1000` في `index.js` ليس دائماً إزاحةَ منطقة: في `opsHealthSweep`
// هو **مُهلةُ ثلاثِ ساعاتٍ بعد انتهاءِ الزيارة** (بجوارِ مُهلةِ ١٢ ساعة). فمنعُ
// الحرفِ جملةً كان سيَخلطُ المعنيَين؛ الحارسُ يَمنعُه داخلَ `new Date(` وحدَها.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const ksa = require("../ksa_time");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  try {
    fn();
    console.log("  ok -", name);
    passed++;
  } catch (e) {
    console.error("  NOT OK -", name, "\n   ", e.message);
    process.exitCode = 1;
  }
}

const idxPath = path.join(__dirname, "..", "index.js");
const idx = fs.readFileSync(idxPath, "utf8");
const mod = fs.readFileSync(path.join(__dirname, "..", "ksa_time.js"), "utf8");

// يَحذفُ أسطرَ التعليقِ الكاملةَ فقط — فـ`https://` يحملُ `//` والتجريدُ الساذج
// يُعمي الحارس (درسُ حارس تمارا). ثمّ نؤكّد أنّ المصطلحَ ما زال في الخامِ كي لا
// يُفرغَ التجريدُ الفحصَ من موضوعه.
const stripComments = (src) => src.split("\n")
    .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
    .join("\n");
const idxNoComments = stripComments(idx);

// ════════════════════════ (أ) حسابُ الحقلَين ════════════════════════

t("(أ١) 14:00 بالرياضِ تُخزَّن 14:00 لا 11:00 — العطلُ الحيّ بعينه", () => {
  const ms = Date.UTC(2026, 9, 7, 11, 0, 0); // 11:00Z = 14:00 بالرياض
  assert.deepStrictEqual(ksa.riyadhBookingFields(ms),
      {bookingDate: "2026-10-07", bookingTimeSlot: "14:00"});
  // ولو قُرئت المكوّناتُ المحلّيّةُ (UTC) لأعطت 11:00 — هذا هو الفرق.
  assert.strictEqual(new Date(ms).getUTCHours(), 11);
});

t("(أ٢) خاصّيّةٌ على كلِّ ساعاتِ اليومِ وكلِّ أيّامِ شهرٍ كامل", () => {
  for (let day = 1; day <= 31; day++) {
    for (let h = 0; h < 24; h++) {
      const ms = Date.UTC(2026, 0, day, h, 0, 0);
      const f = ksa.riyadhBookingFields(ms);
      const expH = (h + 3) % 24;
      const rolls = h + 3 >= 24;
      assert.strictEqual(f.bookingTimeSlot,
          `${String(expH).padStart(2, "0")}:00`, `h=${h}`);
      const expDay = rolls ? day + 1 : day;
      const expected = new Date(Date.UTC(2026, 0, expDay));
      assert.strictEqual(f.bookingDate,
          `${expected.getUTCFullYear()}-` +
          `${String(expected.getUTCMonth() + 1).padStart(2, "0")}-` +
          `${String(expected.getUTCDate()).padStart(2, "0")}`,
          `day=${day} h=${h}`);
    }
  }
});

t("(أ٣) انزلاقُ اليومِ هو عينُ ما كان يُكسَر: 22:00Z = 01:00 الغد", () => {
  assert.deepStrictEqual(ksa.riyadhBookingFields(Date.UTC(2026, 9, 6, 22)),
      {bookingDate: "2026-10-07", bookingTimeSlot: "01:00"});
  // ونهايةُ السنة: 31 ديسمبر 21:00Z = 1 يناير 00:00 بالرياض.
  assert.deepStrictEqual(ksa.riyadhBookingFields(Date.UTC(2026, 11, 31, 21)),
      {bookingDate: "2027-01-01", bookingTimeSlot: "00:00"});
});

t("(أ٤) تَقبلُ Date كما تَقبلُ ميلي-ثانية، وتردُّ null للّحظةِ الفاسدة", () => {
  const ms = Date.UTC(2026, 9, 7, 11);
  assert.deepStrictEqual(ksa.riyadhBookingFields(new Date(ms)),
      ksa.riyadhBookingFields(ms));
  for (const bad of [NaN, undefined, null, "غير رقم", new Date("x")]) {
    assert.deepStrictEqual(ksa.riyadhBookingFields(bad),
        {bookingDate: null, bookingTimeSlot: null}, String(bad));
  }
  assert.strictEqual(ksa.riyadhStamp(NaN), null);
});

t("(أ٥) riyadhLocalDate/Slot/Stamp مشتقّاتٌ لا صيغٌ مستقلّة", () => {
  for (const h of [0, 3, 11, 20, 23]) {
    const ms = Date.UTC(2026, 4, 17, h, 0, 0);
    const f = ksa.riyadhBookingFields(ms);
    assert.strictEqual(ksa.riyadhLocalDate(ms), f.bookingDate);
    assert.strictEqual(ksa.riyadhLocalSlot(ms), f.bookingTimeSlot);
    assert.strictEqual(ksa.riyadhStamp(ms),
        `${f.bookingDate} ${f.bookingTimeSlot}`);
  }
});

// ════════════════════════ (ب) parseKsaIso ════════════════════════

t("(ب١) سلسلةٌ ساذجةٌ تُفهَم كتوقيتِ الرياض، وبـZ/إزاحةٍ تمرُّ كما هي", () => {
  assert.strictEqual(ksa.parseKsaIso("2026-10-07T14:00:00.000").toISOString(),
      "2026-10-07T11:00:00.000Z");
  assert.strictEqual(ksa.parseKsaIso("2026-10-07T11:00:00.000Z").toISOString(),
      "2026-10-07T11:00:00.000Z");
  assert.strictEqual(ksa.parseKsaIso("2026-10-07T14:00:00+03:00").toISOString(),
      "2026-10-07T11:00:00.000Z");
  assert.strictEqual(ksa.parseKsaIso("2026-10-07T14:00:00+0300").toISOString(),
      "2026-10-07T11:00:00.000Z");
  assert.ok(isNaN(ksa.parseKsaIso("ليس تاريخاً").getTime()));
});

t("(ب٢) الذهابُ والعودةُ مُغلَقان: ساذجةٌ ← لحظةٌ ← حقلان = الأصل", () => {
  // هذا ما كان مكسوراً: اللحظةُ صحيحةٌ والمشتقُّ خاطئ.
  for (const h of [0, 1, 2, 8, 14, 22, 23]) {
    const hh = String(h).padStart(2, "0");
    const d = ksa.parseKsaIso(`2026-10-07T${hh}:00:00.000`);
    const f = ksa.riyadhBookingFields(d);
    assert.strictEqual(f.bookingTimeSlot, `${hh}:00`, `h=${h}`);
    assert.strictEqual(f.bookingDate, "2026-10-07", `h=${h}`);
  }
});

t("(ب٣) KSA_OFFSET_MS ثلاثُ ساعاتٍ بالضبط — لا توقيتَ صيفيّاً هنا", () => {
  assert.strictEqual(ksa.KSA_OFFSET_MS, 3 * 60 * 60 * 1000);
});

// ════════════════════════ (ج) حارسُ index.js ════════════════════════

t("(ج١) لا صيغةَ إزاحةٍ يدويّةً داخل new Date( في index.js", () => {
  const hits = idxNoComments.split("\n")
      .map((l, i) => ({l, n: i + 1}))
      .filter(({l}) => /new Date\([^)]*\b3 \* 60 \* 60 \* 1000/.test(l));
  assert.deepStrictEqual(hits.map((h) => h.l.trim()), [],
      "إزاحةُ الرياضِ كُتبت يدويّاً مرّةً أخرى — موضعُها ksa_time.js");
  // والحرفُ نفسُه بمعنىً آخر (مُهلةُ ما بعد الانتهاء) يبقى مسموحاً — ولا بدّ
  // أن يبقى موجوداً، وإلّا فالفحصُ أعلاه بلا موضوعٍ يُميّزه عنه.
  assert.ok(/endMsOf\(d\) \+ 3 \* 60 \* 60 \* 1000/.test(idxNoComments),
      "مُهلةُ الثلاثِ ساعاتٍ في opsHealthSweep اختفت — راجِع الفحصَ أعلاه");
});

t("(ج٢) كلُّ كتابةٍ لحقلَي الحجزِ في index.js تأتي من الوحدةِ أو من زيارةٍ مخزَّنة",
    () => {
      const allowed = new Set([
        // من riyadhBookingFields مباشرةً
        "payload.booking_date = bf.bookingDate;",
        "payload.booking_time_slot = bf.bookingTimeSlot;",
        "upd.booking_date = rbf.bookingDate;",
        "upd.booking_time_slot = rbf.bookingTimeSlot;",
        "booking_date: bookingDate,",
        "booking_time_slot: timeSlot,",
        // تمريرُ موعدٍ مخزَّنٍ سلفاً في scheduled_visits (لا حسابَ منطقةٍ فيه)
        "booking_date: v.date,",
        "booking_time_slot: v.slot,",
      ]);
      const seen = idxNoComments.split("\n")
          .map((l) => l.trim())
          .filter((l) => /^(?:\w+\.)?booking_(?:date|time_slot)\s*[:=]/.test(l));
      assert.ok(seen.length >= 8, `عددُ مواضعِ الكتابةِ ${seen.length} — أقلّ ` +
        "من المتوقَّع: هل أُعيدت صياغتُها فصار الحارسُ بلا موضوع؟");
      const strays = [...new Set(seen.filter((l) => !allowed.has(l)))];
      assert.deepStrictEqual(strays, [],
          "كتابةٌ جديدةٌ لحقلَي الحجز — إن كانت من لحظةٍ زمنيّةٍ فمصدرُها " +
          "ksa_time.riyadhBookingFields، وإلّا فأضفها هنا بوعي:\n" +
          strays.map((x) => "  - " + x).join("\n"));
    });

t("(ج٣) لا getHours()/getMinutes() في index.js — الساعةُ المحلّيّةُ هي الفخّ", () => {
  // التاريخُ المبنيُّ من مكوّناتٍ يَقرأ getFullYear/getMonth/getDate بحقّ (ثلاثةُ
  // مواضع)، أمّا **الساعة** فلا تُقرأُ محلّيّاً في أيِّ موضعٍ صحيح: كلُّ ساعةٍ
  // هنا آتيةٌ من لحظةٍ زمنيّة. فهذا الفحصُ قاطعٌ بلا استثناءات.
  for (const bad of ["getHours()", "getMinutes()"]) {
    assert.ok(!idxNoComments.includes(bad),
        `${bad} في index.js — تُعيدُ ساعةَ UTC لا ساعةَ الرياض`);
  }
  assert.ok(idxNoComments.includes("getUTCHours()") ||
    mod.includes("getUTCHours()"), "لا قراءةَ ساعةٍ في أيِّ موضع — فحصٌ بلا موضوع");
});

t("(ج٤) الصيغةُ حُذفت من index.js فعلاً ولم تُنسَخ", () => {
  for (const gone of ["function _parseKsaIso", "const _riyadhLocalDate",
    "const _pad2"]) {
    assert.ok(!idx.includes(gone), `${gone} ما زال في index.js`);
  }
  assert.ok(idx.includes("require(\"./ksa_time\")"), "الوحدةُ غيرُ مستوردة");
  for (const used of ["riyadhBookingFields(", "riyadhLocalDate(",
    "riyadhLocalSlot(", "riyadhStamp(", "parseKsaIso("]) {
    assert.ok(idx.includes(used), `${used} غيرُ مستعمَلٍ — استيرادٌ ميت`);
  }
  assert.strictEqual(
      (idx.match(/riyadhBookingFields\(/g) || []).length, 5,
      "مواضعُ حقلَي الحجزِ الخمسة (إسنادٌ تلقائيّ/اعتمادٌ إداريّ/نقلُ موعد/" +
      "إنشاءٌ من دفعة/مصالحةُ يتيمة)");
});

t("(ج٥) الوحدةُ نقيّةٌ: لا Firestore ولا db", () => {
  for (const bad of ["require(\"firebase", "getFirestore", "getApp(",
    "initializeApp"]) {
    assert.ok(!stripComments(mod).includes(bad), `ksa_time.js تلمس ${bad}`);
  }
  // والتعليقُ يذكرُ المصطلحَ عمداً (يَشرحُ القاعدة) — فالتجريدُ لازمٌ ولا يُفرِغ.
  assert.ok(mod.includes("timeZone: \"Asia/Riyadh\""),
      "تعليقُ الوحدةِ فقد شرحَ لماذا timeZone لا يَضبطُ منطقةَ العمليّة");
});

t("(ج٦) capacity.js ما زال يَقرأ الحقلَ الذي أصلحناه — وإلّا فالعطلُ بلا أثر", () => {
  const cap = fs.readFileSync(path.join(__dirname, "..", "capacity.js"), "utf8");
  assert.ok(cap.includes("d.booking_time_slot") && cap.includes("d.booking_date"),
      "السعةُ لم تعد تقرأ حقلَي الحجز — أعِد تقييمَ هذا الحارسِ كلِّه");
});

console.log(`\nksa_time tests: ${passed} passed`);
