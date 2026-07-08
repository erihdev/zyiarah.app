import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:zyiarah/screens/moyasar_card_screen.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:zyiarah/utils/global_error_handler.dart';

/// شاشة دفع طلب المتجر — تُفتح فقط بعد موافقة الإدارة على الطلب.
/// طرق الدفع المعتمدة: ميسر (بطاقة) + تمارا + الدفع عند الاستلام (COD).
/// لا تُنشئ طلباً جديداً؛ بل تُحدّث طلب المتجر القائم وتولّد طلب التوصيل والفاتورة.
class StorePaymentScreen extends StatefulWidget {
  final String storeOrderId;
  final String orderCode;
  final List<Map<String, dynamic>> items;
  final double total;
  final String customerName;
  final String customerPhone;

  const StorePaymentScreen({
    super.key,
    required this.storeOrderId,
    required this.orderCode,
    required this.items,
    required this.total,
    required this.customerName,
    required this.customerPhone,
  });

  @override
  State<StorePaymentScreen> createState() => _StorePaymentScreenState();
}

class _StorePaymentScreenState extends State<StorePaymentScreen> {
  String _selectedMethod = 'card'; // 'card' | 'tamara' | 'cod'
  bool _isLoading = false;
  bool _agreeToTerms = false;
  bool _tamaraEnabled = false;

  double get _vat => widget.total - (widget.total / 1.15);
  double get _subtotal => widget.total - _vat;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_configs')
          .doc('main_settings')
          .get();
      if (mounted) {
        setState(() =>
            _tamaraEnabled = doc.data()?['tamara_enabled'] as bool? ?? false);
      }
    } catch (_) {}
  }

  bool get _tamaraAvailable => _tamaraEnabled && widget.total >= 100;

  Future<void> _handlePay() async {
    if (_isLoading) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى الموافقة على الشروط والأحكام')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_selectedMethod == 'cod') {
        await _finalizeStorePayment('cash_on_delivery', isPaid: false);
      } else if (_selectedMethod == 'card') {
        setState(() => _isLoading = false);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoyasarCardScreen(
              amountSAR: widget.total,
              description: 'طلب متجر زيارة #${widget.orderCode}',
              orderId: widget.storeOrderId,
              onSuccess: (paymentId) async {
                setState(() => _isLoading = true);
                await _finalizeStorePayment('card', isPaid: true);
              },
              onFailure: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error, style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.red.shade800,
                  ));
                }
              },
            ),
          ),
        );
      } else if (_selectedMethod == 'tamara') {
        String? checkoutUrl;
        try {
          checkoutUrl = await TamaraService().createCheckoutSession(
            orderId: widget.storeOrderId,
            amount: widget.total,
            customerPhone: widget.customerPhone,
            customerName: widget.customerName,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ في بوابة تمارا: $e')),
            );
          }
          return;
        }
        if (checkoutUrl == null) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تعذّر بدء جلسة الدفع، حاول مجدداً')),
            );
          }
          return;
        }
        if (!mounted) return;
        setState(() => _isLoading = false);
        final bool? paid = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => _StoreTamaraWebView(checkoutUrl: checkoutUrl!),
          ),
        );
        if (paid == true) {
          setState(() => _isLoading = true);
          await _finalizeStorePayment('tamara', isPaid: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        GlobalErrorHandler.handleError(e);
      }
    }
  }

  /// تحديث طلب المتجر بعد نجاح الدفع + توليد طلب التوصيل والفاتورة.
  Future<void> _finalizeStorePayment(String method, {required bool isPaid}) async {
    final user = FirebaseAuth.instance.currentUser;

    // 1) تحديث طلب المتجر القائم
    await FirebaseFirestore.instance
        .collection('store_orders')
        .doc(widget.storeOrderId)
        .update({
      'payment_method': method,
      'is_paid': isPaid,
      'payment_status': isPaid ? 'paid' : 'cod',
      'status': 'processing',
      'paid_at': FieldValue.serverTimestamp(),
    });

    // 2) توليد طلب توصيل مرتبط (Direct Dispatch) — non-fatal
    try {
      await FirebaseFirestore.instance.collection('orders').doc().set({
        'code': widget.orderCode,
        'client_id': user?.uid,
        'client_name': widget.customerName,
        'client_phone': widget.customerPhone,
        'service_type': 'توصيل طلب متجر',
        'service_name': 'توصيل منتجات المتجر',
        'amount': widget.total,
        'is_paid': isPaid,
        'payment_method': method,
        'status': 'pending_admin_approval',
        'source_collection': 'store_orders',
        'store_order_id': widget.storeOrderId,
        'location': const GeoPoint(24.7136, 46.6753),
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    // 3) فاتورة ZATCA (المبلغ شامل الضريبة) — non-fatal
    try {
      final String qr = ZatcaService.generateZatcaQrCode(
        timestamp: DateTime.now(),
        totalAmount: widget.total,
        vatAmount: _vat,
      );
      await ZyiarahPdfService.generateAndUploadInvoice(
        orderId: widget.storeOrderId,
        orderCode: widget.orderCode,
        amount: widget.total,
        qrData: qr,
        serviceName: 'طلب منتجات من المتجر',
        collectionPath: 'store_orders',
      );
    } catch (_) {}

    // 4) إشعار الإدارة بالدفعة — non-fatal
    ZyiarahMessagingService()
        .notifyAdminOfPayment(
          orderCode: widget.orderCode,
          amount: widget.total,
          type: 'store',
          clientName: widget.customerName,
        )
        .catchError((_) {});

    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ZyiarahOrderSuccessScreen(
          orderCode: widget.orderCode,
          invoiceCollection: 'store_orders',
          title: isPaid ? 'تم تأكيد الدفع! 🎉' : 'تم تأكيد الطلب!',
          subtitle: isPaid
              ? 'تم استلام دفعتك بنجاح، سنجهّز منتجاتك ونتواصل معك للتوصيل.'
              : 'سيتم تحصيل المبلغ عند الاستلام. سنجهّز منتجاتك ونتواصل معك للتوصيل.',
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool moyasarReady =
        (dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '').isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          appBar: AppBar(
            title: Text('إتمام دفع طلب المتجر',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF5D1B5E),
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 20),
                  Text('اختر طريقة الدفع',
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  if (moyasarReady)
                    _buildOption(
                      id: 'card',
                      title: 'بطاقة فيزا / مدى',
                      subtitle: 'دفع آمن عبر ميسر',
                      icon: Icons.credit_card,
                    ),
                  if (_tamaraAvailable) ...[
                    const SizedBox(height: 12),
                    _buildOption(
                      id: 'tamara',
                      title: 'تمارا | Tamara',
                      subtitle: 'قسّم فاتورتك على 4 دفعات',
                      icon: Icons.timer_outlined,
                      color: const Color(0xFFE5A170),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _buildOption(
                    id: 'cod',
                    title: 'الدفع عند الاستلام',
                    subtitle: 'ادفع نقداً أو شبكة عند استلام المنتجات',
                    icon: Icons.money,
                    color: Colors.green,
                  ),
                  const SizedBox(height: 20),
                  _buildTerms(),
                  const SizedBox(height: 100),
                ],
              ),
              _buildBottomButton(),
              if (_isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF5D1B5E))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ملخص الطلب #${widget.orderCode}',
              style:
                  GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(height: 24),
          _row('عدد المنتجات', '${widget.items.length}'),
          _row('المبلغ الأساسي', '${_subtotal.toStringAsFixed(2)} ر.س'),
          _row('الضريبة (15%)', '${_vat.toStringAsFixed(2)} ر.س'),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي المستحق',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${widget.total.toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: const Color(0xFF5D1B5E))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 14)),
          Text(value,
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    Color? color,
  }) {
    final bool isSelected = _selectedMethod == id;
    return InkWell(
      onTap: () => setState(() => _selectedMethod = id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3E8F4) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  isSelected ? const Color(0xFF5D1B5E) : Colors.grey.shade200,
              width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF5D1B5E).withValues(alpha: 0.1)
                    : Colors.grey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color ?? const Color(0xFF5D1B5E)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle,
                      style: GoogleFonts.tajawal(
                          fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF5D1B5E)),
          ],
        ),
      ),
    );
  }

  Widget _buildTerms() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: _agreeToTerms
                ? const Color(0xFF5D1B5E)
                : Colors.grey.shade200),
      ),
      child: CheckboxListTile(
        value: _agreeToTerms,
        onChanged: (val) => setState(() => _agreeToTerms = val ?? false),
        activeColor: const Color(0xFF5D1B5E),
        title: Text('أوافق على شروط الخدمة وسياسة الخصوصية الخاصة بزيارة',
            style: GoogleFonts.tajawal(
                fontSize: 12, fontWeight: FontWeight.bold)),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildBottomButton() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _handlePay,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _agreeToTerms ? const Color(0xFF5D1B5E) : Colors.grey.shade300,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white))
              : Text('تأكيد وإتمام الدفع',
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      ),
    );
  }
}

/// WebView مبسّط لدفع تمارا — يُرجع true عند نجاح الدفع.
class _StoreTamaraWebView extends StatefulWidget {
  final String checkoutUrl;
  const _StoreTamaraWebView({required this.checkoutUrl});

  @override
  State<_StoreTamaraWebView> createState() => _StoreTamaraWebViewState();
}

class _StoreTamaraWebViewState extends State<_StoreTamaraWebView> {
  late final WebViewController _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (_done) return;
          if (url.contains('payment-success')) {
            _done = true;
            if (mounted) Navigator.pop(context, true);
          } else if (url.contains('payment-failure') ||
              url.contains('payment-cancel')) {
            _done = true;
            if (mounted) Navigator.pop(context, false);
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إتمام الدفع - تمارا'),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
