class ZyiarahUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  /// تقييمُ المستخدم — **قد يغيب**، وغيابُه ليس 4.9.
  ///
  /// لا شيءَ في المشروع يكتب `rating` على مستند مستخدم: `aggregateDriverRating`
  /// يكتب `rating_avg`/`rating_count` على مجموعة `drivers` وحدها. فكان الافتراضُ
  /// الثابت 4.9 يجعل **كلَّ** عميلةٍ ترى «تقييمك 4.9 ★» وتظنُّه تقييمَها،
  /// وهو رقمٌ لم يحسبه أحد. `null` الآن تعني «لا تقييم» وتُعرض «—».
  final double? rating;
  final String? houseRules;

  ZyiarahUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.rating,
    this.houseRules,
  });

  factory ZyiarahUser.fromMap(String id, Map<String, dynamic> data) {
    // تحويل دفاعي: `rating` بنوع خاطئ (نصّ مثلاً) كان يرمي استثناءً يُعطّل
    // أي شاشة تقرأ هذا المستخدم. و`toI` زالت مع حقول الاشتراك الخمسة.
    double toD(dynamic v, double fallback) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
    return ZyiarahUser(
      uid: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'client',
      rating: data['rating'] == null ? null : toD(data['rating'], 0),
      houseRules: data['house_rules'],
    );
  }

  // **لا `toMap()` هنا — صفرُ مُنادٍ، وتوصيلُها كان خطراً لا إصلاحاً.**
  //
  // كانت تُعيدُ خريطةً كاملةً لمستندِ المستخدمِ ولا يُناديها شيء، ولم يَرَها
  // `no_dead_code_test` لأنّ اسمَ `toMap` يَتصادمُ مع نظائرِه في كلِّ نموذجٍ
  // (العمى المُعلَنُ في رأسِ ذلك الحارس). والكاتبُ الحقيقيُّ للمستندِ
  // `firebase_service.saveUserToRegistry` يَبني خريطتَه بيدٍ ويَكتبُ بـ`set`
  // **بلا `merge`** — فتمريرُه عبرَها كان سيَكتبُ
  // `has_active_subscription: false` و`visits_remaining: 0` فوقَ ما يَكتبُه
  // `_activateContractNow` عند تفعيلِ عقد. شكلانِ لكتابةٍ واحدةٍ وأحدُهما
  // خطر، فحُذِفَ غيرُ المُستعمَلِ منهما (2026-10-08).
  //
  // **وحقولُ الاشتراكِ الخمسةُ زالت معها (2026-10-08).** كانت
  // `has_active_subscription` و`visits_remaining` و`subscription_expiry`
  // و`subscription_total_visits` و`subscription_type`: يَكتبُها الخادمُ على
  // `users/{uid}`، و`fromMap` يَقرؤها، **ولا جالبَ منها يُقرَأُ في أيِّ سطح**
  // (صفرُ `.visitsRemaining` في `lib/` كلِّها). والرصيدُ الحيُّ لكلِّ عقدٍ
  // على `contracts/{id}.visits_remaining` تَقرؤه `contract_visits.dart`،
  // وبطاقةُ الرئيسيّةِ تَبثُّ `contracts` لا مستندَ المستخدم.
  //
  // ونسخةُ المستخدمِ **خاطئةٌ بالبناءِ** مع عقدَين نشطَين: الرصيدُ
  // `increment` (مجموعٌ على العقود) بينما الثلاثةُ الأخرى يَغلِبُ فيها آخرُ
  // كاتب — فـ«١٦ من ٨». وتعليقُ `_activateContractNow` يَقولُ سببَ
  // العدّاداتِ المستقلّةِ بنصِّه: «بدل طمس حقول المستخدم المجمّعة».
  //
  // وما حجبَها هو تسامحُ `own > 1` في `no_dead_code_test`: لكلِّ حقلٍ في
  // صنفِ بياناتٍ ذِكرانِ دفتريّانِ بالبناء (`this.x` ووَسمُ `x:` في
  // `fromMap`)، فيُعَدُّ ثلاثاً ويَمُرّ. الكاشفُ يُفرِّغُهما الآن.
}
