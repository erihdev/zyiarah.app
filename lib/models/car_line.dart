/// بند تنظيف داخلية السيارة: حجم (صغيرة/وسط/كبيرة) × عدد.
///
/// ثلاثة أسعار تحدّدها الإدارة لكل منطقة (مثل المكيفات تماماً)، والعميل يختار
/// أحجاماً وأعداداً في طلب واحد — «نوع السيارة صغيرة وسط كبيرة ولها سعر
/// يتحكمون بها» (قرار المالك 2026-07-18).
enum CarSize { small, medium, large }

extension CarSizeX on CarSize {
  String get label => switch (this) {
        CarSize.small => 'صغيرة',
        CarSize.medium => 'وسط',
        CarSize.large => 'كبيرة',
      };

  String get key => name;
}

/// مفتاح السعر في مستند المنطقة — يطابق حقول شاشة «نطاقات التغطية» حرفياً.
/// مصدر واحد للاسم (درس المكيفات): اختلاف حرف = قراءة حقل غير موجود ⇒ سعر
/// صفر ⇒ خدمة تبدو معطّلة بلا سبب ظاهر.
String carPriceField(CarSize size) => switch (size) {
      CarSize.small => 'carSmallPrice',
      CarSize.medium => 'carMediumPrice',
      CarSize.large => 'carLargePrice',
    };

class CarLine {
  final CarSize size;
  final int count;

  const CarLine({required this.size, this.count = 1});

  String get label => 'سيارة ${size.label}';

  double lineTotal(double unitPrice) => unitPrice * count;

  /// يُكتب في `service_meta` على الطلب — بدونه يصل السائق ولا يعرف كم سيارة
  /// يخدم ولا حجمها، والإدارة لا تملك ما تدقّق به المبلغ.
  Map<String, dynamic> toMap(double unitPrice) => {
        'size': size.key,
        'label': label,
        'count': count,
        'unit_price': unitPrice,
        'line_total': double.parse(lineTotal(unitPrice).toStringAsFixed(2)),
      };
}
