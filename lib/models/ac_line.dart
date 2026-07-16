/// بند مكيفات: عمل (صيانة/غسيل) × نوع (شباك/سبليت) × عدد.
///
/// أربعة أسعار تحدّدها الإدارة لكل منطقة، والعميلة تختار أنواعاً وأعداداً مختلفة في
/// طلب واحد («نعم السعر لكل مكيف ويقدر يختار عدد المكيفات وانواعها»).
enum AcJob { maintenance, wash }

enum AcUnitType { window, split }

extension AcJobX on AcJob {
  String get label => this == AcJob.maintenance ? 'صيانة' : 'غسيل';
  String get key => this == AcJob.maintenance ? 'maintenance' : 'wash';
}

extension AcUnitTypeX on AcUnitType {
  String get label => this == AcUnitType.window ? 'شباك' : 'سبليت';
  String get key => this == AcUnitType.window ? 'window' : 'split';
}

/// مفتاح السعر في مستند المنطقة — يطابق حقول شاشة «نطاقات التغطية» حرفياً.
/// مصدر واحد للاسم: أي اختلاف حرف هنا يعني قراءة حقل غير موجود ⇒ سعر صفر ⇒
/// خدمة تبدو معطّلة بلا سبب ظاهر.
String acPriceField(AcJob job, AcUnitType type) {
  final j = job == AcJob.maintenance ? 'Maint' : 'Wash';
  final t = type == AcUnitType.window ? 'Window' : 'Split';
  return 'ac$j${t}Price';
}

class AcLine {
  final AcJob job;
  final AcUnitType type;
  final int count;

  const AcLine({required this.job, required this.type, this.count = 1});

  String get label => '${job.label} ${type.label}';

  double lineTotal(double unitPrice) => unitPrice * count;

  AcLine copyWith({AcJob? job, AcUnitType? type, int? count}) => AcLine(
        job: job ?? this.job,
        type: type ?? this.type,
        count: count ?? this.count,
      );

  /// يُكتب في `service_meta` على الطلب — بدونه يصل السائق ولا يعرف كم مكيفاً يخدم
  /// ولا نوعه، والإدارة لا تملك ما تدقّق به المبلغ.
  Map<String, dynamic> toMap(double unitPrice) => {
        'job': job.key,
        'type': type.key,
        'label': label,
        'count': count,
        'unit_price': unitPrice,
        'line_total': double.parse(lineTotal(unitPrice).toStringAsFixed(2)),
      };
}
