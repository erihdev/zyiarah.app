import 'package:cloud_functions/cloud_functions.dart';

import 'package:zyiarah/utils/user_facing_error.dart';

/// فشلُ بدءِ جلسةِ تمارا — [message] جملةٌ عربيّةٌ تُعرَضُ كما هي،
/// و[detail] تشخيصٌ للسجلِّ لا للعميلة (رمزُ الخادمِ ونصُّه).
class TamaraCheckoutFailure implements UserFacingFailure {
  @override
  final String message;

  final String? detail;

  const TamaraCheckoutFailure(this.message, {this.detail});

  @override
  String toString() => 'TamaraCheckoutFailure($message, detail: $detail)';
}

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
      // المصادقةِ انقطاعاً في الشبكة.
      //
      // والقرارُ (سببُ الخادمِ إن كان عربيّاً، وإلّا سطرٌ عربيٌّ عامّ) صارَ في
      // `userFacingError` — كان هنا نسخةً مكتوبةً بيدٍ وكانت **تُطرَحُ عند
      // المُنادِيَين كليهما**: شاشةُ دفعِ المتجرِ تَطبعُ احتياطيَّها العامَّ
      // أيّاً كان ما قالَه الخادم، وملخّصُ الدفعِ يَصُبُّ في المُعالِجِ العامِّ
      // الذي كان يَطرحُ `message`. ويُرمى **موسوماً** (`UserFacingFailure`) لا
      // `Exception(نصٍّ)`، فيُميّزَه المُنادي عن استثناءٍ عربيٍّ تشخيصيٍّ
      // («المنتج غير موجود في قاعدة البيانات: …») — نفسُ شكلِ
      // `MoyasarPayFailure`.
      throw TamaraCheckoutFailure(
        userFacingError(e),
        detail: '${e.code}: ${e.message}',
      );
    }
  }
}
