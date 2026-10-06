import 'package:zyiarah/utils/firestore_maps.dart';
import 'package:zyiarah/utils/vat.dart';

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
/// السعر **أساس قبل الضريبة** — وهو ما **يُعرض** للعميلة؛ الضريبة 15% تُضاف
/// عند الدفع وتظهر في تفاصيل الفاتورة وحدها (قرار المالك).

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

/// نفسُ القاعدةِ لقيمةٍ آتيةٍ من Firestore أو من حسابٍ `double`.
///
/// **لماذا:** الرقمُ في Firestore قد يكون `int` أو `double` بحسبِ مَن كتبَه —
/// ومحرّرا الإدارةِ يَكتبانِ `double.tryParse(...) ?? 0.0` — فسعرُ ٣٥ يُخزَّنُ
/// `35.0` و`'$v'` تَطبعُه **«35.0 ر.س»** على رفِّ المتجرِ وفي السلّة. ولا
/// يَظهرُ ذلك في أيِّ فحصٍ: النوعُ صحيحٌ والنصُّ قبيحٌ فحسب. والقاعدةُ هي
/// قاعدةُ `formatSar` نفسُها (صحيحٌ بلا كسور، وإلّا خانتان) — تُطبَّقُ على
/// `Object?` كي تُستعمَلَ مباشرةً على خريطةِ المستند.
String formatSarAny(Object? v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  return formatSar((n ?? 0).toDouble());
}

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
  double get grossPrice => grossFromBaseRounded(basePrice);
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

/// المدّةُ التي تُفحَص بها **إتاحةُ الأيّام** في شريط التواريخ.
///
/// باقةٌ مختارة ⇒ مدّتُها، فهي الفترةُ التي يحجزها الطلبُ فعلاً.
///
/// **بلا اختيارٍ لا تُعرف المدّة**، وكان الشريطُ يُلوَّن بما في الحقل: أربعاً
/// ابتداءً، أو مدّةَ باقةٍ من **منطقةٍ أخرى** بقيت بعد تعطيل نوعها هنا
/// (`_applyZonePackages` يصفّر النوعَ والسعر ولا يصفّر المدّة). والمدّةُ
/// الأطولُ تضيّق: تُظهر «محجوز بالكامل» بالأحمر على يومٍ متّسعٍ لباقةٍ تستطيع
/// العميلةُ شراءها — ودعوى «محجوز» التي لا تصحّ تمنع حجزاً قائماً، ولا سبيلَ
/// لها إلى كشفها.
///
/// فالقاعدة: **أقصرُ** مدّةٍ مسعّرةٍ في المنطقة — اليومُ لا يُستبعَد إلّا إن ضاق
/// عن كلّ باقةٍ تستطيع شراءها. والاتجاهُ المقابل مُعالَجٌ أصلاً: اختيارُ باقةٍ
/// أطولَ ينقل التاريخَ تلقائياً عن يومٍ لم يبقَ يتّسع لها (ويُظهره في الشريط).
///
/// لا باقةَ مسعّرةً بالمرّة ⇒ [fallback]: لا شيءَ يُحجَز على أيّ حال.
int homeStripDurationHours({
  required List<HomePackage> packages,
  required String? selectedType,
  int fallback = 4,
}) {
  if (selectedType != null) {
    for (final p in packages) {
      if (p.type == selectedType && p.sellable) return p.durationHours;
    }
  }
  int? shortest;
  for (final p in packages) {
    if (!p.sellable) continue;
    if (shortest == null || p.durationHours < shortest) {
      shortest = p.durationHours;
    }
  }
  return shortest ?? fallback;
}

/// ما تعرضه قائمةُ الباقات — ثلاثُ حالاتٍ كانت رسالةً واحدة.
///
/// «لا توجد باقات مسعّرة **في منطقتك** حالياً» كانت تُقال كذلك **قبل تحديد
/// المنطقة**: فتقرأ العميلةُ أنّنا نخدم منطقتها ولا نملك لها سعراً، والمطلوبُ
/// منها في الحقيقة تحديدُ موقعٍ داخل النطاق. والشاشةُ نفسها تقول في بطاقةٍ
/// أعلاه «موقعك الحالي خارج نطاق خدماتنا. إن كنتِ داخل نطاقنا حدّدي موقعك من
/// الخريطة» — فتتناقض الرسالتان على شاشةٍ واحدة (رصدَها مختبِرٌ على جهازه).
///
/// دعوى «في منطقتك» لا تصحّ إلّا بمنطقةٍ محدَّدة، فالتمييزُ هنا لا في الشاشة:
/// حالةٌ خالصة تُختبَر بلا Firebase.
enum HomePackagesView {
  /// هناك خيارٌ مسعّرٌ واحدٌ على الأقل ⇒ تُعرض البطاقات.
  packages,

  /// لا منطقةَ بعد — لم يُحدَّد الموقع، أو حُدِّد خارج النطاق. لا تُقال دعوى
  /// عن «منطقتك»؛ المطلوبُ خطوةُ تحديدِ الموقع.
  noZone,

  /// منطقةٌ محدَّدة ولا خيارَ مسعّراً فيها — هنا وحدها تصحّ الدعوى، وتُسمّى
  /// المنطقةُ فيها فلا تبقى مبهمة.
  zoneWithoutPackages,
}

/// أيُّ الحالات الثلاث؟ [zoneName] فارغاً أو `null` = لا منطقة.
HomePackagesView homePackagesView({
  required List<HomePackage> packages,
  required String? zoneName,
}) {
  if (packages.any((p) => p.sellable)) return HomePackagesView.packages;
  return (zoneName?.trim().isEmpty ?? true)
      ? HomePackagesView.noZone
      : HomePackagesView.zoneWithoutPackages;
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
