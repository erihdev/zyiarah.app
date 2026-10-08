import 'package:cloud_firestore/cloud_firestore.dart';

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
  final bool hasActiveSubscription;
  final int visitsRemaining;
  final DateTime? subscriptionExpiry;
  final String? subscriptionType;
  final String? houseRules;
  final int subscriptionTotalVisits;

  ZyiarahUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.rating,
    this.hasActiveSubscription = false,
    this.visitsRemaining = 0,
    this.subscriptionExpiry,
    this.subscriptionType,
    this.houseRules,
    this.subscriptionTotalVisits = 4,
  });

  factory ZyiarahUser.fromMap(String id, Map<String, dynamic> data) {
    // تحويل دفاعي: قيمة بنوع خاطئ (rating نصّ، visits عدد عشري، expiry ليس
    // Timestamp) كانت ترمي استثناءً يُعطّل أي شاشة تقرأ هذا المستخدم.
    double toD(dynamic v, double fallback) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
    int toI(dynamic v, int fallback) =>
        v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
    return ZyiarahUser(
      uid: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'client',
      rating: data['rating'] == null ? null : toD(data['rating'], 0),
      hasActiveSubscription: data['has_active_subscription'] ?? false,
      visitsRemaining: toI(data['visits_remaining'], 0),
      subscriptionExpiry: data['subscription_expiry'] is Timestamp
          ? (data['subscription_expiry'] as Timestamp).toDate()
          : null,
      subscriptionType: data['subscription_type'],
      houseRules: data['house_rules'],
      subscriptionTotalVisits: toI(data['subscription_total_visits'], 4),
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
  // وحقولُ الاشتراكِ الأربعةُ باقيةٌ: `fromMap` يَقرؤها، ولا جالبَ منها
  // يُقرَأُ بعدُ — مرفوعٌ في `CLAUDE.md` بوصفِه حدَّ تسامحِ `own > 1`
  // (مُعامَلُ البانيةِ `this.x` يُعَدُّ ذِكراً فيَحجبُ الحقل).
}
