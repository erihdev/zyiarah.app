import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahPdfReportUtil {
  /// Generates and prints/saves a professional financial report.
  static Future<void> generateFinancialReport({
    required List<DocumentSnapshot> orders,
    required double totalRevenue,
    required int activeOrders,
  }) async {
    final pdf = pw.Document();
    
    // In a real environment with Arabic, you must load a font that supports Arabic glyphs.
    // Since we are in a dev environment, we'll use a standard font for structure, 
    // but a production app would use: pw.Font.ttf(await rootBundle.load("assets/fonts/Tajawal.ttf"))
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                pw.SizedBox(height: 30),
                _buildSummaryTable(totalRevenue, activeOrders, orders.length),
                pw.SizedBox(height: 40),
                _buildOrderList(orders),
                pw.Spacer(),
                _buildFooter(),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Zyiarah_Financial_Report_${DateTime.now().millisecond}.pdf',
    );
  }

  static pw.Widget _buildHeader() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('ZYIARAH ENTERPRISE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            pw.Text('Official Financial Performance Report', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Date: ${intl.DateFormat('yyyy-MM-dd').format(DateTime.now())}'),
            pw.Text('Report ID: ZY-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryTable(double revenue, int active, int total) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Revenue', '${revenue.toStringAsFixed(2)} SAR'),
          _buildStatItem('Active Orders', active.toString()),
          _buildStatItem('Completed Orders', (total - active).toString()),
          _buildStatItem('Estimated VAT (15%)', '${(revenue * 0.15).toStringAsFixed(2)} SAR'),
        ],
      ),
    );
  }

  static pw.Widget _buildStatItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _buildOrderList(List<DocumentSnapshot> docs) {
    final recentDocs = docs.take(15).toList();
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Recent Transactions Log', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Order ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Service', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              ],
            ),
            ...recentDocs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data['code'] ?? doc.id.substring(0, 6))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data['service_name'] ?? 'General')),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${data['final_amount'] ?? 0} SAR')),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data['status'] ?? 'pending')),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by Zyiarah Enterprise Dashboard', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            pw.Text('Page 1 of 1', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ],
    );
  }
}
