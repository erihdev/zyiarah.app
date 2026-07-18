/// الأسعار الافتراضية للخدمات المسعَّرة لكل منطقة (service_zones).
///
/// مصدر واحد للحقيقة: تُستخدم في شاشة مناطق التغطية (إضافة/تعديل) وفي بذر المناطق
/// الافتراضية. الإدارة تعدّلها لكل منطقة على حدة؛ هذه القيم مجرد نقطة بداية تعمل فوراً
/// كي لا تظهر منطقة جديدة بلا سعر.
///
/// ملاحظة: هذه أسعار **شاملة ضريبة القيمة المضافة 15%** (كبقية أسعار التطبيق).
library;

/// سعر المتر المربع لغسيل الكنب (ر.س/م²).
const double kDefaultSofaSqmPrice = 35.0;

/// سعر المتر المربع لغسيل السجاد/الزل (ر.س/م²).
const double kDefaultRugSqmPrice = 15.0;

/// سعر صيانة مكيف شباك — لكل مكيف (ر.س).
const double kDefaultAcMaintWindowPrice = 100.0;

/// سعر صيانة مكيف سبليت — لكل مكيف (ر.س).
const double kDefaultAcMaintSplitPrice = 150.0;

/// سعر غسيل مكيف شباك — لكل مكيف (ر.س).
const double kDefaultAcWashWindowPrice = 80.0;

/// سعر غسيل مكيف سبليت — لكل مكيف (ر.س).
const double kDefaultAcWashSplitPrice = 120.0;

/// تنظيف داخلية السيارة (مراتب وأسقف) — لكل سيارة حسب حجمها (ر.س).
const double kDefaultCarSmallPrice = 100.0;
const double kDefaultCarMediumPrice = 150.0;
const double kDefaultCarLargePrice = 200.0;
