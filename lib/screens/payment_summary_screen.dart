import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  const PaymentSummaryScreen({
    super.key,
    required this.serviceName,
    required this.amount,
    required this.location,
    this.hours,
    this.serviceDate,
  });

  @override
  State<PaymentSummaryScreen> createState() => _PaymentSummaryScreenState();
}

class _PaymentSummaryScreenState extends State<PaymentSummaryScreen> {
  final TamaraService _tamaraService = TamaraService();
  final EdfaPayService _edfaPayService = EdfaPayService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  
  String _selectedPaymentMethod = 'card'; // 'card', 'tamara', or 'subscription'
  bool _isLoading = false;
  ZyiarahUser? _currentUser;

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
          _currentUser = ZyiarahUser.fromMap(user.uid, doc.data()!);
          // Auto-select subscription if available
          if ((_currentUser?.visitsRemaining ?? 0) > 0) {
            _selectedPaymentMethod = 'subscription';
          }
        });
      }
    }
  }

  double get vatAmount => widget.amount * 0.15;
  double get totalWithVat => widget.amount + vatAmount;

  void _handlePayment() async {
    setState(() => _isLoading = true);

    try {
      final orderId = "ORD-${DateTime.now().millisecondsSinceEpoch}";
      
      if (_selectedPaymentMethod == 'subscription') {
        // دفع عبر الاشتراك
        await _orderService.createOrder(
          clientId: _currentUser!.uid,
          serviceType: widget.serviceName,
          amount: 0.0, // لا توجد تكلفة مالية فورية
          location: widget.location,
          paymentMethod: 'subscription',
          hours: widget.hours,
          serviceDate: widget.serviceDate,
        );
        
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ZyiarahInvoiceScreen(
                amount: 0.0,
                orderId: orderId,
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                isSubscription: true,
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
            clientId: _currentUser!.uid,
            serviceType: widget.serviceName,
            amount: totalWithVat,
            location: widget.location,
            paymentMethod: 'card',
            hours: widget.hours,
            serviceDate: widget.serviceDate,
          );

          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ZyiarahInvoiceScreen(
                amount: totalWithVat,
                orderId: orderId,
                hours: widget.hours,
                serviceDate: widget.serviceDate,
              ),
            ),
          );
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
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMapPreview(),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        _buildOrderDetailsCard(),
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

  Widget _buildMapPreview() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(widget.location.latitude, widget.location.longitude),
          initialZoom: 15.0,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: const ['a', 'b', 'c'],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(widget.location.latitude, widget.location.longitude),
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            ],
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 14),
                  const SizedBox(width: 5),
                  Text('الموقع مؤكد', style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
          if (widget.serviceDate != null) 
            _buildRow('التاريخ', '${widget.serviceDate!.year}-${widget.serviceDate!.month}-${widget.serviceDate!.day}'),
          const Divider(height: 30),
          _buildRow('المبلغ', '${widget.amount.toStringAsFixed(2)} ر.س'),
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

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.grey[600], fontSize: 14)),
          Text(value, style: GoogleFonts.tajawal(fontWeight: FontWeight.w600, fontSize: 14)),
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
          subtitle: 'دفع آمن وسريع عبر EdfaPay (كاش باك 5%)',
          icon: Icons.credit_card,
        ),
        const SizedBox(height: 12),
        _buildPaymentOption(
          id: 'tamara',
          title: 'تمارا | Tamara',
          subtitle: 'قسم فاتورتك على 4 دفعات (كاش باك 5%)',
          iconPath: 'assets/logo.png', // Ideally a Tamara logo
        ),
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
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))],
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
