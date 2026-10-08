"use strict";

// price_verify: حلُّ منطقةِ الطلبِ، و«هل نوعُه قابلٌ للتحقّقِ من سعره؟».
// بـ`db` مُزيَّفٍ — لا مُحاكٍ ولا شبكة (قاعدةُ الوحداتِ هنا).

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const {resolveZone, isPriceableKind} = require("../price_verify");
const {PRICEABLE_KINDS, computeExpectedBasePrice} = require("../pricing");

let ok = 0; let fail = 0;
const t = (name, fn) => {
  try { fn(); console.log(`ok - ${name}`); ok++; } catch (e) {
    console.error(`FAIL - ${name}\n    ${e.message}`); fail++;
  }
};
const ta = async (name, fn) => {
  try { await fn(); console.log(`ok - ${name}`); ok++; } catch (e) {
    console.error(`FAIL - ${name}\n    ${e.message}`); fail++;
  }
};

/** `db` مُزيَّفٌ: مستنداتٌ بالمعرّفِ ومستنداتٌ بالاسم. */
function fakeDb({byId = {}, byName = {}} = {}) {
  const calls = {docGets: [], nameQueries: []};
  const db = {
    collection(c) {
      assert.strictEqual(c, "service_zones");
      return {
        doc(id) {
          return {get: async () => {
            calls.docGets.push(id);
            const d = byId[id];
            return {exists: !!d, data: () => d};
          }};
        },
        where(field, op, val) {
          assert.strictEqual(field, "name");
          assert.strictEqual(op, "==");
          return {limit: () => ({get: async () => {
            calls.nameQueries.push(val);
            const d = byName[val];
            return {empty: !d, docs: d ? [{data: () => d}] : []};
          }})};
        },
      };
    },
  };
  return {db, calls};
}

(async () => {
  // ─────────── resolveZone ───────────
  await ta("(١) zone_id يُفضَّل على الاسم", async () => {
    const {db, calls} = fakeDb({
      byId: {z1: {name: "فيفا", by: "id"}},
      byName: {"فيفا": {name: "فيفا", by: "name"}},
    });
    const z = await resolveZone(db, {zone_id: "z1", zone_name: "فيفا"});
    assert.strictEqual(z.by, "id");
    assert.deepStrictEqual(calls.nameQueries, [], "لا استعلامَ بالاسمِ بعد نجاحِ المعرّف");
  });

  await ta("(٢) الاسمُ احتياطٌ حين لا يُوجد المعرّف", async () => {
    const {db, calls} = fakeDb({byName: {"فيفا": {by: "name"}}});
    const z = await resolveZone(db, {zone_id: "missing", zone_name: "فيفا"});
    assert.strictEqual(z.by, "name");
    assert.deepStrictEqual(calls.docGets, ["missing"]);
  });

  await ta("(٣) الاسمُ وحدَه (ما يَكتبُه التطبيقُ فعلاً اليوم)", async () => {
    const {db} = fakeDb({byName: {"الدائر": {by: "name"}}});
    assert.strictEqual((await resolveZone(db, {zone_name: "الدائر"})).by, "name");
  });

  await ta("(٤) لا منطقةَ ⇒ null (لا رميَ ولا تخمين)", async () => {
    const {db} = fakeDb({});
    assert.strictEqual(await resolveZone(db, {zone_name: "لا توجد"}), null);
    assert.strictEqual(await resolveZone(db, {}), null);
    assert.strictEqual(await resolveZone(db, null), null);
  });

  // ─────────── isPriceableKind ───────────
  t("(٥) كلُّ نوعٍ يُسعّرُه pricing.js قابلٌ للتحقّق", () => {
    for (const kind of PRICEABLE_KINDS) {
      assert.ok(isPriceableKind({service_meta: {kind}}), kind);
    }
  });

  t("(٦) event_workers منها — وكان غائباً عن التعدادِ اليدويّ", () => {
    // الثغرةُ بالضبط: نوعٌ يُسعّرُه الخادمُ وكان إسقاطُ المنطقةِ عليه يَمرُّ صامتاً.
    assert.ok(PRICEABLE_KINDS.includes("event_workers"));
    assert.ok(isPriceableKind({service_meta: {kind: "event_workers"}}));
  });

  t("(٧) المتجرُ ليس قابلاً للتحقّق (عناصرُه بلا معرّفِ منتج)", () => {
    assert.ok(!isPriceableKind({service_meta: {kind: "store_products"}}));
  });

  // كان هذا الفحصُ يُثبّتُ `!isPriceableKind({})` — أي أنّ غيابَ المدّةِ
  // يُخرِجُ الطلبَ من نطاقِ التحقّق. وتلك هي الثغرةُ نفسُها: الحقلُ يكتبه
  // العميلُ، فإسقاطُه (أو صفرُه أو تلفُه) كان يُطفئُ إعادةَ التسعيرِ بصمت.
  // أُعيد توجيهُه بوعي لا أُسكِت — و(٢٨) يَشُدُّ أنّ التوسيعَ لا يُنبّهُ
  // على شكلٍ شريف.
  t("(٨) بلا service_meta ⇒ بالساعة ⇒ قابلٌ للتحقّق — أيّاً كانت المدّة", () => {
    assert.ok(isPriceableKind({hours_contracted: 4}));
    for (const bad of [0, "0", "abc", -1, null, undefined, "", false]) {
      assert.ok(isPriceableKind({hours_contracted: bad}),
          `مدّةٌ ${JSON.stringify(bad)} أطفأت التحقّق`);
    }
    assert.ok(isPriceableKind({}), "وإسقاطُ الحقلِ كلِّه كذلك");
    assert.ok(!isPriceableKind(null), "ولا مستندَ ⇒ لا تحقّق");
  });

  t("(٩) نوعٌ مجهولٌ لا يُقرأ قابلاً للتحقّق", () => {
    // لو قُرئ قابلاً لأنتجَ تنبيهاً إداريّاً على كلِّ طلبٍ من نوعٍ جديد.
    assert.ok(!isPriceableKind({service_meta: {kind: "لم_يُولد_بعد"}}));
    assert.ok(!isPriceableKind({service_meta: {kind: "x"}, hours_contracted: 4}));
  });

  // ─────────── القائمةُ لا تَنفكُّ عن المُسعِّر ───────────
  t("(١٠) كلُّ فرعِ kind في pricing.js مُدرَجٌ في PRICEABLE_KINDS", () => {
    const src = fs.readFileSync(path.join(__dirname, "..", "pricing.js"), "utf8");
    const body = src.slice(src.indexOf("function computeExpectedBasePrice"));
    // `kind` وحدَه، غيرَ مسبوقٍ بنقطة: `p.kind === "rug"` داخلَ فرعِ الكنبِ
    // نوعُ **قطعة** لا نوعُ خدمة — وقد التقطَته أوّلُ صيغةٍ لهذا الفحص.
    const branches = new Set(
        [...body.matchAll(/(?:^|[^.\w])kind === "([a-z_]+)"/g)].map((m) => m[1]));
    // store_products مذكورٌ في تعليقٍ لا في فرعٍ — فالمقارنةُ بالفروعِ وحدَها.
    assert.deepStrictEqual([...branches].sort(), [...PRICEABLE_KINDS].sort(),
        `فروعُ المُسعِّر: ${[...branches]} — القائمة: ${PRICEABLE_KINDS}`);
  });

  t("(١١) الأنواعُ المُدرَجةُ تُحسَبُ فعلاً (ولا تُعيدُ null لغيابِ فرع)", () => {
    // عيّنةٌ صالحةٌ لكلِّ نوع: غيابُ الفرعِ يُنتجُ null فيَسقطُ الفحص.
    const zone = {
      sofaSqmPrice: 10, rugSqmPrice: 20, acMaintSplitPrice: 30,
      carSmallPrice: 40, eventWorkerHourPrice: 50,
      packages: {villa: {crews: {"2": {enabled: true, price: 300}}}},
    };
    const samples = {
      sofa_rug_sqm: {pieces: [{kind: "sofa", length_m: 2}]},
      ac_service: {lines: [{job: "maintenance", type: "split", count: 1}]},
      car_interior: {lines: [{size: "small", count: 1}]},
      event_workers: {workers: 2, event_hours: 3},
      home_package: {homeType: "villa", crewCount: 2},
    };
    for (const kind of PRICEABLE_KINDS) {
      const base = computeExpectedBasePrice(
          {service_meta: {kind, ...samples[kind]}}, zone);
      assert.ok(base > 0, `${kind} ⇒ ${base}`);
    }
  });

  // ─────────── المسارانِ لا يَفترقانِ مرّةً أخرى ───────────
  const idx = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

  t("(١٢) لا حلَّ منطقةٍ مكتوباً بيدِه في index.js", () => {
    assert.ok(!idx.includes(".where(\"name\", \"==\", od.zone_name)"),
        "نسخةٌ ثالثةٌ من الاستعلامِ — المسارانِ اختلفا هكذا أوّلَ مرّة");
    assert.strictEqual(
        (idx.match(/priceVerify\.resolveZone\(/g) || []).length, 2,
        "مسارُ ميسر ومسارُ المحفظة");
  });

  t("(١٣) المسارانِ يَطرحانِ الخصمَ الموثوق", () => {
    assert.strictEqual(
        (idx.match(/_computeTrustedDiscount\(/g) || []).length, 3,
        "التعريفُ + نداءانِ (كان نداءً واحداً، فتُرفضُ دفعةُ محفظةٍ بكوبونٍ كبير)");
  });

  t("(١٤) المسارانِ يَسِمانِ ويُنبّهانِ على ما تعذّر التحقّقُ منه", () => {
    // تُجرَّدُ أسطرُ التعليقِ أوّلاً: `index.js` يَذكرُ الوسمَ في ترويسةِ
    // `_flagZoneGeoMismatch` — فعَدَّ الحارسُ ثلاثاً وسَقطَ على التوثيق.
    const code = idx.split("\n")
        .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    // **ثلاثةٌ الآن لا اثنان، وهذا تحديثٌ مقصودٌ لا إسكات.** أُضيف مسارُ
    // طلبِ المتجر (`_verifyStoreOrderPrice`): سلّتُه لم تكن تُعادُ تسعيرُها
    // خادميّاً إطلاقاً، فتعذّرُ تسعيرِها يَلزمُ أن يُوسَمَ ويُنبَّهَ عنه
    // كنظيرِه في `orders`. (نفسُ ما جرى لحارسِ «ثلاثةُ مواضع» في
    // `refund_engine.test.js` حين ظهرَ الرابع.)
    //
    // **والعدُّ على مواضعِ الكتابةِ لا على كلِّ ذكرٍ للاسم** — تحديثٌ ثانٍ
    // مقصود: كان `/price_unverifiable/` يَعُدُّ الذِكرَ أيّاً كان، فلمّا صارَ
    // للوسمِ **قارئٌ** (استعلامُ المكنسةِ وسطرُ سجلِّها) ارتفعَ العددُ إلى
    // خمسةٍ وسَقطَ الفحصُ على إضافةِ قارئ — وهو ما كان ينبغي أن يُسعِدَه.
    assert.strictEqual((code.match(/price_unverifiable: true/g) || []).length, 3,
        "كتابةٌ في كلِّ مسار: ميسر، المحفظة، وطلبُ المتجر");
    // وللوسمِ مكنسةٌ تَقرأُه: ثلاثةُ مواضعَ تَسِمُه ودفعةٌ مُبتلَعةٌ كانت كلَّ
    // ما هناك، فإن فشلت لم يَعلم أحدٌ أبداً.
    assert.ok(code.includes(".where(\"price_unverifiable\", \"==\", true)"),
        "اختفت مكنسةُ «تعذّر التحقّق» — والوسمُ يَعودُ بيانَ موتٍ بلا قارئ");
    // ولا يُفرّغُ التجريدُ الفحص.
    assert.ok(idx.includes("price_unverifiable)"),
        "ذكرُ الوسمِ في الترويسةِ ما زال — فلو غابَ فالتجريدُ حَجبَ شيئاً");
    assert.strictEqual(
        (idx.match(/priceVerify\.isPriceableKind\(/g) || []).length, 2);
    assert.ok(!/function _isPriceableKind/.test(idx),
        "التعدادُ اليدويُّ أُزيل — وهو ما أغفلَ event_workers");
  });

  // ─────────── الصفرُ ليس «لا تحقّق» ───────────
  t("(١٦) مسارُ المحفظةِ يُميّزُ `null` من `0`", () => {
    const code = idx.split("\n")
        .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    // `if (pkgExpectedGross && …)` يَقرأُ الصفرَ كاذباً فيُطفئُ الفحصَين.
    assert.ok(!code.includes("if (pkgExpectedGross && amount <"),
        "الصفرُ يُطفئُ الفحصَ — ميّزْ null من 0");
    assert.ok(code.includes("pkgExpectedGross !== null"),
        "تعذّرُ التحقّقِ يُقال null لا 0");
    assert.ok(code.includes("suspiciousZero"),
        "خصمٌ يَبلغُ السعرَ كاملاً مع دفعٍ موجبٍ يُوسَم");
    // وبالمقابل: اللفظُ ما زال في الخامّ (التعليقُ يَشرحُ الشرطَ المحذوف).
    assert.ok(idx.includes("if (pkgExpectedGross && …)"),
        "شرحُ الشرطِ المحذوفِ ما زال — فلو غابَ فالتجريدُ حَجبَ شيئاً");
  });

  t("(١٧) ولا يَرفضُ على الصفرِ — كما لا يَرفضُ مسارُ ميسر", () => {
    const code = idx.split("\n")
        .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    const i = code.indexOf("const suspiciousZero = verifiable");
    assert.ok(i > -1);
    const j = code.indexOf("runTransaction", i);
    const block = code.slice(i, j);
    const throwAt = block.indexOf("throw new HttpsError");
    const zeroAt = block.indexOf("suspiciousZero ||");
    assert.ok(throwAt > -1 && zeroAt > -1);
    assert.ok(throwAt < zeroAt,
        "الرفضُ قبلَ الوسم، والصفرُ في فرعِ الوسمِ وحدَه");
    // أرضيّةُ ميسر التي تَستثني كوبونَ الـ~100% من الإنفاذِ ما زالت.
    assert.ok(code.includes("expectedNet >= 5"),
        "أرضيّةُ Tier B هي ما يَجعلُ «لا رفض» هنا متّسقاً");
  });

  // ─────── كلُّ مسلكٍ إلى is_paid يُعيدُ التسعير ───────
  //
  // كان التحقّقُ على مسلكَين من خمسةٍ، وكلاهما `onCall` **يَختارُ العميلُ
  // نداءَها**: `moyasarWebhook` بلا إعادةِ تسعيرٍ إطلاقاً (فحصُه «المدفوعُ =
  // المُعلَن» و`expectedAmount` كلُّ حقولِه يَكتبها العميلُ عند الإنشاء)،
  // و`_tamaraFlipPaid` بلا أيِّ فحصِ مبلغ. وفوقَ ذلك يَرتدُّ
  // `verifyMoyasarPayment` على `is_paid === true` **قبلَ** فحصِه، فويب هوكٌ
  // سابقٌ يَستهلكُ الفحصَ كلَّه.
  const code = idx.split("\n")
      .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");

  t("(١٨) تحقّقُ السعرِ دالّةٌ واحدةٌ لا نسخةٌ لكلِّ مسلك", () => {
    assert.strictEqual(
        (code.match(/async function _verifyOrderPriceTierA\(/g) || []).length, 1,
        "تعريفٌ واحد");
    // إعادةُ التسعيرِ نفسُها في موضعَين فقط: الدالّةُ المُشترَكةُ ومسارُ
    // المحفظة (وله سياستُه: يَسِمُ بصمتٍ ويَتّكلُ على المسحِ الدوريّ).
    assert.strictEqual(
        (code.match(/computeExpectedBasePrice\(/g) || []).length, 2,
        "نسخةٌ ثالثةٌ مكتوبةٌ بيدِها — وهكذا افترقَ المسارانِ أوّلَ مرّة");
  });

  t("(١٩) والمسالكُ الثلاثةُ تُناديها", () => {
    assert.strictEqual(
        (code.match(/_verifyOrderPriceTierA\(/g) || []).length, 4,
        "التعريفُ + ثلاثةُ نداءات (verify / webhook / tamara)");
    for (const src of ["\"verify\"", "\"webhook\"", "\"tamara\""]) {
      assert.ok(code.includes(src),
          `المسلكُ ${src} لا يُسمّي نفسَه — فالسجلُّ لا يُميّزُ مَن وَسَم`);
    }
  });

  t("(٢٠) وTier B يَبقى على مسارِ النداءِ وحدَه — بقرارٍ مكتوب", () => {
    // الإنفاذُ (إلغاءٌ/استردادُ بطاقةٍ بلا إنسانٍ في الحلقة) **لم يُوسَّع**:
    // سندُ تفعيلِه جُمع من مسارِ النداء، وإن كان الويب هوكُ يَسبقُه فتلك
    // العيّنةُ لا تُغطّي سكّانَ هذا المسلك. فالويب هوكُ يَسِمُ ويُنبّهُ
    // ويُسجّلُ ما **كان** سيَحجبه، والتفعيلُ قرارُ المالك.
    assert.strictEqual(
        (code.match(/refunds\.voidOrRefundTampered\(/g) || []).length, 1,
        "توسيعُ الإنفاذِ قرارٌ ماليٌّ للمالكِ لا أثرٌ جانبيٌّ لإصلاحِ كشف");
    assert.ok(code.includes("TIER_B_WOULD_BLOCK"),
        "ولا بدَّ من أثرٍ يُقاسُ عليه القرارُ، وإلّا بقيت العيّنةُ ناقصة");
    // وطلبٌ حُجب لا يُقلَبُ مدفوعاً من الويب هوك (الحارسُ القائم).
    assert.ok(code.includes("cur.tamper_blocked === true"),
        "القلبُ يَلزمُ أن يَرفضَ المحجوز");
  });

  t("(٢١) ومسلكُ تمارا Tier A وحدَه — بسببٍ مكتوب", () => {
    const i = code.indexOf("async function _tamaraFlipPaid");
    const j = code.indexOf("\n}\n", i);
    const body = code.slice(i, j);
    assert.ok(body.includes("_verifyOrderPriceTierA("),
        "كان بلا أيِّ فحصِ مبلغ");
    assert.ok(!body.includes("voidOrRefundTampered"),
        "استردادُ تمارا نداءٌ آخرُ ببوّابةٍ أخرى — إنفاذُه قرارٌ مستقلّ");
    // والسببُ مكتوبٌ في الخامّ لا في رأسي.
    assert.ok(idx.includes("deps.gateway || moyasar"),
        "شرحُ اقتصارِ تمارا على Tier A اختفى");
  });

  t("(٢٢) ومجموعةُ المسالكِ إلى is_paid: true مشدودةٌ كاملةً", () => {
    // كما في `amounts.test.js`: تُقارَنُ **المجموعةُ كلُّها** لا وجودُ واحد،
    // فمسلكٌ سادسٌ يَسقطُ فيُراجَع بدلَ أن يَمضيَ بلا تحقّق.
    const names = [];
    const lines = code.split("\n");
    for (let n = 0; n < lines.length; n++) {
      if (!/is_paid: true/.test(lines[n])) continue;
      for (let k = n; k >= 0; k--) {
        const m = lines[k].match(/^(?:exports\.(\w+)|async function (\w+)|function (\w+))/);
        if (m) { names.push(m[1] || m[2] || m[3]); break; }
      }
    }
    assert.deepStrictEqual([...new Set(names)].sort(), [
      "_generateContractVisits", // زيارةُ عقدٍ: amount 0، مدفوعةٌ ضمنَ العقد
      "_tamaraFlipPaid", // ويب هوكُ تمارا ومسحُه — Tier A
      "generateSubscriptionVisits", // كالسابقِ، وبلا عميل
      "moyasarCapturePayment", // قبضُ إدارةٍ لتفويضٍ قائم
      "moyasarWebhook", // Tier A + Tier B
      "payContractWithWallet", // عقدٌ: planPrice من المستندِ لا من وسيط
      "payWithWallet", // تحقّقُه الخاصّ (سياسةٌ أخرى)
      "reconcileOrphanPayments", // المبلغُ من البوّابةِ لا من العميل
      "tabbyWebhook", // إرثيٌّ — لا جلسةَ تابي جديدة
      "verifyMoyasarPayment", // Tier A + Tier B
    ].sort());
  });

  t("(٢٣) ولا يَزعمُ الملفُّ أنّ Tier B مطفأة", () => {
    // **هذا الفحصُ يَقرأُ الخامَّ لا المُجرَّد**، والفرقُ هو الفحصُ نفسُه:
    // الزعمُ المنفيُّ **تعليقٌ**، فمسحُ أسطرِ التعليقِ يُعمي الفحصَ عمّا
    // وُضع له — وهو ما أثبتَه اختبارُ القضمِ أوّلَ مرّة (أعادَ الزعمَ فمرَّ
    // الفحصُ أخضرَ). ولذلك لا يُقتبَسُ اللفظُ كاملاً في شرحِ حذفِه.
    assert.ok(!idx.includes("مطفأة حتى تُثبِت السجلّات"),
        "الزعمُ قديمٌ: ENFORCE_PRICE_TIER_B = true بقرارِ المالك 2026-07-31");
    assert.ok(/ENFORCE_PRICE_TIER_B = true/.test(code),
        "فلو أُطفئت فعلاً فهذا الفحصُ هو ما يُراجَع");
    assert.ok(idx.includes("فُعّلت بقرار المالك (2026-07-31)"),
        "سندُ القرارِ في رأسِ الملفّ ما زال");

    // **والنطاقُ المستودعُ كلُّه، لا هذا الملفَّ (2026-10-07).** الزعمُ
    // صُحِّحَ هنا وبقيَ **نسخةٌ ثانيةٌ** في العميل: تعليقٌ في
    // `payment_summary_screen` يَقولُ «مطفأ فعليّاً ما دام
    // ENFORCE_PRICE_TIER_B=false خادميّاً» فوقَ الفرعِ الذي يَقرأُ
    // `blocked` — وهو الشيءُ الوحيدُ في العميلِ الذي يَمنعُ شاشةَ النجاحِ
    // فوقَ دفعةٍ أُلغيت. فمَن يَقرأُ الزعمَ يَحسبُ الفرعَ ميّتاً فيَحذفُه.
    // «حارسٌ ضيّقٌ وقاعدةٌ عامّة» للمرّةِ الثامنةِ هنا — فالقيمةُ **تُشتَقُّ**
    // من `index.js` وكلُّ ذاكرٍ للعلَمِ في أيِّ لغةٍ يَجبُ أن يُوافقَها.
    const flag = /const ENFORCE_PRICE_TIER_B = (true|false);/.exec(code);
    assert.ok(flag, "تعريفُ العلَمِ اختفى — لا قيمةَ تُشتَقّ");
    const stale = flag[1] === "true" ?
      /ENFORCE_PRICE_TIER_B\s*=?=?\s*false/ :
      /ENFORCE_PRICE_TIER_B\s*=?=?\s*true/;
    const scanned = [];
    const walk = (dir) => {
      for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
        const fp = path.join(dir, e.name);
        if (e.isDirectory()) {
          if (["node_modules", "build", ".git", ".dart_tool"].includes(e.name)) continue;
          walk(fp);
        } else if (/\.(dart|js|ts|tsx)$/.test(e.name) && !/\.test\./.test(e.name) &&
                   !/_test\.dart$/.test(e.name)) {
          const src = fs.readFileSync(fp, "utf8");
          if (!src.includes("ENFORCE_PRICE_TIER_B")) continue;
          scanned.push(fp);
          // الزعمُ المعاكسُ مسموحٌ **مُقتَبَساً** في سياقِ تصحيحِه (بين «…»)
          // ومنفيّاً. فالمقياسُ: كلُّ وِرْدٍ للصيغةِ المعاكسةِ يَجبُ أن
          // يَسبقَه `«` أقربُ من `»` — حجبٌ بالحالةِ لا بالبادئة، كما في
          // تعليقاتِ XML وJSX المسجَّلةِ هنا.
          for (const m of src.matchAll(new RegExp(stale.source, "g"))) {
            const o = src.lastIndexOf("«", m.index);
            const c = src.lastIndexOf("»", m.index);
            assert.ok(o > c,
                `${fp}: يَزعمُ أنّ العلَمَ ${flag[1] === "true" ? "مطفأ" : "مُفعَّل"} ` +
                "وقيمتُه في index.js تَقولُ خلافَ ذلك");
          }
        }
      }
    };
    walk(path.join(__dirname, "..", ".."));
    assert.ok(scanned.length >= 3,
        `انهارَ المسحُ: ${scanned.length} ملفّاً يَذكرُ العلَم`);
    // ومَن يَقرأُ `blocked` في العميلِ ما زال قائماً — فالزعمُ المُصحَّحُ
    // يَحرُسُ فرعاً حقيقيّاً لا تعليقاً معلّقاً في الهواء.
    const pay = fs.readFileSync(path.join(__dirname, "..", "..",
        "lib", "screens", "payment_summary_screen.dart"), "utf8");
    assert.ok(/\['blocked'\]\s*==\s*true/.test(pay),
        "فرعُ الحجبِ في العميلِ زالَ — فلا شيءَ يَمنعُ شاشةَ النجاحِ فوقَ " +
        "دفعةٍ أُلغيت، ويُراجَعُ هذا الفحصُ لا يُسكَت");
  });

  // ─────── وطلبُ المتجرِ كان بلا تحقّقٍ من أيِّ نوع ───────

  t("(٢٤) سلّةُ المتجرِ تُعادُ تسعيرُها خادميّاً — في المسارَين", () => {
    assert.strictEqual(
        (code.match(/_verifyStoreOrderPrice\(/g) || []).length, 3,
        "التعريفُ + نداءانِ (verify / webhook)");
    assert.ok(code.includes("col === \"store_orders\""),
        "الويب هوكُ يَلزمُ أن يُفرِّعَ على المتجر");
    assert.ok(code.includes("orderRef.parent.id === \"store_orders\""),
        "والنداءُ كذلك");
    // وإعادةُ التسعيرِ من `products` تَعيشُ في `pricing.js` لا هنا.
    assert.ok(code.includes("resolveStoreCartBase("),
        "تسعيرُ السلّةِ من products");
    assert.ok(!/async function resolveStoreCartBase/.test(code),
        "نسخةٌ ثانيةٌ في index.js — الوحدةُ هي موضعُها");
  });

  t("(٢٥) وسمٌ وتنبيهٌ لا رفض — قرارٌ مكتوب", () => {
    const i = code.indexOf("async function _verifyStoreOrderPrice");
    const j = code.indexOf("\n}\n", i);
    const body = code.slice(i, j);
    // لا رفضَ بحال: الرفضُ يَحجبُ دفعةَ عميلةٍ حقيقيّةٍ على خطأٍ في الضريبةِ
    // أو التقريب — وهو ما عضَّ مسارَ المحفظةِ مرّتَين هذه الجلسة.
    assert.ok(!body.includes("HttpsError"),
        "الرفضُ أُدخِل — القرارُ كان «وسمٌ وتنبيهٌ لا رفض»");
    assert.ok(!body.includes("throw "),
        "لا رميَ من هذا المسار");
    // والتعذّرُ يُنبّهُ ولا يَصمت (نظيرُ `price_unverifiable` في orders).
    assert.ok(body.includes("price_unverifiable"),
        "تعذّرُ التسعيرِ يَلزمُ أن يُوسَمَ ويُنبَّهَ عنه");
    // والسببُ باقٍ في الخامّ.
    assert.ok(idx.includes("وسمٌ وتنبيهٌ فقط، ولا رفضَ بحال"),
        "شرحُ قرارِ «لا رفض» اختفى");
  });

  t("(٢٦) وتفاوتُ التقريبِ مسموحٌ بريالٍ واحدٍ لا أكثر", () => {
    const i = code.indexOf("async function _verifyStoreOrderPrice");
    const j = code.indexOf("\n}\n", i);
    const body = code.slice(i, j);
    // **النهايةُ جزءٌ من النمط**: `"paid >= expected - 1"` سابقةٌ نصّيّةٌ
    // لـ`- 100`، فاختبارُ القضمِ مرَّ أخضرَ على هامشٍ أوسعَ مئةَ مرّة.
    assert.ok(body.includes("paid >= expected - 1) return;"),
        "هامشُ التقريبِ تغيّر — راجِعْ أثرَه على الدفعاتِ السليمة");
    // والمقارنةُ على الإجماليِّ شاملَ الضريبةِ كما يُنشئُ المتجرُ الطلب.
    assert.ok(body.includes("grossFromBaseRounded(base)"),
        "المتجرُ يُنشئُ total_amount بـgrossFromBaseRounded — فالمقارنةُ نظيرتُها");
    // **والمسحُ يُغطّي المجموعةَ الآن — وهذا هو الفحصُ الذي دعا نصُّه إلى
    // مراجعتِه.** كان هنا تثبيتُ تعليقٍ يَقول «`opsHealthSweep` لا يَمسحُ
    // `store_orders`» ويُحذّرُ من الاعتمادِ عليه، ثمّ سطرٌ يَقول «لو وُسّع
    // المسحُ فهذا الفحصُ هو ما يُراجَع». وُسّع، فهذا هو. والتوسيعُ لم يكن
    // ليُجدي قبلَ ترتيبِ العلمِ: `ops_alerted_mismatch: true` كان يُضبَطُ
    // سلفاً فيُسكِتُ `alertBatch` عن كلِّ مستند.
    assert.ok(!idx.includes("لا يَمسحُ `store_orders`"),
        "عادَ تحذيرٌ صارَ كاذباً — المسحُ يُغطّي المجموعةَ الآن");
    assert.ok(
        /for \(const coll of \["orders", "store_orders"\]\)/.test(code),
        "حلقةُ المجموعتَين في مكنسةِ مراجعةِ السعرِ اختفت");
  });

  // ─────────── المدّةُ حاضرةٌ في كلِّ مُنشئٍ لطلب ───────────
  t("(٢٧) كلُّ حِملٍ يُنشئُ مستندَ orders يكتبُ hours_contracted", () => {
    // هذا ما يُجعلُ توسيعَ (٨) بلا إيجابيّةٍ كاذبة: فرعُ «بلا service_meta»
    // يُنبّهُ `price_unverifiable` متى تعذّرَ الحساب، فلو وُجد شكلٌ شريفٌ
    // بلا مدّةٍ لَأَنبّهَ على كلِّ طلبٍ منه. المسحُ **مُشتَقٌّ**: كلُّ حِملٍ
    // مُوازَنِ الأقواسِ يَحمل `client_id` و`status` معاً.
    const lits = (src, reClient, reStatus) => {
      const out = [];
      for (let i = 0; i < src.length; i++) {
        if (src[i] !== "{") continue;
        let d = 0; let k = i;
        for (; k < src.length; k++) {
          if (src[k] === "{") d++;
          else if (src[k] === "}" && --d === 0) break;
        }
        if (k >= src.length) continue;
        const lit = src.slice(i, k + 1);
        if (lit.length < 6000 && reClient.test(lit) && reStatus.test(lit)) {
          out.push({at: src.slice(0, i).split("\n").length, lit});
        }
      }
      return out;
    };
    const bad = [];
    let scanned = 0;
    const idxSrc = fs.readFileSync(
        path.join(__dirname, "..", "index.js"), "utf8");
    for (const h of lits(idxSrc, /\bclient_id:/, /\bstatus:\s*"/)) {
      scanned++;
      if (!h.lit.includes("hours_contracted")) bad.push(`index.js:${h.at}`);
    }
    const libDir = path.join(__dirname, "..", "..", "lib");
    const walk = (dir) => fs.readdirSync(dir, {withFileTypes: true})
        .flatMap((e) => e.isDirectory() ? walk(path.join(dir, e.name)) :
          (e.name.endsWith(".dart") ? [path.join(dir, e.name)] : []));
    for (const f of walk(libDir)) {
      const src = fs.readFileSync(f, "utf8");
      const rel = path.relative(path.join(__dirname, "..", ".."), f);
      // `store_orders` مجموعةٌ أخرى بشكلٍ آخر ومُحقِّقٍ آخر
      // (`_verifyStoreOrderPrice`) — استثناءٌ مُسمّى، ويُثبَتُ أنّه عنها فعلاً.
      if (rel.endsWith("store_service.dart")) {
        assert.ok(src.includes("store_orders") && !/collection\('orders'\)/.test(src),
            "استثناءُ store_service صارَ كاذباً — صار يُنشئُ في orders");
        continue;
      }
      for (const h of lits(src, /'client_id':/, /'status':/)) {
        scanned++;
        if (!h.lit.includes("hours_contracted")) bad.push(`${rel}:${h.at}`);
      }
    }
    // الأرضيّةُ نزلت من ١٢ إلى ١١ في 2026-10-08: جُمِعت نسختا حِملِ إنشاءِ
    // الطلبِ في العميلِ وحُذفت نسخةٌ ثالثةٌ ميّتةٌ من `checkout_screen`
    // (`order_payload_single_site_test`)، فهبطَ عددُ الأحمالِ بواحد.
    // **وهذه الأرضيّةُ هي ما أمسكَ ذلك** — وهي كذلك الدرسُ: حارسٌ في
    // `functions/test` يَمسحُ `lib/` أيضاً، فـ«لم أمَسَّ `functions/`» لا
    // تَعني أنّ مجموعتَها غيرُ متأثّرة.
    assert.ok(scanned >= 11, `المسحُ وجدَ ${scanned} حِملاً فقط — فحصٌ أجوف`);
    assert.deepStrictEqual(bad, [],
        "حِملٌ يُنشئُ طلباً بلا مدّة — فرعُ «بلا service_meta» سيُنبّهُ عليه:\n" +
        bad.map((x) => "  - " + x).join("\n"));
  });

  t("(٢٨) والفرعانِ المُنادِيانِ يَسِمانِ ولا يَرفضانِ", () => {
    // توسيعُ (٨) آمنٌ **لأنّ** مُخرَجَه وسمٌ وتنبيه. فلو صارَ يَرفعُ
    // `HttpsError` يوماً فالتوسيعُ هو ما يُراجَع.
    const code = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8")
        .split("\n").filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    let n = 0;
    for (let i = code.indexOf("priceVerify.isPriceableKind("); i >= 0;
      i = code.indexOf("priceVerify.isPriceableKind(", i + 1)) {
      n++;
      // **بموازنةِ الأقواسِ لا بشريحةٍ ثابتة**: شريحةُ ١٦٠٠ محرفاً تَتجاوزُ
      // الفرعَ إلى شفرةٍ بعدَه فيها `throw` — فخُّ الحدِّ غيرِ المُوازَن،
      // وقد عضَّ أوّلَ تشغيلٍ لهذا الفحصِ نفسِه.
      const open = code.indexOf("{", code.indexOf(")", i));
      let d = 0; let k = open;
      for (; k < code.length; k++) {
        if (code[k] === "{") d++;
        else if (code[k] === "}" && --d === 0) break;
      }
      const body = code.slice(open, k + 1);
      assert.ok(body.includes("price_unverifiable: true"),
          `فرعُ isPriceableKind #${n} لا يَسِم`);
      assert.ok(body.includes("ops_alerted_unverifiable"),
          `فرعُ isPriceableKind #${n} لا يُنبّه`);
      assert.ok(!/throw new HttpsError/.test(body),
          `فرعُ isPriceableKind #${n} صارَ يَرفضُ دفعاً — راجِعْ توسيعَ (٨)`);
    }
    assert.strictEqual(n, 2, "المُنادِيانِ (ميسر والمحفظة)");
  });

  // ─────────── قاعدةُ الوحدات ───────────
  t("(١٥) الوحدةُ لا تُهيّئُ Firestore — تَستقبلُ db", () => {
    const raw = fs.readFileSync(
        path.join(__dirname, "..", "price_verify.js"), "utf8");
    const code = raw.split("\n")
        .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
    for (const bad of ["getFirestore(", "getApp(", "initializeApp("]) {
      assert.ok(!code.includes(bad), bad);
    }
    // ولا يُفرّغُ التجريدُ الفحص: الملفُّ يَذكرُ القاعدةَ في ترويستِه.
    assert.ok(raw.includes("getFirestore()"),
        "الترويسةُ تَنصُّ القاعدةَ — فلو غابت فالتجريدُ حَجبَ شيئاً");
  });

  console.log(`\n${ok} ok, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
