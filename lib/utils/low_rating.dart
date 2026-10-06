/// **ما تَكتبُه العميلةُ عن خدمةٍ سيّئة، ومَن يَراه.**
///
/// حوارُ التقييمِ (`lib/widgets/rating_dialog.dart`) يَجمعُ **ثلاثةَ أشياء**:
/// نجوماً، وسبباً من قائمة، و**نصّاً تَكتبُه** — ثمّ يَفتحُ الكاميرا ويَطلبُ
/// **صورةً إثباتاً** (`ZyiarahStrings.attachEvidence`)، فتُرفَعُ إلى
/// `order_feedback/` ويُكتَبُ رابطُها في `orders/{id}.rating_evidence_url`.
/// و`storage.rules` تُسمّيها بالاسم: «إثباتٌ ميدانيٌّ لا يُستبدَل ولا يُحذَف».
///
/// **ولم يَكن لاثنَين منها قارئٌ في أيِّ سطحٍ على وجهِ الأرض.** مسحٌ لكلِّ
/// `lib/` و`admin_panel/src/` و`functions/`:
///   • `rating_evidence_url` — **كتابةٌ واحدةٌ وصفرُ قراءة**. فالعميلةُ
///     تَفتحُ الكاميرا وتُصوّرُ المشكلةَ ويُرفَعُ الملفُّ ويُدفَعُ ثمنُ
///     تخزينِه، **ولا أحدَ يَراه أبداً**.
///   • `rating_comment` — يُقرَأُ في موضعٍ واحدٍ، **شرطاً لا عرضاً**:
///     `data['rating_comment'] != null` في حارسِ السمعةِ بلوحةِ المالك. أي
///     أنّ كلماتَها تُستعمَلُ مُرشِّحاً ثمّ تُطرَح.
/// والتنبيهُ الخادميُّ (`notifyAdminOnLowRating`) يَحملُ النجومَ ورقمَ الطلبِ
/// والسببَ المختارَ وحدَها. فالمالكُ يُنبَّهُ عن تقييمٍ نجمةٍ واحدةٍ ثمّ لا
/// يَجدُ لا شكواها ولا صورتَها في أيِّ شاشة.
///
/// **ولا رقمَ قبل أن نعرفه:** الحارسُ كان يَقرأُ
/// `double.tryParse('${data['rating'] ?? 5.0}') ?? 5.0` — تقييمٌ مُلفَّقٌ
/// لطلبٍ لم يُقيَّم. كان غيرَ ضارٍّ بالمصادفةِ (5.0 > 2 فيَخرُج)، وقد سُجِّلَ
/// ذلك في هذا المستودعِ بوصفِه «مُحتملاً شدَّه شرطُ التعليق». فالقاعدةُ هنا
/// تُسمّي الغيابَ غياباً: **لا تقييمَ** تُعيدُ `null`، وما خرجَ عن [1,5]
/// كذلك — ونافذةُ الصلاحيّةِ هي نافذةُ الخادمِ نفسُها
/// (`rewards.aggregateRating`: `r < 1 || r > 5` تُرفَض)، لا اختراعاً هنا.
library;

/// أعلى تقييمٍ يُعَدُّ «منخفضاً» — نفسُ عتبةِ `notifyAdminOnLowRating`
/// (`r > 2` تَخرُج) كي لا تَفترقَ الشاشةُ عن التنبيهِ الذي يَقودُ إليها.
const double kLowRatingMax = 2.0;

/// نافذةُ التقييمِ الصالحِ — مرآةُ `rewards.aggregateRating`.
const double kRatingMin = 1.0;
const double kRatingMax = 5.0;

/// تقييمُ الطلبِ، أو `null` إن لم يُقيَّم. **لا افتراضَ ولا تلفيق:**
/// الغيابُ والفراغُ وغيرُ الرقميِّ وما خرجَ عن النافذةِ كلُّها «لا نعرف».
double? orderRatingOf(Map<String, dynamic> d) {
  final raw = d['rating'];
  final n = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
  if (n == null || n.isNaN) return null;
  if (n < kRatingMin || n > kRatingMax) return null;
  return n;
}

/// طلبٌ قيَّمته العميلةُ تقييماً منخفضاً فعلاً — لا طلبٌ بلا تقييم.
bool orderIsLowRated(Map<String, dynamic> d) {
  final r = orderRatingOf(d);
  return r != null && r <= kLowRatingMax;
}

/// عرضُ التقييم: «1» لا «1.0» (نفسُ قاعدةِ `formatSar`؛ الرقمُ في Firestore
/// قد يكون `int` أو `double` بحسبِ مَن كتبَه).
String ratingLabel(double r) =>
    r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

String? _text(Object? raw) {
  final s = '${raw ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

/// كلماتُها كما كتبَتها، أو `null` إن لم تَكتُب. (نصٌّ فراغٌ ليس تعليقاً —
/// وهو ما كان يَمُرُّ من شرطِ `!= null` فيُعرَضُ سطرٌ فارغ.)
String? ratingCommentOf(Map<String, dynamic> d) => _text(d['rating_comment']);

/// السببُ المختارُ من القائمة.
String? ratingReasonOf(Map<String, dynamic> d) => _text(d['rating_reason']);

/// رابطُ صورةِ الإثبات — `https` وحدَه. قيمةٌ ليست رابطاً تَرمي داخلَ
/// `Image.network` في `build`، فالعرضُ يُطالِبُ بالشكلِ لا بالوجودِ فحسب.
String? ratingEvidenceUrlOf(Map<String, dynamic> d) {
  final s = _text(d['rating_evidence_url']);
  if (s == null) return null;
  return s.startsWith('https://') ? s : null;
}
