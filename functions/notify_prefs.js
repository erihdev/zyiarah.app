"use strict";

// تفضيلات التنبيهات (تصميم Stitch «تفضيلات تنبيهات الزيارة»): العميل يوقف
// «العروض والتسويق» فقط — تنبيهات الطلبات والمدفوعات والمواعيد تصله دائماً
// (تُرسل عبر notification_triggers لا عبر البثّ). البثّ الإداري (notifications_log)
// تسويقي افتراضياً، ما لم يعلّمه الأدمن `operational: true` (صيانة/انقطاع/تنبيه
// مواعيد) فيصل الجميع. دوال نقيّة بلا تبعيات — تُختبر بـ node test/notify_prefs.test.js.

/** البثّ يخضع لإيقاف العروض؟ (كل بثّ إلا التشغيلي) */
function isMarketingBroadcast(data) {
  if (!data) return false;
  return data.operational !== true;
}

/**
 * يُسقط مستندات (fcm_tokens أو users — معرّفها uid) لمن أوقف التسويق.
 * @param {Array<{id: string}>} docs
 * @param {Set<string>} optOut
 * @return {Array<{id: string}>}
 */
function excludeOptedOut(docs, optOut) {
  if (!optOut || optOut.size === 0) return docs;
  return docs.filter((d) => !optOut.has(d.id));
}

module.exports = {isMarketingBroadcast, excludeOptedOut};
