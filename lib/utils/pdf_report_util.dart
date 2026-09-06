import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;

class ZyiarahPdfReportUtil {
  // نفس سبب التضمين المحلي في ZyiarahPdfService: PdfGoogleFonts كانت تجلب الخط
  // عبر http.get بلا timeout فيتجمّد التقرير عند ضعف الاتصال.
  static pw.Font? _baseFont;
  static pw.Font? _boldFont;

  static Future<({pw.Font base, pw.Font bold})> _fonts() async {
    _baseFont ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    _boldFont ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    return (base: _baseFont!, bold: _boldFont!);
  }

  /// Generates and prints/saves a professional financial report.
  static Future<void> generateFinancialReport({
    required List<DocumentSnapshot> orders,
    required double totalRevenue,
    required int activeOrders,
  }) async {
    // «المكتملة» الحقيقية — كان يُشتق بـ (total − active) فيَعُدّ الملغاة ضمن المكتملة.
    final int completedOrders = orders.where((o) {
      final data = o.data() as Map<String, dynamic>?;
      return (data == null ? '' : (data['status'] ?? '')) == 'completed';
    }).length;
    final pdf = pw.Document();
    final f = await _fonts();
    final ttf = f.base;
    final ttfBold = f.bold;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(
          base: ttf,
          bold: ttfBold,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                pw.SizedBox(height: 30),
                _buildSummaryTable(totalRevenue, activeOrders, completedOrders),
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

    // sharePdf (عرض/حفظ عبر النظام) بدل layoutPdf الذي يعلّق على "Loading Preview" في iOS.
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Zyiarah_Financial_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static pw.Widget _buildHeader() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('مؤسسة زيارة',
                style: const pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF660033))),
            pw.Text('التقرير المالي الرسمي',
                style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('التاريخ: ${intl.DateFormat('yyyy-MM-dd').format(DateTime.now())}'),
            pw.Text('رقم التقرير: ZY-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryTable(double revenue, int active, int completed) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: const pw.BoxDecoration(
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          // النموذج المعتمد: المبالغ المخزَّنة شاملة الضريبة — الصافي = الإجمالي ÷ 1.15
          // والضريبة = الإجمالي − الصافي.
          _buildStatItem('الإيراد الإجمالي (شامل الضريبة)', '${revenue.toStringAsFixed(2)} ر.س'),
          _buildStatItem('الصافي قبل الضريبة', '${(revenue / 1.15).toStringAsFixed(2)} ر.س'),
          _buildStatItem('الطلبات النشطة', active.toString()),
          _buildStatItem('الطلبات المكتملة', completed.toString()),
          _buildStatItem('ضريبة القيمة المضافة (15%)',
              '${(revenue - revenue / 1.15).toStringAsFixed(2)} ر.س'),
        ],
      ),
    );
  }

  static pw.Widget _buildStatItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  /// ترجمة حالات الطلب للعرض — الحالة تُخزَّن إنجليزية في المستندات.
  static String _statusAr(String s) => switch (s) {
        'completed' => 'مكتمل',
        'scheduled' => 'مجدول',
        'assigned' => 'مُسند',
        'accepted' => 'مقبول',
        'on_the_way' => 'في الطريق',
        'in_progress' => 'قيد التنفيذ',
        'pending' => 'قيد الانتظار',
        'under_review' => 'قيد المراجعة',
        'awaiting_payment' => 'بانتظار الدفع',
        'cancelled' => 'ملغي',
        'rejected' => 'مرفوض',
        _ => s,
      };

  static pw.Widget _buildOrderList(List<DocumentSnapshot> docs) {
    final recentDocs = docs.take(15).toList();

    pw.Widget headerCell(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(t, style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('سجل آخر المعاملات',
            style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                headerCell('رقم الطلب'),
                headerCell('الخدمة'),
                headerCell('المبلغ'),
                headerCell('الحالة'),
              ],
            ),
            ...recentDocs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data['code'] ?? doc.id.substring(0, 6))),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data['service_name'] ?? 'عامة')),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${data['amount'] ?? data['total_amount'] ?? data['final_amount'] ?? 0} ر.س')),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_statusAr('${data['status'] ?? 'pending'}'))),
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
            pw.Text('صادر من لوحة إدارة زيارة',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            pw.Text('صفحة 1 من 1',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          ],
        ),
      ],
    );
  }
}
