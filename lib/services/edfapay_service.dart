import 'package:flutter_dotenv/flutter_dotenv.dart';

class EdfaPayService {
  // تُقرأ من ملف .env — المفاتيح المطلوبة:
  // EDFAPAY_MERCHANT_ID, EDFAPAY_TERMINAL_ID, EDFAPAY_PASSWORD_KEY
  static String get _mId => dotenv.env['EDFAPAY_MERCHANT_ID'] ?? '';
  static String get _tId => dotenv.env['EDFAPAY_TERMINAL_ID'] ?? '';
  static String get _pKw => dotenv.env['EDFAPAY_PASSWORD_KEY'] ?? '';

  static bool get _isConfigured =>
      _mId.isNotEmpty && _tId.isNotEmpty && _pKw.isNotEmpty;

  Future<void> initialize() async {}

  Future<Map<String, dynamic>> processPayment({
    required double amount,
    required String orderId,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
  }) async {
    if (!_isConfigured) {
      return {
        'success': false,
        'error': 'بوابة الدفع غير مكوّنة — يرجى تحديث بيانات EDFAPAY في edfapay_service.dart',
      };
    }

    try {
      // TODO: استبدل بالتكامل الحقيقي مع edfapg_sdk
      // مثال:
      // final result = await EdfaPgSdk.instance.sale(
      //   mId: _mId, tId: _tId, pKw: _pKw,
      //   amount: amount.toString(), orderId: orderId,
      //   email: customerEmail, phone: customerPhone, name: customerName,
      // );
      // return {'success': result.status == 'approved', 'transactionId': result.transId};
      throw UnimplementedError("يرجى تفعيل التكامل مع EDFAPAY SDK");
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> processApplePay({
    required Map<String, dynamic> paymentData,
    required double amount,
    required String orderId,
  }) async {
    if (!_isConfigured) {
      return {
        'success': false,
        'error': 'بوابة الدفع غير مكوّنة — يرجى تحديث بيانات EDFAPAY في edfapay_service.dart',
      };
    }

    try {
      // TODO: استبدل بالتكامل الحقيقي لـ Apple Pay عبر EDFAPAY
      throw UnimplementedError("يرجى تفعيل Apple Pay عبر EDFAPAY SDK");
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
