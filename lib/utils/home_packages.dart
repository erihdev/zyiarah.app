import 'package:zyiarah/utils/firestore_maps.dart';

/// نظام «باقات السكن» — بديل اختيار الساعات في النظافة بالساعة (قرار المالك):
/// العميل يختار نوع سكنه (شقة صغيرة/متوسطة/فيلا) وعدد الكوادر، والسعر لكل
/// (نوع × عدد كوادر) تتحكم فيه اللوحة **لكل منطقة**، مع تفعيل/تعطيل كل خيار
/// كوادر من اللوحة لكل محافظة.
///
/// المخطط في `service_zones.packages` (تقرؤه هذه الأدوات وتكتبه شاشتا الأدمن
/// — التطبيق والويب — ويتحقق منه التسعير الخادمي functions/pricing.js حرفياً):
/// ```
/// packages: {
///   small:  { desc: '4 غرف + دورتا مياه', durationHours: 4,
///             crews: { '1': {price: 200, enabled: true}, '2': {...}, ... } },
///   medium: { ... }, villa: { ... },
/// }
/// ```
/// السعر **أساس قبل الضريبة** — التطبيق يضيف 15% عند العرض والدفع (نموذج
/// الضريبة المعتمد)، فالمعروض للعميل «شامل الضريبة».

/// أنواع السكن بترتيب العرض الثابت.
const List<String> kHomeTypes = ['small', 'medium', 'villa'];

/// أقصى عدد كوادر قابل للتسعير لكل نوع.
const int kMaxCrews = 4;

const Map<String, String> kHomeTypeLabels = {
  'small': 'شقة صغيرة',
  'medium': 'شقة متوسطة',
  // (ملاحظة العميل 2026-08-01) «فيلا أو دور» بلا كلمة «كامل».
  'villa': 'فيلا أو دور',
};

/// الوصف الافتراضي (قابل للتعديل لكل منطقة من اللوحة).
const Map<String, String> kHomeTypeDefaultDesc = {
  'small': '4 غرف + دورتا مياه',
  'medium': '6 غرف + 3 دورات مياه',
  'villa': 'جميع الغرف ودورات المياه',
};

/// مدة الجدولة الافتراضية بالساعات (تحجز فترة السائق وتُفحص بها السعة —
/// لا تظهر كخيار للعميل). قابلة للتعديل لكل منطقة من اللوحة.
const Map<String, int> kHomeTypeDefaultDuration = {
  'small': 4,
  'medium': 6,
  'villa': 8,
};

/// تنسيق سعرٍ للعرض: صحيحٌ بلا كسور، وإلا فخانتان — الرقاقة والملخص يعرضان
/// **نفس** الرقم الذي يُدفَع (كان تقريب الرقاقة لصفر كسور يُظهر سعراً يخالف الفاتورة).
String formatSar(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// تسمية عدد الكوادر بعربية سليمة.
String crewLabel(int n) => switch (n) {
      1 => 'كادر واحد',
      2 => 'كادران',
      _ => '$n كوادر',
    };

/// خيار كوادر مفعّل ومسعّر داخل باقة.
class CrewOption {
  final int crews;
  final double basePrice; // قبل الضريبة
  const CrewOption(this.crews, this.basePrice);

  /// ما **يُدفع** (شامل الضريبة 15%) — نفس معادلة بقية الخدمات.
  /// ملاحظة: لم يعد هذا ما **يُعرض**؛ العميل يرى `basePrice` (قبل الضريبة) في كل
  /// الشاشات، والضريبة تظهر في «تفاصيل الفاتورة» بشاشة إتمام الطلب فقط (قرار المالك).
  double get grossPrice => ((basePrice * 1.15) * 100).roundToDouble() / 100;
}

/// باقة نوع سكن كما هي في وثيقة المنطقة.
class HomePackage {
  final String type;
  final String desc;
  final int durationHours;
  final List<CrewOption> options; // المفعّلة فقط، مرتبة تصاعدياً بعدد الكوادر

  const HomePackage({
    required this.type,
    required this.desc,
    required this.durationHours,
    required this.options,
  });

  String get label => kHomeTypeLabels[type] ?? type;
  bool get sellable => options.isNotEmpty;
}

/// يقرأ باقات منطقةٍ من وثيقتها. النوع غير الموجود/غير المسعّر يُعاد بلا خيارات
/// (فلا يُعرض للعميل ولا يُباع) — صفر/معطّل = «غير مسعّرة» كسياسة بقية الخدمات.
List<HomePackage> zoneHomePackages(Map<String, dynamic>? zone) {
  final pkgs = stringKeyedMap(zone?['packages']) ?? {};
  return kHomeTypes.map((type) {
    final p = stringKeyedMap(pkgs[type]) ?? {};
    final crews = stringKeyedMap(p['crews']) ?? {};
    final options = <CrewOption>[];
    for (int n = 1; n <= kMaxCrews; n++) {
      final c = stringKeyedMap(crews['$n']);
      if (c == null || c['enabled'] != true) continue;
      final price = (c['price'] as num?)?.toDouble() ?? 0;
      if (price <= 0) continue;
      options.add(CrewOption(n, price));
    }
    return HomePackage(
      type: type,
      desc: (p['desc'] as String?)?.trim().isNotEmpty == true
          ? (p['desc'] as String)
          : (kHomeTypeDefaultDesc[type] ?? ''),
      // تثبيت 1..12: صفر/سالب يعطّل فحص السعة كلياً (حلقة صفرية) ويكسر رياضيات
      // نوافذ التعارض الخادمية (تفترض مدة ≤ يوم)، وخطأ إدخال واحد كان يكفي.
      durationHours: ((p['durationHours'] as num?)?.toInt() ??
              kHomeTypeDefaultDuration[type] ??
              4)
          .clamp(1, 12),
      options: options,
    );
  }).toList();
}
