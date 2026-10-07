/// **ماذا نَقولُ للعميلةِ عن خطأِ بوّابةِ ميسر — مرّةً واحدةً للشاشتَين (2026-10-07).**
///
/// شاشتا SDK (`moyasar_card_screen` و`moyasar_stc_screen`) كانت لكلٍّ منهما
/// نسختُها من المُبدِّل، و**كلتاهما تُسرِّبُ نصَّ البوّابة**:
///
///  • `ApiError.message` و`ValidationError.message` هما `jsonBody['message']`
///    من ميسر — **إنجليزيٌّ** (`moyasar-3.0.5/lib/src/moyasar.dart`).
///  • و`NetworkError.message` حرفٌ إنجليزيٌّ ثابتٌ في الحزمة (`'Network error.'`).
///  • و`PaymentResponse.description` — الذي كانت شاشةُ البطاقةِ تَعرضُه عند
///    الرفض — هو **الوصفُ الذي أرسلناه نحن** (`description = json['description']`،
///    وهو `'خدمة زيارة - …'`): فبطاقةٌ مرفوضةٌ كانت تُنتجُ شريطاً أحمرَ نصُّه
///    **اسمُ خدمتِها**، لا سبباً ولا خطأً.
///  • وأخطرُها أنّ ودجةَ البطاقةِ في الحزمةِ تُحوّلُ استثناءاتِها إلى
///    `ApiError(e.toString())` (`credit_card.dart:113`) — فجسمٌ غيرُ JSON من
///    وكيلٍ أمامَ ميسر (حالةٌ موثَّقةٌ في `functions/moyasar_api.js`) كان
///    يُنتجُ «FormatException: Unexpected character…» في شريطٍ أحمرَ على
///    **مسارِ الدفعِ الأساسيّ**.
///
/// والقاعدةُ مقرَّرةٌ في `moyasar_service.dart` بنصِّها («رسالةُ ميسر
/// إنجليزيّةٌ، فلا تُعرَض: تَذهبُ إلى `detail`») ولها حارسُها — وكان نطاقُه
/// ذاك الملفَّ وحدَه. فتَسكنُ هنا مرّةً، نقيّةً فتُختبَرُ بلا Firebase.
///
/// ومُبدِّلُ الخدمةِ يَبقى حيث هو: مَدخَلُه سلسلةُ `type` من ردٍّ HTTP يُنشئُه
/// بنفسِه، لا كائناتُ أخطاءِ الـSDK — سؤالٌ آخرُ بمَدخَلٍ آخر.
library;

import 'package:moyasar/moyasar.dart';

/// جملةٌ عربيّةٌ للعميلة، وتشخيصٌ للسجلّ، وهل النتيجةُ **مجهولة**.
class MoyasarErrorText {
  /// حرفٌ عربيٌّ ثابتٌ — لا نصَّ من البوّابةِ ولا استقراءَ حالةٍ لاتينيّة.
  final String message;

  /// ما يُطبَعُ ولا يُعرَض (رسالةُ ميسر الإنجليزيّة، أو نصُّ الاستثناء).
  final String detail;

  /// هل قد يَكونُ المبلغُ خُصم؟ «لا نعرف» ليست «فشل»، ودعوةُ الإعادةِ
  /// مكانَها تُنتجُ شحناً مزدوجاً.
  final bool resultUnknown;

  const MoyasarErrorText(this.message,
      {this.detail = '', this.resultUnknown = false});
}

/// الجملةُ الموحَّدةُ لنتيجةٍ مجهولة.
///
/// صادقةٌ في الحالتَين: إن خُصم فـ`reconcileOrphanPayments` يَمسحُ كلَّ دقيقةٍ
/// ويَبني الطلبَ من بيانات الدفع، وإن لم يُخصَم فلا شيءَ حدث. و«لا تُعيدي
/// الدفع» آمنةٌ في الحالتَين.
const String kMoyasarUnknownResult =
    'تعذّر تأكيد الدفع — إن كان المبلغُ قد خُصم فلا تقلقي، سيُؤكَّد طلبكِ '
    'تلقائيّاً أو يُعاد المبلغ. لا تُعيدي الدفع.';

/// ماذا نَعرضُ عن نتيجةِ [result] القادمةِ من `Moyasar.pay`/`verifyOTP` أو من
/// `CreditCard.onPaymentResult`؟
MoyasarErrorText moyasarErrorText(Object? result) {
  if (result is AuthError) {
    return MoyasarErrorText(
        'خطأ في إعداد بوّابة الدفع — تواصلي مع الدعم',
        detail: 'auth: ${result.message}');
  }
  if (result is ValidationError) {
    return MoyasarErrorText(
        'بيانات الدفع غير صحيحة — تحقّقي منها وأعيدي المحاولة',
        detail: 'validation: ${result.message} ${result.errors ?? ''}');
  }
  if (result is NetworkError) {
    // الطلبُ لم يَصِلْ، فلا خصمَ ولا جهالة.
    return const MoyasarErrorText(
        'تعذّر الاتصال بالإنترنت — تحقّقي من الشبكة وأعيدي المحاولة',
        detail: 'network');
  }
  if (result is TimeoutError) {
    // خمسٌ وأربعون ثانيةً بلا ردٍّ: قد تَكونُ ميسر خَصمَت.
    return const MoyasarErrorText(kMoyasarUnknownResult,
        detail: 'timeout', resultUnknown: true);
  }
  if (result is PaymentCanceledError) {
    // ألغتها هي — ليست فشلاً ولا تُقالُ كذلك.
    return const MoyasarErrorText('أُلغيت عملية الدفع', detail: 'canceled');
  }
  if (result is UnprocessableTokenError) {
    return const MoyasarErrorText(
        'تعذّر إتمام الدفع على هذا الجهاز — اختاري طريقةً أخرى',
        detail: 'unprocessable_token');
  }
  if (result is ApiError) {
    // **مجهولٌ بقصد.** نوعُ `ApiError` يَحملُ أمرَين لا يُفرَّقُ بينهما من
    // النوعِ وحدَه: ردُّ 5xx من ميسر (لا خصم)، واستثناءٌ محلّيٌّ حوّلته
    // ودجةُ البطاقةِ (`ApiError(e.toString())` — فقد يَكونُ الخصمُ تمّ
    // وفشلَ تحليلُ الرد). فالأسلمُ قولُ «لا نعرف»، وهو صادقٌ في الحالتَين.
    return MoyasarErrorText(kMoyasarUnknownResult,
        detail: 'api: ${result.message}', resultUnknown: true);
  }
  if (result is UnspecifiedError) {
    // `message` هنا **جسمُ الردِّ كاملاً** (`jsonBody.toString()`) — يُطبَعُ
    // ولا يُعرَضُ بحال.
    return MoyasarErrorText('حدث خطأ غير متوقع في عملية الدفع',
        detail: 'unspecified: ${result.message}');
  }
  if (result is PaymentResponse) {
    // **لا `description`:** هو الوصفُ الذي أرسلناه، فعرضُه يُنتجُ شريطاً
    // أحمرَ نصُّه اسمُ خدمتِها.
    final bool declined = result.status == PaymentStatus.failed;
    return MoyasarErrorText(
        declined
            ? 'لم تُقبل البطاقة — تحقّقي من بياناتها أو استعملي بطاقةً أخرى'
            : 'لم تكتمل عملية الدفع — أعيدي المحاولة أو اختاري طريقةً أخرى',
        detail: 'status=${result.status.name} desc=${result.description ?? ''}');
  }
  return MoyasarErrorText('حدث خطأ غير متوقع في عملية الدفع',
      detail: 'unknown: ${result?.runtimeType}');
}
