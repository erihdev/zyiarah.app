import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahContractPdfService {
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
                      pw.Text('عقد تقديم خدمات إلكتروني', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.purple800)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Zyiarah Platform / منصة زيارة', style: const pw.TextStyle(fontSize: 12)),
                      pw.Text('Contract ID / رقم العقد: #$contractId', style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.purple),
              pw.SizedBox(height: 20),

              // Parties Info
              pw.Text('Parties to the Contract / طرفي التعاقد:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
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
                    _buildTextRow('First Party:', 'Zyiarah General Services Foundation', 'الطرف الأول:', 'مؤسسة زيارة للخدمات العامة'),
                    pw.SizedBox(height: 5),
                    _buildTextRow('Second Party:', userName, 'الطرف الثاني:', 'العميل المذكور أعلاه'),
                    pw.SizedBox(height: 5),
                    _buildTextRow('Phone / الجوال:', userPhone, '', ''),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // Contract Details Table
              pw.Text('Contract Details / تفاصيل العقد:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  _buildTableHeader(['Description / الوصف', 'Details / التفاصيل']),
                  _buildTableRow('Service Plan / الباقة المشتراة', planName),
                  _buildTableRow('Total Visits / إجمالي الزيارات', '$visits visits'),
                  _buildTableRow('Contract Price / قيمة العقد', '${price.toStringAsFixed(2)} SAR'),
                  _buildTableRow('Issue Date / تاريخ الإصدار', intl.DateFormat('yyyy-MM-dd').format(startDate)),
                ],
              ),
              pw.SizedBox(height: 30),

              // Terms & Conditions
              pw.Text('Terms and Conditions / الشروط والأحكام:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.TableBorder.all(color: PdfColors.grey200)),
                child: pw.Text(
                  '1. The provider is committed to delivering the scheduled visits according to the professional standards.\n'
                  '2. The client must ensure arrival of workers is facilitated at the agreed locations.\n'
                  '3. This contract is considered electronically signed and binding upon payment.\n'
                  '1. يلتزم مقدم الخدمة بتنفيذ الزيارات المجدولة حسب معايير التشغيل المعتمدة.\n'
                  '2. يلتزم العميل بتسهيل دخول الكوادر للموقع في المواعيد المحددة.\n'
                  '3. يعتبر هذا العقد موثقاً إلكترونياً وملزماً فور إتمام عملية الدفع.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.black),
                ),
              ),

              pw.Spacer(),
              
              // Footer / Security
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('This is an automated electronic document - No physical signature required', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('هذا مستند إلكتروني آلي - لا يتطلب توقيع فعلي', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
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

    // Printing/Previewing is better for "Download" behavior in Flutter
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Zyiarah_Contract_$contractId.pdf',
    );
  }

  static pw.TableRow _buildTableHeader(List<String> labels) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: labels.map((label) => pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)))).toList(),
    );
  }

  static pw.TableRow _buildTableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(label)),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(value)),
      ],
    );
  }

  static pw.Widget _buildTextRow(String labelEn, String valueEn, String labelAr, String valueAr) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('$labelEn $valueEn', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('$valueAr $labelAr', style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }
}
