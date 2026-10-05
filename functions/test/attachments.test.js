// حارس: **مرفقُ بريدٍ من مخزن المشروع وحده، وبحجمٍ محدود.**
//
// `notification_triggers` قابلة للكتابة من أيّ عميلٍ مسجَّل، وكان
// `processNotificationTriggers` يجلب `attachmentUrls` منها بـ`fetch` بلا أيّ
// تحقّقٍ من الأصل. وحارسا البريد القائمان لا يغطّيان هذا: `isAllowedEmailRecipient`
// يحرس المستلِم، و`emailSenderOk` يحرس المُرسِل — ويمرّ كلاهما لعميلٍ يراسل
// **نفسه** ببريده المسجَّل، وهو مسارٌ مشروعٌ مقصود (تأكيدُ الطلب). فيبقى
// العنوانُ المجلوب حرّاً بيده.
//
// خادمُ البيانات الوصفيّة في جوجل محميٌّ برأسٍ لا يرسله `fetch`، فالأثرُ
// محدود — لكنّ البدائيّةَ حقيقيّة (طلبٌ خارجٌ من شبكة المشروع بعنوانٍ يختاره
// العميل، وتنزيلٌ بحجمٍ يختاره) ولا داعيَ لها: الكاتبُ **الوحيد**
// لـ`attachmentUrls` في المستودع كلِّه هو فاتورةُ ZATCA من `getDownloadURL()`.
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const a = require("../attachments");

let passed = 0;
const t = (name, fn) => {
  try {
    fn();
    console.log(`  ok - ${name}`);
    passed++;
  } catch (e) {
    console.error(`  NOT OK - ${name}\n    ${e.message}`);
    process.exitCode = 1;
  }
};

const P = "zyiarah-app";
const good =
  "https://firebasestorage.googleapis.com/v0/b/zyiarah-app.firebasestorage.app" +
  "/o/invoices%2FINV-1.pdf?alt=media&token=8af5a1f7-00ab-425e-ad5e-6bef44f4cbd8";

t("(أ) رابطُ فاتورةٍ حقيقيّ يُقبل", () => {
  assert.strictEqual(a.isProjectStorageUrl(good, P), true);
});

t("(ب) ودلوُ المشاريع القديمة appspot.com كذلك", () => {
  assert.strictEqual(a.isProjectStorageUrl(
      `https://firebasestorage.googleapis.com/v0/b/${P}.appspot.com/o/x.pdf`, P), true);
});

t("(ج) دلوُ مشروعٍ آخر يُرفض", () => {
  assert.strictEqual(a.isProjectStorageUrl(
      "https://firebasestorage.googleapis.com/v0/b/other.appspot.com/o/x.pdf", P), false);
});

t("(د) مضيفٌ يحتوي الاسمَ ولا يساويه يُرفض", () => {
  // `firebasestorage.googleapis.com.evil.test` يمرّ من أيّ فحصٍ بالاحتواء.
  assert.strictEqual(a.isProjectStorageUrl(
      `https://firebasestorage.googleapis.com.evil.test/v0/b/${P}.appspot.com/o/x`, P), false);
  assert.strictEqual(a.isProjectStorageUrl(
      `https://evil.test/firebasestorage.googleapis.com/v0/b/${P}.appspot.com/o/x`, P), false);
});

t("(هـ) الشبكةُ الداخليّة وما ليس https يُرفض", () => {
  for (const u of [
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/",
    "http://169.254.169.254/latest/meta-data/",
    "http://localhost:8080/admin",
    "file:///etc/passwd",
    `http://firebasestorage.googleapis.com/v0/b/${P}.appspot.com/o/x`,
  ]) {
    assert.strictEqual(a.isProjectStorageUrl(u, P), false, u);
  }
});

t("(و) مسارٌ ناقصٌ أو بلا كائن يُرفض", () => {
  for (const u of [
    `https://firebasestorage.googleapis.com/v0/b/${P}.appspot.com/o/`,
    `https://firebasestorage.googleapis.com/v0/b/${P}.appspot.com`,
    "https://firebasestorage.googleapis.com/",
  ]) {
    assert.strictEqual(a.isProjectStorageUrl(u, P), false, u);
  }
});

t("(ز) قيمٌ غيرُ نصّيّة لا تُسقط الدالّة", () => {
  for (const u of [null, undefined, 0, {}, [], "ليس رابطاً"]) {
    assert.strictEqual(a.isProjectStorageUrl(u, P), false);
  }
});

t("(ح) بلا معرّف مشروعٍ لا يُقبل شيء (فشلٌ مغلق)", () => {
  assert.strictEqual(a.isProjectStorageUrl(good, ""), false);
  assert.strictEqual(a.isProjectStorageUrl(good, null), false);
  assert.strictEqual(a.projectBuckets("").size, 0);
});

t("(ط) الحدُّ عشرةُ ميغابايت", () => {
  assert.strictEqual(a.MAX_ATTACHMENT_BYTES, 10 * 1024 * 1024);
});

// ── موضعُ الاستعمال: قاعدةٌ صحيحةٌ لا يستدعيها أحدٌ تبقى خضراء ──
{
  const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const i = src.indexOf("const attachments = [];");
  const body = src.slice(i, i + 1700);

  t("(ي) الحلقةُ تفحص الأصلَ قبل الجلب", () => {
    assert.ok(i > 0, "لم تُعثر حلقةُ المرفقات");
    const guard = body.indexOf("attachmentsGuard.isProjectStorageUrl(");
    const fetchAt = body.indexOf("await fetch(url)");
    assert.ok(guard > 0, "لا فحصَ للأصل");
    assert.ok(fetchAt > guard, "الفحصُ بعد الجلب — لا يمنع شيئاً");
  });

  t("(ك) والحجمُ يُفحص مُعلَناً وفعليّاً", () => {
    assert.ok(body.includes("content-length"), "لا فحصَ للحجم المُعلَن");
    assert.ok(body.includes("buf.byteLength >"),
        "ردٌّ بلا content-length يتجاوز الحدَّ بلا فحص");
  });

  t("(ل) ومعرّفُ المشروع من البيئة لا مكتوبٌ بيدٍ", () => {
    assert.ok(/const PROJECT_ID = process\.env\.GCLOUD_PROJECT/.test(src));
  });
}

// ═══ مسارُ الكائنِ من الرابطِ — قارئٌ ثانٍ لنفسِ الحارس ═══
//
// `deleteStorageObject` (حذفٌ إداريٌّ خادميّ) يَحتاجُ المسارَ من الرابط،
// وفحصُ المضيفِ والدلوِ مكتوبٌ في هذه الوحدةِ أصلاً — فنسخةٌ ثانيةٌ منه في
// `index.js` هي ما يُحذّرُ منه هذا المستودعُ في كلِّ شريحة.
{
  const PID = "zyiarah-app";
  const url = (p) =>
    `https://firebasestorage.googleapis.com/v0/b/${PID}.appspot.com/o/` +
    `${encodeURIComponent(p)}?alt=media&token=x`;

  t("(م) يُعيدُ المسارَ المفكوكَ لرابطِ المشروع", () => {
    assert.strictEqual(a.storageObjectPath(url("banners/1.jpg"), PID),
        "banners/1.jpg");
    assert.strictEqual(
        a.storageObjectPath(url("products/sub dir/2.png"), PID),
        "products/sub dir/2.png");
  });

  t("(ن) ويَرفضُ ما ليس من المشروعِ — بنفسِ حارسِ المرفقات", () => {
    assert.strictEqual(a.storageObjectPath("https://evil.com/x", PID), null);
    assert.strictEqual(
        a.storageObjectPath(url("banners/1.jpg"), "other-project"), null);
    assert.strictEqual(a.storageObjectPath("not a url", PID), null);
    assert.strictEqual(a.storageObjectPath(null, PID), null);
  });

  t("(ص) ويَرفضُ تجاوزَ المجلّداتِ والمسارَ المطلق", () => {
    // بلا هذا يَخرُجُ المسارُ من البادئةِ المسموحةِ بعد التطبيع.
    assert.strictEqual(a.storageObjectPath(url("../secret"), PID), null);
    assert.strictEqual(a.storageObjectPath(url("banners/../x"), PID), null);
    assert.strictEqual(a.storageObjectPath(url("/abs"), PID), null);
  });

  t("(ض) والحذفُ الإداريُّ يَستعملُها ولا يُعيدُ كتابةَ الفحص", () => {
    const src = fs.readFileSync(
        path.join(__dirname, "..", "index.js"), "utf8");
    const i = src.indexOf("exports.deleteStorageObject");
    assert.ok(i > 0, "الدالّةُ اختفت — فالحذفُ عادَ عميليّاً");
    const fnBody = src.slice(i, src.indexOf("\nexports.", i + 10));
    assert.ok(fnBody.includes("await _assertAdmin(request);"),
        "بلا _assertAdmin يَحذفُ أيُّ مسجَّلٍ");
    assert.ok(fnBody.includes("attachmentsGuard.storageObjectPath("),
        "نسخةٌ ثانيةٌ من فحصِ الأصلِ في index.js");
    // قائمةُ سماحٍ لا منع: الفواتيرُ وإثباتُ الإكمالِ خارجَها عمداً.
    assert.ok(/ALLOWED_PREFIXES = \["banners\/", "products\/", "worker_photos\/"\]/
        .test(fnBody), "قائمةُ البادئاتِ تغيّرت — الفاتورةُ مستندٌ ضريبيّ");
    assert.ok(fnBody.includes("p) => path.startsWith(p)"),
        "البادئةُ تُفحَصُ من أوّلِ المسارِ لا بالاحتواء");
    // كائنٌ غائبٌ ليس فشلاً: الشاشةُ تَحذفُ مستندَ Firestore أوّلاً.
    assert.ok(/e\.code === 404/.test(fnBody), "إعادةُ المحاولةِ تُظهرُ خطأً زائفاً");
  });
}

console.log(`\nattachments tests: ${passed} passed`);
