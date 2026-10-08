import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/invoice_stamp.dart';

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

  /// «أنشِئِ الطلبَ إن غاب وأعطِني كودَه» — يُنادى في مسارِ الخدمةِ وحدَه
  /// (`contractId == null`) ومتى لم يُوجَد المستند.
  ///
  /// كانت هنا **نسخةٌ ثانيةٌ من حِملِ إنشاءِ الطلب** (معامَلةٌ من نحوِ
  /// أربعينَ سطراً) لتلك الحالة — غيرُ مبلوغةٍ عمليّاً، لأنّ
  /// `_createUnpaidServiceOrder` تُنتظَرُ **قبلَ** `createCheckoutSession`
  /// وهي بلا `catch` فرميُها يَمنعُ فتحَ الجلسةِ أصلاً. وقد **انحرفت**
  /// بثلاثةِ حقولٍ: `client_email` و`terrain_surcharge_percent`
  /// و`terrain_surcharge_amount` — فلو عملت لأنشأت طلباً مبلغُه يَشملُ
  /// الوعورةَ وتفصيلُه لا يَذكرُها، وبلا بريدٍ للفاتورة. فالإنشاءُ صارَ
  /// نداءً إلى الموضعِ الواحدِ الذي يَعرفُ السعر.
  final Future<String> Function() ensureOrder;

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
    required this.ensureOrder,
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
              content: Text('تعذّر تحميل صفحة الدفع — تحقّقي من الاتصال'),
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

                // (حُذفت قراءةُ `users/{uid}` هنا في 2026-10-08.) كانت
                // تَجلبُ الاسمَ والهاتفَ لحِملِ الإنشاءِ الاحتياطيِّ وحدَه،
                // فلمّا زالَ الحِملُ صارا **مُسنَدَين بلا قارئ** — ودورةُ
                // شبكةٍ بمهلةِ ٢٠ ثانيةً على مسارِ «نجحَ الدفع» تُغذّي لا
                // شيء. و`analyze` لا يَراها: كلٌّ منهما يُقرَأُ في إسنادِ
                // نفسِه (`x = d['k'] ?? x`) فيَحسبُها المُحلِّلُ مُستعمَلة.
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

                  // الطلبُ أُنشئ مسبقاً (is_paid=false) قبل جلسةِ تمارا؛
                  // فإن وُجد أخذنا كودَه، وإن غابَ طلبنا إنشاءَه من **موضعِ
                  // الإنشاءِ الواحد** (`ensureOrder`) بدلَ نسخةٍ ثانيةٍ من
                  // الحِملِ هنا. والإسنادُ في الحالتَين خادميٌّ: يتكفّلُ به
                  // `sweepUnassignedPaidOrders` بعد أن يَقلبَ
                  // `tamaraWebhook` العلَمَ — وكان المسارُ الاحتياطيُّ وحدَه
                  // يُسنِدُ من العميل، وهو لا يُبلَغ.
                  final existingOrder = await FirebaseFirestore.instance
                      .collection('orders').doc(widget.orderId).get().timeout(kNetCallTimeout);
                  final String tamaraOrderCode = existingOrder.exists
                      ? ((existingOrder.data()?['code'] as String?) ??
                          widget.orderId)
                      : await widget.ensureOrder();
                  await ZyiarahMessagingService().notifyOrderCreated(
                    clientId: user?.uid ?? '',
                    orderCode: tamaraOrderCode,
                    type: 'cleaning',
                    serviceName: widget.serviceType,
                    orderId: widget.orderId,
                  );

                  // ملاحظة: لا نزيد عدّاد استخدام الكوبون من العميل — تكفّلت به الدالة
                  // countCouponUseOnOrderCreate خادميّاً. الزيادة هنا كانت تحسبه مرّتين
                  // لطلبات تمارا (فينفد كوبون maxUses:100 عند ~50 استخداماً حقيقياً).
                }

                // ... بقية المنطق الخاص بـ ZATCA والفاتورة ...
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("تعذّر حفظ بيانات الطلب — أعيدي المحاولة"),
                    backgroundColor: Colors.red,
                  ));
                }
                return; // لا تكمل إذا فشل التسجيل الرئيسي
              }

              // توليد بيانات ZATCA وتوليد الفاتورة في الخلفية (باستخدام الحسابات الصحيحة)
              // لحظةٌ واحدةٌ مُلتقَطةٌ للمطبوعِ والرمزِ معاً.
              final DateTime issuedAt = DateTime.now();
              final String qrData =
                  invoiceQrFor(issuedAt: issuedAt, total: widget.amount);

              // جلب الكود المنشأ حديثاً لإدراجه في الفاتورة. للاشتراك كودُه معرّفُ
              // عقده — ولا نقرأ orders/{id} أصلاً: لا مستند طلب للعقد، وقراءة مستند
              // معدوم تُرفض من القواعد (resource=null) فتقتل الإغلاق كاملاً قبل
              // الفاتورة وشاشة النجاح.
              String orderCode;
              if (widget.contractId != null) {
                orderCode = widget.contractId!;
              } else {
                final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(newOrderId).get().timeout(kNetCallTimeout);
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
                issuedAt: issuedAt,
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
