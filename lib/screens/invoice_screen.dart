import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zyiarah/services/zatca_service.dart';

class ZyiarahInvoiceScreen extends StatelessWidget {
  final double amount;
  final String orderId;

  const ZyiarahInvoiceScreen({
    super.key,
    required this.amount,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    final double vatAmount = amount * 0.15; // الضريبة 15%
    final double subtotal = amount - vatAmount;
    final DateTime now = DateTime.now();

    // توليد QR Code متوافق مع هيئة الزكاة (TLV Base64)
    final String qrData = ZatcaService.generateZatcaQrCode(
      merchantName: "مؤسسة معاذ يحي محمد المالكي",
      vatNumber: "310885360200003",
      timestamp: now,
      totalAmount: amount,
      vatAmount: vatAmount,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("الفاتورة الضريبية",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                const Center(
                  child: Column(
                    children: [
                      Text(
                        "مؤسسة معاذ يحي محمد المالكي",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A)),
                      ),
                      Text("فاتورة ضريبية مبسطة", style: TextStyle(fontSize: 16)),
                      Text("الرقم الضريبي: 310885360200003",
                          style: TextStyle(color: Colors.grey)),
                      Text("س.ت: 7030376342",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const Divider(height: 40, thickness: 2),

                // Order Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("رقم الطلب:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(orderId),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("التاريخ والوقت:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour}:${now.minute.toString().padLeft(2, '0')}"),
                  ],
                ),

                const Divider(height: 40),

                // Amounts
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("المبلغ الخاضع للضريبة:"),
                    Text("${subtotal.toStringAsFixed(2)} ر.س"),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("ضريبة القيمة المضافة (15%):"),
                    Text("${vatAmount.toStringAsFixed(2)} ر.س"),
                  ],
                ),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("الإجمالي مع الضريبة:",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A))),
                    Text("${amount.toStringAsFixed(2)} ر.س",
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ],
                ),

                const SizedBox(height: 40),

                // QR Code
                Center(
                  child: Column(
                    children: [
                      QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200.0,
                        gapless: false,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "امسح الرمز بواسطة تطبيق 'فاتورة' التابع لهيئة الزكاة والدخل للتحقق",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Print/Download Button
                ElevatedButton.icon(
                  onPressed: () {
                    // سيتم إضافة كود الطباعة باستخدام حزمة printing لاحقاً
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('سيتم تفعيل الطباعة لاحقاً')),
                    );
                  },
                  icon: const Icon(Icons.print),
                  label: const Text("طباعة / تحميل PDF",
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: const Text("العودة للرئيسية",
                      style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
