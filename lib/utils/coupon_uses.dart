/// **صفرُ `maxUses` يَعني «بلا حدّ» — وثلاثةُ أسطحٍ قالت ثلاثةَ أشياءَ مختلفة.**
///
/// الخادمُ صريحٌ: `if (maxUses > 0 && uses >= maxUses) return "exhausted";`
/// في `functions/coupons.js` — فصفرٌ (أو غيابٌ أو غيرُ رقميٍّ) يَعني **لا سقفَ
/// إطلاقاً**. ولم يَقُل ذلك أيُّ سطح:
///
/// * **محرِّرُ التطبيقِ** كان يَكتبُ `int.tryParse(maxUsesCtrl.text) ?? 0` بلا
///   أيِّ تحقّق، وحقلُه `TextField` بلا `inputFormatters` — فلوحةُ مفاتيحٍ
///   عربيّةٌ تُدخِلُ «١٠» و`int.tryParse` لها `null`، فيُحفَظُ **صفرٌ** أي
///   **كوبونٌ بلا حدٍّ** مع «تم حفظ كود الخصم بنجاح ✅»: عكسُ ما ضبطَه المالكُ
///   تماماً، وكوبونُ خمسينَ بالمئةِ لمرّةٍ واحدةٍ يَصيرُ مفتوحاً للجميع.
/// * **بطاقةُ التطبيقِ** تَطبعُ «الاستخدام: 5 من **0**» — تُقرأُ «نَفِد»
///   والخادمُ يَعدُّه مفتوحاً.
/// * **جدولُ اللوحةِ** عُرفُه أنّ «بلا حدّ» رقمٌ كبير (`maxUses > 9999 ? '∞'`)
///   لا صفر، فيَطبعُ `0` ويَحسبُ `uses / 0`: مع استخدامٍ موجبٍ يَصيرُ
///   `Infinity` و`Math.min(…, 100)` تُعطي شريطاً **ممتلئاً أحمرَ** — أي
///   «نَفِد» بأعلى صوت، عن كوبونٍ لا سقفَ له. وذاك العُرفُ نفسُه كذبةٌ من
///   الجهةِ الأخرى: كوبونٌ سقفُه 10000 يُرسَمُ «∞» والخادمُ يُنفِّذُ السقف.
///
/// فالقاعدةُ هنا **تَتبعُ الخادمَ حرفاً**: بلا حدٍّ ⟺ ما يَعدُّه الخادمُ بلا
/// حدّ. وهي الحالةُ **الخامسةُ** من «حقلُ قرارٍ يُقرأُ بافتراضٍ صامتٍ يَعرفُه
/// سطحٌ واحد» بعد مفاتيحِ الإصدارِ و`show_in_offers` و`operational` و
/// `store_audience` — إلّا أنّ هذه تُقرأُ على ثلاثةِ أسطحٍ بثلاثةِ معانٍ.
library;

/// العددُ كما يَقرؤه الخادمُ: `Number(coupon.maxUses) || 0` — فغيرُ الرقميِّ
/// والغيابُ والسالبُ كلُّها صفرٌ أي «بلا حدّ».
int couponMaxUses(Object? raw) {
  final n = raw is num ? raw : num.tryParse('${raw ?? ''}');
  if (n == null || !n.isFinite || n <= 0) return 0;
  return n.toInt();
}

/// العددُ المستهلَك — نفسُ تسامحِ الخادمِ (`Number(coupon.uses) || 0`).
int couponUses(Object? raw) {
  final n = raw is num ? raw : num.tryParse('${raw ?? ''}');
  if (n == null || !n.isFinite || n <= 0) return 0;
  return n.toInt();
}

/// بلا سقفٍ — مرآةُ `maxUses > 0 &&` في `couponProblem`.
bool couponIsUnlimited(Object? rawMaxUses) => couponMaxUses(rawMaxUses) == 0;

/// نَفِدَ — مرآةُ `uses >= maxUses` بعد شرطِ السقف.
bool couponIsExhausted(Object? rawUses, Object? rawMaxUses) {
  final max = couponMaxUses(rawMaxUses);
  return max > 0 && couponUses(rawUses) >= max;
}

/// سطرُ الاستخدامِ المعروض. «بلا حدّ» تُقالُ بالكلماتِ لا برقمٍ صفريٍّ يُقرأُ
/// «نَفِد».
String couponUsesLabel(Object? rawUses, Object? rawMaxUses) {
  final uses = couponUses(rawUses);
  if (couponIsUnlimited(rawMaxUses)) {
    return 'الاستخدام: $uses (بلا حدّ)';
  }
  return 'الاستخدام: $uses من ${couponMaxUses(rawMaxUses)}';
}

/// تقدّمُ الشريط، أو `null` حين لا سقفَ — فلا شريطَ يُرسَمُ أصلاً بدلَ أن
/// يُرسَمَ ممتلئاً أو فارغاً، وكلاهما دعوى.
double? couponUsesProgress(Object? rawUses, Object? rawMaxUses) {
  final max = couponMaxUses(rawMaxUses);
  if (max <= 0) return null;
  final r = couponUses(rawUses) / max;
  return r < 0 ? 0.0 : (r > 1 ? 1.0 : r);
}
