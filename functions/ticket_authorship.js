"use strict";

// «أهذه الرسالةُ منّا أم منها؟» — نظيرُ `lib/utils/ticket_authorship.dart`
// و`admin_panel/src/utils/ticketAuthorship.ts`. **مرآةٌ مُعلَنة**، وجدولُ
// الحالاتِ في `functions/test/ticket_authorship.test.js` يُقابَلُ بجدولِ
// الدارت حرفيّاً فافتراقُ جهةٍ يَسقطُ الفحص.
//
// القرارُ كان مكتوباً أربعَ مرّاتٍ بثلاثِ لغاتٍ وقد افترق (التفصيلُ في رأسِ
// ملفِّ الدارت). وهذا الموضعُ هو **الأثقلُ أثراً**: فرعُه يُقرّرُ مَن
// يُنبَّه، فرسالةٌ تَحملُ ادّعاءَ الإدارةِ كانت تُسقِطُ تنبيهَ «رد جديد على
// تذكرة دعم» عن مديرِ الطلباتِ كلَّه.

/** @enum {string} */
const TicketSender = {TEAM: "team", CLIENT: "client"};

/**
 * @param {unknown} v قيمةٌ قد تكون نصّاً.
 * @return {string|null} النصُّ غيرُ الفارغِ أو `null`.
 */
function str(v) {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t === "" ? null : t;
}

/**
 * مَن كتبَ الرسالةَ في تذكرةٍ صاحبُها `ownerUid`.
 * @param {Record<string, unknown>} msg مستندُ الرسالة.
 * @param {string|null|undefined} ownerUid صاحبُ التذكرة.
 * @return {string} `TicketSender.TEAM` أو `TicketSender.CLIENT`.
 */
function ticketMessageSender(msg, ownerUid) {
  const m = msg || {};
  const uid = str(m.senderUid);
  if (uid !== null) {
    return uid === ownerUid ? TicketSender.CLIENT : TicketSender.TEAM;
  }
  const senderId = str(m.senderId);
  const owner = str(ownerUid);
  if (owner !== null && senderId === owner) return TicketSender.CLIENT;
  const role = str(m.senderRole);
  if (role === "admin" || senderId === "admin") return TicketSender.TEAM;
  return TicketSender.CLIENT;
}

/**
 * @param {Record<string, unknown>} msg مستندُ الرسالة.
 * @param {string|null|undefined} ownerUid صاحبُ التذكرة.
 * @return {boolean} هل الرسالةُ من فريقِ الدعم.
 */
function ticketMessageIsFromTeam(msg, ownerUid) {
  return ticketMessageSender(msg, ownerUid) === TicketSender.TEAM;
}

module.exports = {TicketSender, ticketMessageSender, ticketMessageIsFromTeam};
