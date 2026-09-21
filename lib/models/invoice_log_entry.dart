import 'package:zyiarah/models/invoice_view.dart';

/// صفّ في «سجل الفواتير الإلكترونية» الإداري: طلب خدمة أو طلب متجر مدفوع، مع
/// ما تعرضه شاشة النجاح نفسها (InvoiceView) كي يتطابق السجل مع فاتورة العميل.
class InvoiceLogEntry {
  /// 'orders' أو 'store_orders' — المجموعة التي يعيش فيها المستند.
  final String source;
  final String docId;
  final String clientName;
  final InvoiceView view;

  const InvoiceLogEntry({
    required this.source,
    required this.docId,
    required this.clientName,
    required this.view,
  });

  factory InvoiceLogEntry.fromMap(
      String source, String id, Map<String, dynamic> m) {
    final code = (m['code'] ?? id).toString();
    return InvoiceLogEntry(
      source: source,
      docId: id,
      clientName: (m['client_name'] ?? m['userName'] ?? 'عميل').toString(),
      view: InvoiceView.fromOrder(code, m),
    );
  }

  bool get isPaid => view.isPaid;
  bool get isStore => source == 'store_orders';
  String get sourceLabel => isStore ? 'متجر' : 'خدمة';

  /// حالة ملف الفاتورة: جاهز (له رابط)، فشل الإنشاء، أو ما زال قيد الإنشاء.
  String get status {
    if (view.pdfUrl != null) return 'ready';
    if (view.pdfStatus == 'failed') return 'failed';
    return 'pending';
  }

  String get statusLabel => switch (status) {
        'ready' => 'جاهزة',
        'failed' => 'فشل الإنشاء',
        _ => 'قيد الإنشاء',
      };

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return view.orderCode.toLowerCase().contains(q) ||
        clientName.toLowerCase().contains(q) ||
        view.serviceName.toLowerCase().contains(q) ||
        (view.paymentRef?.toLowerCase().contains(q) ?? false);
  }

  /// المدفوع فقط، الأحدث أولاً.
  static List<InvoiceLogEntry> paidNewestFirst(Iterable<InvoiceLogEntry> all) =>
      all.where((e) => e.isPaid).toList()
        ..sort((a, b) => b.view.issuedAt.compareTo(a.view.issuedAt));

  static InvoiceSummary summarize(Iterable<InvoiceLogEntry> entries) {
    var count = 0;
    var gross = 0.0;
    var vat = 0.0;
    var pending = 0;
    var failed = 0;
    final byMethod = <String, double>{};
    for (final e in entries) {
      count++;
      gross += e.view.total;
      vat += e.view.vat;
      byMethod[e.view.paymentLabel] =
          (byMethod[e.view.paymentLabel] ?? 0) + e.view.total;
      if (e.status == 'pending') pending++;
      if (e.status == 'failed') failed++;
    }
    return InvoiceSummary(
      count: count,
      gross: gross,
      vat: vat,
      net: gross - vat,
      byMethod: byMethod,
      pending: pending,
      failed: failed,
    );
  }
}

class InvoiceSummary {
  final int count;
  final double gross;
  final double vat;
  final double net;
  final Map<String, double> byMethod;
  final int pending;
  final int failed;

  const InvoiceSummary({
    required this.count,
    required this.gross,
    required this.vat,
    required this.net,
    required this.byMethod,
    required this.pending,
    required this.failed,
  });
}
