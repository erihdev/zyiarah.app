// حارسٌ دائم: **كلُّ مبلغِ ريالٍ في رسالةٍ تَقرؤها العميلةُ بخانتَين.**
//
// القاعدةُ مقرَّرةٌ في العميلِ (`money_format_test` و`formatSar`: «الرقاقةُ
// والملخّصُ يَعرضانِ نفسَ الرقمِ الذي يُدفَع») **ونطاقُها كان `lib/` واللوحةَ
// — لا `functions/`**. فمسحٌ لكلِّ `queuePush` (٦٤ موضعاً) أعطى ستَّ رسائلَ
// عميليّةٍ تَحملُ ريالاً، **أربعٌ بخانتَين واثنتانِ خامّتان**:
//
//  • `refund_engine.js` — «تعذّر إيجاد فريق لطلبكِ #X فأُعيد ${amount} ر.س»،
//    و`amount` من `refundAmount` أي `grossFromBaseRounded`
//    (`Math.round(x*100)/100`) فالقيمُ بكسرٍ واحدٍ هي الحالةُ المعتادة:
//    «أُعيد 172.5 ر.س» — **بجوارِ أختِها في الملفِّ نفسِه** التي تَقول
//    «172.50». حيٌّ.
//  • `rewards.js` — `${REFERRER_REWARD}`، وهو عددٌ صحيحٌ اليومَ فيُطبَعُ «50»:
//    **وقائيٌّ لا حيّ، ويُقالُ كذلك**.
//
// **والمواضعُ الإداريّةُ مُستثناةٌ بقصد**: الجمهورُ المالكُ، وصيغةُ عرضِه
// قرارٌ قائمٌ لا عطل — ولمسُ شفرةٍ سليمةٍ بلا خللٍ خلفَها مخاطرةٌ بلا مقابل
// (قرارٌ مسجَّلٌ في هذا المستودع). فالفحصُ يَعُدُّها ولا يُفشِلُها، ويَسقطُ
// لو **زادت** — فموضعٌ إداريٌّ جديدٌ يُراجَع.
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const DIR = path.join(__dirname, "..");

/**
 * يُجرِّدُ التعليقاتِ قبلَ المسح — **وقائيٌّ لا حاملٌ، ويُقالُ كذلك**:
 * اختبارُ قضمٍ يُجوِّفُه فلا يَسقطُ شيءٌ اليوم. ويَبقى لأنّ «الحارسَ يَسقطُ
 * على توثيقِه» سُجِّلَ في هذا المستودعِ اثنتَي عشرةَ مرّةً في الاتّجاهِ
 * المُعاكس: تعليقٌ يَذكرُ `${x} ر.س` بجوارِ `queuePush` يُدخِلُ موضعاً وهميّاً
 * في المسح.
 */
function strip(src) {
  const noBlock = src.replace(/\/\*[\s\S]*?\*\//g, " ");
  return noBlock
      .split("\n")
      .map((l) => (l.trimStart().startsWith("//") ? "" : l))
      .join("\n");
}

/** كتلةُ النداءِ بموازنةِ الأقواسِ — لا نافذةَ عدِّ أحرف. */
function callBlock(src, start) {
  const open = src.indexOf("(", start);
  let depth = 1;
  let i = open + 1;
  while (i < src.length && depth > 0) {
    if (src[i] === "(") depth++;
    if (src[i] === ")") depth--;
    i++;
  }
  return src.slice(start, i);
}

/** كلُّ «<تعبير> ر.س» في رسائلِ `queuePush`، بجمهورِها وصيغتِها. */
function riyalTexts() {
  const rows = [];
  for (const f of fs.readdirSync(DIR).filter((x) => x.endsWith(".js"))) {
    if (f.includes("eslint")) continue;
    const src = strip(fs.readFileSync(path.join(DIR, f), "utf8"));
    const re = /queuePush\(/g;
    let m;
    while ((m = re.exec(src)) !== null) {
      const blk = callBlock(src, m.index);
      const admin = blk.slice(0, 40).includes("ADMIN_BROADCAST");
      const inner = /\$\{([^}]*)\}\s*ر\.س/g;
      let im;
      while ((im = inner.exec(blk)) !== null) {
        const expr = im[1].trim();
        rows.push({
          file: f,
          admin,
          formatted: /toFixed|formatSar|toLocale/.test(expr),
          expr,
        });
      }
    }
  }
  return rows;
}

let pass = 0;
let fail = 0;
function check(name, fn) {
  try {
    fn();
    pass++;
    console.log(`ok - ${name}`);
  } catch (e) {
    fail++;
    console.error(`NOT OK - ${name}\n  ${e.message}`);
  }
}

const rows = riyalTexts();

check("المسحُ أصابَ فعلاً — لا فحصٌ أجوف", () => {
  assert.ok(rows.length >= 6,
      `لم تُستخرَج رسائلُ الريال (${rows.length}) — اشتقاقٌ فاشل`);
  assert.ok(rows.some((r) => !r.admin), "لا رسالةَ عميلةٍ في المُستخرَج");
  assert.ok(rows.some((r) => r.admin), "لا رسالةَ إدارةٍ في المُستخرَج");
});

check("كلُّ مبلغٍ في رسالةِ العميلةِ بخانتَين", () => {
  const raw = rows.filter((r) => !r.admin && !r.formatted);
  assert.strictEqual(raw.length, 0,
      "مبلغٌ خامٌّ في رسالةِ العميلة:\n  " +
      raw.map((r) => `${r.file}: \${${r.expr}}`).join("\n  "));
});

check("ومواضعُ الإدارةِ معدودةٌ — زيادةٌ تُراجَع", () => {
  // الجمهورُ المالكُ وصيغتُه قرارٌ قائم؛ العددُ مشدودٌ كي لا يَنمو بصمت.
  const adminRaw = rows.filter((r) => r.admin && !r.formatted).length;
  assert.strictEqual(adminRaw, 6,
      `مواضعُ الإدارةِ الخامّةُ ${adminRaw} لا 6 — راجِعْ الصيغةَ بوعي`);
});

check("والتعليلُ ما زال قائماً: التقريبُ إلى خانتَين يُنتجُ كسراً واحداً", () => {
  // `grossFromBaseRounded` هو مصدرُ `amount`، فلو صارَ عدداً صحيحاً دائماً
  // فالتعليلُ يُراجَعُ لا يُسكَت.
  // **وبجسمِ `grossFromBaseRounded` بعينِه**: صياغةٌ أولى مسحت الملفَّ كلَّه،
  // وفيه مُقرِّبٌ آخرُ بالصيغةِ نفسِها — فمرَّ اختبارُ قضمٍ بدّلَ هذا المُقرِّبَ
  // **أخضرَ** («موضعٌ آخرُ يُرضي الفحصَ»، ثالثُ وقوعٍ لهذا في جلسةٍ واحدة).
  const vat = fs.readFileSync(path.join(DIR, "vat.js"), "utf8");
  const at = vat.indexOf("function grossFromBaseRounded");
  assert.ok(at > -1, "زالت `grossFromBaseRounded` — راجِعْ التعليل");
  const body = vat.slice(at, vat.indexOf("\n}", at));
  assert.ok(/Math\.round\([^)]*\* 100\) \/ 100/.test(body),
      "تغيّرَ تقريبُ الإجمالي — راجِعْ تعليلَ الخانتَين");
});

check("ومضادّةٌ: شرحُ العطلِ ما زال في الخامّ", () => {
  const raw = fs.readFileSync(__filename, "utf8");
  assert.ok(raw.includes("${amount}"),
      "زالَ شرحُ الصيغةِ الخامّةِ من ترويسةِ الحارس");
});

console.log(`\npush money format: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exitCode = 1;
