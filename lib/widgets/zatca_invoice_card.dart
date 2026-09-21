import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zyiarah/models/invoice_view.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// بطاقة «فاتورة ضريبية مبسطة» على الشاشة (تصميم Stitch zatca_1/zatca_2):
/// المنشأة، الرقم الضريبي والسجل، الوقت، رمز QR بصيغة TLV، البنود، الملخص
/// الضريبي، ووسيلة السداد ومرجعها. بيانات المنشأة تُمرَّر صراحةً (افتراضها من
/// ZatcaService بعد ensureConfigLoaded) كي تُختبر البطاقة بلا Firebase.
class ZatcaInvoiceCard extends StatelessWidget {
  final InvoiceView view;
  final String merchantName;
  final String vatNumber;
  final String crNumber;

  ZatcaInvoiceCard({
    super.key,
    required this.view,
    String? merchantName,
    String? vatNumber,
    String? crNumber,
  })  : merchantName = merchantName ?? ZatcaService.merchantName,
        vatNumber = vatNumber ?? ZatcaService.vatNumber,
        crNumber = crNumber ?? ZatcaService.crNumber;

  static String _money(double v) => '${v.toStringAsFixed(2)} ر.س';

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    const ink = ZyiarahTheme.ink;
    const muted = ZyiarahTheme.inkMuted;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── الترويسة ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFFF1F5F9),
            child: Row(children: [
              const Icon(Icons.receipt_long_rounded,
                  color: ZyiarahTheme.brand, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('فاتورة ضريبية مبسطة',
                    style: GoogleFonts.tajawal(
                        fontSize: 15, fontWeight: FontWeight.bold, color: ink)),
              ),
              Text('SIMPLIFIED TAX INVOICE',
                  style: GoogleFonts.tajawal(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: muted,
                      letterSpacing: 0.5)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── المنشأة ───
                Text('المنشأة المزودة للخدمة',
                    style: GoogleFonts.tajawal(fontSize: 11, color: muted)),
                Text(merchantName,
                    style: GoogleFonts.tajawal(
                        fontSize: 16, fontWeight: FontWeight.bold, color: ink)),
                const SizedBox(height: 10),
                _kv('السجل التجاري (CR)', crNumber),
                _kv('الرقم الضريبي (VAT)', vatNumber),
                _kv('رقم الطلب', view.orderCode),
                _kv('التاريخ والوقت', _fmt(view.issuedAt)),
                const SizedBox(height: 14),

                // ─── رمز QR ───
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: view.qrData(),
                        version: QrVersions.auto,
                        size: 118,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.verified_rounded,
                                color: ZyiarahTheme.success, size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                  'رمز QR وفق متطلبات هيئة الزكاة والضريبة والجمارك',
                                  style: GoogleFonts.tajawal(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: ink)),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            'مشفّر بصيغة TLV: اسم المنشأة، الرقم الضريبي، وقت الإصدار، '
                            'الإجمالي شاملاً الضريبة، وقيمة الضريبة. امسحه بتطبيق الهيئة للتحقق.',
                            style: GoogleFonts.tajawal(
                                fontSize: 10.5, color: muted, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ─── البنود ───
                Text('تفاصيل البنود والخدمات',
                    style: GoogleFonts.tajawal(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: ink)),
                const SizedBox(height: 6),
                _lineItem(view.serviceName, _money(view.subtotalBeforeDiscount),
                    sub: 'خاضع لضريبة 15%'),
                if (view.hasDiscount)
                  _lineItem(
                      'الخصم${view.couponCode != null ? ' (${view.couponCode})' : ''}',
                      '- ${_money(view.discountNet)}',
                      valueColor: ZyiarahTheme.error),
                const Divider(height: 20),

                // ─── الملخص ───
                _kv('الإجمالي الخاضع للضريبة (غير شامل)', _money(view.net)),
                _kv('ضريبة القيمة المضافة (15%)', _money(view.vat)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الإجمالي الكلي النهائي',
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: ink)),
                        Text('شامل ضريبة القيمة المضافة 15%',
                            style: GoogleFonts.tajawal(
                                fontSize: 10.5, color: muted)),
                      ],
                    ),
                  ),
                  Text(_money(view.total),
                      style: GoogleFonts.tajawal(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: ZyiarahTheme.brand)),
                ]),
                const SizedBox(height: 14),

                // ─── السداد ───
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: view.isPaid
                        ? const Color(0xFFE1F0E4)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(
                      view.isPaid
                          ? Icons.check_circle_rounded
                          : Icons.schedule_rounded,
                      color: view.isPaid
                          ? const Color(0xFF059669)
                          : const Color(0xFFB45309),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('طريقة السداد: ${view.paymentLabel}',
                              style: GoogleFonts.tajawal(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: ink)),
                          if (view.paymentRef != null)
                            Text('معرّف السداد: ${view.paymentRef}',
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.right,
                                style: GoogleFonts.tajawal(
                                    fontSize: 10.5, color: muted)),
                        ],
                      ),
                    ),
                    Text(view.isPaid ? 'مدفوعة بالكامل' : 'بانتظار تأكيد الدفع',
                        style: GoogleFonts.tajawal(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: view.isPaid
                                ? const Color(0xFF059669)
                                : const Color(0xFFB45309))),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(
            child: Text(k,
                style: GoogleFonts.tajawal(
                    fontSize: 11.5, color: ZyiarahTheme.inkMuted))),
        Text(v,
            textDirection: TextDirection.ltr,
            style: GoogleFonts.tajawal(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ZyiarahTheme.ink)),
      ]),
    );
  }

  Widget _lineItem(String title, String value,
      {String? sub, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.tajawal(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: ZyiarahTheme.ink)),
            if (sub != null)
              Text(sub,
                  style: GoogleFonts.tajawal(
                      fontSize: 10.5, color: ZyiarahTheme.inkMuted)),
          ]),
        ),
        Text(value,
            style: GoogleFonts.tajawal(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: valueColor ?? ZyiarahTheme.ink)),
      ]),
    );
  }
}
