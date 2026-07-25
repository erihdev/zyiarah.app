import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart' as intl;
import 'dart:convert';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class ZyiarahContractSigningScreen extends StatefulWidget {
  final String planName;
  final double planPrice;
  final int planVisits;
  final int planHours;
  final DateTime? bookingDate;
  final String? bookingTimeSlot;
  // (2c) مواعيد الزيارات المتعددة + المنطقة + الموقع — لتوليد وإسناد الزيارات جغرافياً
  final List<Map<String, String>>? scheduledVisits;
  final String? zoneName;
  final GeoPoint? location;
  const ZyiarahContractSigningScreen({
    super.key,
    required this.planName,
    this.planPrice = 0.0,
    this.planVisits = 0,
    this.planHours = 4,
    this.bookingDate,
    this.bookingTimeSlot,
    this.scheduledVisits,
    this.zoneName,
    this.location,
  });

  @override
  State<ZyiarahContractSigningScreen> createState() => _ZyiarahContractSigningScreenState();
}

class _ZyiarahContractSigningScreenState extends State<ZyiarahContractSigningScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF1E293B),
    exportBackgroundColor: Colors.white,
  );

  // سعر الباقة الذي تُدخله الإدارة أساسٌ تُضاف عليه ضريبة 15% (قرار المالك). نُخزّن
  // ونشحن ونعرض هذا الإجمالي شامل الضريبة، وهو نفسه ما يطابقه الخادم (planPrice =
  // الإجمالي المدفوع)، فلا حاجة لتغيير أي دالة تحقّق خادمية.
  double get _grossedPlanPrice =>
      ((widget.planPrice * 1.15) * 100).roundToDouble() / 100;

  final Color brandPurple = const Color(0xFF006FBA);
  bool _isSubmitting = false;
  String _userName = "...";
  String _userPhone = "...";
  final DateTime _contractDate = DateTime.now();
  String _contractTerms = '1. يتم تفعيل العقد تلقائياً فور سداد القيمة واعتماد الإدارة.\n'
      '2. يحق للعميل طلب الخدمة عبر التطبيق ضمن نطاق الباقة.\n'
      '3. يتعهد الطرف الأول بتقديم الخدمة بجودة مهنية معتمدة.';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userName = doc.data()?['name'] ?? user.displayName ?? 'عميل زيارة';
          _userPhone = doc.data()?['phone'] ?? user.phoneNumber ?? 'غير مسجل';
        });
      }
    }

    try {
      final configDoc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
      if (configDoc.exists && mounted) {
        final terms = configDoc.data()?['contract_terms'] as String?;
        if (terms != null && terms.trim().isNotEmpty) {
          setState(() {
            _contractTerms = terms;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching contract terms: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitContract() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى التوقيع أولاً للتوثيق')));
      return;
    }

    setState(() => _isSubmitting = true);

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    try {
      final user = auth.currentUser;
      
      // Capture signature as bytes and convert to Base64
      final signatureBytes = await _controller.toPngBytes();
      String? signatureBase64;
      if (signatureBytes != null) {
        signatureBase64 = base64Encode(signatureBytes);
      }
      
      final contractId = 'CTR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // Re-fetch latest user data to be 100% sure we have the name
      final userDoc = await firestore.collection('users').doc(user?.uid).get();
      final String finalName = userDoc.data()?['name'] ?? user?.displayName ?? 'عميل زيارة';
      final String finalPhone = userDoc.data()?['phone'] ?? user?.phoneNumber ?? 'غير مسجل';

      final docRef = firestore.collection('contracts').doc();
      await docRef.set({
        'contractId': contractId,
        'userId': user?.uid,
        'userPhone': finalPhone,
        'userName': finalName,
        'clientName': finalName, // consistency with admin screen
        'planName': widget.planName,
        // شامل الضريبة (الأساس + 15%) — ما يدفعه العميل ويطابقه الخادم.
        'planPrice': _grossedPlanPrice,
        'planVisits': widget.planVisits,
        // مدة الزيارة — يقرؤها _generateContractVisits/generateSubscriptionVisits (c.hours)
        // بدل القيمة الافتراضية 4 دائماً.
        'hours': widget.planHours,
        'booking_date': widget.bookingDate != null
            ? intl.DateFormat('yyyy-MM-dd').format(widget.bookingDate!)
            : null,
        'booking_time_slot': widget.bookingTimeSlot,
        // (2c) مواعيد الزيارات المتعددة + المنطقة + الموقع — تقرؤها generateSubscriptionVisits
        'scheduled_visits': widget.scheduledVisits,
        'zone_name': widget.zoneName,
        'location': widget.location,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'signedAt': FieldValue.serverTimestamp(),
        'hasSignature': true,
        'signatureData': signatureBase64, // The actual image data
      });

      // تسجيل في سجل التدقيق (اختياري للعملاء كإجراء أمان)
      ZyiarahAuditService().logAction(
        action: 'CLIENT_SIGN_CONTRACT',
        details: {
          'contract_id': contractId,
          'plan': widget.planName,
          'client': _userName,
        },
        targetId: contractId,
      );

      // إشعار الإدارة يتولّاه المُشغّل الخادمي sendNotificationToAdminsOnNewContract
      // عند إنشاء العقد. أزلنا النداء المباشر هنا لأنه كان يُنتج تنبيهاً ثانياً مكرّراً.

      if (!mounted) return;
      // توقيع → صفحة الدفع مباشرة. تفعيل العقد وتوليد زيارات الاشتراك يتمّان عند نجاح الدفع.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSummaryScreen(
            serviceName: widget.planName,
            amount: _grossedPlanPrice, // الأساس + 15% (شامل الضريبة)
            contractId: docRef.id,
            planVisits: widget.planVisits,
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('التوقيع الإلكتروني', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: brandPurple,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildContractPaper(),
                    const SizedBox(height: 30),
                    _buildSignaturePad(),
                  ],
                ),
              ),
            ),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildContractPaper() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Image.asset('assets/logo.png', height: 60, errorBuilder: (_, __, ___) => Icon(Icons.business, color: brandPurple, size: 50)),
                const SizedBox(height: 10),
                Text('اتفاقية تقديم خدمات منزلية', 
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: brandPurple)),
                const SizedBox(height: 5),
                Text('الرقم المرجعي: CTR-XXXX', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ],
            ),
          ),
          const Divider(height: 40),
          _buildContractSection('أطراف الاتفاقية:', 
            'الطرف الأول: مؤسسة زيارة لخدمات التنظيف والصيانة (مقدم الخدمة).\n'
            'الطرف الثاني: السيد/ة $_userName (العميل).\n'
            'رقم الجوال: $_userPhone'),
          const SizedBox(height: 20),
          _buildContractSection('موضوع الاتفاقية:', 
            'وافق الطرف الثاني على الاشتراك في "${widget.planName}" المقدمة من الطرف الأول مقابل مبلغ إجمالي قدره (${_grossedPlanPrice.toStringAsFixed(2)} ر.س) تشمل ضريبة القيمة المضافة، وتتضمن الباقة عدد (${widget.planVisits}) زيارة.'),
          const SizedBox(height: 20),
          _buildContractSection('أهم البنود والشروط:', _contractTerms),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('تاريخ التوثيق:', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
              Text(intl.DateFormat('yyyy/MM/dd').format(_contractDate), 
                style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContractSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
        const SizedBox(height: 8),
        Text(content, style: GoogleFonts.tajawal(fontSize: 12, height: 1.8, color: Colors.blueGrey[700])),
      ],
    );
  }

  Widget _buildSignaturePad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('التوقيع الإلكتروني لمقدم الطلب:', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton(
                onPressed: () => _controller.clear(),
                child: Text('مسح', style: GoogleFonts.tajawal(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: brandPurple.withValues(alpha: 0.2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Signature(
              controller: _controller,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('بالتوقيع أعلاه، أنت توافق على شروط وأحكام الخدمة', 
            style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitContract,
          style: ElevatedButton.styleFrom(
            backgroundColor: brandPurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: _isSubmitting 
            ? const CircularProgressIndicator(color: Colors.white)
            : Text('توثيق وإرسال العقد', style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

