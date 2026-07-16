import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:zyiarah/services/zyiarah_pdf_service.dart';

class ZyiarahOrderSuccessScreen extends StatefulWidget {
  final String orderCode;
  final String title;
  final String subtitle;
  // المجموعة التي تُكتب فيها الفاتورة: 'orders' افتراضياً، و'store_orders' لطلبات المتجر
  // (وإلا تبقى الشاشة على "جاري إنشاء الفاتورة" للأبد لعميل المتجر).
  final String invoiceCollection;

  const ZyiarahOrderSuccessScreen({
    super.key,
    required this.orderCode,
    this.title = "تم استلام طلبك بنجاح!",
    this.subtitle = "شكراً لثقتك بزيارة، طلبك الآن قيد المعالجة وسنقوم بإخطارك بكل جديد.",
    this.invoiceCollection = 'orders',
  });

  @override
  State<ZyiarahOrderSuccessScreen> createState() => _ZyiarahOrderSuccessScreenState();
}

class _ZyiarahOrderSuccessScreenState extends State<ZyiarahOrderSuccessScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;
  bool _retryingInvoice = false;

  // إعادة توليد الفاتورة ورفعها عند فشل المحاولة الأولى — يعيد بناء بيانات ZATCA من
  // وثيقة الطلب نفسها (المبلغ شامل الضريبة 15% ضمنية) ثم يستدعي الخدمة المحصّنة بالمهلة.
  Future<void> _retryInvoice(String docId, Map<String, dynamic> data) async {
    setState(() => _retryingInvoice = true);
    try {
      final double amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final double vat = amount - (amount / 1.15);
      final String qrData = ZatcaService.generateZatcaQrCode(
        timestamp: DateTime.now(),
        totalAmount: amount,
        vatAmount: vat,
      );
      // نمسح علامة الفشل حتى يعود الدوّار أثناء المحاولة.
      await FirebaseFirestore.instance
          .collection(widget.invoiceCollection)
          .doc(docId)
          .update({'invoice_pdf_status': 'retrying'});
      await ZyiarahPdfService.generateAndUploadInvoice(
        orderId: docId,
        orderCode: widget.orderCode,
        amount: amount,
        qrData: qrData,
        serviceName: (data['service_name'] as String?) ?? '-',
        discountAmount: (data['discount_amount'] as num?)?.toDouble() ?? 0,
        couponCode: data['coupon_code'] as String?,
        collectionPath: widget.invoiceCollection,
      );
    } catch (_) {
      // عند تكرار الفشل تُعاد كتابة علامة failed داخل الخدمة فيظهر الزر ثانيةً.
    } finally {
      if (mounted) setState(() => _retryingInvoice = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _checkAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE1F0E4),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: FadeTransition(
                      opacity: _checkAnimation,
                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 80),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 24, color: const Color(0xFF5D1B5E)),
              ),
              const SizedBox(height: 15),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Text("رقم التتبع الخاص بك", style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 5),
                    Text(
                      widget.orderCode,
                      style: GoogleFonts.ibmPlexMono(fontWeight: FontWeight.w900, fontSize: 32, letterSpacing: 2, color: const Color(0xFF5D1B5E)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              
              // Invoice Download Section (Listener)
              _buildInvoiceSection(),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5D1B5E),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  // go لا push: شاشة النجاح نهاية رحلة الطلب، فلا معنى للرجوع إليها.
                  onPressed: () => context.go('/orders'),
                  child: Text("تتبع الطلب الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Text("العودة للرئيسية", style: GoogleFonts.tajawal(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildInvoiceSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(widget.invoiceCollection)
          .where('code', isEqualTo: widget.orderCode)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox();
        }

        final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final docId = snapshot.data!.docs.first.id;
        final invoiceUrl = data['invoice_pdf_url'] as String?;
        final invoiceStatus = data['invoice_pdf_status'] as String?;

        if (invoiceUrl == null) {
          // فشل الرفع (اتصال ضعيف مثلاً) → زر إعادة محاولة بدل دوّار لا ينتهي.
          if (invoiceStatus == 'failed' && !_retryingInvoice) {
            return TextButton.icon(
              onPressed: () => _retryInvoice(docId, data),
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.blueGrey),
              label: Text("تعذّر إنشاء الفاتورة — إعادة المحاولة",
                  style: GoogleFonts.tajawal(fontSize: 12, color: Colors.blueGrey)),
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text("جاري إنشاء الفاتورة الضريبية...", style: GoogleFonts.tajawal(fontSize: 12, color: Colors.blueGrey)),
            ],
          );
        }

        return OutlinedButton.icon(
          onPressed: () =>
              launchUrl(Uri.parse(invoiceUrl), mode: LaunchMode.externalApplication),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            side: const BorderSide(color: Color(0xFF1E293B)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20, color: Color(0xFF1E293B)),
          label: Text("تحميل الفاتورة الضريبية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF5D1B5E))),
        );
      },
    );
  }
}
