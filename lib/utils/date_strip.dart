// شريط التواريخ الأفقي (٣٠ يوماً يبدأ من الغد) في شاشات الحجز الثلاث:
// `hourly_details_screen` و`subscription_plans_screen`
// و`event_worker_packages_screen`.
//
// **لماذا يوجد هذا الملف:** الشاشات الثلاث تنقل الاختيار تلقائياً إلى أوّل
// يومٍ متاح (اليوم المختار مغلقٌ بجدول المنطقة أو ممتلئ، أو مدّة الباقة
// تغيّرت فأفقدته سائقه)، والشريط كان `ListView` بلا `ScrollController` —
// فيبقى عند أوّل العناصر بينما الاختيار قد ينتقل إلى الفهرس ٢٩. النتيجة
// التي صوّرها مختبِر فعلاً: جدولُ منطقة يفتح السبت فقط ⇒ الاختيار ينتقل إلى
// الفهرس ٥ (السبت)، والشريط يعرض الاثنين…الجمعة مغلقةً رماديّة ويقتطع
// البطاقة المختارة عند حرف الشاشة — فيرى العميل صفَّ أيامٍ لا يملك منها
// شيئاً، بلا اختيارٍ ظاهر، والملخّص أسفلَه يذكر تاريخاً لا يراه.
//
// الحساب هنا لا في الشاشات لأنّه حسابٌ خالص يُختبَر دون Firebase: الشاشات
// الثلاث تنسخ البطاقة نفسها (عرض ٥٨ + هامش ٥ على كلّ جانب)، فلو بقي الحساب
// في كلٍّ منها لصار ثلاث نسخ تتباعد — كما تباعدت نسخُ قواعد أخرى في هذا
// المستودع قبلها.

/// عرض بطاقة اليوم الكامل: `width: 58` + `margin: horizontal 5` في الشاشات الثلاث.
const double kDateStripItemExtent = 68.0;

/// عدد أيام الشريط (`itemCount: 30`) — يبدأ من الغد، فلا حجزَ في اليوم نفسه.
const int kDateStripDays = 30;

/// إزاحةُ التمرير التي تُظهر بطاقة [index] في وسط الشريط.
///
/// الإزاحة **منطقية لا بصرية**: الصفر عند أوّل عنصرٍ في اتجاه القراءة، فيصحّ
/// الحساب في RTL كما في LTR (الشاشات الثلاث كلّها داخل `Directionality.rtl`).
///
/// [maxOffset] يأتي من `position.maxScrollExtent` لا من حسابٍ هندسيّ، فالتخطيط
/// الفعليّ هو الذي يحدّ الإزاحة؛ ويُقصّ الناتج داخل `[0, maxOffset]` فلا يرتدّ
/// الشريط (overscroll) عند أوّل العناصر ولا عند آخرها.
double dateStripOffsetFor({
  required int index,
  required double viewportWidth,
  required double maxOffset,
  double itemExtent = kDateStripItemExtent,
}) {
  if (index <= 0 || viewportWidth <= 0 || maxOffset <= 0) return 0;
  final double centered = (index + 0.5) * itemExtent - viewportWidth / 2;
  return centered.clamp(0.0, maxOffset);
}

/// فهرس [date] في الشريط، أو `-1` إن كان خارجه.
///
/// البطاقة عند الفهرس `i` هي `now + (i + 1)` يوماً، فاليوم نفسه و«الأمس» خارج
/// الشريط. المقارنة بالتاريخ لا باللحظة: المرساة منتصفُ النهار لا منتصفُ
/// الليل، فلا يُزحزح الفهرسَ فرقُ ساعةٍ في تغيير توقيتٍ صيفيّ.
int dateStripIndexOf(
  DateTime date,
  DateTime now, {
  int itemCount = kDateStripDays,
}) {
  final DateTime d = DateTime(date.year, date.month, date.day, 12);
  final DateTime n = DateTime(now.year, now.month, now.day, 12);
  final int i = d.difference(n).inDays - 1;
  return (i >= 0 && i < itemCount) ? i : -1;
}
