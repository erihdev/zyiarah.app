import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moyasar/moyasar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zyiarah/utils/moyasar_util.dart';

/// شاشة دفع البطاقة عبر Moyasar SDK.
/// تستدعي [onSuccess] مع payment ID عند نجاح الدفع.
/// تستدعي [onFailure] مع رسالة الخطأ عند الفشل.
class MoyasarCardScreen extends StatelessWidget {
  final double amountSAR;
  final String description;
  final String orderId;
  final void Function(String paymentId) onSuccess;
  final void Function(String error) onFailure;

  const MoyasarCardScreen({
    super.key,
    required this.amountSAR,
    required this.description,
    required this.orderId,
    required this.onSuccess,
    required this.onFailure,
  });

  PaymentConfig get _config => PaymentConfig(
        publishableApiKey: dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '',
        amount: (amountSAR * 100).round(), // Halala
        description: description,
        givenID: MoyasarUtil.givenIdFromOrder(orderId), // UUID صالح لـ Moyasar (منع الشحن المزدوج)
        metadata: {'order_id': orderId},
        creditCard: CreditCardConfig(saveCard: false, manual: false),
      );

  void _handlePaymentResult(BuildContext context, dynamic result) {
    if (result is PaymentResponse) {
      if (result.status == PaymentStatus.paid ||
          result.status == PaymentStatus.authorized) {
        Navigator.of(context).pop();
        onSuccess(result.id);
      } else {
        final msg = result.description ?? 'فشل الدفع — يرجى المحاولة مجدداً';
        onFailure(msg);
      }
    } else if (result is ApiError) {
      onFailure(result.message);
    } else if (result is ValidationError) {
      onFailure(result.message);
    } else if (result is NetworkError) {
      onFailure(result.message);
    } else {
      onFailure('فشل الدفع — يرجى المحاولة مجدداً');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          title: Text(
            'الدفع بالبطاقة',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        backgroundColor: const Color(0xFFF1F5F9),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // شعار الأمان
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'دفع آمن ومشفر عبر ميسر',
                      style: GoogleFonts.tajawal(
                          fontSize: 13, color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Moyasar SDK Credit Card Widget
              CreditCard(
                config: _config,
                locale: const Localization.ar(),
                onPaymentResult: (result) =>
                    _handlePaymentResult(context, result),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
