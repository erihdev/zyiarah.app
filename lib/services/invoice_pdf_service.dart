import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:firebase_storage/firebase_storage.dart';

/// خدمة إنشاء فواتير ZATCA كملفات PDF ورفعها لسحابة التخزين
class InvoicePdfService {
  static Future<String?> generateAndUploadInvoice({
    required String orderId,
    required double amount,
    required String qrData,
  }) async {
    final pdf = pw.Document();

    final double vatAmount = amount * 0.15;
    final double subtotal = amount - vatAmount;

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('Simplified Tax Invoice', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Moath Yahya Mohammed Al-Malki Est.', style: const pw.TextStyle(fontSize: 18)),
                pw.Text('VAT Number: 310885360200003'),
                pw.Text('CR: 7030376342'),
                pw.Divider(height: 40),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Order ID:'),
                    pw.Text(orderId),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Date:'),
                    pw.Text(DateTime.now().toIso8601String().substring(0, 16).replaceAll('T', ' ')),
                  ],
                ),
                pw.Divider(height: 40),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal:'),
                    pw.Text('${subtotal.toStringAsFixed(2)} SAR'),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('VAT (15%):'),
                    pw.Text('${vatAmount.toStringAsFixed(2)} SAR'),
                  ],
                ),
                pw.Divider(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Amount:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${amount.toStringAsFixed(2)} SAR', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 40),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: qrData,
                  width: 150,
                  height: 150,
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final Uint8List pdfBytes = await pdf.save();
      final storageRef = FirebaseStorage.instance.ref().child('invoices/$orderId.pdf');
      
      // رفع الملف إلى Firebase Storage
      await storageRef.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      final downloadUrl = await storageRef.getDownloadURL();
      
      // هنا يمكن تحديث مستند الطلب في Firestore برابط الفاتورة
      // await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      //   'invoice_pdf_url': downloadUrl,
      // });
      
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading PDF: $e');
      return null;
    }
  }
}
