import 'package:zyiarah/utils/home_packages.dart' show crewLabel;

/// انقلابُ سعرِ الكوادر: خيارٌ بكوادرَ **أكثر** بسعرٍ **أدنى** من خيارٍ أقلَّ
/// منه كوادر، في نوعِ السكن نفسِه وفي المنطقة نفسِها.
///
/// وُجد في بيانات الإنتاج (2026-10-04، منطقة «فيفا»، «فيلا أو دور»): كادرٌ
/// واحد 347 ر.س وكادران 320 ر.س — فالعميلةُ ترى الخيارَين جنباً إلى جنب
/// وتأخذ كادرَين بأقلَّ من كادر. ولا شيءَ في المحرِّرَين (شاشةُ الإدارة ولوحةُ
/// الويب) كان يقول شيئاً: حقلُ سعرٍ حرٌّ لكلِّ (نوع × كوادر)، بلا مقارنةٍ ولا
/// تنبيه.
///
/// **تنبيهٌ لا منع**: سعرٌ ترويجيٌّ مقصودٌ قرارٌ تجاريّ، فالقاعدةُ تُظهر
/// الانقلابَ عند الإدخال وتترك القرارَ للإدارة.
class CrewPriceInversion {
  /// الخيارُ المخالف (الأكثرُ كوادرَ والأدنى سعراً).
  final int crews;
  final double price;

  /// الخيارُ الأقلُّ كوادرَ الذي يتجاوزه سعراً (الأعلى سعراً بين من هم أدنى).
  final int lowerCrews;
  final double lowerPrice;

  const CrewPriceInversion({
    required this.crews,
    required this.price,
    required this.lowerCrews,
    required this.lowerPrice,
  });

  /// فرقُ السعر الذي تخسره الإدارةُ على كلِّ طلبٍ يختار الخيارَ الأكثر كوادر.
  double get gap => lowerPrice - price;

  @override
  String toString() => 'CrewPriceInversion($lowerCrews:$lowerPrice → $crews:$price)';

  @override
  bool operator ==(Object other) =>
      other is CrewPriceInversion &&
      other.crews == crews &&
      other.price == price &&
      other.lowerCrews == lowerCrews &&
      other.lowerPrice == lowerPrice;

  @override
  int get hashCode => Object.hash(crews, price, lowerCrews, lowerPrice);
}

/// مواضعُ الانقلاب في نوعِ سكنٍ واحد.
///
/// [prices] خياراتُ الكوادر **المفعّلة والمسعّرة** وحدَها: مفتاحٌ معطَّل أو سعرٌ
/// ≤ 0 لا يُعرض للعميل أصلاً (نصُّ المحرِّر: «المعطَّل/الصفر لا يظهر للعميل»)
/// فليس انقلاباً. والسعرُ غيرُ المنتهي (NaN/∞) يُستبعد: لا يُقارَن ما لا يُقاس.
///
/// يُقارن كلُّ خيارٍ بأعلى سعرٍ بين الخيارات **الأقلِّ منه كوادر** — تقريرٌ
/// واحدٌ لكلِّ خيارٍ مخالف، لا لكلِّ زوجٍ (أربعةُ خيارات تُنتج ستةَ أزواجٍ،
/// وثلاثةُ تنبيهاتٍ على خيارٍ واحدٍ ضجيجٌ يُغرق الإشارة).
List<CrewPriceInversion> crewPriceInversions(Map<int, double> prices) {
  final live = <int, double>{};
  for (final e in prices.entries) {
    if (e.value > 0 && e.value.isFinite) live[e.key] = e.value;
  }
  final keys = live.keys.toList()..sort();
  final out = <CrewPriceInversion>[];
  for (var i = 1; i < keys.length; i++) {
    final n = keys[i];
    var worstCrews = keys[0];
    var worstPrice = live[keys[0]]!;
    for (var j = 1; j < i; j++) {
      if (live[keys[j]]! > worstPrice) {
        worstPrice = live[keys[j]]!;
        worstCrews = keys[j];
      }
    }
    if (live[n]! < worstPrice) {
      out.add(CrewPriceInversion(
          crews: n,
          price: live[n]!,
          lowerCrews: worstCrews,
          lowerPrice: worstPrice));
    }
  }
  return out;
}

/// نصُّ التنبيه المعروض للإدارة — جملةٌ واحدة لكلِّ خيارٍ مخالف.
/// الصياغةُ العربيّة من `crewLabel` نفسِها التي تُسمّي الخيارَ للعميلة، كي
/// يقرأ الأدمنُ الاسمَ الذي تراه هي.
String crewPriceInversionLabel(CrewPriceInversion inv) =>
    '${crewLabel(inv.crews)} بسعر ${inv.price.toStringAsFixed(2)} ر.س — أقلُّ '
    'من ${crewLabel(inv.lowerCrews)} '
    '(${inv.lowerPrice.toStringAsFixed(2)} ر.س). العميلةُ ترى الخيارَين معاً.';
