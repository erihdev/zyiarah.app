// حارس دائم: **تابي محذوف من الجذور** — لا يعود، ولو بسطر واحد.
//
// قرار المالك 2026-09-30: «أنا لا أستخدم تابي، أستخدم فقط تمارا وهي المفعّلة
// في التطبيق». الخيار لم يكن يظهر للعميل أصلاً (لا مفتاح فعّال)، لكن SDK كان
// يُقلَع قبل runApp وكل مسار الشراء كان حيّاً تحت الواجهة — ميزة بلا باب، كما
// كان الدفع عند الاستلام قبل حذفه (انظر no_cod_test.dart).
//
// ما يبقى **عمداً** إلى مرحلة ثانية: tabbyWebhook وtabbyRefundPayment في
// functions/index.js، وفروع *عرض* الطلبات القديمة (invoice_view.dart، شاشات
// الإدارة، Orders.tsx). طلبات مدفوعة بتابي قد تكون قائمة وفواتيرها ZATCA صادرة؛
// حذف الاسترجاع يترك عميلاً بلا طريق، وحذف العرض يكسر فواتير. لذلك يمنع الحارس
// **اختيار** تابي وإقلاعه وحزمته ومفتاحه — لا ذكر اسمه في تسمية طريقة دفع قديمة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'helpers/sources_in.dart';

/// يزيل التعليقات: التعليقات هنا **تشرح ما حُذف**، ففحص المصدر الخام يسقط الحارس
/// على شرحه هو — إنذار كاذب يدفع لتعطيل الحارس فيصير أسوأ من لا شيء.
String _code(String path) {
  final src = File(path).readAsStringSync();
  return src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i == -1 ? l : l.substring(0, i);
      })
      .join('\n');
}

List<File> _dart(String dir) =>
    sourcesIn(dir, atLeast: dir == 'lib' ? 100 : 1);

void main() {
  test('لا حزمة، لا خدمة، لا مفتاح', () {
    expect(File('pubspec.yaml').readAsStringSync().contains('tabby_flutter_inapp_sdk'),
        isFalse, reason: 'حزمة تابي عادت إلى pubspec.yaml');
    expect(File('lib/services/tabby_service.dart').existsSync(), isFalse,
        reason: 'خدمة تابي عادت');
    expect(File('codemagic.yaml').readAsStringSync().contains('TABBY_PUBLIC_KEY'),
        isFalse, reason: 'مفتاح تابي يُحقن في .env من جديد');
  });

  test('لا كود في lib/ يُقلع تابي أو يعرضه خياراً للدفع', () {
    // اسم الحزمة وواجهاتها، والخدمة، واختيار الخيار، وإنشاء طلب أو تأكيده عبره.
    const needles = [
      'tabby_flutter_inapp_sdk',
      'TabbySDK',
      'TabbyService',
      'tabby_service.dart',
      "id: 'tabby'",
      "== 'tabby'",
      "method: 'tabby'",
      "(finalOrderId, 'tabby')",
    ];
    final offenders = <String>[];
    for (final f in _dart('lib')) {
      final code = _code(f.path);
      for (final n in needles) {
        if (code.contains(n)) offenders.add('${f.path}: $n');
      }
    }
    expect(offenders, isEmpty, reason: 'عودة تابي:\n${offenders.join('\n')}');
  });

  test('main لا تنتظر شيئاً اسمه تابي قبل runApp', () {
    final main = _code('lib/main.dart');
    expect(main.contains('Tabby'), isFalse);
    expect(main.contains('runApp('), isTrue, reason: 'main تغيّرت جذرياً — حدِّث الحارس');
  });

  test('شاشة الدفع تعرض تمارا وحدها للتقسيط', () {
    final pay = _code('lib/screens/payment_summary_screen.dart');
    expect(pay.contains("id: 'tamara'"), isTrue, reason: 'تمارا هي التقسيط المعتمد');
    expect(pay.contains('Tabby'), isFalse);
  });
}
