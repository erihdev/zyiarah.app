import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
  // Code Generation — انتقلَ إلى الخادم
  // ─────────────────────────────────────────────────────────
  // كان هنا `_chars` و`_generateCode` (وأبجديّتُهما نفسُها في
  // `REFERRAL_CODE_CHARS` بالخادم، بلا حروفٍ تُشبِهُ أرقاماً). وُلّدَ الكودُ
  // على الجهازِ ما دامَ فحصُ التصادمِ يَبدو ممكناً هناك — ولم يكن.

  /// كودُ الإحالةِ القائمُ، أو واحدٌ جديدٌ **يُولّدُه الخادم**.
  ///
  /// **كان التوليدُ على الجهازِ ولا يَعملُ أبداً.** فحصُ التصادمِ كان
  /// `users.where('referral_code','==',code).limit(1)` — وقاعدةُ `users` هي
  /// `isOwner(userId) || isAdmin()`، فاستعلامُ **قائمةٍ** على المجموعةِ لا
  /// يُثبِتُ أيَّهما ويُرفَضُ عند كلِّ عميلة. والاستعلامُ بلا `try`، فالاستثناءُ
  /// يَخرجُ من الدالّةِ إلى بطاقةِ «كود الإحالة» في «حسابي»: **كلُّ عميلةٍ لا
  /// تَملكُ كوداً بعدُ لا تَستطيعُ الحصولَ على واحدٍ أبداً**، وبرنامجُ الإحالةِ
  /// كلُّه يَبدأُ بذلك الكود. (مُثبَتٌ على مُحاكي القواعدِ لا مُستنتَجاً.)
  ///
  /// والفحصُ لازمٌ لا وسوسةٌ: `applyReferralCode` يَحُلُّ المُحيلَ بالكودِ، فكودانِ
  /// متطابقانِ إسنادٌ خاطئٌ لمكافأةٍ ماليّة. فمكانُه الخادمُ وحدَه
  /// (`exports.ensureReferralCode`).
  ///
  /// والقراءةُ الأولى تَبقى محلّيّةً: `users/{uid}` مقروءٌ بالقواعدِ
  /// (`isOwner`)، فمَن يَملكُ كوداً لا يَدفعُ ثمنَ نداءٍ خادميّ.
  Future<String> getOrCreateReferralCode(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    final doc = await userRef.get().timeout(kNetCallTimeout);

    if (!doc.exists) throw Exception('User $userId not found');

    final existing = doc.data()?['referral_code'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    // النداءُ عديمُ الأثرِ التكراريّ (مَن يَملكُ كوداً يُعادُ له كما هو)،
    // فمهلةٌ هنا آمنةٌ ولا تَحتاجُ صياغةَ «لا نعرف».
    final res = await FirebaseFunctions.instance
        .httpsCallable('ensureReferralCode')
        .call()
        .timeout(kNetCallTimeout);
    final code = (res.data as Map?)?['code'] as String?;
    if (code == null || code.isEmpty) {
      throw Exception('ensureReferralCode returned no code');
    }
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
