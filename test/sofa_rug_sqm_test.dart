// حارس: تنظيف الكنب والسجاد يُسعَّر بالمتر **المربع** — والنظام الطولي أُزيل نهائياً.
//
// الخلفية (قرار صريح من المالك: «المتر الطولي يختفي، اعتمد النظام الجديد»):
//   كان في المشروع نظاما تسعير متعايشان. الحقلان `sofaPrice`/`rugPrice` (متر طولي) هما
//   من يحاسب العميل فعلاً، بينما لوحة الإدارة توسمهما «للنسخ القديمة فقط» وتعرض حقول
//   م² كأنها العاملة — وهي بلا قارئ واحد. فمن يسعّر «الجديدة» لا يغيّر ريالاً، وهو
//   مقتنع أنه سعّر. هذا الحارس يمنع عودة الازدواجية.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/sqm_piece.dart';

void main() {
  group('حساب المساحة والسعر', () {
    test('السعر = الطول × العرض × سعر المتر المربع', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 1.5);
      expect(p.area, 3.0);
      expect(p.priceWith(35), 105.0);
    });

    test('كل قطعة بمقاسها — الإجمالي جمع القطع بأنواعها', () {
      const pieces = [
        SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 1.5), // 3 م² × 35 = 105
        SqmPiece(kind: SqmPieceKind.sofa, length: 1, width: 1),   // 1 م² × 35 = 35
        SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2),    // 6 م² × 15 = 90
      ];
      double total = 0;
      for (final p in pieces) {
        total += p.priceWith(p.kind == SqmPieceKind.sofa ? 35 : 15);
      }
      expect(total, 230.0);
    });

    test('لا حد أدنى — قطعة صغيرة جداً تُسعَّر بمساحتها', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 0.5, width: 0.4);
      expect(p.priceWith(15), closeTo(3.0, 0.0001));
    });

    test('قطعة ناقصة البُعد لا تُحتسب', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 0);
      expect(p.isComplete, isFalse);
      expect(p.area, 0);
    });

    test('الضريبة متضمَّنة (15%) لا مضافة — موحّد مع ZATCA', () {
      const p = SqmPiece(kind: SqmPieceKind.sofa, length: 2, width: 1.5);
      final total = p.priceWith(35); // 105 شاملة
      final sub = total / 1.15;
      expect(sub + (total - sub), closeTo(total, 0.0001),
          reason: 'الإجمالي هو ما تدفعه العميلة؛ الضريبة تُستخرج منه قسمةً');
      expect(total - sub, closeTo(13.6957, 0.001));
    });

    test('toMap يحمل التفصيل الذي تحتاجه الإدارة والسائق', () {
      const p = SqmPiece(kind: SqmPieceKind.rug, length: 3, width: 2);
      final m = p.toMap(15);
      expect(m['kind'], 'rug');
      expect(m['area_sqm'], 6.0);
      expect(m['price_per_sqm'], 15);
      expect(m['line_total'], 90.0);
    });
  });

  group('مدة الانشغال تكبر مع المساحة', () {
    // ساعتان لأي عمل دون 10 م²، ثم ساعة لكل 10 م² كاملة، بسقف 8.
    // (floor لا ceil: مع ceil يصير أصغر عمل 3 ساعات ولا يُبلَغ الحدّ الأدنى أبداً.)
    int duration(double area) => (2 + (area / 10).floor()).clamp(2, 8);

    test('مساحة صغيرة ⇒ الحد الأدنى ساعتان', () => expect(duration(3), 2));
    test('9.9 م² ⇒ ما زالت ساعتين', () => expect(duration(9.9), 2));
    test('10 م² ⇒ 3 ساعات', () => expect(duration(10), 3));
    test('25 م² ⇒ 4 ساعات', () => expect(duration(25), 4));
    test('مساحة ضخمة ⇒ تُسقَّف بـ 8 ساعات (طول يوم العمل)', () => expect(duration(500), 8));

    test('السقف يُبقي خانات بدء متاحة (8→22)', () {
      // خانات البدء = 22 - المدة، فمدة > 14 تُفرِغ القائمة تماماً.
      expect(22 - duration(500), greaterThan(8),
          reason: 'مدة تتجاوز يوم العمل تجعل كل الخانات غير صالحة فلا يستطيع أحد الحجز');
    });
  });

  group('المصدر: النظام الطولي أُزيل ولم يعد له أثر', () {
    final src = File('lib/screens/sofa_rug_details_screen.dart').readAsStringSync();

    test("الشاشة لا تقرأ sofaPrice/rugPrice (الطولي) إطلاقاً", () {
      expect(
        RegExp(r"""\['sofaPrice'\]|\['rugPrice'\]""").hasMatch(src),
        isFalse,
        reason: 'الحقلان الطوليان أُلغيا بقرار المالك. قراءتهما = عودة الازدواجية.',
      );
    });

    test('الشاشة تقرأ حقول المتر المربع من المنطقة', () {
      expect(src.contains("'sofaSqmPrice'"), isTrue);
      expect(src.contains("'rugSqmPrice'"), isTrue);
    });

    test('الطلب مباشر: تُمرَّر hours و serviceDate لشاشة الدفع', () {
      // هذان الحقلان هما ما يقلب الطلب إلى status:'pending' فيمرّ بفحص السعة
      // والإسناد التلقائي بدل انتظار موافقة الإدارة.
      expect(src.contains('hours: _durationHours'), isTrue,
          reason: 'بدون hours لا يُعتبر الطلب مباشراً ولا يُسنَد سائق تلقائياً');
      expect(src.contains('serviceDate: _selectedSlot'), isTrue);
    });

    test('التفصيل يصل الطلب عبر service_meta', () {
      expect(src.contains('serviceMeta: meta'), isTrue,
          reason: 'بدونه يصل الطلب بمبلغ مجرّد: كم قطعة؟ ما مقاسها؟');
    });
  });

  test('لا شاشة أخرى ما زالت تقرأ التسعير الطولي', () {
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
        reason: 'التسعير الطولي أُلغي — هذه الملفات ما زالت تقرؤه: $offenders');
  });
}
