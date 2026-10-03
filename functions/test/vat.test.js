"use strict";

// فحص خاصيّة لا أمثلة: يثبت أن دوال vat.js تُعيد **نفس** ما كانت تُعيده الصيغة
// الحرفية المكتوبة يدوياً في index.js قبل التوحيد، على نطاق أسعار واقعي كامل.
//
// الغرض ليس التأكّد أن ٠.١٥ تساوي ٠.١٥، بل إثبات أن `1 + 0.15` و`1.15` واحدٌ
// في IEEE754 فلا يتسلّل فرقٌ في آخر بتة يُقلب حدَّ تقريب فيغيّر قرشاً في فاتورة.
// والقرش هنا ليس تجميلاً: verifyMoyasarPayment يقارن المدفوع بالمتوقَّع بسماحية
// `> 0.01`، فانحرافٌ على الحدّ يعني رفض دفعٍ سليم أو قبول دفعٍ ناقص.

const assert = require("assert");
const {VAT_RATE, VAT_MULTIPLIER, grossFromBaseRounded, grossFromBase} =
  require("../vat");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  fn();
  console.log(`  ok - ${name}`);
  passed++;
}

t("النسبة ١٥٪ والمعامل ١.١٥ — والمعامل يطابق الحرفيّ بتةً ببتة", () => {
  assert.strictEqual(VAT_RATE, 0.15);
  assert.strictEqual(VAT_MULTIPLIER, 1.15);
  // ليس تحصيلَ حاصل: 0.15 و1.15 غير قابلين للتمثيل تماماً، والمطلوب أن يكون
  // ناتج الجمع هو نفس المضاعف الحرفيّ المستعمل قبل التوحيد.
  assert.strictEqual(1 + VAT_RATE, 1.15);
});

t("grossFromBaseRounded يطابق Math.round(base*1.15*surge*100)/100", () => {
  for (let base = 0; base <= 20000; base += 1) {
    for (const surge of [1, 1.1, 1.25, 1.5, 2]) {
      const legacy = Math.round(base * 1.15 * surge * 100) / 100;
      assert.strictEqual(
          grossFromBaseRounded(base, surge), legacy,
          `انحراف عند base=${base} surge=${surge}`);
    }
  }
});

t("grossFromBaseRounded بلا ذروة يطابق Math.round(base*1.15*100)/100", () => {
  for (let base = 0; base <= 20000; base += 1) {
    assert.strictEqual(
        grossFromBaseRounded(base), Math.round(base * 1.15 * 100) / 100,
        `انحراف عند base=${base}`);
  }
});

t("grossFromBase يطابق base*1.15 الخام", () => {
  for (let base = 0; base <= 20000; base += 1) {
    assert.strictEqual(grossFromBase(base), base * 1.15,
        `انحراف عند base=${base}`);
  }
});

t("الكسور العشرية أيضاً — الأسعار ليست أعداداً صحيحة دائماً", () => {
  for (let cents = 0; cents <= 200000; cents += 7) {
    const base = cents / 100;
    assert.strictEqual(
        grossFromBaseRounded(base), Math.round(base * 1.15 * 100) / 100,
        `انحراف عند base=${base}`);
  }
});

t("index.js لم تبقَ فيه نسبة مكتوبة يدوياً", () => {
  const src = require("fs").readFileSync(
      require("path").join(__dirname, "..", "index.js"), "utf8");
  const bare = src.split("\n")
      .map((l, i) => [i + 1, l.indexOf("//") === -1 ? l : l.slice(0, l.indexOf("//"))])
      .filter(([, l]) => /\b1\.15\b|\b0\.15\b/.test(l));
  assert.deepStrictEqual(
      bare, [],
      "النسبة عادت مكتوبة يدوياً في index.js — استخدم vat.js: " +
      bare.map(([n]) => n).join(", "));
});

console.log(`${passed} vat tests passed.`);
