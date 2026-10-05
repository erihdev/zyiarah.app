import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/utils/error_report.dart';
import 'package:zyiarah/utils/net_timeout.dart';

/// نتيجةُ محاولة ربط كود إحالة بحسابٍ جديد — كلُّ حالةٍ لها رسالتُها.
enum ReferralApplyOutcome {
  /// لا كودَ أُدخل أصلاً.
  none,

  /// رُبط بنجاح.
  applied,

  /// لا مستخدمَ يحمل هذا الكود.
  notFound,

  /// الكودُ كودُ صاحب الحساب نفسِه.
  ownCode,

  /// سبق ربطُ إحالةٍ بهذا الحساب.
  already,

  /// تعذّر الوصول أو ردٌّ غيرُ مفهوم.
  failed,
}

/// ZyiarahReferralService — Viral referral engine.
///
/// Responsibilities:
/// 1. Generate a unique 8-char alphanumeric referral code per user.
/// 2. Register a referral link when a new user signs up via a code.
/// 3. On the referee's first completed order:
///    - Credit the referrer 50 SAR to their Zyiarah Wallet.
///    - Issue the referee a 10% discount coupon for their next order.
class ZyiarahReferralService {
  static final ZyiarahReferralService _instance =
      ZyiarahReferralService._internal();
  factory ZyiarahReferralService() => _instance;
  ZyiarahReferralService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Referrer reward: 50 SAR wallet credit.
  static const double referrerRewardSar = 50.0;

  /// Referee reward: 10% discount on their next order.
  static const double refereeDiscountPercent = 10.0;

  // ─────────────────────────────────────────────────────────
  // Code Generation
  // ─────────────────────────────────────────────────────────

  /// Characters used for code generation.
  /// Excludes visually ambiguous characters (0/O, 1/I/L).
  static const String _chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(8, (_) => _chars[rand.nextInt(_chars.length)]).join();
  }

  /// Returns the existing referral code for [userId], or generates and
  /// persists a collision-free one.
  Future<String> getOrCreateReferralCode(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    final doc = await userRef.get().timeout(kNetCallTimeout);

    if (!doc.exists) throw Exception('User $userId not found');

    final existing = doc.data()?['referral_code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    // Generate a collision-free code (up to 5 retries)
    String code = _generateCode();
    for (int i = 0; i < 5; i++) {
      final collision = await _db
          .collection('users')
          .where('referral_code', isEqualTo: code)
          .limit(1)
          .get().timeout(kNetCallTimeout);
      if (collision.docs.isEmpty) break;
      code = _generateCode();
    }

    await userRef.update({'referral_code': code});
    debugPrint('[ZyiarahReferralService] Generated code $code for $userId');
    return code;
  }

  // ─────────────────────────────────────────────────────────
  // Apply Referral Code at Registration
  // ─────────────────────────────────────────────────────────

  /// Called immediately after a new user registers.
  /// Validates [referralCode], resolves the referrer, and creates a
  /// `referrals` document with `status: 'pending'`.
  /// **تُعيد نتيجةً، ولا تبتلعها.**
  ///
  /// كانت `Future<void>` تبتلع كلَّ خطأٍ في `catch` وتطبع ردَّ الخادم
  /// بـ`debugPrint` ثمّ ترميه. فالعميلةُ التي تُدخل كوداً خاطئاً لا تعرف أنّه
  /// لم يُطبَّق — وتنتظر خصمَ 10% على أوّل طلب — ولا نعرف نحن: `debugPrint`
  /// لا يُجمَع ولا يُرسَل. والخادمُ يردّ `{ok, reason}` بثلاثة أسبابٍ مميَّزة
  /// (`not_found`/`self`/`already`) كانت كلُّها تذهب إلى اللاشيء.
  ///
  /// وكان مُستدعيها في شاشة التسجيل يلفّها بـ`try/catch` معلّقاً عليه
  /// «نتجاهله بصمت» — و`catch` ذاك **غيرُ قابلٍ للوصول** أصلاً لأنّ الدالّة
  /// لا ترمي.
  Future<ReferralApplyOutcome> applyReferralCode({
    required String newUserId,
    required String referralCode,
  }) async {
    final code = referralCode.trim().toUpperCase();
    if (code.isEmpty) return ReferralApplyOutcome.none;
    try {
      // الربط يتم خادمياً: العميل يرسل الكود فقط، والخادم يتحقّق منه ويحدّد
      // المُحيل (referrer_id) — فلا يستطيع العميل منح مكافأة إحالة لأي شخص
      // بضبط الحقل يدوياً. القاعدة تمنع كتابة referrals من العميل.
      final res = await FirebaseFunctions.instance
          .httpsCallable('applyReferralCode')
          .call({'code': code});
      final data = res.data;
      final ok = data is Map && data['ok'] == true;
      if (ok) return ReferralApplyOutcome.applied;
      final reason = data is Map ? '${data['reason']}' : '';
      return switch (reason) {
        'not_found' => ReferralApplyOutcome.notFound,
        'self' => ReferralApplyOutcome.ownCode,
        'already' => ReferralApplyOutcome.already,
        _ => ReferralApplyOutcome.failed,
      };
    } catch (e, st) {
      // مسارٌ يمسّ المال (50 ر.س للمُحيل وخصم 10% للمُحال إليه): يُسجَّل
      // بسببٍ **ثابت** كي تتجمّع في Crashlytics مجموعةً واحدة، والسياقُ
      // المتغيّر في `info`.
      reportSilent(e, st,
          reason: 'referral_apply_failed', info: {'uid': newUserId});
      return ReferralApplyOutcome.failed;
    }
  }

  // processReferralReward أُزيلت: مكافأة الإحالة (50 ر.س للمُحيل + كوبون 10% للمُحال)
  // تُمنح الآن خادمياً وآمنةً من سباقات التزامن عبر onOrderRewards (Cloud Function)
  // التي تطالب وثيقة الإحالة (pending -> rewarded) ذرياً بمعرّف حتمي.
}
