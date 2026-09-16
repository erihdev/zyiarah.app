import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/services/zatca_service.dart';

/// بطاقة الفاتورة على شاشة النجاح (تصميم Stitch، 2026-09-16): تُشتقّ من وثيقة
/// الطلب بالحساب نفسه الذي تُبنى به نسخة PDF، ورمزها TLV يحمل الحقول الخمسة.
void main() {
  Map<int, String> decodeTlv(String b64) {
    final bytes = base64.decode(b64);
    final out = <int, String>{};
    var i = 0;
    while (i < bytes.length) {
      final tag = bytes[i];
      final len = bytes[i + 1];
      out[tag] = utf8.decode(bytes.sublist(i + 2, i + 2 + len));
      i += 2 + len;
    }
    return out;
  }

  group('InvoiceView.fromOrder', () {
    test('يقرأ حقول الطلب كما يكتبها الدفع والخادم', () {
      final v = InvoiceView.fromOrder('ZY-202600042', {
        'service_name': 'تنظيف منزلي',
        'amount': 230,
        'discount_amount': 11.5,
        'coupon_code': 'JAZAN25',
        'is_paid': true,
        'payment_method': 'applepay',
        'moyasar_payment_id': 'MOY-98234',
        'created_at': Timestamp.fromDate(DateTime(2026, 9, 16, 9)),
        'paid_at': Timestamp.fromDate(DateTime(2026, 9, 16, 9, 5)),
        'invoice_pdf_url': 'https://x/y.pdf',
      });
      expect(v.serviceName, 'تنظيف منزلي');
      expect(v.total, 230);
      expect(v.discount, 11.5);
      expect(v.couponCode, 'JAZAN25');
      expect(v.isPaid, isTrue);
      expect(v.paymentLabel, 'Apple Pay');
      expect(v.paymentRef, 'MOY-98234');
      expect(v.issuedAt, DateTime(2026, 9, 16, 9, 5), reason: 'paid_at قبل created_at');
      expect(v.pdfUrl, 'https://x/y.pdf');
      expect(v.hasDiscount, isTrue);
    });

    test('غياب الحقول لا يكسر: صفر ونصوص افتراضية ووقت الآن', () {
      final now = DateTime(2026, 1, 1);
      final v = InvoiceView.fromOrder('X', const {}, now: now);
      expect(v.total, 0);
      expect(v.serviceName, '-');
      expect(v.isPaid, isFalse);
      expect(v.paymentLabel, 'بانتظار الدفع');
      expect(v.paymentRef, isNull);
      expect(v.issuedAt, now);
      expect(v.hasDiscount, isFalse);
      // amount نصّاً (وثيقة قديمة) يُقرأ رقماً.
      expect(InvoiceView.fromOrder('X', {'amount': '115'}).total, 115);
    });

    test('المرجع حسب البوّابة: ميسر ثم تمارا ثم تابي', () {
      expect(InvoiceView.fromOrder('X', {'tamara_order_id': 'T1'}).paymentRef, 'T1');
      expect(InvoiceView.fromOrder('X', {'tabby_payment_id': 'B1'}).paymentRef, 'B1');
      expect(
          InvoiceView.fromOrder('X', {'moyasar_payment_id': 'M1', 'tamara_order_id': 'T1'})
              .paymentRef,
          'M1');
    });

    test('تسميات وسائل الدفع كما تُكتب في payment_method', () {
      expect(InvoiceView.paymentLabelOf('native_pay'), 'Apple Pay');
      expect(InvoiceView.paymentLabelOf('creditcard'), 'بطاقة مدى / ائتمانية');
      expect(InvoiceView.paymentLabelOf('stcpay'), 'STC Pay');
      expect(InvoiceView.paymentLabelOf('tamara'), 'تمارا (Tamara)');
      expect(InvoiceView.paymentLabelOf('tabby'), 'تابي (Tabby)');
      expect(InvoiceView.paymentLabelOf('wallet'), 'محفظة زيارة');
      expect(InvoiceView.paymentLabelOf('subscription'), 'ضمن الاشتراك');
      expect(InvoiceView.paymentLabelOf('weird_gateway'), 'weird_gateway');
    });
  });

  test('الحساب الضريبي يطابق ZyiarahPdfService: الصافي = الإجمالي/1.15 والضريبة 15% منه',
      () {
    final v = InvoiceView.fromOrder('X', {'amount': 230.0, 'discount_amount': 23.0});
    expect(v.net, closeTo(200, 0.001));
    expect(v.vat, closeTo(30, 0.001));
    expect(v.grossBeforeDiscount, 253);
    expect(v.subtotalBeforeDiscount, closeTo(220, 0.001));
    expect(v.discountNet, closeTo(20, 0.001));
    // الصافي + الضريبة = الإجمالي المدفوع.
    expect(v.net + v.vat, closeTo(v.total, 0.001));
  });

  test('رمز QR: خمسة حقول TLV بالبائع والرقم الضريبي والوقت والإجمالي والضريبة', () {
    final v = InvoiceView.fromOrder('X', {
      'amount': 230.0,
      'paid_at': Timestamp.fromDate(DateTime.utc(2026, 9, 16, 9, 0, 0)),
    });
    final tags = decodeTlv(v.qrData());
    expect(tags.keys.toList()..sort(), [1, 2, 3, 4, 5]);
    expect(tags[1], ZatcaService.merchantName);
    expect(tags[2], ZatcaService.vatNumber);
    expect(tags[2], '310885360200003', reason: 'الرقم الضريبي المسجَّل — لا يُغيَّر');
    expect(tags[3], '2026-09-16T09:00:00Z');
    expect(tags[4], '230.00');
    expect(tags[5], '30.00');
  });
}
