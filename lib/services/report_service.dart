import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class ZyiarahReportService {
  /// توليد تقرير PDF للمبيعات والطلبات
  Future<void> generateOrdersReport({
    required List<Map<String, dynamic>> orders,
    required String periodName,
    required double totalRevenue,
  }) async {
    final pdf = pw.Document();
    
    // استخدام خط يدعم العربية من حزمة printing
    final ttf = await PdfGoogleFonts.tajawalRegular();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf),
        textDirection: pw.TextDirection.rtl,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("تقرير مبيعات زيارة - $periodName", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.Text(DateFormat('yyyy-MM-dd').format(DateTime.now())),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard("إجمالي الإيرادات", "$totalRevenue ر.س"),
              _buildStatCard("عدد الطلبات", "${orders.length}"),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.TableHelper.fromTextArray(
            headers: ["كود الطلب", "الخدمة", "العميل", "المبلغ", "الحالة"],
            data: orders.map((o) => [
              o['code'] ?? 'N/A',
              o['service_name'] ?? '-',
              o['user_name'] ?? '-',
              "${o['final_amount'] ?? 0} ر.س",
              o['status'] ?? '-',
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) => pdf.save());
  }

  pw.Widget _buildStatCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
          pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
