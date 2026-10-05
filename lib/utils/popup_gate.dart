import 'package:cloud_firestore/cloud_firestore.dart';

/// **هل يُعرض هذا الإعلانُ المنبثقُ لهذه العميلة؟**
///
/// القاعدةُ المعلنةُ في `functions/notify_prefs.js`: البثُّ الإداريُّ
/// (`notifications_log`) **تسويقيٌّ افتراضياً** ما لم يُوسَم
/// `operational: true`، والتسويقيُّ لا يَصل من أوقف «العروض والتسويق».
///
/// والمنبثقُ كان يَتخطّى ذلك كلَّه: `onNotificationCreated` يَرجعُ مبكراً
/// عند `type === "popup"` — **بحقٍّ**، لأنّ المنبثقَ نافذةٌ داخلَ التطبيقِ
/// فقط ولا يُبثُّ Push ولا يَملأ مركزَ التنبيهات (بلا ذلك الحارسِ كان إعلانٌ
/// واحدٌ يُطلق ثلاثَ قنواتٍ دفعةً واحدة). لكنّ الأثرَ الجانبيَّ أنّ
/// `_deliverBroadcast` لا يَعمل، ومعه `excludeOptedOut`. والعميلُ يَقرأ
/// `notifications_log where type == 'popup'` **مباشرةً** (القواعدُ تُجيزه
/// لكلِّ مسجَّل) — فالإسقاطُ الخادميُّ لا يَمرُّ به أصلاً.
///
/// فمن أوقفت التسويقَ صراحةً كانت تَرى الإعلانَ على كلِّ فتحٍ للتطبيقِ طولَ
/// أربعٍ وعشرين ساعة. القرارُ هنا، نقيّاً، كي يُختبَر بلا Firebase.
///
/// ملاحظةٌ لم تُغيَّر: لا علمَ «شُوهد» في أيِّ مكان، فالإعلانُ يُعاد على كلِّ
/// فتحٍ خلال نافذةِ الأربعِ والعشرين ساعة. هذا سلوكٌ قائمٌ وقرارُه للمالك.

/// نافذةُ عرضِ الإعلانِ من لحظةِ إرساله.
const Duration kPopupMaxAge = Duration(hours: 24);

bool shouldShowPopup(
  Map<String, dynamic>? data, {
  required DateTime now,
  required bool marketingEnabled,
}) {
  if (data == null) return false;
  final raw = data['sent_at'];
  final sentAt = raw is Timestamp ? raw.toDate() : null;
  // بلا لحظةِ إرسالٍ لا نَعرفُ عمرَه — لا نَعرضُ إعلاناً قد يكون من العام الماضي.
  if (sentAt == null) return false;
  final age = now.difference(sentAt);
  if (age.isNegative || age >= kPopupMaxAge) return false;
  // التشغيليُّ يَصلُ الجميعَ (صيانة/انقطاع) — كما في البثِّ تماماً.
  if (data['operational'] == true) return true;
  return marketingEnabled;
}

/// تفضيلُ التسويقِ من وثيقةِ المستخدم — الغيابُ = مُفعَّل (نفسُ تسامحِ
/// `client_notifications_screen._loadPref`: `prefs['marketing'] != false`).
bool marketingEnabledFrom(Map<String, dynamic>? userDoc) {
  final prefs = userDoc?['notification_prefs'];
  return prefs is Map ? prefs['marketing'] != false : true;
}
