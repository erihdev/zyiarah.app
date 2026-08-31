import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_picker_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/services/moyasar_service.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';
import 'package:zyiarah/screens/moyasar_card_screen.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:zyiarah/utils/global_error_handler.dart';

/// شاشة دفع طلب المتجر — تُفتح فور إنشاء الطلب (طلب مباشر، لا موافقة مسبقة).
/// طرق الدفع المعتمدة: ميسر (بطاقة) + تمارا. لا دفع عند الاستلام — أُزيل من الجذور.
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
  String _selectedMethod = 'card'; // 'card' | 'tamara'
  bool _isLoading = false;
  bool _agreeToTerms = false;
  bool _tamaraEnabled = false;
  // عنوان التوصيل — كان الطلب يُنشأ بموقع رياض ثابت (توصيل لمدينة خاطئة). نجمعه الآن.
  GeoPoint? _deliveryLocation;
  // اسم منطقة الطلب السابق الذي وُرث عنوانه منه — للعرض فقط، كي ترى العميلة
  // مصدر العنوان المقترَح وتغيّره إن لم يعد عنوانها. null عند الاختيار اليدوي.
  String? _prefillZoneName;

  double get _vat => widget.total - (widget.total / 1.15);
  double get _subtotal => widget.total - _vat;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadDefaultAddress();
  }

  /// عنوان التوصيل الافتراضي = موقع آخر طلب للعميل (عنوانه المعتاد).
  Future<void> _loadDefaultAddress() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('client_id', isEqualTo: uid)
          .orderBy('created_at', descending: true)
          .limit(5)
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        // نتخطى زيارات الاشتراك المولّدة (sub_*) والمواقع الموروثة لا المُلتقطة
        // (location_inherited=true): موقعها مركز منطقة/نقطة افتراضية لا عنوان
        // العميلة الفعلي — وراثتها هنا تُديم حلقة التسميم على طلبات المتجر.
        if (d.id.startsWith('sub_') || m['location_inherited'] == true) continue;
        final loc = m['location'];
        if (loc is GeoPoint) {
          final zn = m['zone_name'];
          if (mounted) {
            setState(() {
              _deliveryLocation = loc;
              _prefillZoneName =
                  (zn is String && zn.trim().isNotEmpty) ? zn.trim() : null;
            });
          }
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _pickAddress() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationPickerScreen(serviceName: 'عنوان توصيل الطلب'),
      ),
    );
    GeoPoint? loc;
    if (result is GeoPoint) {
      loc = result;
    } else if (result is Map && result['location'] is GeoPoint) {
      loc = result['location'] as GeoPoint;
    }
    if (loc != null && mounted) {
      // لا «حفظ مسبق» للعنوان على المستند هنا: قاعدة store_orders تشترط على أي
      // تحديث من العميل أن يكون status='under_review'، والطلب قبل الدفع
      // awaiting_payment — فكل كتابة مسبقة كانت تُرفض permission-denied ويبتلعها
      // catchError فتبدو ناجحة وهي ميتة. العنوان يُكتب في _finalizeStorePayment
      // (الكتابة الوحيدة التي تجيزها القاعدة) مع إعادة محاولة كي لا يضيع.
      setState(() {
        _deliveryLocation = loc;
        // عنوان مُختار يدوياً — لم يعد موروثاً من طلب سابق فنُخفي سطر المصدر.
        _prefillZoneName = null;
      });
    }
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
  // هل تتوفّر أي طريقة دفع؟ (بطاقة عبر مفتاح Moyasar أو تمارا) — لتعطيل زر الدفع
  // حين لا تُعرَض أي طريقة، بدل زرّ ميّت يفتح شاشة بمفتاح فارغ.
  bool get _hasPaymentMethod =>
      _tamaraAvailable || (dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '').isNotEmpty;

  Future<void> _handlePay() async {
    if (_isLoading) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى الموافقة على الشروط والأحكام')),
      );
      return;
    }
    if (_deliveryLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد عنوان التوصيل أولاً')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      // البطاقة (Moyasar) هي الطريقة الافتراضية، لكنها لا تُعرَض حين يغيب المفتاح.
      // لو بقيت الطريقة 'card' بلا مفتاح لفُتحت شاشة بطاقة بمفتاح فارغ (طريق مسدود).
      // نحوّل لتمارا إن توفّرت، وإلا نُبلغ المستخدم بدل المتابعة.
      final moyasarReady = (dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '').isNotEmpty;
      if (_selectedMethod == 'card' && !moyasarReady) {
        if (_tamaraAvailable) {
          _selectedMethod = 'tamara';
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('طريقة الدفع بالبطاقة غير متاحة حالياً')),
          );
          return;
        }
      }
      if (_selectedMethod == 'card') {
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
                // is_paid=false يكتبه العميل (القاعدة تمنعه من true)، ثم نؤكّد خادميّاً
                // فوراً عبر verifyMoyasarPayment (يقلب is_paid=true بعد فحص المبلغ). كان
                // المتجر يعتمد على webhook ميسر وحده (المعلّق) فيبقى الطلب غير مؤكَّد.
                await _finalizeStorePayment('card', isPaid: false, paymentId: paymentId);
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
          // is_paid=false — يؤكّده tamaraWebhook خادمياً (لا يكتبه العميل).
          await _finalizeStorePayment('tamara', isPaid: false);
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
  Future<void> _finalizeStorePayment(String method, {required bool isPaid, String? paymentId}) async {
    try {
    // 1) تحديث طلب المتجر القائم (is_paid=false — القاعدة تمنع العميل من كتابة true)
    // **بإعادة محاولة**: القاعدة تشترط status='under_review' على أي تحديث عميل،
    // فأي «حفظ مسبق» للعنوان قبل الدفع مرفوض حتماً — هذه الكتابة بعد الدفع هي
    // الفرصة الوحيدة لحفظ عنوان التوصيل، وفشلها العابر (شبكة) كان يترك طلباً
    // مدفوعاً بلا عنوان نهائياً (يختفي زر الخريطة في لوحة الإدارة).
    Object? finalizeErr;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await FirebaseFirestore.instance
            .collection('store_orders')
            .doc(widget.storeOrderId)
            .update({
          'payment_method': method,
          'is_paid': isPaid,
          'payment_status': isPaid ? 'paid' : 'awaiting_confirmation',
          'status': 'under_review',
          // عنوان التوصيل على طلب المتجر نفسه — كان يعيش على طلب توصيل مرتبط
          // في orders أُلغي (طلب المتجر هو السجل الوحيد الآن).
          'delivery_location': _deliveryLocation,
          'paid_at': FieldValue.serverTimestamp(),
        });
        finalizeErr = null;
        break;
      } catch (e) {
        finalizeErr = e;
        debugPrint('[store finalize update attempt $attempt] $e');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    if (finalizeErr != null) throw finalizeErr;

    // 1b) تأكيد خادمي فوري للبطاقة: verifyMoyasarPayment يقلب is_paid=true (متجاوزاً
    // القواعد) بعد فحص المبلغ ويُشعر العميل — فلا يبقى الطلب معلّقاً بانتظار webhook.
    bool serverConfirmed = isPaid;
    if (method == 'card' && paymentId != null && paymentId.isNotEmpty) {
      try {
        serverConfirmed = await MoyasarService.verifyPayment(paymentId, widget.storeOrderId);
      } catch (_) {
        // فشل التأكيد المباشر (شبكة) — يبقى moyasarWebhook احتياطاً.
      }
    }
    isPaid = isPaid || serverConfirmed;

    // (المتجر المباشر) أُلغي طلب التوصيل المرتبط في orders: كان يُنتج بطاقتين
    // للعميل وسجلّين على الإدارة مزامنتهما يدوية. طلب المتجر هو السجل الوحيد،
    // والإدارة تديره من شاشة طلبات المتجر: under_review ⇒ delivering ⇒ delivered.

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

    // 4) إشعار الإدارة بالطلب المدفوع + بياناته يتم الآن **خادمياً** عند قلب is_paid
    //    (sendNotificationToAdminsOnNewStoreOrder): إيميل لبريد الإدارة + إشعار لوحة
    //    الويب مع الأصناف والمبلغ. أُزيل نداء notifyAdminOfPayment العميلي لتفادي تنبيه
    //    إداري مكرّر (كان بلا إيميل)، والخادمي أوثق (لا يعتمد على بقاء التطبيق حيّاً).

    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ZyiarahOrderSuccessScreen(
          orderCode: widget.orderCode,
          invoiceCollection: 'store_orders',
          // isPaid=false تعني «لم يؤكّده الخادم بعد» لا «لم تدفع»: كلا المسارَين
          // (بطاقة/تمارا) يمرّران false لأن التأكيد خادميّ (webhook/verify). وكان
          // النصّ هنا يقول «سيتم تحصيل المبلغ عند الاستلام» — فتقرأه كلُّ عميلة
          // دفعت بالبطاقة للتوّ. بقيّة من الدفع عند الاستلام، وقد حُذف من الجذور.
          title: isPaid ? 'تم تأكيد الدفع! 🎉' : 'تم استلام طلبك!',
          subtitle: isPaid
              ? 'طلبك الآن تحت المراجعة — ستصلك إشعارات التوصيل أولاً بأول.'
              : 'جارٍ تأكيد دفعتك — بعد التأكيد يصبح طلبك تحت المراجعة وتصلك الإشعارات أولاً بأول.',
        ),
      ),
      (route) => route.isFirst,
    );
    } catch (e) {
      // الدفع نجح والطلب موجود مسبقاً (أُنشئ قبل الدفع) — لا نُظهر أي خطأ إطلاقاً.
      // verify يؤكّده، والمُصالِح الدوري يؤكّد أي سجلّ غير مدفوع. نعرض شاشة النجاح دائماً.
      debugPrint('[store finalize non-fatal after paid] $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ZyiarahOrderSuccessScreen(
            orderCode: widget.orderCode,
            invoiceCollection: 'store_orders',
            title: 'تم تأكيد الطلب!',
            subtitle: 'استلمنا طلبك من المتجر، سنجهّزه ونتواصل معك للتوصيل.',
          ),
        ),
        (route) => route.isFirst,
      );
    }
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
            backgroundColor: const Color(0xFF660033),
            foregroundColor: Colors.white,
          ),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 20),
                  Text('عنوان التوصيل',
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickAddress,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _deliveryLocation == null
                                ? Colors.red.shade200
                                : Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on,
                              color: _deliveryLocation == null
                                  ? Colors.red
                                  : const Color(0xFF660033)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _deliveryLocation == null
                                ? Text(
                                    'اضغط لتحديد عنوان التوصيل',
                                    style: GoogleFonts.tajawal(color: Colors.red),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'تم تحديد عنوان التوصيل ✓',
                                        style: GoogleFonts.tajawal(
                                            color: Colors.grey.shade700),
                                      ),
                                      // مصدر العنوان المقترَح — كان التأكيد أعمى
                                      // فتظن العميلة أنه عنوانها الحالي حتماً.
                                      if (_prefillZoneName != null)
                                        Text(
                                          'العنوان من طلبك السابق — منطقة $_prefillZoneName',
                                          style: GoogleFonts.tajawal(
                                              fontSize: 11,
                                              color: Colors.grey.shade500),
                                        ),
                                    ],
                                  ),
                          ),
                          if (_deliveryLocation != null)
                            TextButton(
                              onPressed: _pickAddress,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                minimumSize: const Size(0, 36),
                              ),
                              child: Text(
                                'تغيير',
                                style: GoogleFonts.tajawal(
                                    color: const Color(0xFF660033),
                                    fontWeight: FontWeight.bold),
                              ),
                            )
                          else
                            const Icon(Icons.chevron_left, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
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
                  // لا «دفع عند الاستلام»: أُزيل من الجذور — الدفع مقدَّم دائماً.
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
                          color: Color(0xFF660033))),
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
                      color: const Color(0xFF660033))),
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
                  isSelected ? const Color(0xFF660033) : Colors.grey.shade200,
              width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF660033).withValues(alpha: 0.1)
                    : Colors.grey.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color ?? const Color(0xFF660033)),
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
              const Icon(Icons.check_circle, color: Color(0xFF660033)),
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
                ? const Color(0xFF660033)
                : Colors.grey.shade200),
      ),
      child: CheckboxListTile(
        value: _agreeToTerms,
        onChanged: (val) => setState(() => _agreeToTerms = val ?? false),
        activeColor: const Color(0xFF660033),
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
          onPressed: (_isLoading || !_hasPaymentMethod) ? null : _handlePay,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _agreeToTerms ? const Color(0xFF660033) : Colors.grey.shade300,
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
        backgroundColor: const Color(0xFF660033),
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
