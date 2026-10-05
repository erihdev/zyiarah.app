"use strict";

// أيُّ حقلٍ هو «المبلغ» — تشغيل: node test/amounts.test.js (ضمن npm test).
//
// ═══ ما يحرسه ═══
//
// سؤالان على ستّة مواضع، وكان كلٌّ يكتب ترتيبه بيده:
//
//   (أ) كم كان يجب أن يُدفَع؟   moyasarWebhook، tabbyWebhook، reconcileOrphanPayments
//   (ب) كم نستردّ؟             _fullRefundAmount، moyasarRefundPayment،
//                              _autoResolveUnfulfilledPaidOrder
//
// **والاسترداد كان متّفقاً في مواضعه الثلاثة** — فحصتُه أوّلاً لأنه الأخطر،
// فوجدتُه سليماً. والانحراف كان في فحص التلاعب:
//
//   moyasarWebhook / tabbyWebhook:  final_amount أوّلاً
//   reconcileOrphanPayments:        **amount أوّلاً**
//
// ومقارنةُ المكنسة `paidH >= expectedH` (لا تساوياً) تجعل الأثر باتجاهٍ واحد:
//
//   تعديلٌ صاعد (رسوم توصيل): المتوقَّع أقلّ ⇒ الدفعة تغطّيه ⇒ يُستردّ الطلب.
//   تعديلٌ هابط (حذف صنف، خصم): المتوقَّع أكبر ⇒ «amount too low» ⇒ **لا يُستردّ**
//                             طلبٌ دفع العميل ثمنه، والمكنسة هي شبكة أمانه الأخيرة.
//
// **وهو كامنٌ لا حيّ، والتمييز جزءٌ من الصدق:** لا شيء في المستودع يكتب
// `final_amount` (١٢ قراءةً في index.js وصفر كتابة)، وطلب المتجر يُنشأ
// بـ`amount == total_amount`. فتحلّ المواضع كلها إلى القيمة نفسها اليوم، ويصير
// العطل حيّاً متى ضُبط `final_amount` من خارج التطبيق — وهو ما تتوقّعه الشفرة
// («بعد تعديل الإدارة») وتعرضه شاشة طلبات المتجر: «المعتمد: X (السلة: Y)».
// فالإصلاح وقائيّ.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {FIELD_ORDER, expectedAmount, refundAmount, toHalalas} = require("../amounts");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  fn();
  console.log("  ok -", name);
  passed++;
}

t("الترتيب: المعتمد إدارياً يسبق سعر السلة دائماً", () => {
  // «وإلا رُفضت دفعة حقيقية عند تعديل السعر» — تعليق moyasarWebhook.
  assert.strictEqual(expectedAmount({amount: 150, total_amount: 150, final_amount: 100}), 100);
  assert.strictEqual(refundAmount({amount: 150, total_amount: 150, final_amount: 100}), 100);
  assert.deepStrictEqual(FIELD_ORDER,
      ["final_amount", "total_amount", "planPrice", "amount"]);
});

t("**الانحراف الذي أُصلح**: amount أوّلاً كان يعطي قيمةً أخرى", () => {
  // ترتيب reconcileOrphanPayments القديم، منقولاً كي يُقاس عليه الفرق.
  const old = (d) => Number(d.amount ?? d.final_amount ?? d.total_amount ?? d.planPrice ?? 0);
  const adjustedDown = {amount: 150, total_amount: 150, final_amount: 100};
  assert.strictEqual(old(adjustedDown), 150, "القديم: سعر السلة");
  assert.strictEqual(expectedAmount(adjustedDown), 100, "الجديد: المعتمد");

  // والأثر: المكنسة تقارن `paidH >= expectedH`. العميل دفع المعتمد (100).
  const paidH = toHalalas(100);
  assert.ok(paidH >= toHalalas(expectedAmount(adjustedDown)), "بالجديد: يُستردّ");
  assert.ok(!(paidH >= toHalalas(old(adjustedDown))),
      "بالقديم: «amount too low» — طلبٌ مدفوع لا يُستردّ");
});

t("التعديل الصاعد كان يمرّ في الحالتين — فالأثر باتجاهٍ واحد", () => {
  // رسوم توصيل: المعتمد أكبر من السلة. العميل دفع المعتمد.
  const old = (d) => Number(d.amount ?? d.final_amount ?? d.total_amount ?? d.planPrice ?? 0);
  const up = {amount: 100, total_amount: 100, final_amount: 150};
  const paidH = toHalalas(150);
  assert.ok(paidH >= toHalalas(old(up)), "القديم: يمرّ (المتوقَّع 100 ≤ المدفوع)");
  assert.ok(paidH >= toHalalas(expectedAmount(up)), "الجديد: يمرّ أيضاً");
});

t("`??` لا `||`: صفرٌ صريح قيمةٌ لا غياب", () => {
  // `final_amount: 0` قرارٌ (طلبٌ مجّاني، أو تسويةٌ كاملة) لا حقلٌ غائب.
  // و`||` كان يتخطّاه إلى حقلٍ آخر فيُطالب العميل بمبلغٍ لا يستحقّ.
  assert.strictEqual(expectedAmount({final_amount: 0, amount: 99}), 0);
  assert.strictEqual(refundAmount({final_amount: 0, amount: 99}), 0);
  // والغياب الحقيقي يتخطّى.
  assert.strictEqual(expectedAmount({final_amount: null, amount: 99}), 99);
  assert.strictEqual(expectedAmount({final_amount: undefined, amount: 99}), 99);
});

t("التدرّج كاملاً: كل حقلٍ يُستعمل عند غياب ما قبله", () => {
  assert.strictEqual(refundAmount({total_amount: 80, planPrice: 70, amount: 60}), 80);
  assert.strictEqual(refundAmount({planPrice: 70, amount: 60}), 70, "باقة");
  assert.strictEqual(refundAmount({amount: 60}), 60);
  assert.strictEqual(refundAmount({}), 0, "بلا حقول = صفر لا NaN");
  assert.strictEqual(refundAmount(null), 0);
  assert.strictEqual(refundAmount(undefined), 0);
});

t("القيم النصّية تُحوَّل، والفاسدة تصير صفراً لا NaN", () => {
  // Firestore قد تُسلّم الحقل نصّاً. وNaN في مقارنةٍ ماليّة يُنتج false دائماً،
  // فيصير «المبلغ غير كافٍ» بلا سبب مفهوم.
  assert.strictEqual(refundAmount({final_amount: "230.5"}), 230.5);
  assert.strictEqual(refundAmount({final_amount: "abc"}), 0);
  assert.ok(!Number.isNaN(refundAmount({final_amount: "abc"})));
});

t("amountField يُدرَج بعد المعتمدة لا قبلها", () => {
  // moyasarWebhook يسمّي الحقل الأساسي لمجموعته (طلبات=amount، متجر=total_amount).
  assert.strictEqual(expectedAmount({final_amount: 100, amount: 150}, "amount"), 100,
      "المعتمد يسبق الحقل المُسمّى");
  assert.strictEqual(expectedAmount({quotePrice: 55}, "quotePrice"), 55,
      "حقلٌ خارج التدرّج يُقرأ حين يُسمّى");
  assert.strictEqual(expectedAmount({quotePrice: 55}), 0,
      "ولا يُقرأ حين لا يُسمّى");
});

t("toHalalas يقرّب ولا يقطع — القطع يبخس هللةً في كل مقارنة", () => {
  assert.strictEqual(toHalalas(230.5), 23050);
  assert.strictEqual(toHalalas(11.115), 1112, "تقريب لا قطع (1111 بالقطع)");
  assert.strictEqual(toHalalas(0), 0);
});

t("السؤالان مفصولان بالاسم — لا يُغيَّر أحدهما ضمناً", () => {
  // يتّفقان اليوم، وليسا نفس السؤال: الأوّل يُقارَن بما وصل من البوابة،
  // والثاني يُرسَل إليها. فصلُهما يجعل تغيير أحدهما قراراً صريحاً.
  const src = fs.readFileSync(path.join(__dirname, "..", "amounts.js"), "utf8");
  assert.ok(/function expectedAmount\(/.test(src));
  assert.ok(/function refundAmount\(/.test(src));
});

t("**لا تدرّج مكتوب إنلاين خارج الوحدة** — الحارس الذي يمنع عودة الانحراف", () => {
  // بلا هذا الحدّ يُكتب ترتيبٌ سابعٌ بيد في أوّل ميزةٍ قادمة — كما كُتب ستّ
  // مرّات قبله — ولا يسقط شيء. ومبالغ **العرض** مستثناة بقصد: سؤالها «ما
  // نُظهره»، وتستعمل `||` فيتخطّى الصفر، وهو مقبولٌ في عرضٍ لا مال.
  const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  // **تُجرَّد أسطرُ التعليق أوّلاً.** `_verifyOrderPriceTierA` تشرح الثغرةَ
  // باقتباس التدرّج نفسِه، فسقط هذا الحارسُ على توثيقِ غيره — وهو العطلُ
  // المتكرّر هنا. والمضادّة أدناه تمنع أن يُفرّغ التجريدُ الفحصَ.
  const code = src.split("\n")
      .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join("\n");
  // تدرّجٌ ماليّ = حقلان من التدرّج أو أكثر متسلسلان بـ?? أو ||
  const chains = (code.match(
      /(?:final_amount|total_amount|planPrice|\bamount)\s*(?:\?\?|\|\|)\s*[\w.[\]"']+\s*(?:\?\?|\|\|)\s*[\w.[\]"']+/g) || [])
      .map((c) => c.trim()).sort();
  // المجموعة كاملةً تُقارَن، لا بالاحتواء: فأي سلسلةٍ جديدة تسقط الفحص، وتغيُّر
  // سطر العرض يسقطه أيضاً فيُراجَع بوعي. (والنمط ليس فارغاً — يجد هاتين.)
  assert.deepStrictEqual(
      chains,
      [
        "total_amount ?? o.final_amount ?? \"",
        "total_amount || after.final_amount || 0",
      ].sort(),
      "تدرّجُ حقولٍ ماليّ مكتوب إنلاين — استعمل expectedAmount أو refundAmount.\n" +
      "المسموح سطرا **عرضٍ** فقط (بريد الإدارة وصفّ طلب المتجر). الموجود:\n" +
      chains.map((c) => "  - " + c).join("\n"));
  // المضادّة: التدرّجُ القانونيُّ ما زال مذكوراً في الخامّ (توثيقُ الثغرة)،
  // فلو غابَ فالتجريدُ حَجبَ أكثرَ من التعليقات ولم يَبقَ للفحصِ ما يجده.
  assert.ok(/final_amount \?\? total_amount \?\? planPrice/.test(src),
      "اختفى اقتباسُ التدرّجِ من التوثيق — راجِعْ ما جرّده الفحص");
  assert.ok(code.length < src.length, "التجريدُ لم يُزِل شيئاً — نمطٌ معطوب");
});

console.log(`\namounts tests: ${passed} passed`);
