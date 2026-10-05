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
      // لا بادئةَ تَنسبُ السببَ خطأً: كلُّ أخطاءِ `createTamaraCheckout`
      // مكتوبةٌ بالعربيّةِ للعميلةِ («يجب تسجيل الدخول أولاً»، «بيانات الطلب
      // ناقصة»…)، وكانت تُلفُّ بـ«فشل الاتصال ببوابة التقسيط: » فيُقرأ خطأُ
      // المصادقةِ انقطاعاً في الشبكة. ويَصلُ النصُّ كما هو، فإن غابَ
      // (رسالةٌ إنجليزيّةٌ من المنصّةِ أو فراغ) وقعنا على نصٍّ عربيٍّ عامّ
      // بدل تسريبِ نصٍّ لاتينيٍّ في واجهةٍ عربيّة.
      final m = (e.message ?? '').trim();
      final ar = RegExp(r'[\u0621-\u064A]').hasMatch(m);
      throw Exception(ar
          ? m
          : 'تعذّر بدء الدفع بالتقسيط — أعيدي المحاولة أو اختاري طريقةً أخرى');
    }
  }
}
