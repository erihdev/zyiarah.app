import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:zyiarah/utils/time_format.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart' as intl;
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:zyiarah/services/zatca_service.dart';

class ZyiarahPdfService {
  /// أداة مساعدة لمعالجة النصوص العربية وتشكيلها بشكل صحيح داخل الـ PDF
  static String _ar(String input) {
    if (input.isEmpty) return "";
    return ArabicReshaper().reshape(input);
  }

  // خطوط الـ PDF مضمّنة كأصول محلية ومحفوظة في الذاكرة بعد أول تحميل.
  //
  // البديل السابق `PdfGoogleFonts.tajawalRegular()` كان ينفّذ
  // `http.get('https://fonts.gstatic.com/...')` بلا timeout عند كل توليد. فإذا
  // كان الاتصال ضعيفاً أو محجوباً، لا يعود الـ await أبداً — فتبقى معاينة الطباعة
  // معلّقة إلى الأبد وهو ما كان يظهر للمستخدم كأن العقد "لا يُحمَّل".
  static pw.Font? _baseFont;
  static pw.Font? _boldFont;

  static Future<({pw.Font base, pw.Font bold})> _fonts() async {
    _baseFont ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    _boldFont ??=
        pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    return (base: _baseFont!, bold: _boldFont!);
  }

  // ============================================================================
  // 1. توليد فاتورة ضريبية ZATCA (ZATCA Invoice)
  // ============================================================================
  static Future<String?> generateAndUploadInvoice({
    required String orderId,
    required String orderCode,
    required double amount, // المبلغ النهائي المدفوع بعد الخصم (شامل الضريبة)
    required String qrData,
    required String serviceName,
    double discountAmount = 0.0, // الخصم الإجمالي
    String? couponCode,
    String collectionPath = 'orders',
  }) async {
    // (E) تحميل بيانات المنشأة من إعدادات النظام قبل بناء الفاتورة
    await ZatcaService.ensureConfigLoaded();

    final pdf = pw.Document();
    final f = await _fonts();
    final arabicFont = f.base;
    final arabicFontBold = f.bold;

    // --- تصحيح حسابات ZATCA الضريبية ---
    // المبلغ الإجمالي قبل أي خصومات (شامل الضريبة)
    final double originalTotalInclusive = amount + discountAmount;
    
    // المبالغ الأساسية (قبل الضريبة)
    final double subtotalBeforeDiscount = originalTotalInclusive / 1.15;
    final double discountSubtotal = discountAmount / 1.15;
    final double netSubtotal = amount / 1.15; // المجموع الفرعي بعد الخصم
    
    // قيمة الضريبة 15% على المبلغ الصافي
    final double vatAmount = netSubtotal * 0.15;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Tax Invoice', style: const pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_ar('فاتورة ضريبية مبسطة'), style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_ar(ZatcaService.merchantName), style: const pw.TextStyle(fontSize: 14)),
                    pw.Text(_ar('الرقم الضريبي: ${ZatcaService.vatNumber}'), style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(_ar('سجل تجاري: ${ZatcaService.crNumber}'), style: const pw.TextStyle(fontSize: 12)),
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
                pw.Text(_ar('رقم الطلب / Order ID: #$orderCode')),
                pw.Text(_ar('التاريخ / Date: ${DateTime.now().toString().substring(0, 16)}')),
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
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('الوصف / Description'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('المجموع / Total'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar(serviceName))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${subtotalBeforeDiscount.toStringAsFixed(2)} SAR')),
                  ],
                ),
                if (discountAmount > 0)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('الخصم / Discount (${couponCode ?? ""})'))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('-${discountSubtotal.toStringAsFixed(2)} SAR', style: const pw.TextStyle(color: PdfColors.red))),
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
                    _buildSummaryRow(_ar('المجموع الفرعي / Net Subtotal:'), netSubtotal.toStringAsFixed(2)),
                    _buildSummaryRow(_ar('ضريبة القيمة المضافة / VAT (15%):'), vatAmount.toStringAsFixed(2)),
                    _buildSummaryRow(_ar('الإجمالي / Total:'), amount.toStringAsFixed(2), isBold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 40),

            // ZATCA QR Code
            pw.Center(
              child: pw.Column(
                children: [
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qrData, width: 100, height: 100),
                  pw.SizedBox(height: 5),
                  pw.Text('Authorized Tax Invoice - ZATCA Compliant', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(_ar('فاتورة ضريبية معتمدة ومتوافقة مع هيئة الزكاة والضريبة'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    try {
      final Uint8List pdfBytes = await pdf.save();
      final storageRef = FirebaseStorage.instance.ref().child('invoices/$orderId.pdf');

      // مهلة زمنية على كل عملية شبكية: بلا timeout كان الرفع على اتصال ضعيف أو محجوب
      // لا يعود أبداً، فيبقى دوّار "جاري إنشاء الفاتورة الضريبية..." يدور للأبد. الآن
      // تفشل العملية بأمان خلال ثوانٍ محدودة بدل التعليق.
      await storageRef
          .putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'))
          .timeout(const Duration(seconds: 30));
      final downloadUrl =
          await storageRef.getDownloadURL().timeout(const Duration(seconds: 15));

      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(orderId)
          .update({'invoice_pdf_url': downloadUrl}).timeout(const Duration(seconds: 15));

      return downloadUrl;
    } catch (e) {
      debugPrint('Error generating/uploading ZATCA invoice: $e');
      // نعلّم الوثيقة بالفشل حتى تُظهر الواجهة زرّ إعادة المحاولة بدل دوّار أبدي.
      // ملاحظة: يتطلب سماح قواعد Firestore بمفتاح invoice_pdf_status ضمن تعديلات
      // العميل (orders وstore_orders) — بدونه يُرفَض الوسم ولا يظهر زر الإعادة.
      try {
        await FirebaseFirestore.instance
            .collection(collectionPath)
            .doc(orderId)
            .update({'invoice_pdf_status': 'failed'}).timeout(
                const Duration(seconds: 10));
      } catch (statusErr) {
        // لا نبتلعه بصمت: رفض الصلاحيات هنا يعني بقاء العميل على دوّار الفاتورة.
        debugPrint('INVOICE_STATUS_WRITE_FAILED [$collectionPath/$orderId]: $statusErr');
      }
      return null;
    }
  }

  // ============================================================================
  // 2. تقرير مبيعات الإدارة (Admin Sales Report)
  // ============================================================================
  static Future<void> generateOrdersReport({
    required List<Map<String, dynamic>> orders,
    required String periodName,
    required double totalRevenue,
  }) async {
    final pdf = pw.Document();
    final f = await _fonts();
    final ttf = f.base;
    final ttfBold = f.bold;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(_ar("تقرير مبيعات زيارة - $periodName"), style: const pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.Text(intl.DateFormat('yyyy-MM-dd').format(DateTime.now())),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard(_ar("إجمالي الإيرادات"), "$totalRevenue ر.س"),
              _buildStatCard(_ar("عدد الطلبات"), "${orders.length}"),
            ],
          ),
          pw.SizedBox(height: 30),
          pw.TableHelper.fromTextArray(
            headers: [_ar("كود الطلب"), _ar("الخدمة"), _ar("العميل"), _ar("المبلغ"), _ar("الحالة")],
            data: orders.map((o) => [
              o['code'] ?? 'N/A',
              _ar(o['service_name'] ?? '-'),
              _ar(o['user_name'] ?? o['client_name'] ?? '-'),
              "${o['final_amount'] ?? o['amount'] ?? 0} ر.س",
              _ar(o['status'] ?? '-'),
            ]).toList(),
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );

    // نُولّد البايتات أولاً ثم نشاركها عبر ورقة المشاركة بدل معاينة الطباعة.
    // `layoutPdf` يفتح شاشة طباعة iOS التي تعلّق على "Loading Preview" عند ترسيم
    // المستند؛ `sharePdf` يعرضه عبر عارض النظام (QuickLook) بلا ترسيم طباعة.
    final Uint8List reportBytes = await pdf.save();
    await Printing.sharePdf(bytes: reportBytes, filename: 'Zyiarah_Report.pdf');
  }

  // ============================================================================
  // 3. توثيق العقد الإلكتروني (Contract Document)
  // ============================================================================
  static Future<void> generateAndDownloadContract({
    required String contractId,
    required String planName,
    required String userName,
    required String userPhone,
    required double price,
    required int visits,
    required DateTime startDate,
    String? signatureData,
  }) async {
    final pdf = pw.Document();
    final f = await _fonts();
    final arabicFont = f.base;
    final arabicFontBold = f.bold;

    Uint8List? logoBytes;
    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    // فكّ التوقيع بأمان: بادئة data-URI أو محارف/تلف كانت تجعل base64Decode يرمي داخل
    // build (أثناء save) → تعلق معاينة الطباعة للأبد. عند أي فشل نتجاهل التوقيع فقط.
    Uint8List? signatureBytes;
    if (signatureData != null && signatureData.isNotEmpty) {
      try {
        var s = signatureData;
        final comma = s.indexOf(',');
        if (s.startsWith('data:') && comma != -1) s = s.substring(comma + 1);
        signatureBytes = base64Decode(s.replaceAll(RegExp(r'\s'), ''));
      } catch (_) {
        signatureBytes = null;
      }
    }

    // جدول الزيارات المجدولة (أسبوعي/شهري): نقرأ الطلبات المولّدة لهذا العقد كي يعرض
    // العقد تاريخ ووقت كل زيارة لا عددها فقط. مرتّبة بترتيب الزيارة.
    final List<List<String>> visitRows = [];
    try {
      final vs = await FirebaseFirestore.instance
          .collection('orders')
          .where('contract_id', isEqualTo: contractId)
          .get();
      final docs = vs.docs.map((d) => d.data()).toList()
        ..sort((a, b) => ((a['visit_index'] ?? 0) as num)
            .compareTo((b['visit_index'] ?? 0) as num));
      for (final v in docs) {
        visitRows.add([
          'زيارة ${v['visit_index'] ?? '-'}/${v['total_visits'] ?? docs.length}',
          '${v['booking_date'] ?? '-'}',
          formatSlot12(v['booking_time_slot'] as String?).isEmpty
              ? '-'
              : formatSlot12(v['booking_time_slot'] as String?),
        ]);
      }
    } catch (_) {/* إن تعذّر الجلب يبقى العقد بالتفاصيل الأساسية */}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoBytes != null) pw.Image(pw.MemoryImage(logoBytes), width: 80) else pw.SizedBox(width: 80),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_ar('منصة زيارة / Zyiarah Platform'), style: const pw.TextStyle(fontSize: 12)),
                    pw.Text(_ar('رقم العقد: #$contractId / Contract ID'), style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Text(_ar('عقد تقديم خدمات إلكتروني'), style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF660033)))),
            pw.SizedBox(height: 20),
            pw.Divider(color: const PdfColor.fromInt(0xFF8E2B5C)),
            pw.SizedBox(height: 20),

            // Parties
            pw.Text(_ar('طرفي التعاقد / Parties to the Contract:'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.grey50, borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: PdfColors.grey200)),
              child: pw.Column(
                children: [
                  _buildTextRow('First Party:', _ar('مؤسسة زيارة للخدمات العامة'), _ar('الطرف الأول:'), 'Zyiarah General Services Foundation'),
                  pw.SizedBox(height: 5),
                  _buildTextRow('Second Party:', _ar(userName), _ar('الطرف الثاني:'), 'The Client mentioned above'),
                  pw.SizedBox(height: 5),
                  _buildTextRow('Phone / الجوال:', userPhone, '', ''),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // Contract Details Table
            pw.Text(_ar('تفاصيل العقد / Contract Details:'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('الوصف / Description'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('التفاصيل / Details'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ]
                ),
                _buildTableRow(_ar('الباقة المشتراة / Service Plan'), _ar(planName)),
                _buildTableRow(_ar('إجمالي الزيارات / Total Visits'), _ar('$visits زيارة')),
                _buildTableRow(_ar('قيمة العقد / Contract Price'), _ar('${price.toStringAsFixed(2)} ر.س')),
                _buildTableRow(_ar('تاريخ الإصدار / Issue Date'), intl.DateFormat('yyyy-MM-dd').format(startDate)),
              ],
            ),
            pw.SizedBox(height: 20),

            // Visit Schedule (جدول الزيارات — تاريخ ووقت كل زيارة)
            if (visitRows.isNotEmpty) ...[
              pw.Text(_ar('جدول الزيارات / Visit Schedule:'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1.4),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('الزيارة / Visit'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('التاريخ / Date'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar('الوقت / Time'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
                    ],
                  ),
                  ...visitRows.map((r) => pw.TableRow(
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(_ar(r[0]), style: const pw.TextStyle(fontSize: 11))),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(r[1], style: const pw.TextStyle(fontSize: 11))),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(r[2], style: const pw.TextStyle(fontSize: 11))),
                        ],
                      )),
                ],
              ),
              pw.SizedBox(height: 30),
            ],

            // Terms
            pw.Text(_ar('الشروط والأحكام / Terms and Conditions:'), style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey200)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_ar('1. يلتزم مقدم الخدمة بتنفيذ الزيارات المجدولة حسب معايير التشغيل المعتمدة.'), style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(_ar('2. يلتزم العميل بتسهيل دخول الكوادر للموقع في المواعيد المحددة.'), style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(_ar('3. يعتبر هذا العقد موثقاً إلكترونياً وملزماً فور إتمام عملية الدفع.'), style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 5),
                  pw.Text('1. The provider is committed to delivering the scheduled visits according to the professional standards.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  pw.Text('2. The client must ensure arrival of workers is facilitated at the agreed locations.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  pw.Text('3. This contract is considered electronically signed and binding upon payment.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 40),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(_ar('ختم المنصة'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    if (logoBytes != null) pw.Opacity(opacity: 0.5, child: pw.Image(pw.MemoryImage(logoBytes), width: 60)),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(_ar('توقيع العميل (الطرف الثاني)'), style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    if (signatureBytes != null)
                      pw.Image(pw.MemoryImage(signatureBytes), width: 100),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 30),
            
            // Footer
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(_ar('هذا مستند إلكتروني آلي - لا يتطلب توقيع فعلي'), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('This is an automated electronic document - Trusted by Zyiarah Platform', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.SizedBox(height: 10),
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: 'Zyiarah-Contract-$contractId-$userName', width: 50, height: 50),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // نُولّد البايتات أولاً ثم نشاركها عبر ورقة المشاركة (QuickLook) بدل معاينة الطباعة.
    // `layoutPdf` كان يفتح شاشة طباعة iOS ويعلّق على «Loading Preview» عند الترسيم؛
    // `sharePdf` يعرض العقد مباشرةً ويتيح الحفظ في «الملفات» أو المشاركة أو الطباعة منه.
    final Uint8List bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'Zyiarah_Contract_$contractId.pdf');
  }

  // --- Helpers ---
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

  static pw.Widget _buildStatCard(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
      child: pw.Column(
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        ],
      ),
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
