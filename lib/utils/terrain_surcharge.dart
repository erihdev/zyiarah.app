/// تسعير القرى والوعورة (قرار المالك 2026-09-16 — تصميم Stitch `_56`).
///
/// كل منطقة (قرية/مركز) قد تتبع محافظة أمّاً (`governorate`) ولها طبيعة تضاريس
/// (`terrain`: مرتفعات جبلية / سهلية منبسطة) ورسوم وعورة `terrain_surcharge_percent`
/// تُضاف على **الأساس قبل الضريبة** لطلبات هذه المنطقة — لا على الأسعار الثابتة
/// (العقود). المصدر الموثوق مستند المنطقة: الخادم يعيد الحساب منه
/// (`functions/pricing.js → applyTerrainSurcharge`) ويتجاهل ما يكتبه العميل.
library;

const String kTerrainMountain = 'mountain';
const String kTerrainPlain = 'plain';

/// نسبة رسوم الوعورة من قيمة خام (رقم/نص/null): 0..100، وغير الرقمي/السالب = 0.
double terrainPercentFrom(dynamic raw) {
  final double n = raw is num
      ? raw.toDouble()
      : (double.tryParse('${raw ?? ''}'.trim()) ?? 0.0);
  if (n.isNaN || n <= 0) return 0.0;
  return n > 100 ? 100.0 : n;
}

String terrainLabel(String? terrain) {
  switch (terrain) {
    case kTerrainMountain:
      return 'مرتفعات جبلية';
    case kTerrainPlain:
      return 'سهلية منبسطة';
    default:
      return 'غير محدّدة';
  }
}

/// «15» لا «15.0»، و«12.5» كما هي.
String fmtPercent(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// تفصيل الفاتورة كما تعرضه شاشة الدفع وتحسبه ZATCA:
/// أساس + وعورة + ذروة − خصم = صافٍ، والصافي + الضريبة (15%) = الإجمالي.
///
/// [amount] هو المبلغ الشامل للضريبة كما تمرّره شاشة الخدمة (الأساس × 1.15).
/// السعر الثابت (عقد/اشتراك) لا وعورة ولا ذروة ولا خصم عليه — الخادم يطابقه حرفياً.
class PriceBreakdown {
  final double amount;
  final double terrainPercent;
  final double surgeFactor;
  final double discount;
  final bool fixedPrice;

  const PriceBreakdown({
    required this.amount,
    this.terrainPercent = 0.0,
    this.surgeFactor = 1.0,
    this.discount = 0.0,
    this.fixedPrice = false,
  });

  double get _pct => fixedPrice ? 0.0 : terrainPercent;
  double get _surge => fixedPrice ? 1.0 : surgeFactor;

  /// المشحون قبل الخصم (شامل الضريبة): الأساس × (1 + الوعورة) × الذروة.
  double get grossBeforeDiscount => amount * (1 + _pct / 100) * _surge;

  /// الإجمالي المستحق — مقرّب لخانتين، ولا يهبط تحت الصفر (كوبون أكبر من الطلب).
  double get total {
    final raw = grossBeforeDiscount - (fixedPrice ? 0.0 : discount);
    final clamped = raw < 0 ? 0.0 : raw;
    return (clamped * 100).roundToDouble() / 100;
  }

  double get subtotal => total / 1.15;
  double get vat => total - subtotal;

  // صفوف العرض قبل الضريبة — تُجمَع على الصافي.
  double get rowBase => amount / 1.15;
  double get rowTerrain => amount * (_pct / 100) / 1.15;
  double get rowSurge => amount * (1 + _pct / 100) * (_surge - 1) / 1.15;
  double get rowDiscount {
    if (fixedPrice) return 0.0;
    final capped = discount.clamp(0.0, grossBeforeDiscount);
    return capped / 1.15;
  }
}

/// مناطق محافظةٍ واحدة — لقائمة الأدمن (تصميم Stitch «المحافظات والنطاقات النشطة»).
class GovernorateGroup<T> {
  /// null = مناطق بلا محافظة (تُعرض أخيراً).
  final String? governorate;
  final List<T> zones;
  const GovernorateGroup(this.governorate, this.zones);
}

/// يجمّع المناطق تحت محافظاتها بترتيب أول ظهور، والبلا-محافظة مجموعة أخيرة.
List<GovernorateGroup<T>> groupByGovernorate<T>(
    Iterable<T> zones, String? Function(T zone) governorateOf) {
  final byName = <String, List<T>>{};
  final none = <T>[];
  for (final z in zones) {
    final g = (governorateOf(z) ?? '').trim();
    if (g.isEmpty) {
      none.add(z);
    } else {
      byName.putIfAbsent(g, () => <T>[]).add(z);
    }
  }
  return [
    for (final e in byName.entries) GovernorateGroup<T>(e.key, e.value),
    if (none.isNotEmpty) GovernorateGroup<T>(null, none),
  ];
}
