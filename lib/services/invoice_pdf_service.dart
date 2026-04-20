import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:zyiarah/services/zatca_service.dart';

/// خدمة إنشاء فواتير ZATCA كملفات PDF ورفعها لسحابة التخزين
class InvoicePdfService {
  static Future<String?> generateAndUploadInvoice({
    required String orderId,
    required String orderCode,
    required double amount,
    required String qrData,
    required String serviceName,
    double discountAmount = 0.0,
    String? couponCode,
  }) async {
    final pdf = pw.Document();

    // التحميل المسبق للخطوط العربية لدعم الواجهة الثنائية
    final arabicFont = await PdfGoogleFonts.tajawalRegular();
    final arabicFontBold = await PdfGoogleFonts.tajawalBold();

    // الحسابات المالية الصحيحة (شامل الضريبة)
    final double total = amount;
    final double subtotal = total / 1.15;
    final double vatAmount = total - subtotal;
    final double baseServicePrice = (total + discountAmount) / 1.15;

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
              // Header Segment
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Tax Invoice', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      pw.Text('فاتورة ضريبية مبسطة', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(ZatcaService.merchantName, style: const pw.TextStyle(fontSize: 14)),
                      pw.Text('الرقم الضريبي: ${ZatcaService.vatNumber}', style: const pw.TextStyle(fontSize: 12)),
                      pw.Text('سجل تجاري: ${ZatcaService.crNumber}', style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Divider(),

              // Order Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Order ID / رقم الطلب: #$orderCode'),
                  pw.Text('Date / التاريخ: ${DateTime.now().toString().substring(0, 16)}'),
                ],
              ),
              pw.SizedBox(height: 30),

              // Items Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Description / الوصف', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total / المجموع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(serviceName)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${baseServicePrice.toStringAsFixed(2)} SAR')),
                    ],
                  ),
                  if (discountAmount > 0)
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Discount / الخصم (${couponCode ?? "Coupon"})')),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('-${(discountAmount / 1.15).toStringAsFixed(2)} SAR', style: const pw.TextStyle(color: PdfColors.red))),
                      ],
                    ),
                ],
              ),

              pw.SizedBox(height: 30),

              // Summary
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _buildSummaryRow('Subtotal / المجموع الفرعي:', subtotal.toStringAsFixed(2)),
                      _buildSummaryRow('VAT (15%) / ضريبة القيمة المضافة:', vatAmount.toStringAsFixed(2)),
                      _buildSummaryRow('Total / الإجمالي:', total.toStringAsFixed(2), isBold: true),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),
              
              // ZATCA QR Code
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 100,
                      height: 100,
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text('Authorized Tax Invoice - ZATCA Compliant', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('فاتورة ضريبية معتمدة ومتوافقة مع هيئة الزكاة والضريبة', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    try {
      final Uint8List pdfBytes = await pdf.save();
      final storageRef = FirebaseStorage.instance.ref().child('invoices/$orderId.pdf');
      
      await storageRef.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      final downloadUrl = await storageRef.getDownloadURL();
      
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'invoice_pdf_url': downloadUrl,
      });
      
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading PDF: $e');
      return null;
    }
  }

  static pw.Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 12, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.SizedBox(width: 20),
          pw.Text('$value SAR', style: pw.TextStyle(fontSize: 12, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }
}
