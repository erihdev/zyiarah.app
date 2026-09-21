import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/zatca_service.dart';

/// ما تعرضه بطاقة «فاتورة ضريبية مبسطة» على شاشة نجاح الطلب — مشتقّ من وثيقة
/// الطلب نفسها التي تُبنى منها نسخة PDF، وبالحساب نفسه في
/// ZyiarahPdfService.generateAndUploadInvoice (المبلغ شامل الضريبة 15% ضمنياً).
///
/// (تصميم Stitch، 2026-09-16) قبلها كانت الشاشة تعرض زرّ تحميل PDF فقط؛ الرمز
/// والبيانات لا يراها العميل إلا بفتح الملف.
class InvoiceView {
  final String orderCode;
  final String serviceName;

  /// المبلغ المدفوع بعد الخصم، شامل الضريبة.
  final double total;

  /// الخصم شامل الضريبة (كما يُخزَّن في discount_amount).
  final double discount;
  final String? couponCode;
  final DateTime issuedAt;
  final String paymentMethod;
  final String? paymentRef;
  final bool isPaid;
  final String? pdfUrl;
  final String? pdfStatus;

  const InvoiceView({
    required this.orderCode,
    required this.serviceName,
    required this.total,
    required this.discount,
    required this.couponCode,
    required this.issuedAt,
    required this.paymentMethod,
    required this.paymentRef,
    required this.isPaid,
    required this.pdfUrl,
    required this.pdfStatus,
  });

  static const double vatRate = 0.15;

  /// الصافي الخاضع للضريبة بعد الخصم.
  double get net => total / (1 + vatRate);
  double get vat => net * vatRate;

  /// الإجمالي قبل الخصم (شامل الضريبة) وصافيه — لصفّ الخصم.
  double get grossBeforeDiscount => total + discount;
  double get subtotalBeforeDiscount => grossBeforeDiscount / (1 + vatRate);
  double get discountNet => discount / (1 + vatRate);
  bool get hasDiscount => discount > 0;

  String get paymentLabel => paymentLabelOf(paymentMethod);

  /// تسميات وسائل الدفع كما تُكتب في payment_method (التطبيق والخادم معاً).
  static String paymentLabelOf(String method) {
    switch (method.toLowerCase()) {
      case 'applepay':
      case 'apple_pay':
      case 'native_pay':
        return 'Apple Pay';
      case 'googlepay':
      case 'google_pay':
        return 'Google Pay';
      case 'samsungpay':
      case 'samsung_pay':
        return 'Samsung Pay';
      case 'creditcard':
      case 'card':
      case 'mada':
        return 'بطاقة مدى / ائتمانية';
      case 'stcpay':
      case 'stc_pay':
        return 'STC Pay';
      case 'tamara':
        return 'تمارا (Tamara)';
      case 'tabby':
        return 'تابي (Tabby)';
      case 'wallet':
        return 'محفظة زيارة';
      case 'subscription':
        return 'ضمن الاشتراك';
      case '':
      case 'pending':
        return 'بانتظار الدفع';
      default:
        return method;
    }
  }

  factory InvoiceView.fromOrder(String orderCode, Map<String, dynamic> data,
      {DateTime? now}) {
    double toD(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    DateTime? toT(dynamic v) => v is Timestamp ? v.toDate() : null;
    String? str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return InvoiceView(
      orderCode: orderCode,
      serviceName:
          str(data['service_name']) ?? str(data['service_type']) ?? '-',
      total: toD(data['amount']),
      discount: toD(data['discount_amount']),
      couponCode: str(data['coupon_code']),
      issuedAt: toT(data['paid_at']) ??
          toT(data['created_at']) ??
          now ??
          DateTime.now(),
      paymentMethod: str(data['payment_method']) ?? '',
      // الرقم المرجعي حسب البوّابة — كما يكتبه الخادم على الوثيقة.
      paymentRef: str(data['moyasar_payment_id']) ??
          str(data['tamara_order_id']) ??
          str(data['tabby_payment_id']),
      isPaid: data['is_paid'] == true,
      pdfUrl: str(data['invoice_pdf_url']),
      pdfStatus: str(data['invoice_pdf_status']),
    );
  }

  /// رمز TLV/Base64 نفسه الذي يُطبع في PDF (البائع، الرقم الضريبي، الوقت،
  /// الإجمالي شاملاً الضريبة، قيمة الضريبة).
  String qrData() => ZatcaService.generateZatcaQrCode(
        timestamp: issuedAt,
        totalAmount: total,
        vatAmount: vat,
      );
}
