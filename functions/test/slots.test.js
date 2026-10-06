"use strict";

// نافذةُ شَغل السائق ومسندُ التداخل — تشغيل: node test/slots.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// سؤالٌ واحد بصياغتين — **إلى متى يَشغل هذا الطلبُ سائقَه، وهل يتداخل مع فترةٍ
// أخرى؟** — كان مكتوباً بيدٍ في **٢٣** موضعاً:
//
//   مدّةُ الطلب `Number(x.hours_contracted || 4)` ............. ١٦ موضعاً
//   مسحُ التعارض (نافذة −٢٤س + الحالات النشطة + المقارنة) ...... ٧ مواضع
//
// **ولم يكن فيه انحراف، وقول ذلك جزءٌ من الصدق.** فحصتُ السبعةَ أوّلاً بحثاً عن
// تباعد: النوافذ كلّها −٢٤س، ومجموعاتُ الحالات متطابقةٌ **مجموعةً** (تختلف
// ترتيباً، ولا أثر لذلك في استعلام `in`)، والمقارنةُ بالصيغة نفسها في الخمسة،
// والافتراضُ ٤ في السادسة عشرة. والموضعُ الوحيد المختلف — `["scheduled",
// "assigned", "accepted"]` في `unassignJobsOnDriverDisable` — **مقصودٌ وموثَّق**:
// «الجارية فعلاً (on_the_way/in_progress) تُترك عمداً — قرارها بشري». فلم
// أوحّده، ويحرس هذا الملفّ بقاءَه مستقلاً.
//
// فالتوحيدُ **وقائيّ**، وهذا ما يجعله نافعاً: تغييرُ الافتراضي من ٤ ساعات —
// قرارُ منتَجٍ محتمل — يلزمه اليوم تعديلُ ١٦ موضعاً معاً، وهو شكلُ قصّة الضريبة
// نفسها (٢٧ موضعاً، ٥٪ ← ١٥٪، وموضعٌ منسيٌّ يُنتج خطأً صامتاً).
//
// ═══ وفرقٌ كامن أُصلح: موضعُ القوس في Number() ═══
//
// المواضع كانت تكتب `Number(x.hours_contracted || 4)`. والقوسُ مهمّ:
//
//   Number("abc" || 4)  →  Number("abc")  →  NaN
//   Number("abc") || 4  →  4
//
// و`NaN` تُنتج `Invalid Date`، ومقارنةُ التداخل مع `Invalid Date` **false**
// دائماً — أي **«السائق حرّ»**. فحقلٌ تالف (أو سالب) يُنتج حجزاً مزدوجاً بصمت،
// وهو أسوأ اتجاهٍ ممكن للخطأ. الوحدةُ تسقط على الافتراضي المحافظ.
// **كامنٌ لا حيّ:** لا موضع في المستودع يكتب `hours_contracted` نصّاً غير
// رقميّ أو سالباً (يُكتب `Number(md.hours || 4)` أو عدداً).
//
// ═══ ولمَ `||` هنا صحيح بخلاف amounts.js ═══
//
// هناك `??` واجب: صفرٌ صريح **قرار** (طلبٌ مجّاني، تسويةٌ كاملة) و`||` يتخطّاه
// فيُحمّل العميلَ ما لا يلزمه. وهنا العكس: صفرُ ساعاتٍ ليس قراراً بل حقلٌ غير
// مضبوط. فالاختلافُ مقصود، والسؤالان مختلفان.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const slots = require("../slots");

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

/** @param {Date|string} d @return {object} طابعٌ شبيه بـTimestamp */
const ts = (d) => ({toDate: () => new Date(d)});
const H = 60 * 60 * 1000;
const T0 = new Date("2026-07-20T08:00:00Z");

// ════════════════════════════ orderHours ════════════════════════════

t("مدّةٌ صريحة تُستعمل كما هي (عدداً أو نصّاً رقميّاً)", () => {
  assert.strictEqual(slots.orderHours({hours_contracted: 6}), 6);
  assert.strictEqual(slots.orderHours({hours_contracted: "12"}), 12);
  assert.strictEqual(slots.orderHours({hours_contracted: 1.5}), 1.5);
});

t("الغياب/الصفر/null → الافتراضيّ ٤ (نفسُ سلوك المواضع الـ١٦)", () => {
  for (const v of [undefined, null, 0, ""]) {
    assert.strictEqual(slots.orderHours({hours_contracted: v}), 4, String(v));
    // وهو عينُ ما كان `Number(x || 4)` يُعطيه — فلا انحراف في المسار الحيّ.
    assert.strictEqual(Number(v || 4), 4, String(v));
  }
  assert.strictEqual(slots.orderHours({}), 4);
  assert.strictEqual(slots.orderHours(null), 4);
});

t("**الفرق الكامن**: نصٌّ تالف أو سالب → ٤ لا NaN", () => {
  for (const bad of ["abc", "", {}, [], -2, NaN]) {
    assert.strictEqual(slots.orderHours({hours_contracted: bad}), 4,
        `قيمة ${JSON.stringify(bad)}`);
  }
  // والصيغةُ القديمة كانت تُعطي NaN لنصٍّ غير رقميّ — وNaN تُقرأ «السائق حرّ».
  const corrupt = "abc"; // متغيّرٌ لا ثابتٌ: eslint يرفض `"abc" || 4`
  assert.ok(Number.isNaN(Number(corrupt || 4)), "النمطُ القديم يُنتج NaN فعلاً");
  assert.strictEqual(Number(corrupt) || 4, 4, "والنمطُ الجديد يسقط على الافتراضي");
});

t("منطقيٌّ تالفٌ → الافتراضيّ لا ساعةً واحدة (Number(true) === 1)", () => {
  assert.strictEqual(slots.orderHours({hours_contracted: true}), 4);
  assert.strictEqual(slots.orderHours({hours_contracted: false}), 4);
  assert.strictEqual(slots.orderHours(null, true), 4, "وكذلك كمُدّةٍ مُمرَّرة");
});

t("مدّةٌ مُمرَّرة صراحةً تتقدّم على الحقل (التوجيه المباشر)", () => {
  assert.strictEqual(slots.orderHours({hours_contracted: 4}, 8), 8);
  // وغيابُها لا يحجب الحقل (كان `durationHours || orderData.hours_contracted || 4`).
  assert.strictEqual(slots.orderHours({hours_contracted: 6}, undefined), 6);
  assert.strictEqual(slots.orderHours({hours_contracted: 6}, null), 6);
  assert.strictEqual(slots.orderHours({hours_contracted: 6}, 0), 6,
      "صفرُ ساعاتٍ ليس قراراً — يسقط على الحقل كما كان `||` يفعل");
});

// ═════════════════════════ orderEnd / النافذة ═════════════════════════

t("نهايةُ الفترة = البداية + المدّة", () => {
  assert.strictEqual(slots.orderEnd(T0, {hours_contracted: 6}).getTime(),
      T0.getTime() + 6 * H);
  assert.strictEqual(slots.orderEnd(T0, {}).getTime(), T0.getTime() + 4 * H);
  assert.strictEqual(slots.orderEnd(T0, {hours_contracted: 4}, 12).getTime(),
      T0.getTime() + 12 * H);
});

t("نافذةُ المسح −٢٤س بالضبط (لا −٨س ولا حدودَ يومٍ تقويميّ)", () => {
  assert.strictEqual(slots.CONFLICT_LOOKBACK_HOURS, 24);
  assert.strictEqual(slots.conflictWindowStart(T0).getTime(),
      T0.getTime() - 24 * H);
  // الحادثةُ التي أوجبت −٢٤: باقةُ سكنٍ ١٢ ساعة تبدأ قبل الفترة بـ١٠ ساعات.
  const long = {service_date: ts(new Date(T0.getTime() - 10 * H)),
    hours_contracted: 12};
  assert.ok(slots.conflictWindowStart(T0) <= long.service_date.toDate(),
      "النافذة يجب أن تبلغها");
  assert.ok(slots.overlapsSlot(long, T0, new Date(T0.getTime() + 4 * H)),
      "وتُحسَب متداخلة");
  // ولو كانت −٨س لخرجت من الاستعلام أصلاً فبقي السائق «حرّاً».
  const eight = new Date(T0.getTime() - 8 * H);
  assert.ok(long.service_date.toDate() < eight,
      "بـ−٨س كانت تسقط من الاستعلام — وهذا هو العطل الذي أُصلح");
});

// ═══════════════════════════ overlapsSlot ═══════════════════════════

t("التداخلُ بالصيغة نفسها: البداية < نهايةُ الآخر && بدايتُه < النهاية", () => {
  const slotEnd = new Date(T0.getTime() + 4 * H); // 08:00–12:00
  const at = (h, hrs) => ({service_date: ts(new Date(T0.getTime() + h * H)),
    hours_contracted: hrs});
  assert.strictEqual(slots.overlapsSlot(at(2, 4), T0, slotEnd), true, "جزئيّ بعد");
  assert.strictEqual(slots.overlapsSlot(at(-2, 4), T0, slotEnd), true, "جزئيّ قبل");
  assert.strictEqual(slots.overlapsSlot(at(1, 1), T0, slotEnd), true, "محتوى");
  assert.strictEqual(slots.overlapsSlot(at(-1, 8), T0, slotEnd), true, "محيط");
});

t("التماسُّ على الحدّ ليس تداخلاً (في الطرفين)", () => {
  const slotEnd = new Date(T0.getTime() + 4 * H);
  // ينتهي الآخر لحظةَ بدئنا.
  assert.strictEqual(slots.overlapsSlot(
      {service_date: ts(new Date(T0.getTime() - 4 * H)), hours_contracted: 4},
      T0, slotEnd), false, "نهايتُه = بدايتُنا");
  // يبدأ الآخر لحظةَ انتهائنا.
  assert.strictEqual(slots.overlapsSlot(
      {service_date: ts(slotEnd), hours_contracted: 4}, T0, slotEnd), false,
  "بدايتُه = نهايتُنا");
});

t("بلا service_date أو بطابعٍ تالف → لا تداخل (كلُّ موضعٍ كان يتخطّاه)", () => {
  const slotEnd = new Date(T0.getTime() + 4 * H);
  for (const bad of [null, {}, {service_date: null},
    {service_date: "2026-07-20"}, {service_date: ts("not a date")}]) {
    assert.strictEqual(slots.overlapsSlot(bad, T0, slotEnd), false,
        JSON.stringify(bad));
  }
});

t("مدّةٌ تالفة لا تُنتج «حرّاً»: تُحسَب ٤ ساعات فتتداخل", () => {
  const slotEnd = new Date(T0.getTime() + 4 * H);
  const corrupt = {service_date: ts(new Date(T0.getTime() + 1 * H)),
    hours_contracted: "٦"}; // أرقامٌ عربيّة-هنديّة: Number() تُعطي NaN
  assert.ok(Number.isNaN(Number("٦")), "فعلاً NaN");
  assert.strictEqual(slots.overlapsSlot(corrupt, T0, slotEnd), true,
      "**الفرق الكامن**: بالصيغة القديمة كانت Invalid Date فتُقرأ «حرّ»");
});

// ══════════════════════════ الحالاتُ النشطة ══════════════════════════

t("مجموعةُ التعارض خمسُ حالاتٍ، وpending خارجَها بقصد", () => {
  assert.deepStrictEqual([...slots.CONFLICT_STATUSES].sort(),
      ["accepted", "assigned", "in_progress", "on_the_way", "scheduled"]);
  assert.ok(!slots.CONFLICT_STATUSES.includes("pending"),
      "طلبٌ لم يُسنَد لا يَشغل أحداً");
  assert.ok(slots.CONFLICT_STATUSES.includes("assigned"),
      "استبعادُ assigned كان يجعل السائق «المُسنَد» حرّاً في كل استعلامات " +
      "الانشغال فيُحجَز لمهمتين متداخلتين");
});

// ══════════════════════════ حرّاس المصدر ══════════════════════════

const idx = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

// ═══ نطاقُ حارسِ المدّة: **كلُّ** وحدات `functions/` لا `index.js` وحدَه ═══
//
// كان هذا الفحصُ يقرأ `index.js` فقط، وقاعدتُه عامّة («المدّةُ في
// `slots.orderHours`») — فمرَّ أخضرَ على **الموضعِ السابعَ عشَر** القائمِ في
// `capacity.js` منذ الشريحةِ نفسِها، بالقوسِ الخاطئِ الذي وُجدت الشريحةُ
// لإصلاحه. وهو نمطُ «حارسٌ ضيّقٌ وقاعدةٌ عامّة» للمرّةِ السابعةِ في هذا
// المستودع. فالنطاقُ **مُشتَقٌّ** من المجلّد الآن: وحدةٌ جديدةٌ تدخله بنفسها.
const modules = fs.readdirSync(path.join(__dirname, ".."))
    .filter((f) => f.endsWith(".js") && f !== "slots.js" &&
        f !== "eslint.config.js")
    .map((f) => ({name: f,
      raw: fs.readFileSync(path.join(__dirname, "..", f), "utf8")}));

/**
 * حجبُ التعليقات قبل المسح — وإلّا سقطَ الفحصُ على توثيقِه: ترويسةُ
 * `capacity.js` وتعليقاتُ `index.js` تُسمّي الصيغةَ الممنوعةَ لتشرحَ لمَ
 * زالت. و`//` لا تُحجَبُ إن سبقَها `:` (فـ`https://` ليست تعليقاً).
 * @param {string} src المصدرُ الخامّ.
 * @return {string} المصدرُ بلا تعليقات.
 */
function stripComments(src) {
  return src
      .replace(/\/\*[\s\S]*?\*\//g, " ")
      .split("\n")
      .map((l) => l.trim().startsWith("//") ? "" : l.replace(/(^|[^:])\/\/.*$/, "$1"))
      .join("\n");
}

t("لا موضعَ يكتب مدّةَ الطلب بيده في أيِّ وحدةٍ من functions/", () => {
  assert.ok(modules.length >= 12,
      `المسحُ قرأ ${modules.length} وحدةً فقط — فحصٌ أخضرُ أجوف`);
  const hits = [];
  for (const m of modules) {
    const code = stripComments(m.raw);
    // (أ) سلسلةُ الافتراضي على الحقل نفسه.
    for (const x of code.match(/hours_contracted\s*\|\|/g) || []) {
      hits.push(`${m.name}: ${x.replace(/\s+/g, " ")} ...`);
    }
    // (ب) نفسُها على الحقلِ المُجاورِ في مستندِ العقد/الـmetadata (`c.hours`,
    //     `md.hours`) — وهو ما كان يكتب NaN في `hours_contracted` نفسِه.
    for (const x of code.match(/\bhours\s*\|\|\s*\d/g) || []) {
      hits.push(`${m.name}: ${x.replace(/\s+/g, " ")}`);
    }
    // (ج) الحسابُ من الحقل مباشرةً داخل Number(...).
    for (const x of code.match(/Number\([^)]*hours_contracted/g) || []) {
      hits.push(`${m.name}: ${x.replace(/\s+/g, " ")}`);
    }
  }
  // مقارنةٌ **بالمجموعة الكاملة** لا بالعدد: الموضعُ المسموحُ واحدٌ وسببُه
  // مكتوب، فموضعٌ ثانٍ يُراجَع بوعي بدل أن يُمرَّر تحت سماحٍ عامّ.
  assert.deepStrictEqual(hits.sort(), [
    // `pricing.js` تقرأ سعرَ المدّة من خريطةِ المنطقة بمفتاحِ المدّة —
    // بحثٌ في خريطةٍ لا سلسلةُ افتراضي، ومحروسٌ بـ`if (!hp || isNaN(hp))`.
    "pricing.js: Number(prices[String(order.hours_contracted",
  ].sort(), "سلسلةُ المدّة عادت إنلاين — موضعُها slots.orderHours:\n" +
      hits.map((x) => "  - " + x).join("\n"));
  // ومضادّةٌ: الحجبُ لم يُفرِغ المصدرَ — الصيغةُ الممنوعةُ ما زالت في الخامّ
  // داخل التعليقات التي تشرح زوالَها.
  assert.ok(modules.some((m) => m.raw.includes("hours_contracted || 4")),
      "التعليقُ الحاملُ للقرار حُذف — أو الحجبُ يَبتلعُ شفرةً");
});

t("المُستهلكونَ يُنادونَ القاعدةَ فعلاً", () => {
  assert.ok(idx.includes("slots.orderHours("), "index.js لا يُناديها");
  const cap = fs.readFileSync(path.join(__dirname, "..", "capacity.js"), "utf8");
  assert.ok(/slots\.orderHours\(/.test(cap),
      "capacity.js لا تُنادي القاعدة — وعدُّ الساعات هو ما يُقرّرُ الإتاحة");
  assert.ok(cap.includes("require(\"./slots\")"), "ولا تستوردها");
  // ومولِّدا زياراتِ العقد: `Invalid Date` هناك تُقرأ «السائق حرّ» دائماً.
  assert.strictEqual(
      (idx.match(/slots\.orderHours\(\{hours_contracted: c\.hours\}\)/g) || []).length,
      2, "مولِّدا الزيارات — أحدهما عاد يحسب المدّة بيده");
});

t("capacity.js تبقى قابلةً للاختبار بلا مُحاكٍ", () => {
  // عبارةُ «بلا تبعيات» في ترويستها كانت تحرُسُ هذا، لا النقاءَ لذاته:
  // وحدةٌ نقيّةٌ تستوردُ وحدةً نقيّةً لا تَنقضُه (قاعدةُ refund_engine.js).
  const cap = fs.readFileSync(path.join(__dirname, "..", "capacity.js"), "utf8");
  for (const bad of ["getFirestore", "getApp", "initializeApp"]) {
    assert.ok(!stripComments(cap).includes(bad), `capacity.js تلمس ${bad}`);
  }
});

t("لا موضعَ يكتب نافذةَ المسح أو مقارنةَ التداخل بيده", () => {
  assert.ok(!/getTime\(\) - 24 \* 60 \* 60 \* 1000/.test(idx),
      "حسابُ النافذة إنلاين — موضعُه slots.conflictWindowStart");
  assert.strictEqual(
      (idx.match(/slots\.conflictWindowStart\(/g) || []).length, 5,
      "مواضعُ المسح الخمسة");
  assert.strictEqual((idx.match(/slots\.overlapsSlot\(/g) || []).length, 5,
      "مقارناتُ التداخل الخمس");
  // الصيغةُ القديمة للمقارنة لم تَعُد في index.js.
  assert.ok(!/< oEnd && oStart </.test(idx),
      "مقارنةُ التداخل مكتوبةٌ إنلاين من جديد");
});

t("مجموعاتُ الحالات الباقية هي **بالضبط** غيرُ المتعلّقة بالانشغال", () => {
  // بالمقارنة الكاملة لا بالاحتواء: مجموعةٌ سادسة تُسقط الفحص فتُراجَع بوعي.
  const sets = (idx.match(/\["scheduled"[^\]]*\]/g) || [])
      .map((x) => x.replace(/\s+/g, " ")).sort();
  assert.deepStrictEqual(sets, [
    // (أ) «هل أُبلِغ العميلَ بتغيّر الموعد؟» — سؤالٌ آخر، نفسُ المجموعة اليوم.
    "[\"scheduled\", \"accepted\", \"assigned\", \"on_the_way\", \"in_progress\"]",
    // (ب) قرارُ المالك الموثَّق: الجارية فعلاً تُترك للسائق — **لا تُوحَّد**.
    "[\"scheduled\", \"assigned\", \"accepted\"]",
    // (ج) نطاقُ تقرير الصحّة التشغيليّة — سؤالٌ آخر كذلك.
    "[\"scheduled\", \"assigned\", \"accepted\", \"on_the_way\", \"in_progress\"]",
  ].map((x) => x.replace(/\s+/g, " ")).sort(),
  "مجموعةُ حالاتٍ جديدة إنلاين — إن كان السؤال «هل السائق مشغول؟» " +
      "فموضعُها slots.CONFLICT_STATUSES، وإلّا فأضفها هنا بوعي:\n" +
      sets.map((x) => "  - " + x).join("\n"));
});

t("قرارُ unassignJobsOnDriverDisable باقٍ مستقلاً وموثَّقاً", () => {
  const i = idx.indexOf("exports.unassignJobsOnDriverDisable");
  const body = idx.substring(i, idx.indexOf("exports.", i + 10));
  assert.ok(body.includes("[\"scheduled\", \"assigned\", \"accepted\"]"),
      "الجاريةُ فعلاً تُترك عمداً — توحيدُها يسلب السائقَ مهمّةً يؤدّيها");
  assert.ok(!body.includes("slots.CONFLICT_STATUSES"),
      "وُحِّدت بالخطأ — وهي سؤالٌ آخر وقرارٌ بشريّ");
  assert.ok(idx.includes("الجارية فعلاً (on_the_way/in_progress) تُترك عمداً"),
      "التعليقُ الذي يحمل القرار حُذف");
});

t("الوحدةُ نقيّة: لا Firestore ولا db", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "slots.js"), "utf8");
  for (const bad of ["require(\"firebase", "getFirestore", "db.", "(db,"]) {
    assert.ok(!src.includes(bad), `slots.js تلمس ${bad}`);
  }
});

console.log(`\nslots tests: ${passed} passed`);
