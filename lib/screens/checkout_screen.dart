import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zyiarah/screens/invoice_screen.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/invoice_pdf_service.dart';
import 'package:zyiarah/services/counter_service.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';

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
  final String? maintenanceId;
  final String? contractId;
  final int? planVisits;

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
    this.maintenanceId,
    this.contractId,
    this.planVisits,
  });

  @override
  State<TamaraCheckoutScreen> createState() => _TamaraCheckoutScreenState();
}

class _TamaraCheckoutScreenState extends State<TamaraCheckoutScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) async {
            if (url.contains('payment-success') || url.contains('payment-success-mock')) {
                String newOrderId = widget.orderId;
                try {
                final user = FirebaseAuth.instance.currentUser;
                
                if (widget.maintenanceId != null) {
                  // تحديث طلب الصيانة
                  await FirebaseFirestore.instance.collection('maintenance_requests').doc(widget.maintenanceId).update({
                    'status': 'paid',
                    'paymentMethod': 'tamara',
                    'paidAt': FieldValue.serverTimestamp(),
                    'totalAmountPaid': widget.amount,
                  });
                } else if (widget.contractId != null) {
                  // تفعيل العقد الإلكتروني
                  await FirebaseFirestore.instance.collection('contracts').doc(widget.contractId).update({
                    'status': 'active',
                    'paymentMethod': 'tamara',
                    'activatedAt': FieldValue.serverTimestamp(),
                  });

                  await FirebaseFirestore.instance.collection('users').doc(user?.uid).update({
                    'visits_remaining': FieldValue.increment(widget.planVisits ?? 0),
                  });

                  // إرسال إشعار التفعيل
                  await ZyiarahNotificationTriggerService().notifyContractActivated(
                    user?.uid ?? '',
                    widget.serviceType,
                    widget.planVisits ?? 0,
                  );

                  // سجل التدقيق
                  ZyiarahAuditService().logAction(
                    action: 'ACTIVATE_CONTRACT_TAMARA',
                    details: {
                      'contract_id': widget.contractId,
                      'plan': widget.serviceType,
                      'visits': widget.planVisits,
                    },
                    targetId: widget.contractId,
                  );
                } else {
                  // Generate Alphanumeric Code for Tamara Order (Ensures consistency)
                  final seq = await ZyiarahCounterService().getNextOrderNumber();
                  final orderCode = ZyiarahOrderUtil.formatSmartCode(seq);

                  // إنشاء طلب خدمة جديد بهوية محددة مسبقاً
                  await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).set({
                    'code': orderCode,
                    'client_id': user?.uid ?? "unauthenticated_user", 
                    'client_name': user?.displayName ?? 'عميل زيارة',
                    'service_type': widget.serviceType,
                    'amount': widget.amount,
                    'status': 'pending',
                    'location': widget.location,
                    'payment_method': 'tamara',
                    'created_at': FieldValue.serverTimestamp(),
                    'hours_contracted': widget.hours ?? 4,
                    'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
                    'zone_name': widget.zoneName,
                    'worker_count': widget.workerCount,
                    'coupon_code': widget.couponCode,
                    'discount_amount': widget.discountAmount,
                  });

                  if (widget.couponCode != null) {
                    try {
                      final couponSnap = await FirebaseFirestore.instance
                          .collection('promo_codes')
                          .where('code', isEqualTo: widget.couponCode)
                          .get();
                      if (couponSnap.docs.isNotEmpty) {
                        await couponSnap.docs.first.reference.update({
                          'uses': FieldValue.increment(1)
                        });
                      }
                    } catch (e) {
                      debugPrint("Coupon usage update failed (likely permission restriction): $e");
                    }
                  }
                }

                // ... بقية المنطق الخاص بـ ZATCA والفاتورة ...
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("خطأ في تسجيل بيانات الطلب: $e"),
                    backgroundColor: Colors.red,
                  ));
                }
                return; // لا تكمل إذا فشل التسجيل الرئيسي
              }

              // توليد بيانات ZATCA وتوليد الفاتورة في الخلفية (باستخدام الحسابات الصحيحة)
              final double vatAmount = widget.amount - (widget.amount / 1.15);
              final String qrData = ZatcaService.generateZatcaQrCode(
                timestamp: DateTime.now(),
                totalAmount: widget.amount,
                vatAmount: vatAmount,
              );

              // جلب الكود المنشأ حديثاً لإدراجه في الفاتورة
              final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(newOrderId).get();
              final String orderCode = orderDoc.data()?['code'] ?? newOrderId.substring(0, 8).toUpperCase();

              InvoicePdfService.generateAndUploadInvoice(
                orderId: newOrderId,
                orderCode: orderCode,
                amount: widget.amount,
                qrData: qrData,
                serviceName: widget.serviceType,
                discountAmount: widget.discountAmount,
                couponCode: widget.couponCode,
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
