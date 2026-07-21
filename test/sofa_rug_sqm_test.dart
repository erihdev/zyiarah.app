// حارس: الكنب يُسعَّر بالمتر **الطولي** (الطول فقط)، والسجاد بالمتر **المربع**
// (الطول × العرض). قرار المزوّد (نوهل): «الطول عند الكنب يُحسب متر طولي لا متر مربع،
// والزل يُحسب الطول في العرض». قبل ذلك كان النوعان يُسعَّران بالمساحة معاً — فيُحاسَب
// الكنب على مساحته لا طوله. هذا الحارس يمنع عودة تسعير الكنب بالمساحة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/sqm_piece.dart';

void main() {
  group('حساب الكنب — بالمتر الطولي (الطول فقط)', () {
    test('السعر = الطول × سعر المتر الطولي (العرض لا يدخل)', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 1.5);
      // العرض 1.5 موجود لكنه لا يؤثّر: 2 × 27 = 54 (لا 3 م² × 27 = 81).
      expect(p.billedMeasure, 2.0);
      expect(p.priceWith(27), 54.0);
    });

    test('الكنب يكتمل بالطول وحده — بلا حاجة لعرض', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2);
      expect(p.isComplete, isTrue);
      expect(p.priceWith(27), 54.0);
    });

    test('كنب بلا طول لا يُحتسب', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 0, width: 2);
      expect(p.isComplete, isFalse);
      expect(p.billedMeasure, 0);
    });
  });

  group('حساب السجاد — بالمتر المربع (الطول × العرض)', () {
    test('السعر = الطول × العرض × سعر المتر المربع', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2);
      expect(p.area, 6.0);
      expect(p.billedMeasure, 6.0);
      expect(p.priceWith(12), 72.0);
    });

    test('السجاد يحتاج الطول والعرض معاً', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 0);
      expect(p.isComplete, isFalse);
      expect(p.area, 0);
    });

    test('لا حد أدنى — سجادة صغيرة تُسعَّر بمساحتها', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 0.5, width: 0.4);
      expect(p.priceWith(12), closeTo(2.4, 0.0001));
    });
  });

  test('الإجمالي = جمع القطع بأنواعها (كنب طولي + سجاد مساحي)', () {
    const pieces = [
      SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 1.5), // 2 م.ط × 27 = 54
      SqmPiece(kind: SqmPieceKind.sofa, length: 1), //             1 م.ط × 27 = 27
      SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2), //    6 م²  × 12 = 72
    ];
    double total = 0;
    for (final p in pieces) {
      total += p.priceWith(p.kind == SqmPieceKind.sofa ? 27 : 12);
    }
    expect(total, 153.0);
  });

  test('سعر القطعة أساسٌ قبل الضريبة — الضريبة تُضاف 15% عند الدفع', () {
    const p = SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2);
    final base = p.priceWith(12); // 72 أساس (قبل الضريبة)
    final withVat = base * 1.15; // ما يدفعه العميل بعد إضافة الضريبة
    expect(base, 72.0);
    expect(withVat, closeTo(82.8, 0.0001));
  });

  group('toMap يحمل التفصيل الذي تحتاجه الإدارة والسائق', () {
    test('السجاد: مساحة + وحدة متر مربع', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2);
      final m = p.toMap(12);
      expect(m['kind'], 'rug');
      expect(m['uses_area'], isTrue);
      expect(m['unit'], 'متر مربع');
      expect(m['billed_measure'], 6.0);
      expect(m['price_per_unit'], 12);
      expect(m['line_total'], 72.0);
    });

    test('الكنب: طول + وحدة متر طولي (العرض لا يدخل الإجمالي)', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2);
      final m = p.toMap(27);
      expect(m['kind'], 'sofa');
      expect(m['uses_area'], isFalse);
      expect(m['unit'], 'متر طولي');
      expect(m['billed_measure'], 2.0);
      expect(m['price_per_unit'], 27);
      expect(m['line_total'], 54.0);
    });
  });

  group('مدة الانشغال تكبر مع حجم العمل', () {
    // ساعتان لأي عمل صغير، ثم ساعة لكل 10 وحدات، بسقف 8.
    int duration(double work) => (2 + (work / 10).floor()).clamp(2, 8);

    test('عمل صغير ⇒ الحد الأدنى ساعتان', () => expect(duration(3), 2));
    test('9.9 ⇒ ما زالت ساعتين', () => expect(duration(9.9), 2));
    test('10 ⇒ 3 ساعات', () => expect(duration(10), 3));
    test('25 ⇒ 4 ساعات', () => expect(duration(25), 4));
    test('حجم ضخم ⇒ يُسقَّف بـ 8 ساعات (طول يوم العمل)', () => expect(duration(500), 8));
  });

  group('المصدر: الكنب طولي والسجاد مساحي في الشاشة', () {
    final src =
        File('lib/screens/sofa_rug_details_screen.dart').readAsStringSync();

    test('الشاشة لا تقرأ sofaPrice/rugPrice (الطولي القديم بالعدّاد) إطلاقاً', () {
      expect(
        RegExp(r"""\['sofaPrice'\]|\['rugPrice'\]""").hasMatch(src),
        isFalse,
        reason: 'التسعير الطولي القديم بالعدّاد أُلغي بقرار المالك.',
      );
    });

    test('الشاشة تقرأ حقول السعر من المنطقة', () {
      expect(src.contains("'sofaSqmPrice'"), isTrue);
      expect(src.contains("'rugSqmPrice'"), isTrue);
    });

    test('الطلب مباشر: تُمرَّر hours و serviceDate لشاشة الدفع', () {
      expect(src.contains('hours: _durationHours'), isTrue,
          reason: 'بدون hours لا يُعتبر الطلب مباشراً ولا يُسنَد سائق تلقائياً');
      expect(src.contains('serviceDate: _selectedSlot'), isTrue);
    });

    test('بطاقة «كيف يُحسب السعر؟» تشرح قاعدتَي الطولي والمربع', () {
      expect(src.contains('كيف يُحسب السعر؟'), isTrue);
      expect(src.contains('سعر المتر الطولي'), isTrue,
          reason: 'الكنب يُشرَح بالمتر الطولي (الطول فقط)');
      expect(src.contains('سعر المتر المربع'), isTrue,
          reason: 'السجاد يُشرَح بالمتر المربع (الطول × العرض)');
      expect(src.contains('متر طولي'), isTrue);
    });

    test('التفصيل يصل الطلب عبر service_meta', () {
      expect(src.contains('serviceMeta: meta'), isTrue,
          reason: 'بدونه يصل الطلب بمبلغ مجرّد: كم قطعة؟ ما مقاسها؟');
    });
  });

  test('لا شاشة أخرى ما زالت تقرأ التسعير الطولي القديم', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      if (RegExp(r"""\['sofaPrice'\]|\['rugPrice'\]""").hasMatch(s)) {
        offenders.add(f.path.replaceAll(r'\', '/'));
      }
    }
    expect(offenders, isEmpty,
        reason: 'التسعير الطولي القديم أُلغي — هذه الملفات ما زالت تقرؤه: $offenders');
  });
}
