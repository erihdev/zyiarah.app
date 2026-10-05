/// **«أهذه الرسالةُ منّا أم منها؟» كان مكتوباً أربعَ مرّاتٍ ولا يَتّفق
/// (2026-10-05).**
///
/// رسائلُ التذاكرِ تُكتَبُ من أربعةِ أسطح، والقرارُ يُقرَأُ في أربعةِ مواضعَ
/// بثلاثِ لغات — وقد **افترقت**:
///
///   • `functions/index.js` (`sendNotificationOnTicketReply`):
///     `senderRole === "admin" || senderId === "admin"`
///   • `admin_panel/src/pages/Support.tsx`: المِثلُ
///   • `lib/screens/support_screen.dart` (شاشةُ العميلة): المِثلُ
///   • `lib/screens/admin/admin_ticket_details_screen.dart`:
///     **`senderRole != 'admin'` وحدَه**
///
/// فالرابعُ يُخالِفُ الثلاثةَ: رسالةٌ تَحملُ `senderId: 'admin'` بلا
/// `senderRole` — وهو ما تَكتبُه **لوحةُ الويبِ** جزئيّاً — تُقرأُ في اللوحةِ
/// وفي الخادمِ «من الفريق»، وفي تطبيقِ الإدارةِ «من العميلة». سطحانِ
/// إداريّانِ يَقرآنِ الخيطَ الواحدَ على وجهَين.
///
/// ═══ وما هو أثقلُ من الافتراق ═══
///
/// الحقلانِ **يَكتبُهما العميلُ**: قاعدةُ `messages` كانت `allow create` بلا
/// قيدٍ على المحتوى، فمالكةُ التذكرةِ تُنشئُ رسالةً بـ`senderRole: 'admin'`
/// فتُسقِطُ تنبيهَ «رد جديد على تذكرة دعم» عن الإدارةِ، وتُرسَمُ رسالتُها في
/// جهةِ الفريقِ على شاشتَي الإدارة. (مُثبَتٌ على المُحاكي.) **القاعدةُ هي
/// الإصلاحُ الجذريُّ** وهي محجوزةٌ خلفَ STAGE-C؛ وهذا الملفُّ يُوحّدُ القرارَ
/// ويُصلِحُ الافتراقَ، ويَجعلُ نزولَ القاعدةِ كافياً بلا جولةٍ ثانية.
///
/// ═══ القاعدة ═══
///
/// **المِعيارُ هو الفاعلُ لا الادّعاء**: رسالةٌ كاتبُها ليس صاحبةَ التذكرةِ
/// هي من الفريق. فالسطحانِ الإداريّانِ يَكتبانِ uid الأدمنِ الحقيقيَّ الآن
/// (`senderUid`) — وهو إصلاحُ نقصٍ قائمٍ بذاته: لم يُسجّلْ أيُّ سطحٍ **أيُّ
/// أدمنٍ** أجاب.
///
/// والاحتياطيُّ للمستنداتِ القديمةِ (بلا `senderUid`) يَقرأُ الادّعاءَ كما
/// كان — **لكن بشرطٍ جديد**: ادّعاءٌ يَصحبُه uid صاحبةِ التذكرةِ يُنقَضُ
/// بنفسِه، فيُقرأُ «منها». وهذا ما يَعضُّ اليومَ على الصياغةِ التي يُنتجُها
/// مسارُ التطبيقِ نفسُه؛ وصياغةٌ تَحذفُ `senderId` تَبقى مقبولةً حتى تَنزلَ
/// القاعدة — يُقالُ كما هو، لا يُدّعى غيرُه.
library;

/// كاتبُ رسالةِ التذكرة.
enum TicketSender {
  /// من فريقِ الدعم (الإدارة).
  team,

  /// من صاحبةِ التذكرة.
  client,
}

String? _str(Object? v) {
  if (v is String) {
    final String t = v.trim();
    return t.isEmpty ? null : t;
  }
  return null;
}

/// مَن كتبَ [msg] في تذكرةٍ صاحبُها [ownerUid].
///
/// [ownerUid] قد يكون `null` حين لا يُعرَفُ المالكُ بعد (مستندُ التذكرةِ لم
/// يُحمَّل) — فيُقرأُ الادّعاءُ وحدَه كما كان قبلَ هذه القاعدة.
TicketSender ticketMessageSender(Map<String, dynamic> msg, String? ownerUid) {
  final String? uid = _str(msg['senderUid']);
  if (uid != null) {
    // الفاعلُ معروف: القرارُ بنيويٌّ لا ادّعائيّ.
    return uid == ownerUid ? TicketSender.client : TicketSender.team;
  }
  final String? senderId = _str(msg['senderId']);
  // uid صاحبةِ التذكرةِ يَنقضُ أيَّ ادّعاءٍ بأنّها الإدارة.
  if (ownerUid != null && senderId == ownerUid) return TicketSender.client;
  final String? role = _str(msg['senderRole']);
  if (role == 'admin' || senderId == 'admin') return TicketSender.team;
  return TicketSender.client;
}

/// اختصارٌ للقُرّاء.
bool ticketMessageIsFromTeam(Map<String, dynamic> msg, String? ownerUid) =>
    ticketMessageSender(msg, ownerUid) == TicketSender.team;

/// الحقولُ التي يُجيزُها `firestore.rules` لكتابةِ العميلةِ في `messages`.
///
/// مجموعةٌ كاملةٌ: الحارسُ يُقابِلُها بما يَكتبُه التطبيقُ فعلاً، فحقلٌ جديدٌ
/// في الشاشةِ بلا تعديلِ القاعدةِ يَسقطُ الفحصَ بدلَ أن يُرفَضَ عند العميلة.
const List<String> kClientTicketMessageFields = <String>[
  'senderId',
  'senderRole',
  'text',
  'sentAt',
];
