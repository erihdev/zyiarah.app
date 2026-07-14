// حارس انحدار لخطوط الـ PDF.
//
// كانت `PdfGoogleFonts.tajawalRegular()` تنفّذ `http.get` إلى fonts.gstatic.com
// بلا timeout عند كل توليد فاتورة أو عقد أو تقرير. على اتصال ضعيف أو محجوب لا يعود
// الـ await أبداً، فتبقى معاينة الطباعة معلّقة إلى ما لا نهاية — وهو ما ظهر للمستخدم
// كأن العقد "لا يُحمَّل". الخطّان الآن أصلان محليان.
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('خطوط الـ PDF مضمّنة كأصول ولا تحتاج شبكة', () async {
    final base =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));

    // صفحة تحوي نفس أنماط النص التي تظهر في الفواتير والعقود:
    // عربي متصل، أرقام، عملة، ونص مختلط عربي/إنجليزي.
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: base, bold: bold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('فاتورة ضريبية مبسطة — Tax Invoice',
                style: pw.TextStyle(font: bold, fontSize: 16)),
            pw.Text('الرقم الضريبي: 310885360200003',
                style: pw.TextStyle(font: base, fontSize: 14)),
            pw.Text('الإجمالي شامل الضريبة: 345.00 ر.س',
                style: pw.TextStyle(font: base, fontSize: 14)),
            pw.Text('عقد تقديم خدمات إلكتروني — الذي يلي',
                style: pw.TextStyle(font: base, fontSize: 14)),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    expect(bytes.length, greaterThan(1000),
        reason: 'يجب أن يُنتج مستنداً حقيقياً لا صفحة فارغة');
  });

  test('لا توجد أي مناداة على PdfGoogleFonts في كود التطبيق', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsStringSync().split('\n')) {
        // نتجاهل التعليقات التي تشرح سبب الإزالة.
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('PdfGoogleFonts')) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'PdfGoogleFonts يجلب الخط عبر الشبكة بلا timeout ويجمّد توليد '
            'المستندات. استخدم مُحمِّل الخطوط المحلي بدلاً منه.\n'
            '${offenders.join('\n')}');
  });
}
