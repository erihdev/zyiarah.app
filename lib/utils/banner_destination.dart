/// **وجهةُ البنرِ الترويجيّ: قرارٌ واحدٌ لسطحَين ومُحرِّرٍ.**
///
/// مستندُ `promo_banners` يَحملُ `routeType` و`actionUrl`، ويُرسَمُ في
/// **سطحَين**: البنرُ الرئيسيُّ في `client_dashboard` (placement = main)
/// وقسمُ العروضِ في `offers_screen` (placement = offers). والقاعدةُ كانت
/// مكتوبةً **مرّتَين** — وقائمةُ الوجهاتِ متطابقةً في النسختَين، و**الفالُّ
/// وحدَه افترق**: لوحةُ العميلةِ تَقولُ «هذا الرابط غير متاح حالياً»
/// لوجهةٍ لا تُعرَف، وقسمُ العروضِ كان `dest` فيه يَبقى `null` فلا تَنقلُ
/// الضغطةُ ولا تُقالُ كلمة — «زرٌّ يُضغَطُ فلا يَحدثُ شيء».
///
/// **والحالةُ قابلةُ الوصولِ اليومَ ليست وجهةً مجهولةً بل وجهةٌ معروفةٌ
/// بلا رابط:** مُحرِّرُ البنراتِ يُسمّي حقلَ الرابطِ «رابط الواتساب
/// (اختياري)» ويَتحقّقُ من الصورةِ وحدَها قبلَ «حفظ ونشر» — فالأدمنُ
/// يَختارُ «رابط واتساب (خارجي)» ويَترُكُ الحقلَ فارغاً فيُنشَرُ بنرٌ
/// ضغطتُه لا تَفعلُ شيئاً. وشرطُ `actionUrl.isNotEmpty` في السطحَين
/// يُسقِطُه من فرعِ الرابطِ، ثمّ لا يُطابِقُ أيَّ وجهةِ خدمة.
///
/// فالتصنيفُ يَسكنُ هنا مرّةً — نقيّاً بلا Firestore ولا ودجات، فيُختبَرُ
/// بلا مُحاكٍ — و**كلُّ سطحٍ يُحوّلُ `BannerServiceTarget` إلى شاشتِه
/// بمُبدِّلٍ شامل** (`switch` على تعدادٍ، فإضافةُ وجهةٍ بلا شاشةٍ **خطأُ
/// ترجمةٍ** في السطحَين لا سقوطٌ صامت — نفسُ قرارِ الوسيطِ المطلوبِ في
/// `passed` و`audience`).
library;

/// وجهةُ خدمةٍ داخلَ التطبيق. الأسماءُ هي قيمُ `routeType` المخزَّنةُ
/// نفسُها، ومُحرِّرُ البنراتِ هو مَن يَكتبُها.
enum BannerServiceTarget {
  hourlyCleaning,
  sofaRug,
  acService,
  subscriptions,
  store,
  support,
}

/// ما تَفعلُه الضغطةُ.
enum BannerTapKind {
  /// رابطٌ خارجيٌّ صالحٌ — يُفتَح.
  externalUrl,

  /// وجهةُ خدمةٍ داخليّة.
  service,

  /// «صورة فقط» بقرارِ الأدمن (`none` أو حقلٌ غائب) — الصمتُ هو الصواب.
  silent,

  /// وجهةٌ لا نَعرفُها، أو رابطٌ خارجيٌّ بلا رابط. تُقالُ ولا تُبتلَع.
  unavailable,
}

/// نتيجةُ التصنيف.
class BannerTap {
  final BannerTapKind kind;

  /// غيرُ فارغٍ متى كان `kind == externalUrl` فقط.
  final String url;

  /// غيرُ `null` متى كان `kind == service` فقط.
  final BannerServiceTarget? service;

  const BannerTap._(this.kind, {this.url = '', this.service});

  static const BannerTap silent = BannerTap._(BannerTapKind.silent);
  static const BannerTap unavailable = BannerTap._(BannerTapKind.unavailable);
}

/// خريطةُ قيمةِ `routeType` المخزَّنةِ إلى وجهةِ الخدمة. مفاتيحُها هي
/// بعينِها ما يَكتبُه `admin_banners_screen`، ومعها مرادفانِ قديمانِ
/// (`/ac`, `/rug_cleaning`) لمستنداتٍ قائمةٍ في الإنتاج: إصلاحُ الكاتبِ
/// وحدَه لا يُعيدُ كتابةَ ما كُتب.
const Map<String, BannerServiceTarget> kBannerServiceRoutes = {
  '/hourly_cleaning': BannerServiceTarget.hourlyCleaning,
  '/sofa_cleaning': BannerServiceTarget.sofaRug,
  '/rug_cleaning': BannerServiceTarget.sofaRug,
  '/ac': BannerServiceTarget.acService,
  '/ac_service': BannerServiceTarget.acService,
  '/subscriptions': BannerServiceTarget.subscriptions,
  '/store': BannerServiceTarget.store,
  '/support': BannerServiceTarget.support,
};

/// **القيمةُ التي يَكتبُها المُحرِّرُ لكلِّ وجهة، واسمُها المعروض.**
///
/// المُحرِّرُ يَبني قائمتَه من هذه الخريطةِ بدلَ تعدادٍ مكتوبٍ بيد، فلا
/// يَعرِضُ وجهةً لا يَقرؤها البنرُ ولا يُغفِلُ وجهةً يَقرؤها: كان يَعرِضُ
/// ستّاً ويَقرأُ السطحانِ **سبعاً** — فخدمةُ المكيّفاتِ مقروءةٌ في
/// الطرفَين ولا يَستطيعُ الأدمنُ أن يُوجِّهَ بنراً إليها («المفتاحُ حاضرٌ
/// والقدرةُ غائبة»، وهو شكلُ `store_audience` بعينِه).
///
/// وكانت للكنبِ والزلِ **خيارانِ** بقيمتَين (`/sofa_cleaning`،
/// `/rug_cleaning`) تَفتحانِ الشاشةَ نفسَها؛ جُمِعا في خيارٍ واحدٍ لأنّ
/// خيارَين لا يَختلفُ أثرُهما فخٌّ لا ميزة — والقيمةُ القديمةُ تَبقى
/// مقروءةً في `kBannerServiceRoutes` لمستنداتِ الإنتاج.
const Map<BannerServiceTarget, ({String route, String label})>
    kBannerTargetOptions = {
  BannerServiceTarget.hourlyCleaning:
      (route: '/hourly_cleaning', label: 'خدمة التنظيف المنزلي'),
  BannerServiceTarget.sofaRug:
      (route: '/sofa_cleaning', label: 'خدمة تنظيف الكنب والزل'),
  BannerServiceTarget.acService:
      (route: '/ac_service', label: 'صيانة وغسيل المكيفات'),
  BannerServiceTarget.subscriptions:
      (route: '/subscriptions', label: 'باقات الاشتراك'),
  BannerServiceTarget.store: (route: '/store', label: 'المتجر'),
  BannerServiceTarget.support: (route: '/support', label: 'الدعم الفني'),
};

/// قيمةُ `routeType` التي تَعني «رابطٌ خارجيٌّ في `actionUrl`».
const String kBannerExternalRoute = 'whatsapp';

/// قيمةُ `routeType` التي تَعني «صورة فقط».
const String kBannerNoRoute = 'none';

/// نصُّ الوجهةِ غيرِ المتاحة — واحدٌ للسطحَين.
const String kBannerUnavailableText = 'هذا الرابط غير متاح حالياً';

/// **هل الرابطُ الخارجيُّ قابلٌ للفتحِ أصلاً؟** رابطٌ بلا مُخطَّطٍ
/// (`wa.me/966…` بدل `https://wa.me/966…`) لا يَفتحُه `launchUrl`، فتُقابَلُ
/// العميلةُ بفشلٍ عن بنرٍ نُشر للتوّ. والقاعدةُ واحدةٌ للمُحرِّرِ ولقارئِ
/// البنر: المُحرِّرُ يَرفُضُ الحفظَ، والقارئُ يَقولُ «غير متاح» بدلَ أن
/// يُحاوِلَ ويَفشلَ برسالةِ عطلٍ عابرٍ لا تَصِف الحال.
bool bannerExternalUrlIsUsable(String? url) {
  final String u = (url ?? '').trim();
  if (u.isEmpty) return false;
  final Uri? parsed = Uri.tryParse(u);
  return parsed != null && parsed.hasScheme && parsed.scheme.isNotEmpty;
}

/// يُصنّفُ ضغطةَ البنر. نقيّةٌ: لا Firestore ولا `BuildContext`.
BannerTap bannerTapOf(Map<String, dynamic>? data) {
  final String routeType = (data?['routeType'] ?? '').toString().trim();
  final String actionUrl = (data?['actionUrl'] ?? '').toString().trim();

  // الغيابُ والفراغُ يُقرآنِ «صورة فقط» كما كان في السطحَين: مستندٌ قديمٌ
  // بلا الحقلِ ليس وجهةً مجهولةً، فلا يُقالُ عنه «غير متاح».
  if (routeType.isEmpty || routeType == kBannerNoRoute) return BannerTap.silent;

  if (routeType == kBannerExternalRoute) {
    if (!bannerExternalUrlIsUsable(actionUrl)) return BannerTap.unavailable;
    return BannerTap._(BannerTapKind.externalUrl, url: actionUrl);
  }

  final BannerServiceTarget? target = kBannerServiceRoutes[routeType];
  if (target != null) {
    return BannerTap._(BannerTapKind.service, service: target);
  }

  return BannerTap.unavailable;
}
