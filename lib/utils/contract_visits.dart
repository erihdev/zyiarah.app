/// **رصيدُ زياراتِ العقد: الوسمُ يَتبعُ المصدر.**
///
/// `contracts/{id}.visits_remaining` حقلٌ حيٌّ يَكتبُه الخادمُ ويُحرّكُه:
/// `_activateContractNow` يَضَعُه مع `visits_total` عند التفعيل، و
/// `rewards.settleVisitAccounting` يَخصِمُ منه زيارةً مكتملةً ويَرُدُّ
/// زيارةً أُلغيت بعد أن احتُسبت. أمّا `planVisits` فهو **حجمُ الباقةِ**
/// الذي كتبَته شاشةُ التوقيعِ عند الشراء، ولا يَتغيّرُ أبداً.
///
/// **وثلاثةُ أسطحٍ تَعرضُ العدد، وواحدٌ منها كان يَقرأُ الرصيد.** بطاقةُ
/// الرئيسيّةِ (`client_dashboard`) تَقرأُ `visits_remaining` وتَعرضُ
/// «٣ / ١٢»؛ أمّا «عقودي الإلكترونية» فكانت تَقولُ «الزيارات **المتبقية**:
/// ١٢ زيارة» من `planVisits`، وتفاصيلُ العقدِ عند الأدمنِ «الزيارات
/// **المتاحة**: ١٢ زيارة» كذلك. فعميلةٌ استهلكت تسعاً من اثنتَي عشرةَ
/// تَقرأُ رقمَين متناقضَين عن رصيدِها في تطبيقٍ واحد، والأدمنُ يُجيبُ
/// «كم بقيَ لها؟» من ورقةٍ تَحملُ حجمَ الباقةِ لا الرصيد — فيَعِدُ بخدمةٍ
/// لا رصيدَ لها. وهو حيٌّ في كلِّ عقدٍ تجاوزَ زيارتَه الأولى.
///
/// **والقاعدةُ أنّ الوسمَ يَتبعُ المصدر**: رصيدٌ معروفٌ ⇒ «المتبقية»؛
/// رصيدٌ لم يُكتَبْ بعدُ (عقدٌ لم يُفعَّلْ، أو عقدٌ قديمٌ قبلَ العدّاد)
/// ⇒ «زيارات الباقة» بحجمِ الباقة — لا «متبقية» فوقَ رقمِ باقةٍ أبداً؛
/// ولا شيءَ معروفٌ ⇒ «—» بلا رقم.
///
/// وما يَصفُ **الباقةَ المشتراةَ** لا رصيداً لا يَمُرُّ من هنا بقصد: نصُّ
/// الاتفاقيّةِ و«عدد الزيارات» في ورقةِ تفاصيلِها و`planVisits` المُمرَّرُ
/// إلى شاشةِ الدفعِ وإلى الـPDF — كلُّها عن حجمِ الباقةِ وهي صحيحةٌ كما هي.
library;

/// حالةُ عدِّ الزيارات — ثلاثيّةٌ نقيّةٌ تُختبَرُ بلا Firebase.
enum ContractVisitsKind {
  /// `visits_remaining` مكتوبٌ: الرقمُ رصيدٌ فعليّ.
  remaining,

  /// الرصيدُ لم يُكتَبْ، وحجمُ الباقةِ معروف.
  planOnly,

  /// لا رصيدَ ولا حجم — فلا رقم.
  unknown,
}

/// رقمٌ من مستندِ Firestore: `num` أو نصٌّ رقميّ (مستنداتُ الإنتاجِ قد
/// تَحملُ نصّاً — نفسُ تسامحِ `couponExpiryMs` و`publishedBuild`)، وغيرُ
/// ذلك غيابٌ لا صفر.
int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toInt() : null;
  return int.tryParse(v.toString().trim());
}

/// حجمُ الباقة: ما كتبَه الخادمُ عند التفعيل، وإلّا ما كتبَته شاشةُ
/// التوقيع. غيرُ الموجبِ ليس حجماً.
int? contractVisitsTotal(Map<String, dynamic>? d) {
  final int? t = _asInt(d?['visits_total']) ?? _asInt(d?['planVisits']);
  return (t != null && t > 0) ? t : null;
}

/// الرصيدُ المتبقّي، أو `null` متى لم يُكتَبْ بعد.
///
/// سالبٌ يُقرأُ صفراً — صفرٌ **معروفٌ** لا مجهول — ويُقَصُّ عند حجمِ
/// الباقةِ متى عُرف، فلا يُعرَضُ «٦ / ٤».
int? contractVisitsRemaining(Map<String, dynamic>? d) {
  final int? r = _asInt(d?['visits_remaining']);
  if (r == null) return null;
  final int? t = contractVisitsTotal(d);
  final int lo = r < 0 ? 0 : r;
  return (t != null && lo > t) ? t : lo;
}

/// ما يُعرَضُ عن زياراتِ عقدٍ واحد.
class ContractVisitsView {
  final ContractVisitsKind kind;

  /// الرقمُ المعروض — `null` فقط عند [ContractVisitsKind.unknown].
  final int? count;

  /// حجمُ الباقةِ متى عُرف.
  final int? total;

  const ContractVisitsView(this.kind, this.count, this.total);

  /// أنَعرفُ الرصيدَ فعلاً؟ شريطُ التقدّمِ ونصُّ «س / ص» مشروطانِ به.
  bool get knowsBalance => kind == ContractVisitsKind.remaining;

  /// الوسمُ يَتبعُ المصدر.
  String get label {
    switch (kind) {
      case ContractVisitsKind.remaining:
        return 'الزيارات المتبقية';
      case ContractVisitsKind.planOnly:
        return 'زيارات الباقة';
      case ContractVisitsKind.unknown:
        return 'الزيارات';
    }
  }

  /// الرقمُ بوحدتِه، أو «—» عند الجهل.
  String get text => count == null ? '—' : '$count زيارة';

  /// «٣ / ١٢» متى عُرف الرصيدُ والحجمُ، وإلّا [text] وحدَه — فشرطةُ
  /// النسبةِ تَدّعي رصيداً.
  String get ratioText =>
      (knowsBalance && total != null) ? '$count / $total' : text;

  /// نسبةُ الشريط، أو `null` فلا شريط: شريطٌ ممتلئٌ فوقَ رصيدٍ مجهولٍ
  /// يَقولُ إنّ الباقةَ كاملةٌ ولم يَعُدَّها أحد.
  double? get progress {
    if (!knowsBalance || total == null || total! <= 0 || count == null) {
      return null;
    }
    return (count! / total!).clamp(0.0, 1.0);
  }
}

/// القاعدةُ في موضعٍ واحدٍ للأسطحِ الثلاثة.
ContractVisitsView contractVisitsView(Map<String, dynamic>? d) {
  final int? total = contractVisitsTotal(d);
  final int? rem = contractVisitsRemaining(d);
  if (rem != null) {
    return ContractVisitsView(ContractVisitsKind.remaining, rem, total);
  }
  if (total != null) {
    return ContractVisitsView(ContractVisitsKind.planOnly, total, total);
  }
  return const ContractVisitsView(ContractVisitsKind.unknown, null, null);
}
