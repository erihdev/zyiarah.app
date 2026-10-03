/// إبلاغ صامت عن فشلٍ غير مُجهِض — يصل Crashlytics ولا يزعج المستخدم.
///
/// في الشفرة ثلاث معاملات للخطأ، وكانت تنقص واحدةً:
///
///   ١. `rethrow` — الخطأ مُجهِض، يصعد لمن يعرف كيف يعرضه.
///   ٢. `GlobalErrorHandler.handleError` — يُسجّل **ويُظهر إشعاراً** للمستخدم.
///   ٣. `debugPrint` — لا شيء في الإنتاج. **الفراغ كان هنا.**
///
/// الثالثة هي الأخطر لأنها تبدو معالجةً وليست كذلك: `debugPrint` لا يُجمَّع ولا
/// يُرسَل، فالفشل في جهاز العميل لا يترك أثراً. ومعالج `main.dart` العامّ لا يراه
/// أيضاً — فالخطأ التُقط هنا ولم يصعد إليه.
///
/// فمواضع كـ«فشل توليد فاتورة ZATCA بعد الدفع» أو «فشل حفظ رمز الإشعارات» كانت
/// تمرّ بلا علم أحد: الطلب مدفوع بلا فاتورة ضريبية، والمستخدم يتوقّف عن تلقّي
/// الإشعارات، ولا شيء في أي لوحة يقول ذلك.
///
/// **ليست لكل `catch`.** ابتلاعُ فشل **التعويض** صحيح ومقصود (حذف حسابٍ يتيم ثم
/// `rethrow` للخطأ الأصلي — انظر `firebase_service.dart`)، وكذلك عملياتُ «أفضل
/// جهد» كحذف صورةٍ من المخزن بعد حذف مستندها. تُستعمل هذه الدالة حيث الفشل
/// **يخصّ المال أو الامتثال أو استمرار الخدمة**، وتُترك البقية كما هي.
///
/// **ولا ترمي أبداً:** فشلُ الإبلاغ نفسه لا يجوز أن يكسر النداء المحيط به.
library;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// يُبلّغ عن [error] كغير قاتل، مع [reason] مفتاحاً قصيراً ثابتاً للتجميع.
///
/// [reason] يجب أن يكون نصّاً ثابتاً لا يحمل قيماً متغيّرة (معرّفات، مبالغ) —
/// Crashlytics يجمّع بالسبب، فسببٌ متغيّر يُنتج ألف مجموعة بواحدة في كلٍّ.
/// السياق المتغيّر يُمرَّر في [info].
void reportSilent(
  Object error,
  StackTrace? stack, {
  required String reason,
  Map<String, Object?> info = const {},
}) {
  // يبقى للتطوير المحلّي: الطرفية أسرع من لوحة Crashlytics أثناء العمل.
  debugPrint('[$reason] $error${info.isEmpty ? '' : ' $info'}');

  // Crashlytics بلا تنفيذ على الويب — استدعاؤه هناك يرمي (نفس حَصر main.dart).
  if (kIsWeb) return;

  try {
    final c = FirebaseCrashlytics.instance;
    for (final e in info.entries) {
      c.setCustomKey(e.key, e.value?.toString() ?? 'null');
    }
    c.recordError(error, stack, reason: reason, fatal: false);
  } catch (_) {
    // Firebase غير مُهيَّأ (اختبار وحدة)، أو Crashlytics معطَّل. الإبلاغ
    // وسيلةٌ لا غاية — ولا يجوز أن يُسقط ما جاء يُراقبه.
  }
}
