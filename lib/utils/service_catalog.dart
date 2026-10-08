/// كتالوجُ الخدماتِ المعروضةِ على العميلةِ — تسميةً ووصفاً وشارةَ سعرٍ
/// وأيقونةً وصورةً — في موضعٍ واحدٍ لكلِّ سطحٍ يَعرضُه.
///
/// **سببُ وجودِه:** الكتالوجُ كان مكتوباً بيدٍ **مرّتَين** — شبكةُ لوحةِ
/// العميلةِ (`client_dashboard._buildGrid`) وشاشةُ الاستكشافِ قبلَ الدخول
/// (`guest_explore_screen._services`) — فافترقا:
///
///   • **شاشةُ الزائرِ تَعرضُ ستّاً واللوحةُ سبعاً**: «عاملات للمناسبات»
///     غائبةٌ عنها كلّيّاً. وهي السطحُ الذي يَراه **مَن لم يُسجّلْ بعد**، أي
///     الجمهورُ الذي وُجدت الشاشةُ لأجلِه — فخدمةٌ تُباعُ لا يَراها.
///   • **وشارةُ سعرِ المكيفاتِ كانت «حسب الطلب»** — وهي صياغةُ **طلبِ عرضِ
///     السعرِ** الذي أُزيلَ من الجذر: تعليقُ اللوحةِ يَقولُها نصّاً («صارت
///     طلباً مباشراً مسعّراً بدل طلب عرض سعر ينتظر تسعير الإدارة») وشارتُها
///     «سعر لكل مكيف». فزائرةٌ تَقرأُ «حسب الطلب» تَنتظرُ تسعيراً يدويّاً،
///     والشاشةُ خلفَ الضغطةِ تُسعّرُ فوراً لكلِّ وحدة. ومعها الوصفُ
///     («تنظيف وصيانة شاملة» مقابلَ «شباك أو سبليت») والأيقونةُ (مفتاحُ
///     صيانةٍ عامٌّ مقابلَ `ac_unit_rounded`).
///
/// والصياغةُ المُعتمَدةُ هنا هي **صياغةُ اللوحة**: هي المُصحَّحةُ، وتعليقاتُها
/// تَحملُ تعليلَ كلِّ تصحيح. وما يَبقى خاصّاً بكلِّ سطحٍ هو **ودجةُ البطاقةِ
/// وسلوكُ الضغطة** — اللوحةُ تَفتحُ الشاشةَ، وشاشةُ الزائرِ تَطلبُ الدخولَ —
/// فالبياناتُ وحدَها هي ما يُوحَّد.
library;

import 'package:flutter/material.dart';

/// مُعرّفُ الخدمة. `switch` عليه في موضعِ الضغطةِ **شامِلٌ إلزاماً**: خدمةٌ
/// تُضافُ هنا ولا فرعَ لها تُسقِطُ الترجمةَ — لا تَمرُّ بلا وجهة.
enum ZyiarahService {
  hourlyCleaning,
  sofaRug,
  subscriptions,
  acService,
  carInterior,
  eventWorkers,
  store,
}

/// بطاقةُ خدمةٍ في الكتالوج — بياناتٌ لا سلوك.
class ZyiarahServiceCard {
  final ZyiarahService id;
  final String title;
  final String subtitle;

  /// شارةُ السعرِ: نصٌّ لا رقم. كلُّ الأسعارِ تُقرَأُ من مستندِ المنطقةِ أو
  /// من كتالوجِ الباقاتِ، فأيُّ رقمٍ هنا يَبيتُ — وقد باتَ: البطاقةُ كانت
  /// تَحملُ `numericPrice: 50.0` **لا يَقرؤه شيءٌ في جسمِها** والتعليقُ
  /// فوقَها يَقولُ إنّ «من 50 ر.س» لم تَعُدْ تُطابقُ أيَّ سعرٍ خلفَ الضغطة.
  final String priceLabel;

  final Color themeColor;
  final Color iconBgColor;
  final IconData icon;
  final String imagePath;

  const ZyiarahServiceCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceLabel,
    required this.themeColor,
    required this.iconBgColor,
    required this.icon,
    required this.imagePath,
  });
}

/// الكتالوجُ بترتيبِ العرض.
const List<ZyiarahServiceCard> kServiceCatalog = [
  ZyiarahServiceCard(
    id: ZyiarahService.hourlyCleaning,
    title: 'تنظيف منزلي',
    // (باقات السكن) البطاقة تعكس المنتج الجديد: باقة بنوع السكن وعدد
    // الكوادر — لا ساعات ولا «من 50 ر.س» التي لم تعد تطابق أي سعر خلف الضغطة.
    subtitle: 'باقة حسب نوع سكنك وعدد الكوادر',
    priceLabel: 'حسب الباقة',
    themeColor: Color(0xFF10B981),
    iconBgColor: Color(0xFFE1F0E4),
    icon: Icons.access_time_filled,
    imagePath: 'assets/images/hourly_cleaning.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.sofaRug,
    title: 'تنظيف الكنب والزل',
    subtitle: 'تنظيف عميق بالبخار',
    priceLabel: 'حسب المتر',
    themeColor: Color(0xFF8B5CF6),
    iconBgColor: Color(0xFFF1E9FE),
    icon: Icons.chair,
    imagePath: 'assets/images/sofa_cleaning.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.subscriptions,
    title: 'باقات الاشتراك',
    // «زيارات مجدولة» بلا «شهرية»: مدّةُ الباقةِ من الكتالوجِ لا ثابتةٌ هنا.
    subtitle: 'زيارات مجدولة',
    priceLabel: 'باقات شهرية',
    themeColor: Color(0xFF10B981),
    iconBgColor: Color(0xFFE1F0E4),
    icon: Icons.workspace_premium,
    imagePath: 'assets/images/monthly_cleaning.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.acService,
    title: 'صيانة وغسيل المكيفات',
    // صارت طلباً مباشراً مسعّراً بدل طلب عرض سعر ينتظر تسعير الإدارة —
    // فلا «حسب الطلب» ولا مفتاحُ صيانةٍ عامّ.
    subtitle: 'شباك أو سبليت',
    priceLabel: 'سعر لكل مكيف',
    themeColor: Color(0xFF475569),
    iconBgColor: Color(0xFFF1F5F9),
    icon: Icons.ac_unit_rounded,
    imagePath: 'assets/images/company_cleaning.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.carInterior,
    title: 'تنظيف داخلية السيارة',
    subtitle: 'مراتب وأسقف السيارة',
    priceLabel: 'حسب حجم السيارة',
    themeColor: Color(0xFF0E7490),
    iconBgColor: Color(0xFFE0F2FE),
    icon: Icons.directions_car_filled_rounded,
    imagePath: 'assets/images/car_cleaning.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.eventWorkers,
    title: 'عاملات للمناسبات',
    subtitle: 'باقات جاهزة بأسعار ثابتة',
    priceLabel: 'باقات مسبقة الإعداد',
    themeColor: Color(0xFF9333EA),
    iconBgColor: Color(0xFFF3E8FF),
    icon: Icons.celebration_rounded,
    imagePath: 'assets/images/event_workers.png',
  ),
  ZyiarahServiceCard(
    id: ZyiarahService.store,
    title: 'متجر المنظفات',
    subtitle: 'أدوات احترافية',
    priceLabel: 'عروض حصرية',
    themeColor: Color(0xFF660033),
    iconBgColor: Color(0xFFFCEEFA),
    icon: Icons.storefront,
    imagePath: 'assets/images/store.png',
  ),
];
