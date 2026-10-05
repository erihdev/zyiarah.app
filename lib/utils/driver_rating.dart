/// **«٥٫٠ ★» لسائقٍ لم يُقيّمه أحد — القاعدةُ في موضعٍ واحدٍ الآن.**
///
/// مسارا توفيرِ السائق (تطبيقُ الأدمن ولوحةُ الويب) يَبذُران `rating: 5.0`
/// على مستندِ السائق **بلا عدّاد**، و`aggregateDriverRating` يَستثني هذا
/// البذرَ من المتوسّطِ صراحةً (`count > 0 ? … : 0`) — أي أنّ الخادمَ نفسَه
/// يَعرفُ أنّ ٥٫٠ ليست تقييماً. فالفاصلُ هو **`rating_count`** لا وجودُ
/// `rating`.
///
/// عُولج هذا في سطحَين — `admin_staff_performance_screen` (عرضاً **وفرزاً**)
/// و`Drivers.tsx` — وبَقي **سطحٌ ثالث**: `admin_drivers_screen`، وهو القائمةُ
/// الرئيسةُ للسائقين في تطبيقِ الإدارة. وكان يَعرضُ «★ ٥٫٠» **وتحتَه
/// «(٠ تقييم)» مباشرةً** — سطرانِ يُكذّبانِ أحدَهما الآخرَ في البطاقةِ عينِها؛
/// وشارةُ «متميّز» في نفسِ الملفِّ كانت تَشترطُ العدّادَ بصحّة، فالكاتبُ
/// كان يَعرفُ القاعدةَ وطبّقَها في موضعٍ وأغفلَها في الآخر.
///
/// وحارسُ المسألةِ (`driver_rating_claim_test`) كان يَقرأُ **قائمةً مكتوبةً
/// بيدٍ** من ملفَّين، والقاعدةُ عامّة — وهو نمطُ «حارسٌ ضيّقٌ وقاعدةٌ عامّة»
/// الذي تَكرّرَ في هذا المستودعِ مرّاتٍ. فنطاقُه الآن **مُشتَقٌّ**: كلُّ ملفٍّ
/// يَقرأُ `rating_avg` يَجبُ أن يَمرَّ بهذه القاعدةِ أو يُستثنى بسببٍ مكتوب.
library;

/// ما يُعرَضُ متى لا تقييم — نفسُ الشكلِ المستعمَلِ في بقيّةِ الواجهات
/// («إجمالي الحجوزات» و«تقييمك» في ملفِّ العميلة، والتقييمُ في لوحةِ الويب).
const String kNoRatingLabel = '—';

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

/// متوسّطُ تقييمِ السائق، أو `null` متى لم يُقيّمه أحد.
///
/// القيمُ قد تُخزَّن نصّاً، فالتحويلُ متسامح — لكنّ **صفرَ العدّادِ غيابٌ لا
/// صفر**: `0` تقييماتٍ تعني «لا نعرف»، بخلافِ متوسّطٍ قيمتُه `0` وهو تقييمٌ.
double? driverRatingOf(Object? ratingAvg, Object? ratingCount) {
  if (_asInt(ratingCount) <= 0) return null;
  if (ratingAvg is num) return ratingAvg.toDouble();
  return double.tryParse('${ratingAvg ?? ''}');
}

/// نصُّ التقييمِ للعرض: رقمٌ بخانةٍ عشريّةٍ واحدة، أو [kNoRatingLabel].
String driverRatingLabel(Object? ratingAvg, Object? ratingCount) {
  final double? r = driverRatingOf(ratingAvg, ratingCount);
  return r == null ? kNoRatingLabel : r.toStringAsFixed(1);
}

/// هل لهذا السائقِ تقييمٌ حقيقيٌّ يَصلحُ للعرضِ والفرز؟
bool driverIsRated(Object? ratingAvg, Object? ratingCount) =>
    driverRatingOf(ratingAvg, ratingCount) != null;
