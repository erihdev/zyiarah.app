import 'package:zyiarah/utils/env.dart';

/// **مفتاحُ ميسر القابلُ للنشرِ، من موضعٍ واحدٍ ومضمَّنٌ في الشفرة.**
///
/// مفتاحٌ `pk_` مُصمَّمٌ ليُشحَنَ داخلَ التطبيق: يُنشئُ دفعةً ولا يَقرأُ
/// ولا يَستردُّ ولا يُلغي — تلك للمفتاحِ السرّيِّ وحدَه، وهو في Secret Manager
/// خادميّاً ولا يَقربُ هذا الملفّ. وكان يُقرأُ من `.env` وحدَه، فكلُّ مسارِ
/// بناءٍ لا يَكتبُه (المعاينةُ، وسرُّ GitHub الفارغ) يُنتجُ تطبيقاً بلا بطاقةٍ
/// ولا Apple Pay بلا خطأ — `moyasarReady` كاذبٌ بصمت. قرارُ المالك
/// (2026-10-24): المفتاحُ في الشفرة، فكلُّ بناءٍ يَحملُه.
///
/// قيمةٌ في `.env` تَغلِبُ إن وُجدت (لتبديلِ المفتاحِ بلا إصدار شفرة)،
/// وإلّا فالمضمَّن.
const String kMoyasarPublishableKey = 'pk_live_3PtXDdfAFQeHZGjQMqJkKDyCJNJUPNh6wgh5h2MU';

/// المفتاحُ الذي يَستعملُه التطبيق — كلُّ قارئٍ يَمُرُّ من هنا.
String moyasarPublishableKey() {
  final fromEnv = envOrEmpty('MOYASAR_PUBLISHABLE_KEY').trim();
  return fromEnv.isNotEmpty ? fromEnv : kMoyasarPublishableKey;
}
