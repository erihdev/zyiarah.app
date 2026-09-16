import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/widgets/zatca_invoice_card.dart';

/// بطاقة «فاتورة ضريبية مبسطة» على الشاشة (تصميم Stitch zatca_1/zatca_2).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  InvoiceView view({bool paid = true, double discount = 0, String? coupon}) =>
      InvoiceView(
        orderCode: 'ZY-202600042',
        serviceName: 'تنظيف منزلي (شقة - 2 كوادر)',
        total: 230,
        discount: discount,
        couponCode: coupon,
        issuedAt: DateTime(2026, 9, 16, 9, 30),
        paymentMethod: 'applepay',
        paymentRef: 'MOY-98234',
        isPaid: paid,
        pdfUrl: null,
        pdfStatus: null,
      );

  Future<void> pump(WidgetTester t, Widget w) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(child: w),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('تعرض المنشأة والرقم الضريبي والسجل والرمز والمبالغ والسداد', (t) async {
    await pump(
        t,
        ZatcaInvoiceCard(
          view: view(),
          merchantName: 'مؤسسة معاذ يحي محمد المالكي',
          vatNumber: '310885360200003',
          crNumber: '7030376342',
        ));
    expect(find.text('فاتورة ضريبية مبسطة'), findsOneWidget);
    expect(find.text('مؤسسة معاذ يحي محمد المالكي'), findsOneWidget);
    expect(find.text('310885360200003'), findsOneWidget);
    expect(find.text('7030376342'), findsOneWidget);
    expect(find.text('ZY-202600042'), findsOneWidget);
    expect(find.text('2026/09/16 09:30'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('تنظيف منزلي (شقة - 2 كوادر)'), findsOneWidget);
    // الصافي 200 يظهر مرتين (سطر البند بلا خصم = الصافي، وصفّ الملخص).
    expect(find.text('200.00 ر.س'), findsNWidgets(2));
    expect(find.text('30.00 ر.س'), findsOneWidget);
    expect(find.text('230.00 ر.س'), findsOneWidget);
    expect(find.text('طريقة السداد: Apple Pay'), findsOneWidget);
    expect(find.text('معرّف السداد: MOY-98234'), findsOneWidget);
    expect(find.text('مدفوعة بالكامل'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('الخصم يظهر صفّاً بكوده، وغير المدفوع يُعلَّم بانتظار التأكيد', (t) async {
    await pump(t, ZatcaInvoiceCard(view: view(paid: false, discount: 23, coupon: 'JAZAN25')));
    expect(find.text('الخصم (JAZAN25)'), findsOneWidget);
    expect(find.text('- 20.00 ر.س'), findsOneWidget);
    expect(find.text('220.00 ر.س'), findsOneWidget, reason: 'البند قبل الخصم');
    expect(find.text('بانتظار تأكيد الدفع'), findsOneWidget);
    expect(find.text('مدفوعة بالكامل'), findsNothing);
  });

  test('شاشة النجاح تعرض البطاقة للمدفوع فقط وتشارك ملف PDF المرفوع نفسه', () {
    final src = File('lib/screens/order_success_screen.dart').readAsStringSync();
    expect(src.contains('if (view.isPaid) ...['), isTrue,
        reason: 'فاتورة ضريبية لطلب غير مدفوع ليست فاتورة');
    expect(src.contains('ZatcaInvoiceCard(view: view)'), isTrue);
    expect(src.contains('InvoiceView.fromOrder(widget.orderCode, data)'), isTrue);
    expect(src.contains('ZatcaService.ensureConfigLoaded()'), isTrue,
        reason: 'بيانات المنشأة من إعدادات النظام لا الافتراضيات وحدها');
    expect(src.contains('.refFromURL(url)'), isTrue);
    expect(src.contains('Printing.sharePdf('), isTrue);
    expect(src.contains('"مشاركة الفاتورة"'), isTrue);
    expect(src.contains('if (invoiceUrl == null) {'), isTrue,
        reason: 'زرّا التحميل والمشاركة لا يظهران قبل رفع الملف');
    expect(src.contains('SingleChildScrollView('), isTrue,
        reason: 'البطاقة أطول من الشاشة');
  });
}
