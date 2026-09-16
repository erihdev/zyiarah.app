import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/models/invoice_log_entry.dart';
import 'package:zyiarah/screens/admin/admin_invoices_screen.dart';

/// شاشة سجل الفواتير الإلكترونية (تصميم Stitch `_61`): ملخص الشهر، البحث،
/// الحالات وأزرارها، والتنقّل بين الأشهر. المحمّل محقون فلا Firebase هنا.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  InvoiceLogEntry e(String code,
          {String source = 'orders',
          double amount = 230,
          String method = 'applepay',
          String? url,
          String? status,
          String client = 'عميل'}) =>
      InvoiceLogEntry.fromMap(source, 'id-$code', {
        'code': code,
        'client_name': client,
        'service_name': 'خدمة $code',
        'amount': amount,
        'is_paid': true,
        'payment_method': method,
        if (url != null) 'invoice_pdf_url': url,
        if (status != null) 'invoice_pdf_status': status,
        'created_at': Timestamp.fromDate(DateTime(2026, 9, 10, 9, 30)),
      });

  final sample = [
    e('ZY-A', client: 'أم محمد', url: 'https://x/a.pdf'),
    e('ZY-B', source: 'store_orders', amount: 115, method: 'wallet', status: 'failed'),
    e('ZY-C', amount: 345, method: 'tamara'),
  ];

  Future<List<DateTime>> pump(WidgetTester t,
      {List<InvoiceLogEntry>? items, bool fail = false}) async {
    // القائمة كسولة: صفّ ثالث خارج نافذة 600px لا يُبنى — نطوّل النافذة.
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final asked = <DateTime>[];
    await t.pumpWidget(MaterialApp(
      home: AdminInvoicesScreen(
        now: DateTime(2026, 9, 16),
        loader: (m) async {
          asked.add(m);
          if (fail) throw StateError('offline');
          return items ?? sample;
        },
      ),
    ));
    await t.pump();
    await t.pump();
    return asked;
  }

  testWidgets('ملخص الشهر: العدد والإجمالي والضريبة والصافي وتوزيع الوسائل والحالات',
      (t) async {
    final asked = await pump(t);
    expect(asked, [DateTime(2026, 9, 1)]);
    expect(find.text('سبتمبر 2026'), findsOneWidget);
    expect(find.text('3 فاتورة مدفوعة هذا الشهر'), findsOneWidget);
    expect(find.text('690.00 ر.س'), findsOneWidget);
    expect(find.text('90.00 ر.س'), findsOneWidget);
    expect(find.text('600.00 ر.س'), findsOneWidget);
    expect(find.text('Apple Pay: 230.00 ر.س'), findsOneWidget);
    expect(find.text('1 قيد الإنشاء • 1 فشلت'), findsOneWidget);
  });

  testWidgets('الصفوف: الكود والمصدر والحالة وأزرارها', (t) async {
    await pump(t);
    expect(find.text('ZY-A'), findsOneWidget);
    expect(find.text('أم محمد — خدمة ZY-A'), findsOneWidget);
    expect(find.text('جاهزة'), findsOneWidget);
    expect(find.text('فتح PDF'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
    expect(find.text('متجر'), findsOneWidget);
    expect(find.text('فشل الإنشاء'), findsOneWidget);
    expect(find.text('إعادة إنشاء الفاتورة'), findsOneWidget);
    expect(find.text('قيد الإنشاء'), findsOneWidget);
    expect(find.text('إنشاء الفاتورة الآن'), findsOneWidget);
    expect(find.text('منها ضريبة 30.00 ر.س'), findsOneWidget);
  });

  testWidgets('البحث يصفّي الصفوف، والملخص يبقى للشهر كله', (t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'أم محمد');
    await t.pump();
    expect(find.text('ZY-A'), findsOneWidget);
    expect(find.text('ZY-B'), findsNothing);
    expect(find.text('3 فاتورة مدفوعة هذا الشهر'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'لا شيء');
    await t.pump();
    expect(find.text('لا نتائج تطابق البحث'), findsOneWidget);
  });

  testWidgets('التنقّل للشهر السابق يطلب شهره من المحمّل', (t) async {
    final asked = await pump(t);
    await t.tap(find.byTooltip('الشهر السابق'));
    await t.pump();
    await t.pump();
    expect(asked.last, DateTime(2026, 8, 1));
    expect(find.text('أغسطس 2026'), findsOneWidget);
  });

  testWidgets('شهر بلا فواتير', (t) async {
    await pump(t, items: const []);
    expect(find.text('لا فواتير في هذا الشهر'), findsOneWidget);
  });

  testWidgets('فشل التحميل → خطأ مع إعادة المحاولة، ولا انهيار', (t) async {
    await pump(t, fail: true);
    expect(find.text('تعذّر تحميل الفواتير'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('القائمة والقواعد: للسوبر والمحاسب، والمحاسب يقرأ طلبات المتجر', () {
    final menu = File('lib/screens/admin/admin_more_screen.dart').readAsStringSync();
    expect(
        RegExp(r"'page': const AdminInvoicesScreen\(\),\s*'roles': \['super_admin', 'accountant_admin'\],")
            .hasMatch(menu),
        isTrue);
    final rules = File('firestore.rules').readAsStringSync();
    expect(
        RegExp(r"match /store_orders/\{orderId\} \{[\s\S]*?allow read: if isLoggedIn\(\) &&\s*\(request\.auth\.uid == resource\.data\.client_id \|\| isOrdersManager\(\) \|\|\s*isAccountantAdmin\(\)\);")
            .hasMatch(rules),
        isTrue,
        reason: 'سجل الفواتير يجمع طلبات المتجر — يقرؤها المحاسب أيضاً');
    final rulesTest = File('functions/test/rules.roles.test.js').readAsStringSync();
    expect(rulesTest.contains('accountant CAN read store_orders'), isTrue);
    // الشاشة تعيد استخدام حساب فاتورة العميل والمشاركة المشتركة.
    final src = File('lib/screens/admin/admin_invoices_screen.dart').readAsStringSync();
    expect(src.contains('ZyiarahPdfService.shareUploadedInvoice('), isTrue);
    expect(src.contains("orderBy('created_at', descending: true)"), isTrue,
        reason: 'مدى created_at وحده — لا فهرس مركّب جديد');
    expect(src.contains("where('is_paid'"), isFalse);
  });
}
