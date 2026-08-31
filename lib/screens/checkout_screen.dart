import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/services/counter_service.dart';
import 'package:zyiarah/services/order_service.dart';

class TamaraCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final double amount;
  final String orderId;
  final String serviceType;
  // nullable: لا نستبدل موقعاً غائباً بإحداثيات الرياض الوهمية — يُغفل الحقل من الطلب.
  final GeoPoint? location;
  final int? hours;
  final DateTime? serviceDate;
  final String? zoneName;
  final int workerCount;
  final String? couponCode;
  final double discountAmount;
  final String? contractId;
  final int? planVisits;
  final String? customerName;
  final String? customerPhone;
  // تفصيل الخدمة (باقات السكن/كنب/مكيفات…) — يُكتب مع الطلب الاحتياطي وإلا فقد
  // الطلبُ هويته: الإدارة/السائق بلا تفصيل والتسعير الخادمي يظنه ساعات قديمة.
  final Map<String, dynamic>? serviceMeta;
  /// Callback يُستدعى بعد نجاح الدفع وإنشاء الطلب — يمرر كود الطلب للمتصل.
  /// إذا كان null يتم التوجيه لـ ZyiarahOrderSuccessScreen مباشرة.
  final Future<void> Function(String orderCode)? onOrderCreated;

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
    this.contractId,
    this.planVisits,
    this.customerName,
    this.customerPhone,
    this.serviceMeta,
    this.onOrderCreated,
  });



  @override
  State<TamaraCheckoutScreen> createState() => _TamaraCheckoutScreenState();
}

class _TamaraCheckoutScreenState extends State<TamaraCheckoutScreen> {
  late final WebViewController _controller;
  bool _paymentProcessed = false; // guard against duplicate onPageStarted fires
  bool _pageLoading = true; // مؤشّر تحميل أثناء فتح صفحة تمارا

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _pageLoading = false);
          },
          onWebResourceError: (err) {
            // فشل تحميل الصفحة الأولى (شبكة/جلسة منتهية) → أغلق برسالة بدل بياض.
            if (_paymentProcessed || !_pageLoading || !mounted) return;
            _paymentProcessed = true;
            // نلتقط الـ messenger قبل pop لأن السياق يُتلَف بعده فلا يظهر التنبيه.
            final messenger = ScaffoldMessenger.of(context);
            Navigator.of(context).pop();
            messenger.showSnackBar(const SnackBar(
              content: Text('تعذّر تحميل صفحة الدفع — تحقّق من الاتصال'),
              backgroundColor: Colors.red,
            ));
          },
          onPageStarted: (url) async {
            if (_paymentProcessed) return;
            // إلغاء/فشل الدفع → أغلق الشاشة برسالة بدل ترك المستخدم عالقاً في الصفحة.
            if (url.contains('payment-cancel') || url.contains('payment-failure')) {
              _paymentProcessed = true;
              if (mounted) {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                messenger.showSnackBar(const SnackBar(
                  content: Text('تم إلغاء الدفع عبر تمارا'),
                  backgroundColor: Colors.orange,
                ));
              }
              return;
            }
            if (url.contains('payment-success')) {
                _paymentProcessed = true;
                String newOrderId = widget.orderId;
                final user = FirebaseAuth.instance.currentUser;

                // جلب اسم العميل الحقيقي من Firestore (displayName فارغ في معظم الحالات)
                String clientName = 'عميل زيارة';
                String clientPhone = widget.customerPhone ?? 'غير متوفر';
                if (user != null) {
                  try {
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                    if (userDoc.exists) {
                      clientName = userDoc.data()?['name'] ?? clientName;
                      clientPhone = userDoc.data()?['phone'] ?? clientPhone;
                    }
                  } catch (_) {}
                }

                try {

                if (widget.contractId != null) {
                  // التفعيل (status='active') + منح الزيارات + توليدها + الإشعار يتم
                  // خادميّاً في activateContractOnPaid عند قلب is_paid عبر tamara webhook
                  // (مرجع تمارا = معرّف العقد). لا كتابة من العميل — القواعد تمنعها.
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
                  final bool isHourly = widget.hours != null && widget.serviceDate != null;

                  String tamaraOrderCode = '';
                  // الطلب أُنشئ مسبقاً (is_paid=false) قبل جلسة تمارا؛ إن وُجد نتخطّى
                  // الإنشاء والإسناد — يتكفّل sweepUnassignedPaidOrders بالإسناد بعد
                  // أن يقلب tamaraWebhook is_paid=true.
                  final existingOrder = await FirebaseFirestore.instance
                      .collection('orders').doc(widget.orderId).get();
                  if (existingOrder.exists) {
                    tamaraOrderCode = existingOrder.data()?['code'] ?? widget.orderId;
                    await ZyiarahMessagingService().notifyOrderCreated(
                      clientId: user?.uid ?? '',
                      orderCode: tamaraOrderCode,
                      type: 'cleaning',
                      serviceName: widget.serviceType,
                      orderId: widget.orderId,
                    );
                  } else {
                  await FirebaseFirestore.instance.runTransaction((transaction) async {
                    final nextId = await ZyiarahCounterService().getNextOrderNumber(transaction);
                    tamaraOrderCode = ZyiarahOrderUtil.formatSmartCode(nextId);
                    transaction.set(
                      FirebaseFirestore.instance.collection('orders').doc(widget.orderId),
                      {
                        'code': tamaraOrderCode,
                        'client_id': user?.uid ?? "unauthenticated_user",
                        'client_name': clientName,
                        'client_phone': clientPhone,
                        'user_phone': clientPhone,
                        'service_type': widget.serviceType,
                        'service_name': widget.serviceType,
                        'amount': widget.amount,
                        // is_paid يقلبه tamaraWebhook خادمياً — يوافق قاعدة Stage-C.
                        'is_paid': false,
                        'status': 'pending',
                        // موقع غائب ⇒ نُغفل الحقل (لا إحداثيات وهمية) — المستهلكون يتحمّلون غيابه.
                        if (widget.location != null) 'location': widget.location,
                        'payment_method': 'tamara',
                        'created_at': FieldValue.serverTimestamp(),
                        'hours_contracted': widget.hours ?? 4,
                        'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
                        'zone_name': widget.zoneName,
                        'worker_count': widget.workerCount,
                        'coupon_code': widget.couponCode,
                        'discount_amount': widget.discountAmount,
                        if (widget.serviceMeta != null)
                          'service_meta': widget.serviceMeta,
                        if (isHourly && widget.serviceDate != null) ...{
                          'booking_date': '${widget.serviceDate!.year}-'
                              '${widget.serviceDate!.month.toString().padLeft(2, '0')}-'
                              '${widget.serviceDate!.day.toString().padLeft(2, '0')}',
                          'booking_time_slot':
                              '${widget.serviceDate!.hour.toString().padLeft(2, '0')}:00',
                        },
                      },
                    );
                  });

                  if (isHourly) {
                    // تعيين سائق تلقائياً وتحديث الطلب إلى accepted
                    final assigned = await ZyiarahOrderService().autoAssignDriverForHourly(
                      orderId: widget.orderId,
                      startDateTime: widget.serviceDate!,
                      durationHours: widget.hours!,
                    );
                    if (assigned) {
                      await ZyiarahMessagingService().notifyOrderCreated(
                        clientId: user?.uid ?? '',
                        orderCode: tamaraOrderCode,
                        type: 'cleaning',
                        serviceName: widget.serviceType,
                        orderId: widget.orderId,
                      );
                    } else {
                      // في حالة تعذر التعيين المباشر، لا نلغي الطلب المدفوع بتمارا! بل يبقى pending للتوزيع اليدوي ونرسل الإشعار الافتراضي
                      await ZyiarahMessagingService().notifyOrderCreated(
                        clientId: user?.uid ?? '',
                        orderCode: tamaraOrderCode,
                        type: 'cleaning',
                        serviceName: widget.serviceType,
                        orderId: widget.orderId,
                      );
                    }
                  } else {
                    await ZyiarahMessagingService().notifyOrderCreated(
                      clientId: user?.uid ?? '',
                      orderCode: tamaraOrderCode,
                      type: 'cleaning',
                      serviceName: widget.serviceType,
                      orderId: widget.orderId,
                    );
                  }
                  } // نهاية مسار الإنشاء الاحتياطي (الطلب غير موجود مسبقاً)

                  // ملاحظة: لا نزيد عدّاد استخدام الكوبون من العميل — تكفّلت به الدالة
                  // countCouponUseOnOrderCreate خادميّاً. الزيادة هنا كانت تحسبه مرّتين
                  // لطلبات تمارا (فينفد كوبون maxUses:100 عند ~50 استخداماً حقيقياً).
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

              // جلب الكود المنشأ حديثاً لإدراجه في الفاتورة. للاشتراك كودُه معرّفُ
              // عقده — ولا نقرأ orders/{id} أصلاً: لا مستند طلب للعقد، وقراءة مستند
              // معدوم تُرفض من القواعد (resource=null) فتقتل الإغلاق كاملاً قبل
              // الفاتورة وشاشة النجاح.
              String orderCode;
              if (widget.contractId != null) {
                orderCode = widget.contractId!;
              } else {
                final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(newOrderId).get();
                orderCode = orderDoc.data()?['code'] ?? newOrderId.substring(0, 8).toUpperCase();
              }

              // للاشتراك تُكتب الفاتورة على مستند العقد الحقيقي contracts/{contractId} —
              // كان المعرّف العشوائي newOrderId (لا مستند عقد به) فتضيع فاتورة الاشتراك.
              final String invoiceCollection =
                  widget.contractId != null ? 'contracts' : 'orders';
              final String invoiceDocId = widget.contractId ?? newOrderId;
              ZyiarahPdfService.generateAndUploadInvoice(
                orderId: invoiceDocId,
                orderCode: orderCode,
                amount: widget.amount,
                qrData: qrData,
                serviceName: widget.serviceType,
                discountAmount: widget.discountAmount,
                couponCode: widget.couponCode,
                collectionPath: invoiceCollection,
              ).then((downloadUrl) {
                if (downloadUrl != null) {
                  FirebaseFirestore.instance
                      .collection(invoiceCollection)
                      .doc(invoiceDocId)
                      .update({
                    'invoice_pdf_url': downloadUrl,
                  });
                }
              });

              // إرسال تأكيد بالبريد الإلكتروني للعميل والمسؤول (تمارا)
              String finalCommCode = orderCode;
              if (widget.contractId != null) finalCommCode = widget.contractId!;

              await ZyiarahMessagingService().notifyNewOrder({
                'code': finalCommCode,
                'client_name': widget.customerName ?? user?.displayName ?? 'عميل زيارة',
                'client_phone': widget.customerPhone ?? user?.phoneNumber ?? 'غير متوفر',
                'service_type': widget.serviceType,
                'amount': widget.amount,
                'zone': widget.zoneName ?? 'غير محدد',
                'date_time': widget.serviceDate != null ? intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!) : 'غير محدد',
                'worker_count': widget.workerCount,
                'coupon': widget.couponCode ?? 'لا يوجد',
              }, customerEmail: user?.email);



              // توجيه المستخدم لشاشة النجاح الموحدة
              if (!mounted) return;
              if (widget.onOrderCreated != null) {
                await widget.onOrderCreated!(finalCommCode);
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ZyiarahOrderSuccessScreen(orderCode: finalCommCode),
                  ),
                  (route) => route.isFirst,
                );
              }
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
        backgroundColor: const Color(0xFF660033),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_pageLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF660033))),
        ],
      ),
    );
  }
}
