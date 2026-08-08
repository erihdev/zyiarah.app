import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// قرار المالك (2026-08-08): **كل سعر يراه العميل قبل الضريبة**، ولا يرى المبلغ
/// شامل الضريبة إلا في «تفاصيل الفاتورة» بشاشة إتمام الطلب.
///
/// هذه الحارسة تمنع رجوع الضريبة إلى شاشات الاختيار: كانت كل شاشة تفاصيل تعرض
/// «المجموع الفرعي + ضريبة 15% + الإجمالي المطلوب» قبل الوصول للدفع، وباقات
/// السكن كانت تعرض `grossPrice` (الأساس × 1.15) على البطاقات.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// نصّ الشاشة بلا تعليقات: التعليقات تشرح أن المبلغ المُمرَّر «شامل الضريبة»،
  /// وبدون تجريدها تلتقط الحارسة شرحاً لا نصّ واجهة فتفشل بلا سبب حقيقي.
  String uiOnly(String p) => read(p)
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// شاشات اختيار الخدمة — يراها العميل **قبل** إتمام الطلب.
  const selectionScreens = [
    'lib/screens/ac_service_details_screen.dart',
    'lib/screens/car_interior_details_screen.dart',
    'lib/screens/sofa_rug_details_screen.dart',
    'lib/screens/store_schedule_screen.dart',
    'lib/screens/hourly_details_screen.dart',
  ];

  group('شاشات الاختيار لا تعرض ضريبة ولا إجمالياً شاملاً', () {
    for (final path in selectionScreens) {
      test(path, () {
        final s = uiOnly(path);
        expect(s.contains('ضريبة القيمة المضافة (15%)'), isFalse,
            reason: 'صفّ الضريبة مكانه تفاصيل الفاتورة لا شاشة الاختيار');
        expect(s.contains('الإجمالي شامل الضريبة'), isFalse);
        expect(s.contains('الإجمالي المطلوب'), isFalse,
            reason: 'عنوان يوحي بمبلغ نهائي شامل الضريبة');
        expect(s.contains('الإجمالي قبل الضريبة'), isTrue,
            reason: 'العنوان الصريح الذي يفهمه العميل');
        expect(s.contains('تُضاف ضريبة القيمة المضافة 15% عند إتمام الطلب'),
            isTrue,
            reason: 'تنويه واضح كي لا يُفاجأ العميل بالفرق عند الدفع');
      });
    }
  });

  test('باقات السكن تُعرض بسعر الأساس لا grossPrice', () {
    final s = read('lib/screens/hourly_details_screen.dart');
    expect(s.contains('formatSar(opt.basePrice)'), isTrue);
    expect(s.contains('formatSar(opt.grossPrice)'), isFalse,
        reason: 'grossPrice يُدفع ولا يُعرض');
  });

  test('المبلغ المُمرَّر للدفع يبقى شاملاً الضريبة', () {
    // الحارسة المقابلة: تغيير **العرض** يجب ألا يُنقص ما يُشحن فعلاً — شاشة الدفع
    // تشتقّ الأساس بقسمة الإجمالي على 1.15، فتمرير مبلغ بلا ضريبة يخصم أقل.
    expect(read('lib/screens/hourly_details_screen.dart')
        .contains('amount: grandTotal'), isTrue);
    expect(read('lib/screens/sofa_rug_details_screen.dart')
        .contains('amount: grandTotal'), isTrue);
    expect(read('lib/utils/home_packages.dart')
        .contains('basePrice * 1.15'), isTrue);
  });

  test('تفاصيل الفاتورة وحدها تعرض الضريبة والإجمالي', () {
    final pay = read('lib/screens/payment_summary_screen.dart');
    expect(pay.contains("_buildRowDetail('المبلغ الأساسي'"), isTrue);
    expect(pay.contains("_buildRowDetail('الضريبة (15%)'"), isTrue);
    expect(pay.contains('totalWithVat / 1.15'), isTrue,
        reason: 'الأساس يُشتقّ من الإجمالي المشحون');
  });
}
