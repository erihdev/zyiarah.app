import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/utils/broadcast_target.dart';

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
///
/// **والنصفُ الثاني من الحفرةِ نفسِها بقيَ مفتوحاً سنةً — الجمهور
/// (2026-10-07).** الشرحُ أعلاه يَقولُها بنفسِه: `_deliverBroadcast` **لا
/// يَعملُ** للمنبثق، والعميلُ يَقرأُ المجموعةَ مباشرةً. وذاك المسارُ هو
/// الموضعُ **الوحيدُ** الذي يُرشِّحُ بـ`target` — فالإصلاحُ السابقُ أخذَ
/// منه `excludeOptedOut` وتركَ المُرشِّحَ. والاستعلامُ العميليُّ
/// `where type == 'popup'` بلا أيِّ ذكرٍ للجمهور، فإعلانٌ منبثقٌ موسومٌ
/// «السائقين فقط» — وكلا المحرِّرَين يَكتبُه — كان **يُعرَضُ لكلِّ عميلةٍ**
/// تَفتحُ التطبيق، بعنوانِه ونصِّه وأزرارِه المكتوبةِ للسائقين، ولا يَراه
/// سائقٌ واحد (`checkAndShowPopup` مُنادى من `client_dashboard` وحدَه).
/// والأدمنُ يَرى «تم النشر بنجاح».
///
/// والترتيبُ هو الإصلاح: الجمهورُ يُفحَصُ **قبلَ** قِصَرِ `operational`،
/// لأنّ «تشغيليٌّ» يَرفعُ تفضيلَ التسويقِ لا الجمهورَ — وإشعارٌ تشغيليٌّ
/// للسائقين («الورشةُ مغلقةٌ اليوم») ليس للعميلة.

/// نافذةُ عرضِ الإعلانِ من لحظةِ إرساله.
const Duration kPopupMaxAge = Duration(hours: 24);

/// أسماءُ الجمهورِ هي **قيمُ الحقلِ نفسُها** — فلا خريطةَ ثانيةً من الدورِ
/// (`client`) إلى الجمهور (`clients`) تَنحرِف.
const String kClientAudience = 'clients';
const String kDriverAudience = 'drivers';

/// كم إعلاناً يُقرأُ قبلَ اختيارِ أوّلِ ما يُعرَض.
///
/// `limit(1)` كان يَجعلُ إعلاناً لجمهورٍ آخرَ **يَحجبُ** إعلاناً حيّاً لهذا
/// الجمهور. والفهرسُ المركَّبُ `(type, sent_at)` هو نفسُه، فالكلفةُ أربعُ
/// قراءاتٍ لا فهرسٌ جديد.
const int kPopupScanLimit = 5;

/// **أهذا الإعلانُ لهذا الجمهور؟**
///
/// غيابُ الحقلِ «الجميع» — مستنداتٌ قديمةٌ بلا `target`، وهو كذلك فالُّ
/// `_deliverBroadcast` نفسُه. و`all_users` (اسمُ موضوعِ FCM) يُحَلُّ عبرَ
/// `broadcastTargetOf`، لأنّ المسارَ المجدولَ كتبَه في الحقلِ حتى
/// 2026-10-07 ومستنداتُ الإنتاجِ القائمةُ تَحملُه.
bool popupTargetsAudience(
  Map<String, dynamic>? data, {
  required String audience,
}) {
  final Object? raw = data?['target'];
  final String t = broadcastTargetOf(raw == null ? 'all' : raw.toString());
  return t == 'all' || t == audience;
}

bool shouldShowPopup(
  Map<String, dynamic>? data, {
  required DateTime now,
  required bool marketingEnabled,
  // **مطلوبٌ لا مُفترَض**: موضعُ نداءٍ منسيٌّ لا يَجوزُ أن يُبقي السلوكَ
  // القديمَ (عرضُ إعلانِ السائقينَ للعميلة) صامتاً — نفسُ قرارِ `passed`
  // في قاعدةِ «تتبّع السائق».
  required String audience,
}) {
  if (data == null) return false;
  // الجمهورُ أوّلاً: «تشغيليٌّ» يَرفعُ تفضيلَ التسويقِ لا الجمهور.
  if (!popupTargetsAudience(data, audience: audience)) return false;
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
