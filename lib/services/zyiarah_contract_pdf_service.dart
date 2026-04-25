import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:arabic_reshaper/arabic_reshaper.dart';

class ZyiarahContractPdfService {
  static String _ar(String input) {
    if (input.isEmpty) return "";
    // Connect Arabic characters properly
    return ArabicReshaper().reshape(input);
  }

  static Future<void> generateAndDownloadContract({
    required String contractId,
    required String planName,
    required String userName,
    required String userPhone,
    required double price,
    required int visits,
    required DateTime startDate,
  }) async {
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.tajawalRegular();
    final arabicFontBold = await PdfGoogleFonts.tajawalBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicFontBold,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Electronic Service Contract', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.purple800)),
                      pw.Text(_ar('عقد تقديم خدمات إلكتروني'), textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.purple800)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(_ar('منصة زيارة / Zyiarah Platform'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 12)),
                      pw.Text(_ar('رقم العقد: #$contractId / Contract ID'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.purple),
              pw.SizedBox(height: 20),

              // Parties Info
              pw.Text(_ar('طرفي التعاقد / Parties to the Contract:'), textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.TableBorder.all(color: PdfColors.grey200),
                ),
                child: pw.Column(
                  children: [
                    _buildTextRow('First Party:', _ar('مؤسسة زيارة للخدمات العامة'), 'الطرف الأول:', 'Zyiarah General Services Foundation'),
                    pw.SizedBox(height: 5),
                    _buildTextRow('Second Party:', _ar(userName), 'الطرف الثاني:', 'The Client mentioned above'),
                    pw.SizedBox(height: 5),
                    _buildTextRow('Phone / الجوال:', _ar(userPhone), '', ''),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // Contract Details Table
              pw.Text(_ar('تفاصيل العقد / Contract Details:'), textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  _buildTableHeader([_ar('الوصف / Description'), _ar('التفاصيل / Details')]),
                  _buildTableRow(_ar('الباقة المشتراة / Service Plan'), _ar(planName)),
                  _buildTableRow(_ar('إجمالي الزيارات / Total Visits'), _ar('$visits زيارة')),
                  _buildTableRow(_ar('قيمة العقد / Contract Price'), _ar('${price.toStringAsFixed(2)} ر.س')),
                  _buildTableRow(_ar('تاريخ الإصدار / Issue Date'), intl.DateFormat('yyyy-MM-dd').format(startDate)),
                ],
              ),
              pw.SizedBox(height: 30),

              // Terms & Conditions
              pw.Text(_ar('الشروط والأحكام / Terms and Conditions:'), textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.TableBorder.all(color: PdfColors.grey200)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_ar('1. يلتزم مقدم الخدمة بتنفيذ الزيارات المجدولة حسب معايير التشغيل المعتمدة.'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(_ar('2. يلتزم العميل بتسهيل دخول الكوادر للموقع في المواعيد المحددة.'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(_ar('3. يعتبر هذا العقد موثقاً إلكترونياً وملزماً فور إتمام عملية الدفع.'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 5),
                    pw.Text('1. The provider is committed to delivering the scheduled visits according to the professional standards.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('2. The client must ensure arrival of workers is facilitated at the agreed locations.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('3. This contract is considered electronically signed and binding upon payment.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ),

              pw.Spacer(),
              
              // Footer / Security
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(_ar('هذا مستند إلكتروني آلي - لا يتطلب توقيع فعلي'), textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('This is an automated electronic document - No physical signature required', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.SizedBox(height: 10),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: 'Zyiarah-Contract-$contractId-$userName',
                      width: 60,
                      height: 60,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Zyiarah_Contract_$contractId.pdf',
    );
  }

  static pw.TableRow _buildTableHeader(List<String> labels) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: labels.map((label) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList(),
    );
  }

  static pw.TableRow _buildTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label, textDirection: pw.TextDirection.rtl)),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value, textDirection: pw.TextDirection.rtl)),
      ],
    );
  }

  static pw.Widget _buildTextRow(String labelEn, String valueEn, String labelAr, String valueAr) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('$labelEn $valueEn', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('$valueAr $labelAr', textDirection: pw.TextDirection.rtl, style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
