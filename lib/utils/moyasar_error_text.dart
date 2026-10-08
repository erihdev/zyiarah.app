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
///
/// ---
///
/// **ومسارا الدفعِ الأصليِّ كانا خارجَ هذا كلِّه (2026-10-08).** Apple Pay
/// وSamsung Pay يَمُرّانِ بحزمةِ ميسر فيَصِلُهما **النوعُ نفسُه**، وكان لكلٍّ
/// منهما مُبدِّلُه المكتوبُ بيدٍ في `payment_summary_screen` — ثلاثُ نتائجَ:
///
///  • `ApiError.message` و`ValidationError.message` كانا يُعرَضانِ **خامَّين**،
///    وهما `jsonBody['message']` من ميسر أي **إنجليزيّان** — على مسارِ الدفعِ
///    الأصليِّ في iOS، المنصّةِ التي تَنتظرُ المراجعة.
///  • وكلُّ ما سوى الأربعةِ المُعدَّدةِ يَقعُ على «فشل الدفع عبر X» — ومنه
///    `PaymentCanceledError`: وهو ما تُرسِلُه الحزمةُ حين **تُغلِقُ هي** ورقةَ
///    Apple Pay (`onApplePayError`)، فإغلاقُها بيدِها كان يُنتجُ شريطاً أحمرَ
///    «فشل الدفع» — ومنه `TimeoutError` (خمسٌ وأربعون ثانيةً بلا ردّ) وهو
///    **مجهولُ النتيجة**: دعوى فشلٍ عن دفعةٍ قد تَكونُ تمّت.
///  • و**جملةُ النتيجةِ المجهولةِ كانت مكتوبةً ثلاثَ مرّاتٍ في تلك الشاشةِ**
///    بصياغةٍ تُخالِفُ هذه الوحدةَ في الشيءِ الوحيدِ الذي يُهمّ: «سيُعالَج
///    طلبكِ تلقائياً. **وإلّا فأعيدي المحاولة**» — دعوةُ إعادةٍ على نتيجةٍ
///    مجهولة، وهي بعينُها ما يَمنعُه `kMoyasarUnknownResult` («لا تُعيدي
///    الدفع») ويَشدُّه فحصُ شاشتَي SDK.
///
/// **و`given_id` هو الفرقُ بين خطأٍ وشحنٍ مزدوج**، فصارَ للقرارِ حقلُه:
/// الشاشةُ كانت تُجدّدُ المعرّفَ على `ApiError` — و`ApiError` من
/// `Moyasar.pay` هو **ردُّ 5xx**، أي أنّ الطلبَ بَلغَ ميسر وفشلَ خادمُها،
/// فقد تَكونُ الدفعةُ أُنشِئت. فتجديدُ المعرّفِ هناك يُلغي حمايةَ ميسر من
/// التكرارِ: الإعادةُ تُنشئُ دفعةً **ثانية**. والإبقاءُ عليه آمنٌ في
/// الحالتَين — تُنشَأُ إن لم تُنشَأْ، وتُرفَضُ إن أُنشِئت، والرفضُ نفسُه
/// حالةٌ مفهومةٌ تُقرأُ «لا تُعيدي الدفع» وتُنقِذُها المكنسةُ.
///
/// **فالقاعدةُ: لا تجديدَ إلّا على نتيجةٍ مؤكَّدةٍ مُسجَّلة**، أي
/// `resultUnknown ⇒ !givenIdConsumed` — ثابتٌ يَشدُّه الفحصُ، لأنّ نقضَه
/// هو الشحنُ المزدوجُ بعينِه.
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

  /// هل سجّلت ميسر محاولةً بهذا `given_id`؟
  ///
  /// المعرّفُ حمايةُ ميسر من الشحنِ المزدوج: محاولةٌ ثانيةٌ به تُرفَض. فمتى
  /// سُجِّلت محاولةٌ **وجبَ** تجديدُه وإلّا دارت العميلةُ في رفضٍ لا مخرجَ
  /// منه؛ ومتى كانت النتيجةُ مجهولةً **حُرِّمَ** تجديدُه وإلّا صارت الإعادةُ
  /// دفعةً ثانية. والافتراضُ `false` لأنّ الشكَّ يَجبُ أن يَقرأَ «لم تُسجَّل».
  final bool givenIdConsumed;

  const MoyasarErrorText(this.message,
      {this.detail = '',
      this.resultUnknown = false,
      this.givenIdConsumed = false});
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
    // **حالةٌ واحدةٌ من 4xx تَعني أنّ محاولةً سابقةً سُجِّلت فعلاً:**
    // `given_id` مُستعمَلٌ سلفاً. والمقروءُ هنا **اسمُ حقلِنا** لا نصُّ
    // البوّابة — مفتاحٌ في `errors`، أو في `message` حين تُعيدُه ميسر نصّاً
    // واحداً (`ValidationError.messageOnly`). فبلا هذه الحالةِ يَصيرُ
    // الإبقاءُ على المعرّفِ طريقاً مسدوداً: كلُّ إعادةٍ تُرفَضُ برسالةِ
    // «بيانات الدفع غير صحيحة» وهي كاذبة، والدفعةُ الأولى معلَّقة.
    final bool idTaken = (result.errors?.containsKey('given_id') ?? false) ||
        result.message.contains('given_id');
    if (idTaken) {
      // و**لا تجديدَ هنا**: وجودُ دفعةٍ بهذا المعرّفِ يَعني أنّ
      // `reconcileOrphanPayments` سيَبنيها طلباً خلالَ دقيقة، فالإعادةُ لا
      // لزومَ لها والتجديدُ يُنشئُ دفعةً ثانية. فالرسالةُ تَقولُ «لا تُعيدي
      // الدفع» والمكنسةُ هي المَخرَج — فلا طريقَ مسدودٌ ولا شحنٌ مزدوج.
      return MoyasarErrorText(kMoyasarUnknownResult,
          detail: 'validation: given_id taken — ${result.message}',
          resultUnknown: true);
    }
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
        detail: 'status=${result.status.name} desc=${result.description ?? ''}',
        // ردُّ 2xx: ميسر أنشأت مستندَ دفعةٍ بهذا المعرّف، فاستعمالُه ثانيةً
        // يُرفَض — وهذه هي الحالةُ الوحيدةُ المؤكَّدةُ من الحزمة.
        givenIdConsumed: true);
  }
  return MoyasarErrorText('حدث خطأ غير متوقع في عملية الدفع',
      detail: 'unknown: ${result?.runtimeType}');
}
