/// **حقلٌ رقميٌّ في محرِّرٍ إداريٍّ: يُرفَضُ غيرُ الصالحِ ولا يُبتلَعُ صفراً.**
///
/// محرِّرا باقاتِ الاشتراكِ وعاملاتِ المناسباتِ (`admin_subscriptions_screen`،
/// `admin_event_worker_packages_screen`) ولوحةُ الويب (`Contracts.tsx`) كانت
/// كلُّها تَكتبُ `double.tryParse(x) ?? 0.0` و`int.tryParse(x) ?? 0` — فقيمةٌ
/// لا تَنحلُّ إلى رقمٍ تُخزَّنُ **صفراً** مع «تمّ الحفظُ بنجاح»، والنتيجةُ
/// باقةٌ **لا تُباع**:
///
/// * **السعرُ صفراً** → بطاقةُ الباقةِ تُعرَضُ للعميلةِ بـ«0 ر.س» (مجّاناً)،
///   فتَجدولُ زياراتِها وتُتابع — ثمّ تَرفُضُ قاعدةُ إنشاءِ العقدِ المستندَ
///   (`planPrice > 0` في `firestore.rules`)، فتَرى خطأَ صلاحيّاتٍ عن باقةٍ
///   أُعلِنَت لها. ولو بَلغَ الدفعَ لرفضَه `payContractWithWallet` («سعر
///   الباقة غير صالح») ولرفضَ `_validateContractPlan` التفعيلَ (`base > 0`).
/// * **الزياراتُ صفراً** → `onPressed` لزرِّ المتابعةِ `null` بلا أيِّ رسالة
///   (`visits <= 0` في `subscription_plans_screen`): بطاقةٌ تُعرَضُ ولا
///   يُمكِنُ شراؤها، والإدارةُ لا تَعلم.
///
/// **والحالةُ حيّةٌ لا نظريّة:** حقولُ المحرِّرِ الدارتيِّ `TextField` بـ
/// `keyboardType: TextInputType.number` **بلا `inputFormatters`**، فلوحةُ
/// مفاتيحٍ عربيّةٌ تُدخِلُ «٣٥٠» و`double.tryParse('٣٥٠')` هي `null`. ولوحةُ
/// الويبِ `<input type="number">` فتَمنعُ ذلك، لكنّ حقلَ الزياراتِ ليس
/// إلزاميّاً في أيِّ جهة: تركُه فارغاً يَكتبُ صفراً في الأربعِ.
///
/// فالقاعدةُ: **نُطبِّعُ ثمّ نتحقّقُ ثمّ نَرفُضُ** — نفسُ قرارِ السعةِ
/// اليوميّةِ ورقمِ البناءِ في `admin_settings_screen` («نرفض غير الصالح بدل
/// ابتلاعه») ونفسِ تسامحِ `publishedBuild`/`couponExpiryMs` مع الشكلِ الذي
/// يَكتبُه إنسان.
library;

/// تطبيعُ الأرقامِ: العربيّةُ-الهنديّةُ (٠..٩) والفارسيّةُ (۰..۹) إلى
/// لاتينيّة، والفاصلةُ العربيّةُ «٫» إلى نقطة، وفاصلُ الآلافِ «٬» يُحذَف،
/// ومعها علاماتُ الاتّجاهِ غيرُ المرئيّةِ (U+200E/200F/U+061C) التي تَلتصقُ
/// بالرقمِ عند لصقِه من مستندٍ عربيّ.
String normalizeDigits(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660)); // ٠..٩
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0)); // ۰..۹
    } else if (rune == 0x066B) {
      out.write('.'); // ٫
    } else if (rune == 0x066C ||
        rune == 0x200E ||
        rune == 0x200F ||
        rune == 0x061C) {
      // فاصلُ الآلافِ وعلاماتُ الاتّجاه: تُحذَف
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().trim();
}

/// رقمٌ موجبٌ صالح، أو `null` — والـ`null` يَعني **غيرَ صالح** (فارغٌ، أو لا
/// يَنحلُّ إلى رقم، أو ليس أكبرَ من صفر)، فلا يُبتلَعُ إلى قيمةٍ افتراضيّة.
double? positiveNum(String raw) {
  final v = double.tryParse(normalizeDigits(raw));
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

/// نفسُ القاعدةِ لعددٍ صحيحٍ موجب — **مُشتَقّةً من `positiveNum`** لا من
/// `int.tryParse`: الأخيرةُ تَرُدُّ `null` لـ«3e2» و«4.0» بينما `Number` في
/// الجافاسكربت تَقبلُهما، فمرآةٌ مبنيّةٌ عليها تَنحرِفُ عن أختِها في حالاتٍ
/// يُنتجُها لصقٌ من جدول. والحدُّ `1e15` يَحمي `toInt()` من مدًى لا يَسعُه.
int? positiveInt(String raw) {
  final v = positiveNum(raw);
  if (v == null || v != v.roundToDouble() || v > 1e15) return null;
  return v.toInt();
}

/// **حقلٌ اختياريٌّ: الفراغُ قرارٌ، وخطأُ الكتابةِ ليس قراراً.**
///
/// الفراغُ يُعيدُ `whenEmpty` — وهي قيمةٌ **مقصودةٌ** تَختلفُ بالحقل: صفرٌ
/// يَعني «غيرُ معروضة» في أسعارِ المنطقة، و«بلا حدّ» في `maxUses` وفي
/// `max_orders_per_day`. أمّا نصٌّ لا يَنحلُّ إلى رقمٍ فيُعيدُ `null` =
/// **غيرُ صالح**، فلا يُبتلَعُ إلى تلك القيمةِ المقصودةِ بصمت. والسالبُ
/// مرفوضٌ (لا معنى له في أيٍّ من هذه الحقول) والصفرُ المكتوبُ صريحاً مقبول.
double? optionalNum(String raw, {required double whenEmpty}) {
  final t = normalizeDigits(raw);
  if (t.isEmpty) return whenEmpty;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite || v < 0) return null;
  return v;
}

/// نفسُ القاعدةِ لعددٍ صحيحٍ — مُشتَقّةً من `optionalNum` كي لا تَنحرِفَ عن
/// المرآةِ على «3e2» و«4.0» (نفسُ سببِ `positiveInt`).
int? optionalInt(String raw, {required int whenEmpty}) {
  final v = optionalNum(raw, whenEmpty: whenEmpty.toDouble());
  if (v == null || v != v.roundToDouble() || v > 1e15) return null;
  return v.toInt();
}

/// **تسميةُ أوّلِ حقلٍ مكتوبٍ لا يَنحلُّ إلى رقمٍ غيرِ سالب**، أو `null` إن
/// صحّت كلُّها. الفراغُ **يَمُرُّ** — فهو قرارٌ مقصودٌ في هذه الحقول — والمعنى
/// يَبقى عند الكاتبِ (`optionalNum` مع `whenEmpty` المناسبة).
///
/// وُجد لأنّ محرِّرَ المناطقِ وحدَه يَحملُ **أربعةً وثلاثين** حقلاً رقميّاً،
/// فبوّابةٌ واحدةٌ تُسمّي الحقلَ المُخطِئَ أنفعُ من أربعةٍ وثلاثينَ فحصاً —
/// ورسالةٌ عامّةٌ («تحقّقي من الأرقام») تَترُكُ المالكَ يَبحثُ في شبكةٍ من
/// الصناديق.
String? firstInvalidNumber(Map<String, String> fields) {
  for (final e in fields.entries) {
    if (optionalNum(e.value, whenEmpty: 0) == null) return e.key;
  }
  return null;
}

/// العددُ المجاورُ لكلمةِ «زيار» في نصِّ الباقةِ — **نفسُ** احتياطيِّ العميلِ
/// (`subscription_plans_screen`) والخادمِ (`_validateContractPlan`)، فالمحرِّرُ
/// يَرفُضُ ما لا يَستطيعُ أحدُهما حلَّه بعينِه.
int visitsFromText(String text) {
  final m = RegExp(r'(\d+)\s*زيار').firstMatch(normalizeDigits(text));
  if (m == null) return 0;
  return int.tryParse(m.group(1) ?? '') ?? 0;
}

/// عددُ الزياراتِ الذي يُكتَبُ على الباقة: الحقلُ إن صحّ، وإلّا المُستخرَجُ من
/// النصّ. وكتابةُ المُستخرَجِ **تُفعِّلُ فحصَ الخادمِ** للزيارات: كان يُتخطّى
/// كلَّه متى كان `pkg.visits <= 0`، فيَقبلُ أيَّ `planVisits` يُعلِنُه العميل.
int resolvedVisits({required String visitsField, required String text}) =>
    positiveInt(visitsField) ?? visitsFromText(text);

/// رسالةُ الخطأِ الأولى، أو `null` إن صحّ الحِمل. `workers` غيرُ `null` في
/// باقاتِ عاملاتِ المناسباتِ وحدَها — الخادمُ يَفرضُ تطابقَ العددِ متى كان
/// `pkg.workers > 0` ويَتخطّى الفحصَ عند الصفر.
String? packageFormError({
  required String title,
  required String price,
  required String visits,
  required String hours,
  required String text,
  String? workers,
}) {
  if (title.trim().isEmpty) return 'أدخِل اسم الباقة';
  if (positiveNum(price) == null) {
    return 'السعر يجب أن يكون رقماً أكبر من صفر';
  }
  if (visits.trim().isNotEmpty && positiveInt(visits) == null) {
    return 'عدد الزيارات يجب أن يكون رقماً صحيحاً أكبر من صفر';
  }
  if (visits.trim().isEmpty && visitsFromText(text) <= 0) {
    return 'أدخِل عدد الزيارات — باقة بلا عدد زيارات لا يستطيع العميل شراءها';
  }
  if (hours.trim().isNotEmpty && positiveInt(hours) == null) {
    return 'عدد الساعات لكل زيارة يجب أن يكون رقماً صحيحاً أكبر من صفر';
  }
  if (workers != null && positiveInt(workers) == null) {
    return 'عدد العاملات يجب أن يكون رقماً صحيحاً أكبر من صفر';
  }
  return null;
}
