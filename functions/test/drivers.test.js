"use strict";
// أهلية السائق للإسناد — تشغيل: node test/drivers.test.js (ضمن npm test).
//
// ═══ ما يحرسه هذا الملف ═══
//
// القاعدة (H3): لا يُسنَد طلب لمستند `drivers/{id}` إلا إذا كان `id` حسابَ دخولٍ
// حقيقياً بدور سائق في `users/{id}`. سببُها أن معرّف مستند السائق **قد لا يكون
// uid**: لوحة الويب كانت تُنشئه بـ`addDoc` بمعرّف عشوائي بلا حساب Auth وبلا
// `users/{uid}` — والمستندات القديمة باقية. وإسناد طلبٍ لأحدها يُخفيه عن
// الجميع، لأن القواعد وتطبيق السائق يربطان الرؤية بـ`auth.uid == driver_id`
// (`firestore.rules:171`). فالطلب مدفوع، ويقول للعميل «تم تعيين سائق»، ولا أحد
// يراه أبداً.
//
// وكانت القاعدة **مكتوبةً مرّتين ومفروضةً في موضعين من أربعة**:
//
//   _findFreeDriverForSlot    (المُسنِد الآلي)      ✓ تفرضها
//   getHourlyAvailability     (عدّاد السعة)         ✓ تفرضها — نسخةً ثانية
//   approveAndAssignOrder     (إسناد الأدمن يدوياً)  ✗ النشاط وحده
//   rescheduleAssignedOrder   (إعادة الإسناد)       ✗ النشاط وحده
//
// فالمسار الآلي محصَّن والمسار **الذي يستعمله الأدمن بيده** مكشوف. وهذا ما
// يفعله التكرار: تُضاف القاعدة حيث ظهر العَرَض ويُنسى الموضع الآخر.
//
// وتباعُد الأوّلَين له حادثةٌ موثَّقة: عدّادٌ يفوق ما يقبله المُسنِد يُظهر يوماً
// «متاحاً» فيدفع العميل ثم لا يجد المُسنِد سائقاً مؤهَّلاً، فيعلق الطلب المدفوع
// حتى الاسترداد الآلي.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  hasDriverRole, isActiveDriverDoc, isAssignableDriver,
  assignabilityProblem, chunk,
} = require("../drivers");

const SRC = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

let passed = 0;
/**
 * @param {string} name اسم الفحص
 * @param {Function} fn جسم الفحص
 */
function t(name, fn) {
  fn();
  passed++;
  console.log("  ok -", name);
}

// ── القاعدة نفسها ───────────────────────────────────────────────────────

t("الدور: staff_role يسبق role (نفس ترتيب القواعد و_assertAdmin)", () => {
  assert.strictEqual(hasDriverRole({staff_role: "driver"}), true);
  assert.strictEqual(hasDriverRole({role: "driver"}), true, "احتياط الحسابات القديمة");
  // الكادر يحمل role:'admin' + staff_role:'<الدور الحقيقي>' — فالأسبقية تهمّ
  // في الاتجاهين: كادرٌ إداري لا يصير سائقاً، وسائقٌ مسجَّل كذلك لا يُستبعَد.
  assert.strictEqual(hasDriverRole({role: "admin", staff_role: "driver"}), true);
  assert.strictEqual(hasDriverRole({role: "driver", staff_role: "accountant_admin"}), false,
      "staff_role هو الحاكم — لا يُقرأ role إلا عند غيابه");
});

t("الدور: كل ما ليس سائقاً مستبعَد — ومنه الغياب وكادر التنظيف", () => {
  assert.strictEqual(hasDriverRole(null), false, "لا users/{id} = مسودّة addDoc القديمة");
  assert.strictEqual(hasDriverRole(undefined), false);
  assert.strictEqual(hasDriverRole({}), false, "مستند بلا دور");
  assert.strictEqual(hasDriverRole({role: "client"}), false);
  assert.strictEqual(hasDriverRole({role: "admin"}), false);
  // اللوحة تكتب users/{uid}.role = staffType، وقد يكون كادر تنظيف لا سائق
  // توصيل: له حساب يعمل، ولا تظهر له الطلبات المُسنَدة.
  assert.strictEqual(hasDriverRole({role: "cleaner"}), false);
  assert.strictEqual(hasDriverRole({role: "Driver"}), false, "حسّاس لحالة الأحرف كالقواعد");
});

t("النشاط: الغياب يعني نشطاً (!== false لا === true)", () => {
  // المستندات القديمة بلا الحقل — واعتبارها غير نشطة كان يُفرِغ الأسطول.
  assert.strictEqual(isActiveDriverDoc({}), true);
  assert.strictEqual(isActiveDriverDoc({is_active: true}), true);
  assert.strictEqual(isActiveDriverDoc({is_active: false}), false);
  assert.strictEqual(isActiveDriverDoc(null), false, "لا مستند = لا سائق");
  // "false" نصّاً ليست false — نثبّتها كي لا يُسكِت تغييرٌ الفرق صامتاً.
  assert.strictEqual(isActiveDriverDoc({is_active: "false"}), true);
});

t("القاعدة تجمع النصفين: يلزم النشاط **و** حساب الدخول", () => {
  assert.strictEqual(isAssignableDriver({}, {role: "driver"}), true);
  assert.strictEqual(isAssignableDriver({is_active: false}, {role: "driver"}), false,
      "موقوف ولو كان حسابه سائقاً");
  assert.strictEqual(isAssignableDriver({}, null), false,
      "نشطٌ بلا حساب دخول — هذه هي مسودّة addDoc التي تُخفي الطلب");
  assert.strictEqual(isAssignableDriver(null, {role: "driver"}), false);
  assert.strictEqual(isAssignableDriver(null, null), false);
});

t("سبب الرفض يقول للأدمن ما العمل — لا رفضاً مبهماً", () => {
  assert.strictEqual(assignabilityProblem({}, {role: "driver"}), null, "مؤهَّل = لا مشكلة");
  assert.match(assignabilityProblem(null, null), /غير موجود/);
  assert.match(assignabilityProblem({is_active: false}, {role: "driver"}), /غير نشط/);
  // المسار اليدوي يحتاج أن يميّز الحالتين: مستندٌ بلا حساب ≠ حسابٌ بدور آخر،
  // والعلاج مختلف (أنشئ حساباً / صحّح التصنيف).
  const noAccount = assignabilityProblem({}, null);
  assert.match(noAccount, /بلا حساب دخول/);
  assert.match(noAccount, /إضافة سائق/, "يسمّي الإجراء");
  const wrongRole = assignabilityProblem({}, {role: "cleaner"});
  assert.match(wrongRole, /ليس سائق توصيل/);
  assert.notStrictEqual(noAccount, wrongRole, "سببان مختلفان لعلاجين مختلفين");
});

t("chunk يقسّم ولا يفقد عنصراً، ويحتمل الفراغ", () => {
  assert.deepStrictEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.deepStrictEqual(chunk([1, 2], 5), [[1, 2]], "أقل من القطعة = قطعة واحدة");
  assert.deepStrictEqual(chunk([], 3), [], "الفراغ لا يُنتج قطعةً فارغة");
  assert.deepStrictEqual(chunk(null, 3), []);
  const big = Array.from({length: 701}, (_, i) => i);
  const parts = chunk(big, 300);
  assert.strictEqual(parts.length, 3);
  assert.strictEqual(parts.flat().length, 701, "لا عنصر يُفقَد");
});

// ── الحارس: كل مسارات الإسناد تفرض القاعدة ──────────────────────────────

/**
 * جسم دالّة بعدّ الأقواس، بدءاً من سطرٍ يطابق [startRe].
 * @param {RegExp} startRe نمط سطر البداية
 * @return {string} نصّ الجسم
 */
function bodyOf(startRe) {
  const lines = SRC.split("\n");
  const start = lines.findIndex((l) => startRe.test(l));
  assert.notStrictEqual(start, -1, `لم يُعثر على ${startRe}`);
  // نبدأ العدّ من **أوّل `{` بعد قائمة الوسائط**، لا من أوّل `{` في السطر:
  // `onCall({cpu: 0.25}, async (request) => {` يفتح ويُغلق كائن الإعدادات في
  // نفس السطر، فالعدّ الساذج ينتهي عند `}` الخاصة به ويُعيد جسماً فارغاً —
  // وهذا ما أوقع أوّل كتابةٍ لي فقرأت كل الدوال «بلا فحص».
  let depth = 0;
  let seen = false;
  const out = [];
  for (let i = start; i < lines.length; i++) {
    const clean = lines[i]
        .replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, "\"\"")
        .replace(/`[^`]*`/g, "``").replace(/\/\/.*$/, "");
    out.push(lines[i]);
    for (const ch of clean) {
      if (ch === "{") {
        depth++; seen = true;
      } else if (ch === "}") {
        depth--;
        // جسم الدالّة هو الكتلة التي تبقى مفتوحةً لأكثر من سطر.
        if (seen && depth === 0 && i > start) return out.join("\n");
      }
    }
    if (seen && depth === 0 && i > start) return out.join("\n");
  }
  assert.fail(`تعذّر إيجاد نهاية جسم ${startRe}`);
}

t("المسارات الأربعة كلها تمرّ على دالّة الأهلية الواحدة", () => {
  // سبباً سبباً لا عدّاً: عند السقوط يقول الفحص **أيُّ** مسارٍ فقد حرسه.
  const paths = {
    "_findFreeDriverForSlot (المُسنِد الآلي)": {
      re: /^async function _findFreeDriverForSlot\(/,
      needs: "_eligibleDriverDocs",
    },
    "approveAndAssignOrder (إسناد الأدمن يدوياً)": {
      re: /^exports\.approveAndAssignOrder\s*=/,
      needs: "_assertAssignableDriver",
    },
    "rescheduleAssignedOrder (إعادة الإسناد لسائق آخر)": {
      re: /^exports\.rescheduleAssignedOrder\s*=/,
      needs: "_assertAssignableDriver",
    },
    "getHourlyAvailability (عدّاد السعة)": {
      re: /^exports\.getHourlyAvailability\s*=/,
      needs: "_eligibleDriverDocs",
    },
  };
  const missing = [];
  for (const [label, {re, needs}] of Object.entries(paths)) {
    const body = bodyOf(re);
    assert.ok(body.split("\n").length > 3, `جسم ${label} قصير — فحص الأقواس كسر`);
    if (!body.includes(needs)) missing.push(`${label} → ينادي ${needs}`);
  }
  assert.deepStrictEqual(
      missing, [],
      "مسار إسناد بلا فحص أهلية. إسنادٌ لمستندٍ بلا حساب دخول يُخفي الطلب " +
      "المدفوع عن الجميع (القواعد تربط الرؤية بـauth.uid == driver_id):\n" +
      missing.map((m) => "  - " + m).join("\n"));
});

t("القاعدة غير مكتوبة ثانيةً داخل index.js", () => {
  // كانت نسختان حرفيّتان، ويحفظ تطابقَهما **تعليق**. فمن أعاد كتابتها إنلاين
  // أعاد المشكلة كاملةً، ولن يُسقط الفحص أعلاه لأن الدالّة ستبقى منادَاة.
  const lines = SRC.split("\n");
  const inline = lines
      .map((l, i) => [i + 1, l])
      .filter(([, l]) => /staff_role\s*\|\|/.test(l));
  // **الاستثناءُ بالاسمِ لا بالجِوار.** كانت القاعدةُ «لا يوجد `_assertAdmin`
  // ولا `allowedRoles` في الخمسةِ والعشرينَ سطراً فوقَه» — فنصُّ تعليقٍ
  // يَذكرُ `_assertAdmin` يُرضيها، وقد حدثَ: شرحٌ فوقَ `deleteStaffAccount`
  // يُسمّيه فمرَّت قراءةٌ إنلاين للدور. فالإسنادُ الآن إلى **الدالّةِ
  // المُحيطة** بالاسم، ولكلِّ مُستثنًى سببُه.
  const ALLOWED = {
    // يَقرآنِ دورَ **الأدمنِ** لا السائق — سؤالٌ آخرُ، وموضعُهما هو موضعُه.
    "_assertAdmin": "دور الأدمن، قاعدة أخرى",
    "_assertSuperAdmin": "دور الأدمن، قاعدة أخرى",
    // لا يَحسبُ دوراً إطلاقاً: يَنسخُ الحقلَ من `users` إلى رمزِ الإشعارات
    // كي لا تَبقى نسخةُ التوجيهِ بائتةً بعد ترقيةٍ أو تنزيل.
    "syncRoleToPushToken": "نسخُ حقلٍ لا حسابُ دور",
  };
  const enclosing = (ln) => {
    for (let i = ln - 1; i >= 0; i--) {
      const m = lines[i].match(
          /^(?:exports\.(\w+)\s*=|(?:async\s+)?function\s+(\w+)\s*\()/);
      if (m) return m[1] || m[2];
    }
    return "<top-level>";
  };
  const offenders = inline.filter(([ln]) => !(enclosing(ln) in ALLOWED));
  assert.deepStrictEqual(
      offenders.map(([ln, l]) => `L${ln}: ${l.trim()}`), [],
      "دور السائق محسوبٌ إنلاين — استعمل hasDriverRole من drivers.js");
});

t("قراءة users للسائقين دفعةً واحدة لا نداءً لكل سائق", () => {
  // getHourlyAvailability أسخنُ نداء في مسار الحجز (أربع شاشات تستدعيه)، وكان
  // يقرأ users/{id} لكل سائق في نداءٍ منفصل. getAll نداءٌ واحد لكل قطعة.
  const body = bodyOf(/^async function _eligibleDriverDocs\(/);
  assert.ok(/_getAllChunked/.test(body), "يجب أن يستعمل _getAllChunked");
  const getAll = bodyOf(/^async function _getAllChunked\(/);
  assert.ok(/db\.getAll\(/.test(getAll), "getAll هو النداء الواحد");
  assert.ok(/chunk\(refs, GET_ALL_CHUNK\)/.test(getAll),
      "التقسيم لازم: getAll نداءٌ واحد لكن حجم الطلب محدود");
});

console.log(`\ndrivers tests: ${passed} passed`);
