import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';

/// شاشة WebView لإتمام دفع تمارا الخاص بطلبات المتجر.
/// لا تُنشئ الطلب في Firestore إلا بعد تأكيد نجاح الدفع (payment-success URL).
class StoreTamaraCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final String orderId;
  final List<Map<String, dynamic>> items;
  final double total;
  final String customerName;
  final String customerPhone;

  const StoreTamaraCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.orderId,
    required this.items,
    required this.total,
    required this.customerName,
    required this.customerPhone,
  });

  @override
  State<StoreTamaraCheckoutScreen> createState() => _StoreTamaraCheckoutScreenState();
}

class _StoreTamaraCheckoutScreenState extends State<StoreTamaraCheckoutScreen> {
  late final WebViewController _controller;
  bool _paymentProcessed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) async {
          if (_paymentProcessed) return;
          if (url.contains('payment-success') || url.contains('payment-success-mock')) {
            _paymentProcessed = true;
            final user = FirebaseAuth.instance.currentUser;

            try {
              // Transaction ذري: عداد + إنشاء طلب المتجر في خطوة واحدة
              final docRef = FirebaseFirestore.instance
                  .collection('store_orders')
                  .doc(widget.orderId);
              final counterRef = FirebaseFirestore.instance
                  .collection('metadata')
                  .doc('order_counter');
              String orderCode = '';

              await FirebaseFirestore.instance.runTransaction((tx) async {
                final counterSnap = await tx.get(counterRef);
                final lastId = counterSnap.exists
                    ? ((counterSnap.data()?['last_id'] as num?)?.toInt() ?? 100)
                    : 100;
                final nextId = lastId + 1;
                orderCode = ZyiarahOrderUtil.formatSmartCode(nextId);
                if (counterSnap.exists) {
                  tx.update(counterRef, {'last_id': nextId});
                } else {
                  tx.set(counterRef, {'last_id': nextId});
                }
                tx.set(docRef, {
                  'code': orderCode,
                  'client_id': user?.uid ?? 'unauthenticated',
                  'client_name': widget.customerName,
                  'client_phone': widget.customerPhone,
                  'items': widget.items,
                  'total_amount': widget.total,
                  'payment_method': 'tamara',
                  'status': 'pending',
                  'created_at': FieldValue.serverTimestamp(),
                });
              });

              // (E) فاتورة ضريبية ZATCA لطلب المتجر (تمارا) — non-fatal، المبلغ شامل الضريبة
              final double storeVat = widget.total - (widget.total / 1.15);
              final String storeQr = ZatcaService.generateZatcaQrCode(
                timestamp: DateTime.now(),
                totalAmount: widget.total,
                vatAmount: storeVat,
              );
              ZyiarahPdfService.generateAndUploadInvoice(
                orderId: widget.orderId,
                orderCode: orderCode,
                amount: widget.total,
                qrData: storeQr,
                serviceName: 'طلب منتجات من المتجر',
                collectionPath: 'store_orders',
              ).catchError((_) => null);

              // إشعارات non-fatal — الإخفاق لا يوقف تجربة المستخدم
              ZyiarahMessagingService().notifyOrderCreated(
                clientId: user?.uid ?? '',
                orderCode: orderCode,
                serviceName: 'طلب منتجات من المتجر',
                type: 'store',
              ).catchError((_) {});

              ZyiarahMessagingService().notifyNewOrder({
                'code': orderCode,
                'client_name': widget.customerName,
                'client_phone': widget.customerPhone,
                'service_type': 'طلب منتجات نظافة (تمارا)',
                'amount': widget.total,
                'zone': 'طلب عبر المتجر',
                'date_time': DateTime.now().toString().split('.')[0],
                'worker_count': 0,
                'coupon': 'لا يوجد',
              }, customerEmail: user?.email).catchError((_) {});

              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ZyiarahOrderSuccessScreen(
                    orderCode: orderCode,
                    title: 'تم استلام طلب المتجر!',
                    subtitle: 'لقد وصل طلبك للإدارة، سنقوم بتجهيز منتجاتك والتواصل معك فوراً.',
                  ),
                ),
              );
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('خطأ في تسجيل الطلب: $e'),
                  backgroundColor: Colors.red,
                ));
              }
            }
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
