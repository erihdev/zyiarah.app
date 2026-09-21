import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/invoice_log_entry.dart';

/// سجل الفواتير الإلكترونية (تصميم Stitch `_61`، 2026-09-16): صفوفه من وثائق
/// الطلبات بالحساب نفسه في فاتورة العميل، وملخّص الشهر يجمعها.
void main() {
  InvoiceLogEntry e(String code,
          {String source = 'orders',
          double amount = 230,
          bool paid = true,
          String method = 'applepay',
          String? url,
          String? status,
          DateTime? at,
          String client = 'عميل'}) =>
      InvoiceLogEntry.fromMap(source, 'id-$code', {
        'code': code,
        'client_name': client,
        'service_name': 'خدمة $code',
        'amount': amount,
        'is_paid': paid,
        'payment_method': method,
        if (url != null) 'invoice_pdf_url': url,
        if (status != null) 'invoice_pdf_status': status,
        'created_at': Timestamp.fromDate(at ?? DateTime(2026, 9, 10)),
      });

  test('fromMap: الكود والعميل والمصدر، والافتراضيات عند الغياب', () {
    final a = e('ZY-1', client: 'أم محمد');
    expect(a.view.orderCode, 'ZY-1');
    expect(a.clientName, 'أم محمد');
    expect(a.isStore, isFalse);
    expect(a.sourceLabel, 'خدمة');
    final s = InvoiceLogEntry.fromMap('store_orders', 'abc', const {});
    expect(s.view.orderCode, 'abc', reason: 'بلا code → معرّف المستند');
    expect(s.clientName, 'عميل');
    expect(s.sourceLabel, 'متجر');
    expect(s.isPaid, isFalse);
  });

  test('status: جاهزة برابط، فشل بالعلامة، وإلا قيد الإنشاء', () {
    expect(e('a', url: 'https://x/a.pdf').status, 'ready');
    expect(e('a', url: 'https://x/a.pdf').statusLabel, 'جاهزة');
    expect(e('b', status: 'failed').status, 'failed');
    expect(e('b', status: 'failed').statusLabel, 'فشل الإنشاء');
    expect(e('c').status, 'pending');
    expect(e('c', status: 'retrying').statusLabel, 'قيد الإنشاء');
    // رابط موجود يغلب علامة فشل قديمة.
    expect(e('d', url: 'https://x/d.pdf', status: 'failed').status, 'ready');
  });

  test('matches: بالكود أو العميل أو الخدمة أو المرجع، بلا حساسية لحالة الأحرف', () {
    final x = InvoiceLogEntry.fromMap('orders', 'i', {
      'code': 'ZY-202600042',
      'client_name': 'جابر الفيفي',
      'service_name': 'تنظيف منزلي',
      'moyasar_payment_id': 'MOY-98234',
      'is_paid': true,
    });
    expect(x.matches(''), isTrue);
    expect(x.matches('zy-2026'), isTrue);
    expect(x.matches('جابر'), isTrue);
    expect(x.matches('منزلي'), isTrue);
    expect(x.matches('moy-98'), isTrue);
    expect(x.matches('غير موجود'), isFalse);
  });

  test('paidNewestFirst: المدفوع فقط، الأحدث أولاً', () {
    final list = InvoiceLogEntry.paidNewestFirst([
      e('old', at: DateTime(2026, 9, 1)),
      e('unpaid', paid: false, at: DateTime(2026, 9, 20)),
      e('new', at: DateTime(2026, 9, 15)),
    ]);
    expect(list.map((x) => x.view.orderCode).toList(), ['new', 'old']);
  });

  test('summarize: العدد والإجمالي والضريبة والصافي وتوزيع الوسائل والحالات', () {
    final s = InvoiceLogEntry.summarize([
      e('a', amount: 230, method: 'applepay', url: 'u'),
      e('b', amount: 115, method: 'wallet', status: 'failed', source: 'store_orders'),
      e('c', amount: 345, method: 'tamara'),
      e('d', amount: 115, method: 'applepay', url: 'u'),
    ]);
    expect(s.count, 4);
    expect(s.gross, closeTo(805, 0.001));
    expect(s.vat, closeTo(105, 0.001));
    expect(s.net, closeTo(700, 0.001));
    expect(s.byMethod['Apple Pay'], closeTo(345, 0.001));
    expect(s.byMethod['محفظة زيارة'], closeTo(115, 0.001));
    expect(s.byMethod['تمارا (Tamara)'], closeTo(345, 0.001));
    expect(s.pending, 1);
    expect(s.failed, 1);
    final empty = InvoiceLogEntry.summarize(const []);
    expect(empty.count, 0);
    expect(empty.byMethod, isEmpty);
  });
}
