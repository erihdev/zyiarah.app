import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/services/edfapay_service.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:zyiarah/screens/invoice_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/models/user_model.dart';

import 'package:zyiarah/services/order_service.dart';

class PaymentSummaryScreen extends StatefulWidget {
  final String serviceName;
  final double amount;
  final GeoPoint location;
  final int? hours;
  final DateTime? serviceDate;
  final String? zoneName;
  final int workerCount;

  const PaymentSummaryScreen({
    super.key,
    required this.serviceName,
    required this.amount,
    required this.location,
    this.hours,
    this.serviceDate,
    this.zoneName,
    this.workerCount = 1,
  });

  @override
  State<PaymentSummaryScreen> createState() => _PaymentSummaryScreenState();
}

class _PaymentSummaryScreenState extends State<PaymentSummaryScreen> {
  final TamaraService _tamaraService = TamaraService();
  final EdfaPayService _edfaPayService = EdfaPayService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  
  String _selectedPaymentMethod = 'card'; // 'card', 'tamara', 'subscription' or 'cod'
  bool _isLoading = false;
  bool _codEnabled = false;
  ZyiarahUser? _currentUser;
  Map<String, dynamic> _paymentConfigs = {};

  final TextEditingController _couponController = TextEditingController();
  double _discountAmount = 0.0;
  String? _appliedCoupon;
  bool _isValidatingCoupon = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final configDoc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
      
      if (doc.exists && mounted) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(user.uid, doc.data()!);
          if (configDoc.exists) {
            _paymentConfigs = configDoc.data()!;
            _codEnabled = _paymentConfigs['cod_enabled'] ?? false;
          }
          // Auto-select subscription if available
          if ((_currentUser?.visitsRemaining ?? 0) > 0) {
            _selectedPaymentMethod = 'subscription';
          }
        });
      }
    }
  }

  bool _isCodAvailableForService() {
    // تم تفعيل الدفع عند الاستلام ليكون متاحاً لجميع الخدمات
    return true;
  }

  double get vatAmount => (widget.amount - _discountAmount) * 0.15;
  double get totalWithVat => (widget.amount - _discountAmount) + vatAmount;

  Future<void> _validateCoupon() async {
    if (_couponController.text.isEmpty) return;

    setState(() => _isValidatingCoupon = true);
    
    final couponData = await _orderService.validateCoupon(_couponController.text);
    
    if (mounted) {
      setState(() {
        _isValidatingCoupon = false;
        if (couponData != null) {
          _appliedCoupon = _couponController.text.toUpperCase();
          double value = (couponData['value'] as num).toDouble();
          if (couponData['type'] == 'percentage') {
            _discountAmount = widget.amount * (value / 100);
          } else {
            _discountAmount = value;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم تطبيق الكود بنجاح"), backgroundColor: Colors.green),
          );
        } else {
          _appliedCoupon = null;
          _discountAmount = 0.0;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("كود الخصم غير صحيح أو منتهي"), backgroundColor: Colors.red),
          );
        }
      });
    }
  }

  Future<void> _showSuccessAnimation() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.network(
              'https://lottie.host/85cc1144-6729-4d64-88aa-3e753456c636/Hw4h8Pndr5.json',
              width: 200,
              height: 200,
              repeat: false,
            ),
            const SizedBox(height: 10),
            Text('تمت العملية بنجاح', 
              style: GoogleFonts.tajawal(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }

  void _handlePayment() async {
    setState(() => _isLoading = true);

    try {
      final orderId = "ORD-${DateTime.now().millisecondsSinceEpoch}";
      
      if (_selectedPaymentMethod == 'subscription') {
        // دفع عبر الاشتراك
        await _orderService.createOrder(
          clientId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          serviceType: widget.serviceName,
          amount: 0.0, // لا توجد تكلفة مالية فورية
          location: widget.location,
          paymentMethod: 'subscription',
          hours: widget.hours,
          serviceDate: widget.serviceDate,
          zoneName: widget.zoneName,
          workerCount: widget.workerCount,
          couponCode: _appliedCoupon,
          discountAmount: _discountAmount,
        );
        
        if (mounted) {
          setState(() => _isLoading = false);
          await _showSuccessAnimation();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ZyiarahInvoiceScreen(
                amount: 0.0,
                orderId: orderId,
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                isSubscription: true,
                workerCount: widget.workerCount,
                couponCode: _appliedCoupon,
                discountAmount: _discountAmount,
              ),
            ),
          );
        }
      } else if (_selectedPaymentMethod == 'cod') {
        // دفع عند الاستلام
        await _orderService.createOrder(
          clientId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
          serviceType: widget.serviceName,
          amount: totalWithVat,
          location: widget.location,
          paymentMethod: 'cod',
          hours: widget.hours,
          serviceDate: widget.serviceDate,
          zoneName: widget.zoneName,
          workerCount: widget.workerCount,
          couponCode: _appliedCoupon,
          discountAmount: _discountAmount,
        );
        
        if (mounted) {
          setState(() => _isLoading = false);
          await _showSuccessAnimation();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ZyiarahInvoiceScreen(
                amount: totalWithVat,
                orderId: orderId,
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                isSubscription: false,
                workerCount: widget.workerCount,
                couponCode: _appliedCoupon,
                discountAmount: _discountAmount,
              ),
            ),
          );
        }
      } else if (_selectedPaymentMethod == 'tamara') {
        String? checkoutUrl = await _tamaraService.createCheckoutSession(
          orderId: orderId,
          amount: totalWithVat,
          customerPhone: _currentUser?.phone ?? "500000000",
          customerName: _currentUser?.name ?? "عميل زيارة",
        );

        if (checkoutUrl != null && mounted) {
          setState(() => _isLoading = false);
          bool? paymentSuccess = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TamaraCheckoutScreen(
                checkoutUrl: checkoutUrl,
                amount: totalWithVat,
                orderId: orderId,
                serviceType: widget.serviceName,
                location: widget.location,
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                zoneName: widget.zoneName,
                workerCount: widget.workerCount,
                couponCode: _appliedCoupon,
                discountAmount: _discountAmount,
              ),
            ),
          );
          if (paymentSuccess == true && mounted) {
            Navigator.pop(context, true); // Success back to dashboard
          }
        } else {
          throw Exception("خطأ في بدء جلسة تمارا");
        }
      } else {
        // EdfaPay / Card Payment
        final result = await _edfaPayService.processPayment(
          amount: totalWithVat,
          orderId: orderId,
          customerEmail: _currentUser?.email ?? "customer@zyiarah.com",
          customerPhone: _currentUser?.phone ?? "500000000",
          customerName: _currentUser?.name ?? "عميل زيارة",
        );

        if (result['success'] == true && mounted) {
          // جلب OrderService لإنشاء الطلب في الداتا بيس لأن EdfaPay (المحاكي) لا يفعل ذلك تلقائياً هنا
          await _orderService.createOrder(
            clientId: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            serviceType: widget.serviceName,
            amount: totalWithVat,
            location: widget.location,
            paymentMethod: 'card',
            hours: widget.hours,
            serviceDate: widget.serviceDate,
            zoneName: widget.zoneName,
            workerCount: widget.workerCount,
            couponCode: _appliedCoupon,
            discountAmount: _discountAmount,
          );

          setState(() => _isLoading = false);
          if (mounted) {
            await _showSuccessAnimation();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ZyiarahInvoiceScreen(
                  amount: totalWithVat,
                  orderId: orderId,
                  hours: widget.hours,
                  serviceDate: widget.serviceDate,
                  workerCount: widget.workerCount,
                  couponCode: _appliedCoupon,
                  discountAmount: _discountAmount,
                ),
              ),
            );
          }
        } else {
          throw Exception(result['error'] ?? "فشلت عملية الدفع بالبطاقة");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('ملخص الطلب والدفع', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInvoiceHeader(),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        _buildOrderDetailsCard(),
                        const SizedBox(height: 20),
                        _buildCouponSection(),
                        const SizedBox(height: 20),
                        _buildPaymentMethods(),
                        const SizedBox(height: 100), // Space for sticky button
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildBottomButton(),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceHeader() {
    final double basePrice = widget.amount - _discountAmount;
    final double vat = basePrice * 0.15;
    final double total = basePrice + vat;

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Color(0xFF5D1B5E),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(
            'فاتورة الطلب التقديرية',
            style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInvoiceStat('المجموع', '${basePrice.toStringAsFixed(2)} ر.س'),
              _buildInvoiceStat('الضريبة (15%)', '${vat.toStringAsFixed(2)} ر.س'),
              _buildInvoiceStat('الإجمالي', '${total.toStringAsFixed(2)} ر.س', isBold: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceStat(String label, String value, {bool isBold = false}) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.tajawal(
          color: Colors.white, 
          fontSize: 16, 
          fontWeight: isBold ? FontWeight.w900 : FontWeight.bold
        )),
      ],
    );
  }

  Widget _buildMapPreview() {
    return const SizedBox.shrink(); // Historically removed as requested
  }

  Widget _buildOrderDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تفاصيل الفاتورة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(height: 30),
          _buildRow('الخدمة', widget.serviceName),
          if (widget.hours != null) _buildRow('المدة', '${widget.hours} ساعات'),
          _buildRow('عدد العاملات', widget.workerCount == 1 ? "عاملة واحدة" : "عاملتين"),
          if (widget.serviceDate != null) 
            _buildRow('التاريخ', '${widget.serviceDate!.year}-${widget.serviceDate!.month}-${widget.serviceDate!.day}'),
          if (widget.zoneName != null) _buildRow('المنطقة', widget.zoneName!),
          const Divider(height: 30),
          _buildRow('المبلغ الأساسي', '${widget.amount.toStringAsFixed(2)} ر.س'),
          if (_discountAmount > 0) 
            _buildRow('الخصم ($_appliedCoupon)', '-${_discountAmount.toStringAsFixed(2)} ر.س', isDiscount: true),
          _buildRow('الضريبة (15%)', '${vatAmount.toStringAsFixed(2)} ر.س'),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الإجمالي', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              Text('${totalWithVat.toStringAsFixed(2)} ر.س', 
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF2563EB))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 14)),
          Text(value, style: GoogleFonts.tajawal(
            fontWeight: FontWeight.w600, 
            fontSize: 14, 
            color: isDiscount ? Colors.red : Colors.black
          )),
        ],
      ),
    );
  }

  Widget _buildCouponSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('كود الخصم', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  decoration: InputDecoration(
                    hintText: 'أدخل كود الخصم هنا',
                    hintStyle: GoogleFonts.tajawal(fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  ),
                  onChanged: (val) {
                    if (_appliedCoupon != null) {
                      setState(() {
                        _appliedCoupon = null;
                        _discountAmount = 0.0;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isValidatingCoupon ? null : _validateCoupon,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5D1B5E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isValidatingCoupon 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('تطبيق', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (_appliedCoupon != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('تم تطبيق الكود: $_appliedCoupon', 
                style: GoogleFonts.tajawal(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    final int remainingVisits = _currentUser?.visitsRemaining ?? 0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('اختر طريقة الدفع', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 15),
        if (remainingVisits > 0)
          _buildPaymentOption(
            id: 'subscription',
            title: 'باقة زيارة جولد',
            subtitle: 'سيتم خصم زيارة واحدة (المتبقي: $remainingVisits)',
            icon: Icons.workspace_premium,
            color: Colors.amber.shade700,
          ),
        const SizedBox(height: 12),
        _buildPaymentOption(
          id: 'card',
          title: 'بطاقة فيزا / مدى / Apple Pay',
          subtitle: 'دفع آمن وسريع عبر EdfaPay',
          icon: Icons.credit_card,
        ),
        const SizedBox(height: 12),
        _buildPaymentOption(
          id: 'tamara',
          title: 'تمارا | Tamara',
          subtitle: 'قسم فاتورتك على 4 دفعات',
          iconPath: 'assets/logo.png', // Ideally a Tamara logo
        ),
        if (_isCodAvailableForService()) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'cod',
            title: 'الدفع عند الاستلام',
            subtitle: 'دفع نقدي لمقدم الخدمة بعد أو قبل البدء',
            icon: Icons.money,
            color: Colors.green,
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentOption({
    required String id, 
    required String title, 
    required String subtitle, 
    IconData? icon, 
    String? iconPath,
    Color? color,
  }) {
    bool isSelected = _selectedPaymentMethod == id;
    return InkWell(
      onTap: () => setState(() => _selectedPaymentMethod = id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade200, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: id == 'card' ? Colors.black : Colors.white, 
                shape: BoxShape.circle, 
                border: Border.all(color: Colors.grey.shade100)
              ),
              child: id == 'card' 
                ? const Icon(Icons.apple, color: Colors.white, size: 24) // Apple Pay representation
                : id == 'tamara'
                  ? const Icon(Icons.timer_outlined, color: Color(0xFFE5A170))
                  : icon != null 
                    ? Icon(icon, color: color ?? const Color(0xFF2563EB))
                    : Image.asset('assets/logo.png', width: 24, height: 24), // Fallback
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (id == 'card') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                          child: const Text('STC Pay', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.purple)),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF2563EB)),
          ],
        ),
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
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: ElevatedButton(
          onPressed: _handlePayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('تأكيد وإتمام الدفع', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      ),
    );
  }
}
