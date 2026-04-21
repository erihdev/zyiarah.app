import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/tamara_service.dart';
import 'package:zyiarah/services/edfapay_service.dart';
import 'package:zyiarah/screens/checkout_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/services/counter_service.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/screens/order_success_screen.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/zyiarah_comm_service.dart';


class PaymentSummaryScreen extends StatefulWidget {
  final String serviceName;
  final double amount;
  final GeoPoint? location;
  final int? hours;
  final DateTime? serviceDate;
  final String? zoneName;
  final int workerCount;
  final String? maintenanceId;
  final String? contractId;
  final int? planVisits;

  const PaymentSummaryScreen({
    super.key,
    required this.serviceName,
    required this.amount,
    this.location,
    this.hours,
    this.serviceDate,
    this.zoneName,
    this.workerCount = 1,
    this.maintenanceId,
    this.contractId,
    this.planVisits,
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
  ZyiarahUser? _currentUser;
  bool _agreeToTerms = false;

  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  double _discountAmount = 0.0;
  String? _appliedCoupon;
  bool _isValidatingCoupon = false;
  bool _needsPhoneUpdate = false;

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
          
          final phone = _currentUser?.phone ?? '';
          if (phone.isEmpty || phone == '000000000' || phone.length < 9) {
            _needsPhoneUpdate = true;
          } else {
            _phoneController.text = phone;
          }

          // Auto-select subscription if available and not paying for a contract
          if ((_currentUser?.visitsRemaining ?? 0) > 0 && widget.contractId == null) {
            _selectedPaymentMethod = 'subscription';
          }
        });
      }
    }
  }

  bool _isCodAvailableForService() {
    if (widget.contractId != null) return false;
    return true;
  }

  // Correct Financial Math for ZATCA (Assumes amount is inclusive of VAT)
  double get totalWithVat => widget.amount - _discountAmount;
  double get subtotal => totalWithVat / 1.15;
  double get vatAmount => totalWithVat - subtotal;

  Future<void> _validateCoupon() async {
    if (_couponController.text.isEmpty) return;
    setState(() => _isValidatingCoupon = true);
    
    final couponData = await _orderService.validateCoupon(
      _couponController.text,
      currentUserZone: widget.zoneName,
    );
    
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

  Future<void> _navigateToSuccess(String code) async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ZyiarahOrderSuccessScreen(
          orderCode: code,
        ),
      ),
    );
  }

  void _handlePayment() async {
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى الموافقة على الشروط والأحكام"), backgroundColor: Colors.red));
      return;
    }

    if (_needsPhoneUpdate && (_phoneController.text.isEmpty || _phoneController.text.length < 9)) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text("يرجى إدخال رقم جوال صحيح (مثال: 0500000000)"), backgroundColor: Colors.red),
       );
       return;
    }

    setState(() => _isLoading = true);

    try {
      if (_needsPhoneUpdate) {
        await FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).update({
          'phone': _phoneController.text.trim(),
        });
      }

      final String finalOrderId = widget.maintenanceId ?? FirebaseFirestore.instance.collection('orders').doc().id;
      final seq = await ZyiarahCounterService().getNextOrderNumber();
      final orderCode = ZyiarahOrderUtil.formatSmartCode(seq);

      if (_selectedPaymentMethod == 'subscription') {
        if (widget.maintenanceId != null) {
          await FirebaseFirestore.instance.collection('maintenance_requests').doc(widget.maintenanceId).update({
            'status': 'paid',
            'paymentMethod': 'subscription',
            'paidAt': FieldValue.serverTimestamp(),
          });
        } else {
          await FirebaseFirestore.instance.collection('orders').doc(finalOrderId).set({
            'code': orderCode,
            'client_id': FirebaseAuth.instance.currentUser?.uid,
            'client_name': _currentUser?.name ?? 'عميل زيارة',
            'service_type': widget.serviceName,
            'amount': 0.0,
            'status': 'pending',
            'location': widget.location ?? const GeoPoint(24.7136, 46.6753),
            'payment_method': 'subscription',
            'created_at': FieldValue.serverTimestamp(),
            'hours_contracted': widget.hours ?? 4,
            'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
            'zone_name': widget.zoneName,
            'worker_count': widget.workerCount,
            'coupon_code': _appliedCoupon,
            'discount_amount': _discountAmount,
          });
        }
        
        if (mounted) {
          setState(() => _isLoading = false);
          await _finalizeOrderWithInvoice(
            orderId: finalOrderId,
            orderCode: orderCode,
            paymentMethod: 'subscription',
          );

          // إرسال تأكيد بالبريد الإلكتروني للفخامة
          await ZyiarahCommService().notifyNewOrder({
            'code': orderCode,
            'client_name': _currentUser?.name ?? 'عميل زيارة',
            'client_phone': _currentUser?.phone ?? 'غير متوفر',
            'service_type': widget.serviceName,
            'amount': 0.0,
            'zone': widget.zoneName ?? 'غير محدد',
            'date_time': widget.serviceDate != null ? intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!) : 'غير محدد',
            'worker_count': widget.workerCount,
            'coupon': _appliedCoupon ?? 'لا يوجد',
          }, customerEmail: _currentUser?.email);


          await _navigateToSuccess(orderCode);
        }

      } else if (_selectedPaymentMethod == 'cod') {
        if (widget.maintenanceId != null) {
          await FirebaseFirestore.instance.collection('maintenance_requests').doc(widget.maintenanceId).update({
            'status': 'waiting_payment_cod',
            'paymentMethod': 'cod',
            'paidAt': FieldValue.serverTimestamp(),
          });
        } else {
          await FirebaseFirestore.instance.collection('orders').doc(finalOrderId).set({
            'code': orderCode,
            'client_id': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
            'client_name': _currentUser?.name ?? 'عميل زيارة',
            'service_type': widget.serviceName,
            'amount': totalWithVat,
            'status': 'pending',
            'location': widget.location ?? const GeoPoint(24.7136, 46.6753),
            'payment_method': 'cod',
            'created_at': FieldValue.serverTimestamp(),
            'hours_contracted': widget.hours ?? 4,
            'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
            'zone_name': widget.zoneName,
            'worker_count': widget.workerCount,
            'coupon_code': _appliedCoupon,
            'discount_amount': _discountAmount,
          });
        }
        
        if (mounted) {
          setState(() => _isLoading = false);
          await _finalizeOrderWithInvoice(
            orderId: finalOrderId,
            orderCode: orderCode,
            paymentMethod: 'cod',
            paidAmount: totalWithVat,
          );

          // إرسال تأكيد بالبريد الإلكتروني للعميل والمسؤول
          await ZyiarahCommService().notifyNewOrder({
            'code': orderCode,
            'client_name': _currentUser?.name ?? 'عميل زيارة',
            'client_phone': _currentUser?.phone ?? 'غير متوفر',
            'service_type': widget.serviceName,
            'amount': totalWithVat,
            'zone': widget.zoneName ?? 'غير محدد',
            'date_time': widget.serviceDate != null ? intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!) : 'غير محدد',
            'worker_count': widget.workerCount,
            'coupon': _appliedCoupon ?? 'لا يوجد',
          }, customerEmail: _currentUser?.email);


          await _navigateToSuccess(orderCode);
        }

      } else if (_selectedPaymentMethod == 'tamara') {
        String? checkoutUrl = await _tamaraService.createCheckoutSession(
          orderId: finalOrderId,
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
                orderId: finalOrderId,
                serviceType: widget.serviceName,
                location: widget.location ?? const GeoPoint(24.7136, 46.6753),
                hours: widget.hours,
                serviceDate: widget.serviceDate,
                zoneName: widget.zoneName,
                workerCount: widget.workerCount,
                couponCode: _appliedCoupon,
                discountAmount: _discountAmount,
                maintenanceId: widget.maintenanceId,
                contractId: widget.contractId,
                planVisits: widget.planVisits,
                customerName: _currentUser?.name ?? "عميل زيارة",
                customerPhone: _currentUser?.phone ?? "0500000000",
              ),
            ),
          );
          if (paymentSuccess == true && mounted) {
            Navigator.pop(context, true);
          }
        } else {
          throw Exception("خطأ في بدء جلسة تمارا");
        }
      } else {
        final result = await _edfaPayService.processPayment(
          amount: totalWithVat,
          orderId: finalOrderId,
          customerEmail: _currentUser?.email ?? "customer@zyiarah.com",
          customerPhone: _currentUser?.phone ?? "500000000",
          customerName: _currentUser?.name ?? "عميل زيارة",
        );

        if (result['success'] == true && mounted) {
          if (widget.maintenanceId != null) {
            await FirebaseFirestore.instance.collection('maintenance_requests').doc(widget.maintenanceId).update({
              'status': 'paid',
              'paymentMethod': _selectedPaymentMethod,
              'paidAt': FieldValue.serverTimestamp(),
              'totalAmount': totalWithVat,
            });
          } else if (widget.contractId != null) {
            await FirebaseFirestore.instance.collection('contracts').doc(widget.contractId).update({
              'status': 'active',
              'paymentMethod': _selectedPaymentMethod,
              'activatedAt': FieldValue.serverTimestamp(),
            });
            await FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).update({
              'visits_remaining': FieldValue.increment(widget.planVisits ?? 0),
            });
            await ZyiarahNotificationTriggerService().notifyContractActivated(
              _currentUser?.uid ?? '', 
              widget.serviceName, 
              widget.planVisits ?? 0
            );

            // تسجيل تفعيل العقد في سجل التدقيق
            ZyiarahAuditService().logAction(
              action: 'ACTIVATE_CONTRACT',
              details: {
                'contract_id': widget.contractId,
                'client': _currentUser?.name ?? 'غير معروف',
                'plan': widget.serviceName,
                'visits': widget.planVisits ?? 0,
              },
              targetId: widget.contractId,
            );
          } else {
            await FirebaseFirestore.instance.collection('orders').doc(finalOrderId).set({
              'code': orderCode,
              'client_id': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
              'client_name': _currentUser?.name ?? 'عميل زيارة',
              'service_type': widget.serviceName,
              'amount': totalWithVat,
              'status': 'pending',
              'location': widget.location ?? const GeoPoint(24.7136, 46.6753),
              'payment_method': _selectedPaymentMethod,
              'created_at': FieldValue.serverTimestamp(),
              'hours_contracted': widget.hours ?? 4,
              'service_date': widget.serviceDate != null ? Timestamp.fromDate(widget.serviceDate!) : null,
              'zone_name': widget.zoneName,
              'worker_count': widget.workerCount,
              'coupon_code': _appliedCoupon,
              'discount_amount': _discountAmount,
            });
          }

          setState(() => _isLoading = false);
          if (mounted) {
            if (widget.contractId == null && widget.maintenanceId == null) {
            await _finalizeOrderWithInvoice(
              orderId: finalOrderId,
              orderCode: orderCode,
              paymentMethod: _selectedPaymentMethod,
              paidAmount: totalWithVat,
            );

            // إرسال تأكيد بالبريد الإلكتروني بعد نجاح الدفع بالبطاقة
            await ZyiarahCommService().notifyNewOrder({
              'code': orderCode,
              'client_name': _currentUser?.name ?? 'عميل زيارة',
              'client_phone': _currentUser?.phone ?? 'غير متوفر',
              'service_type': widget.serviceName,
              'amount': totalWithVat,
              'zone': widget.zoneName ?? 'غير محدد',
              'date_time': widget.serviceDate != null ? intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!) : 'غير محدد',
              'worker_count': widget.workerCount,
              'coupon': _appliedCoupon ?? 'لا يوجد',
            }, customerEmail: _currentUser?.email);


            await _navigateToSuccess(orderCode);
          }
        }
 else {
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

  /// Unified Finalization: Saves Order + Triggers ZATCA Invoice
  Future<void> _finalizeOrderWithInvoice({
    required String orderId,
    required String orderCode,
    required String paymentMethod,
    double paidAmount = 0,
  }) async {
    // 1. Generate ZATCA QR Code Data
    final String qrData = ZatcaService.generateZatcaQrCode(
      timestamp: DateTime.now(),
      totalAmount: totalWithVat,
      vatAmount: vatAmount,
    );

    // 2. Trigger PDF Invoice Generation (Bilingual)
    InvoicePdfService.generateAndUploadInvoice(
      orderId: orderId,
      orderCode: orderCode,
      amount: totalWithVat,
      qrData: qrData,
      serviceName: widget.serviceName,
      discountAmount: _discountAmount,
      couponCode: _appliedCoupon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  _buildInvoiceHeader(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (_needsPhoneUpdate) _buildPhoneUpdateCard(),
                        const SizedBox(height: 20),
                        _buildOrderDetailsCard(),
                        const SizedBox(height: 20),
                        _buildCouponSection(),
                        const SizedBox(height: 20),
                        _buildPaymentMethods(),
                        const SizedBox(height: 25),
                        _buildTermsAndConditions(),
                        const SizedBox(height: 100),
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
          const SizedBox(height: 20),
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

  Widget _buildPhoneUpdateCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, color: Colors.red),
              const SizedBox(width: 8),
              Text('مطلوب رقم الجوال للتواصل', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: 'مثال: 0501234567',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
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
          _buildRowDetail('الخدمة', widget.serviceName),
          if (widget.hours != null) _buildRowDetail('المدة', '${widget.hours} ساعات'),
          _buildRowDetail('عدد العاملات', widget.workerCount == 1 ? "عاملة واحدة" : "عاملتين"),
          if (widget.serviceDate != null) 
            _buildRowDetail('التاريخ', intl.DateFormat('yyyy-MM-dd').format(widget.serviceDate!)),
          if (widget.zoneName != null) _buildRowDetail('المنطقة', widget.zoneName!),
          const Divider(height: 30),
          _buildRowDetail('المبلغ الأساسي', '${widget.amount.toStringAsFixed(2)} ر.س'),
          if (_discountAmount > 0) 
            _buildRowDetail('الخصم ($_appliedCoupon)', '-${_discountAmount.toStringAsFixed(2)} ر.س', isDiscount: true),
          _buildRowDetail('الضريبة (15%)', '${vatAmount.toStringAsFixed(2)} ر.س'),
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

  Widget _buildRowDetail(String label, String value, {bool isDiscount = false}) {
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
        if (remainingVisits > 0 && widget.contractId == null)
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
          icon: Icons.timer_outlined,
          color: const Color(0xFFE5A170),
        ),
        if (_isCodAvailableForService()) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'cod',
            title: 'الدفع عند الاستلام',
            subtitle: 'دفع نقدي لمقدم الخدمة عند الوصول',
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
    required IconData icon, 
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
                color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.1) : Colors.grey.shade50, 
                shape: BoxShape.circle, 
              ),
              child: Icon(icon, color: color ?? const Color(0xFF2563EB)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14)),
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

  Widget _buildTermsAndConditions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _agreeToTerms ? const Color(0xFF2563EB) : Colors.grey.shade200),
      ),
      child: CheckboxListTile(
        value: _agreeToTerms,
        onChanged: (val) => setState(() => _agreeToTerms = val ?? false),
        activeColor: const Color(0xFF2563EB),
        title: Text(
          "أوافق على شروط الخدمة وسياسة الخصوصية الخاصة بزيارة",
          style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
        ),
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
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: ElevatedButton(
          onPressed: _handlePayment,
          style: ElevatedButton.styleFrom(
            backgroundColor: _agreeToTerms ? const Color(0xFF2563EB) : Colors.grey.shade300,
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
