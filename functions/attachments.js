/**
 * مرفقاتُ البريد: **من مخزن المشروع وحده، وبحجمٍ محدود.**
 *
 * `notification_triggers` قابلة للكتابة من أيّ عميلٍ مسجَّل (firestore.rules:
 * `allow create: if isLoggedIn()`)، و`processNotificationTriggers` كان يأخذ
 * `attachmentUrls` منها و**يجلبها بـ`fetch` من الخادم** بلا أيّ تحقّق من
 * الأصل. وحارسا البريد القائمان لا يغطّيان هذا: `isAllowedEmailRecipient`
 * يحرس **المستلِم**، و`emailSenderOk` يحرس **المُرسِل** — ويسمح لعميلٍ عاديّ
 * بالإرسال إلى بريده المسجَّل هو (تأكيدٌ ذاتيّ مشروع). فعميلٌ يكتب مُشغِّلاً
 * موجَّهاً إلى نفسه ببريده هو يمرّ من الحارسَين، ويبقى `attachmentUrls` حرّاً.
 *
 * ما يُتيحه ذلك: جعلُ الخادم يطلب عنواناً يختاره العميل (SSRF بصلاحية خروج
 * المشروع)، وتنزيلُ ملفٍّ ضخمٍ بأمره (ذاكرة وكلفة). خادمُ البيانات الوصفيّة في
 * جوجل محميٌّ برأسٍ لا يرسله `fetch`، فالأثرُ محدود — لكنّ البدائيّةَ حقيقيّة
 * ولا داعيَ لها أصلاً.
 *
 * وكلُّ مرفقٍ شرعيٍّ في المشروع رابطُ تنزيلٍ من مخزن Firebase الخاصّ به:
 * فاتورةُ ZATCA من `getDownloadURL()` في `zyiarah_pdf_service.dart` — وهو
 * الكاتبُ الوحيد لـ`attachmentUrls` في المستودع كلِّه. فالقَصرُ عليه لا يمسّ
 * أيَّ مسارٍ قائم.
 */

/** أقصى حجمٍ لمرفقٍ واحد (بايت) — فاتورةُ PDF أصغرُ من هذا بمراحل. */
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

/**
 * أسماءُ دلاء المشروع المقبولة. Firebase يستعمل `<project>.firebasestorage.app`
 * للمشاريع الجديدة و`<project>.appspot.com` للقديمة — كلاهما مقبول.
 * @param {?string} projectId معرّف المشروع.
 * @return {Set<string>} أسماءُ الدلاء.
 */
function projectBuckets(projectId) {
  const p = String(projectId || "").trim();
  if (!p) return new Set();
  return new Set([`${p}.firebasestorage.app`, `${p}.appspot.com`]);
}

/**
 * هل هذا رابطُ تنزيلٍ من مخزن هذا المشروع؟
 *
 * الشكل: `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?...`
 * ويُفحص المضيفُ **كاملاً** لا بالاحتواء: `firebasestorage.googleapis.com.evil`
 * يحتوي الاسمَ ولا يساويه.
 *
 * @param {*} u الرابط.
 * @param {?string} projectId معرّف المشروع.
 * @return {boolean} صحيحٌ إن كان من مخزن المشروع.
 */
function isProjectStorageUrl(u, projectId) {
  let url;
  try {
    url = new URL(String(u));
  } catch {
    return false;
  }
  if (url.protocol !== "https:") return false;
  if (url.hostname !== "firebasestorage.googleapis.com") return false;
  const m = url.pathname.match(/^\/v0\/b\/([^/]+)\/o\/.+/);
  if (!m) return false;
  return projectBuckets(projectId).has(decodeURIComponent(m[1]));
}

module.exports = {MAX_ATTACHMENT_BYTES, projectBuckets, isProjectStorageUrl};
