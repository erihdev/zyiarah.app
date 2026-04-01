import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zyiarah/screens/invoice_screen.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/invoice_pdf_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TamaraCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final double amount;
  final String orderId;
  final String serviceType;
  final GeoPoint location;
  final int? hours;
  final DateTime? serviceDate;
  final String? zoneName;
  final int workerCount;
  final String? couponCode;
  final double discountAmount;

  const TamaraCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    required this.amount,
    required this.orderId,
    required this.serviceType,
    required this.location,
    this.hours,
    this.serviceDate,
    this.zoneName,
    this.workerCount = 1,
    this.couponCode,
    this.discountAmount = 0.0,
  });

  @override
  State<TamaraCheckoutScreen> createState() => _TamaraCheckoutScreenState();
}

class _TamaraCheckoutScreenState extends State<TamaraCheckoutScreen> {
  late final WebViewController _controller;
  final ZyiarahOrderService _orderService = ZyiarahOrderService();

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            if (url.contains('payment-success') || url.contains('payment-success-mock')) {
              // إنشاء الطلب في Firestore
              final String newOrderId = await _orderService.createOrder(
                clientId: FirebaseAuth.instance.currentUser?.uid ?? "guest_client", 
                serviceType: widget.serviceType,
                amount: widget.amount,
                location: widget.location,
                paymentMethod: 'tamara',
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                zoneName: widget.zoneName,
                workerCount: widget.workerCount,
                couponCode: widget.couponCode,
                discountAmount: widget.discountAmount,
              );

              // توليد بيانات ZATCA وتوليد الفاتورة في الخلفية
              final double vatAmount = widget.amount * 0.15;
              final String qrData = ZatcaService.generateZatcaQrCode(
                merchantName: "مؤسسة معاذ يحي محمد المالكي",
                vatNumber: "310885360200003",
                timestamp: DateTime.now(),
                totalAmount: widget.amount,
                vatAmount: vatAmount,
              );

              InvoicePdfService.generateAndUploadInvoice(
                orderId: newOrderId,
                amount: widget.amount,
                qrData: qrData,
              ).then((downloadUrl) {
                if (downloadUrl != null) {
                  FirebaseFirestore.instance
                      .collection('orders')
                      .doc(newOrderId)
                      .update({
                    'invoice_pdf_url': downloadUrl,
                  });
                }
              });

              // توجيه المستخدم لصفحة النجاح (الفاتورة) داخل التطبيق
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ZyiarahInvoiceScreen(
                    amount: widget.amount,
                    orderId: newOrderId,
                    hours: widget.hours,
                    serviceDate: widget.serviceDate,
                    workerCount: widget.workerCount,
                    couponCode: widget.couponCode,
                    discountAmount: widget.discountAmount,
                  ),
                ),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("إتمام الدفع - تمارا"),
        backgroundColor: const Color(0xFF5D1B5E),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
