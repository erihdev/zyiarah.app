import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zyiarah/services/zatca_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ZyiarahInvoiceScreen extends StatelessWidget {
  final double amount;
  final String orderId;
  final int? hours;
  final DateTime? serviceDate;
  final int workerCount;
  final String? couponCode;
  final double discountAmount;

  final bool isSubscription;
  final double? cashbackEarned;

  const ZyiarahInvoiceScreen({
    super.key,
    required this.amount,
    required this.orderId,
    this.hours,
    this.serviceDate,
    this.workerCount = 1,
    this.couponCode,
    this.discountAmount = 0.0,
    this.isSubscription = false,
    this.cashbackEarned,
  });

  @override
  Widget build(BuildContext context) {
    final double vatAmount = amount - (amount / 1.15);
    final DateTime now = DateTime.now();

    // ZATCA QR base64
    final String qrData = ZatcaService.generateZatcaQrCode(
      timestamp: now,
      totalAmount: amount,
      vatAmount: vatAmount,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text("الفاتورة الضريبية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildSmartBadge(),
              const SizedBox(height: 20),
              _buildInvoiceBody(context, qrData, now, vatAmount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5D1B5E), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5D1B5E).withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("رقم التسجيل الضريبي", style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 10)),
                  Text("310885360200003", style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              const Icon(Icons.verified_user_rounded, color: Colors.amber, size: 24),
            ],
          ),
          const SizedBox(height: 20),
          Text("رمز التتبع الرقمي (Smart ID)", style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            orderId,
            style: GoogleFonts.ibmPlexMono(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceBody(BuildContext context, String qrData, DateTime now, double vatAmount) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Corporate Header
          Center(
            child: Column(
              children: [
                Text(
                  "مؤسسة معاذ يحي محمد المالكي",
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                ),
                Text("فاتورة ضريبية مبسطة", style: GoogleFonts.tajawal(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          _buildInfoRow("تاريخ الإصدار", "${now.year}-${now.month}-${now.day}"),
          _buildInfoRow("وقت الإصدار", "${now.hour}:${now.minute}"),
          if (hours != null) _buildInfoRow("مدة الخدمة", "$hours ساعة"),
          _buildInfoRow("الطاقم", workerCount == 1 ? "عاملة واحدة" : "عاملتين"),
          if (serviceDate != null) 
            _buildInfoRow("موعد الخدمة", "${serviceDate!.year}-${serviceDate!.month}-${serviceDate!.day}"),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          ),
          
          // Money Details
          _buildAmountRow("المبلغ الخاضع للضريبة", "${(amount - vatAmount).toStringAsFixed(2)} ر.س"),
          if (discountAmount > 0) 
            _buildAmountRow("خصم الكوبون ($couponCode)", "-${discountAmount.toStringAsFixed(2)} ر.س", isDiscount: true),
          _buildAmountRow("ضريبة القيمة المضافة (15%)", "${vatAmount.toStringAsFixed(2)} ر.س"),
          
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("الإجمالي المستحق", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1E293B))),
                Text(
                  "${amount.toStringAsFixed(2)} ر.س",
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFF059669)),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Dual QR Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildQrItem("QR الزكاة (ZATCA)", qrData, const Color(0xFF1E293B)),
              _buildQrItem("تتبع الخدمة (Track)", "zyiarah://track/$orderId", const Color(0xFF5D1B5E)),
            ],
          ),
          
          const SizedBox(height: 40),
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: const Color(0xFF64748B), fontSize: 13)),
          Text(value, style: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF334155))),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, String value, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: const Color(0xFF475569), fontSize: 14)),
          Text(
            value,
            style: GoogleFonts.tajawal(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDiscount ? Colors.red.shade600 : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrItem(String label, String data, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 100,
            gapless: false,
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: color),
            dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(
                   content: Text('سيتم حفظ الفاتورة في جهازك قريباً', style: GoogleFonts.tajawal()),
                   backgroundColor: const Color(0xFF1E293B),
                 ),
               );
            },
            icon: const Icon(Icons.file_download_outlined),
            label: Text("تحميل / طباعة الفاتورة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: Text("العودة للرئيسية", style: GoogleFonts.tajawal(color: const Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
