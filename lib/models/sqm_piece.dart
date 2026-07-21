/// قطعة تُسعَّر حسب نوعها:
/// - **الكنب**: بالمتر **الطولي** — السعر = الطول × سعر المتر الطولي (العرض لا يدخل).
/// - **السجاد**: بالمتر **المربع** — السعر = الطول × العرض × سعر المتر المربع.
///
/// قرار المزوّد (نوهل): «الطول عند الكنب يُحسب متر طولي لا متر مربع، والزل يُحسب
/// الطول في العرض». قبل ذلك كان النوعان يُسعَّران بالمساحة معاً — فكان الكنب يُحاسَب
/// على مساحته لا طوله. هذا الملف مصدر الحقيقة الوحيد لحسبة القطعة.
enum SqmPieceKind { sofa, rug }

extension SqmPieceKindX on SqmPieceKind {
  String get label => this == SqmPieceKind.sofa ? 'كنب' : 'سجاد';

  /// المفتاح المخزَّن في الطلب — إنجليزي ثابت كي لا تكسره ترجمة أو تغيير نص واجهة.
  String get key => this == SqmPieceKind.sofa ? 'sofa' : 'rug';

  /// السجاد يُسعَّر بالمساحة (م²)؛ الكنب بالطول (متر طولي).
  bool get usesArea => this == SqmPieceKind.rug;

  /// وحدة التسعير للعرض النصّي.
  String get unitLabel => usesArea ? 'متر مربع' : 'متر طولي';
  String get unitShort => usesArea ? 'م²' : 'م.ط';
}

class SqmPiece {
  final SqmPieceKind kind;

  /// بالأمتار. صفر = لم يُدخَل بعد (لا يُحتسب ولا يمنع الإرسال بذاته).
  final double length;
  final double width;

  const SqmPiece({required this.kind, this.length = 0, this.width = 0});

  /// مساحة القطعة (تُستخدم للسجاد وللإحصاء). للكنب لا تدخل التسعير.
  double get area => length * width;

  /// المقدار الخاضع للتسعير: مساحة (م²) للسجاد، طول (متر طولي) للكنب.
  double get billedMeasure => kind.usesArea ? area : length;

  /// الكنب يكتمل بالطول وحده؛ السجاد يحتاج الطول والعرض.
  bool get isComplete => kind.usesArea ? (length > 0 && width > 0) : length > 0;

  /// السعر = المقدار الخاضع للتسعير × سعر الوحدة.
  double priceWith(double rate) => billedMeasure * rate;

  SqmPiece copyWith({SqmPieceKind? kind, double? length, double? width}) =>
      SqmPiece(
        kind: kind ?? this.kind,
        length: length ?? this.length,
        width: width ?? this.width,
      );

  /// يُكتب داخل `service_meta` على الطلب كي تعرف الإدارة والسائق التفصيل بالضبط —
  /// الطلب القديم كان يصل بمبلغ مجرّد بلا بيان.
  Map<String, dynamic> toMap(double rate) => {
        'kind': kind.key,
        'label': kind.label,
        'length_m': length,
        // العرض للسجاد فقط؛ يبقى 0 للكنب (لا يدخل حسبته).
        'width_m': width,
        'uses_area': kind.usesArea,
        'unit': kind.unitLabel,
        'billed_measure': double.parse(billedMeasure.toStringAsFixed(2)),
        'area_sqm': double.parse(area.toStringAsFixed(2)),
        'price_per_unit': rate,
        'line_total': double.parse(priceWith(rate).toStringAsFixed(2)),
      };
}
