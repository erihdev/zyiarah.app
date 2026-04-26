import 'package:cloud_functions/cloud_functions.dart';

/// خدمة الربط مع بوابة تمارا عبر Cloud Function آمنة
/// الـ API token محفوظ في Firebase Secret Manager — لا يُكشف للعميل أبداً
class TamaraService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<String?> createCheckoutSession({
    required String orderId,
    required double amount,
    required String customerPhone,
    required String customerName,
  }) async {
    try {
      final callable = _functions.httpsCallable('createTamaraCheckout');
      final result = await callable.call({
        'orderId': orderId,
        'amount': amount,
        'customerPhone': customerPhone,
        'customerName': customerName,
      });
      return result.data['checkoutUrl'] as String?;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('فشل الاتصال ببوابة التقسيط: ${e.message}');
    }
  }
}
