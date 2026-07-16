/// قطعة تُسعَّر بالمتر المربع (كنبة أو سجادة) — كل قطعة بمقاسها.
///
/// حلّت محلّ التسعير بالمتر الطولي القديم (`sofaPrice`/`rugPrice` وعدّاد + و −) الذي
/// كان يسأل عن «عدد الأمتار» بلا معنى هندسي. الآن: الطول × العرض = المساحة، والمساحة
/// × سعر المتر المربع للنوع = السعر. **لا حد أدنى.**
enum SqmPieceKind { sofa, rug }

extension SqmPieceKindX on SqmPieceKind {
  String get label => this == SqmPieceKind.sofa ? 'كنب' : 'سجاد';

  /// المفتاح المخزَّن في الطلب — إنجليزي ثابت كي لا تكسره ترجمة أو تغيير نص واجهة.
  String get key => this == SqmPieceKind.sofa ? 'sofa' : 'rug';
}

class SqmPiece {
  final SqmPieceKind kind;

  /// بالأمتار. صفر = لم تُدخَل بعد (لا تُحتسب ولا تمنع الإرسال بذاتها).
  final double length;
  final double width;

  const SqmPiece({required this.kind, this.length = 0, this.width = 0});

  double get area => length * width;

  bool get isComplete => length > 0 && width > 0;

  double priceWith(double pricePerSqm) => area * pricePerSqm;

  SqmPiece copyWith({SqmPieceKind? kind, double? length, double? width}) => SqmPiece(
        kind: kind ?? this.kind,
        length: length ?? this.length,
        width: width ?? this.width,
      );

  /// يُكتب داخل `service_meta` على الطلب كي تعرف الإدارة والسائق ما المطلوب بالضبط —
  /// الطلب القديم كان يصل بمبلغ مجرّد بلا تفصيل.
  Map<String, dynamic> toMap(double pricePerSqm) => {
        'kind': kind.key,
        'label': kind.label,
        'length_m': length,
        'width_m': width,
        'area_sqm': double.parse(area.toStringAsFixed(2)),
        'price_per_sqm': pricePerSqm,
        'line_total': double.parse(priceWith(pricePerSqm).toStringAsFixed(2)),
      };
}
