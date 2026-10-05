// «أهذه الرسالةُ منّا أم منها؟» — **مرآةٌ مُعلَنة** لـ
// `lib/utils/ticket_authorship.dart` و`functions/ticket_authorship.js`.
// جدولُ الحالاتِ في `ticketAuthorship.test.ts` يُقابَلُ بجدولِ الدارت
// حرفيّاً، فافتراقُ جهةٍ يَسقطُ الفحص.
//
// القرارُ كان مكتوباً أربعَ مرّاتٍ وقد افترق: هذا الملفُّ كان يَقرأُ
// `senderRole === 'admin' || senderId === 'admin'` بينما تطبيقُ الإدارةِ
// يَقرأُ `senderRole` وحدَه — فسطحانِ إداريّانِ يَقرآنِ الخيطَ الواحدَ على
// وجهَين. والتفصيلُ (والتلفيقُ الذي يُسكِتُ تنبيهَ الدعم) في رأسِ ملفِّ
// الدارت.

export type TicketSender = 'team' | 'client';

export interface TicketMessageLike {
  senderUid?: string | null;
  senderId?: string | null;
  senderRole?: string | null;
}

function str(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t === '' ? null : t;
}

/** مَن كتبَ الرسالةَ في تذكرةٍ صاحبُها `ownerUid`. */
export function ticketMessageSender(
  msg: TicketMessageLike,
  ownerUid: string | null | undefined,
): TicketSender {
  const uid = str(msg?.senderUid);
  if (uid !== null) return uid === ownerUid ? 'client' : 'team';
  const senderId = str(msg?.senderId);
  const owner = str(ownerUid);
  if (owner !== null && senderId === owner) return 'client';
  const role = str(msg?.senderRole);
  if (role === 'admin' || senderId === 'admin') return 'team';
  return 'client';
}

export function ticketMessageIsFromTeam(
  msg: TicketMessageLike,
  ownerUid: string | null | undefined,
): boolean {
  return ticketMessageSender(msg, ownerUid) === 'team';
}
