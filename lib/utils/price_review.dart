/// **وسمُ مراجعةِ السعرِ كان يُكتَبُ ولا يَقرأُه أحدٌ (2026-10-05).**
///
/// تحقّقُ السعرِ الخادميُّ سياستُه **Tier A: وسمٌ وتنبيهٌ لا رفض** — القرارُ
/// مقصودٌ ومُعلَّلٌ في `price_verify.js` و`_verifyStoreOrderPrice`: الرفضُ
/// يَحجبُ دفعةَ عميلةٍ حقيقيّةٍ إن أخطأنا في الضريبةِ أو التقريب. فمُخرَجُ
/// الفحصِ كلُّه أربعةُ أعلامٍ على المستند — `price_mismatch`،
/// `price_unverifiable`، `price_expected`/`price_expected_net`،
/// `price_shadow_ratio` — وإشعارٌ إداريٌّ نصُّه «راجع المبالغ واسترد الفارق
/// أو اعتمده».
///
/// **ولا قارئَ لأيٍّ منها في أيِّ واجهة**: صفرُ ورودٍ في `lib/` وصفرُ ورودٍ
/// في `admin_panel/src/`. فالإدارةُ تَتلقّى دفعةً بخمسةِ أكوادٍ ثمّ تَفتحُ
/// الطلبَ فتَراه طلباً عاديّاً تماماً: لا مبلغاً متوقَّعاً، ولا نسبةً، ولا
/// وسماً، ولا سبيلَ إلى القولِ «راجعتُه واعتمدتُه». فالوسمُ بيانٌ ميتٌ،
/// والتنبيهُ يُحيلُ إلى شاشةٍ لا تَعرفُه.
///
/// **والأثرُ الثاني أنّ نافذةَ المكنسةِ لا تُصرَّف.** `opsHealthSweep`
/// يَستعلمُ `where("price_mismatch","==",true).limit(200)`، ولا شيءَ في
/// المستودعِ يَمحو العلمَ — فكلُّ طلبٍ وُسِمَ يَبقى في مجموعةِ الاستعلامِ
/// للأبد، وهو عينُ عطلِ «نافذةٌ تَمتلئُ بما لا يُزيلُه أحد» الذي وُجد مرّتَين
/// في هذه الجلسة (نافذةُ البثِّ المجدول، ونافذةُ «مدفوعٌ وعالق»).
/// والاعتمادُ هنا هو ما يُزيل.
///
/// **دقّةٌ تَخصُّ الرقمَ المعروض:** مسارُ ميسر يَكتبُ `price_expected`
/// **قبلَ** الخصمِ الموثوقِ و`price_expected_net` بعدَه، والمقارنةُ التي
/// أنتجت الوسمَ كانت على **الصافي**. فعرضُ `price_expected` وحدَه يُضخّمُ
/// الفارقَ بقيمةِ الكوبون، فتَستردُّ الإدارةُ فرقاً لا تَملكُه. ولذلك
/// [PriceReview.expected] تُقدّمُ الصافيَ متى وُجد.
library;

/// نوعُ الوسمِ على الطلب.
enum PriceReviewKind {
  /// لا وسم.
  none,

  /// مدفوعٌ أقلَّ من المتوقَّع (`price_mismatch`).
  underpaid,

  /// نوعٌ قابلٌ للتسعيرِ تعذّر تسعيرُه — منطقةٌ غائبةٌ أو سلّةٌ بمنتجٍ محذوف
  /// (`price_unverifiable`). ليس نقصاً في الدفع: هو «لا نعلم».
  unverifiable,
}

/// الحقلانِ اللذانِ **تَستعلمُهما** المكنسة — وإبطالُهما هو تصريفُ النافذة.
const List<String> kPriceReviewQueryFlags = <String>[
  'price_mismatch',
  'price_unverifiable',
];

/// حقولُ الشاهدِ: تَبقى بعد الاعتماد (الرقمُ الذي بُني عليه القرارُ لا يُمحى).
const List<String> kPriceReviewEvidenceFields = <String>[
  'price_paid',
  'price_expected',
  'price_expected_net',
  'price_shadow_ratio',
  'coupon_rejected_reason',
];

/// أسبابُ رفضِ الكوبونِ كما يُعيدُها `functions/coupons.js` — بالعربيّة.
///
/// الكوبونُ المرفوضُ خادميّاً لا يُرفَضُ له الطلب (قرارٌ مقصود: سباقُ تطبيقٍ
/// ودفعٍ يَبلغُ بعضَها بحسنِ نيّة)، فالعميلةُ تُخدَمُ بالخصمِ الذي رأته.
/// لكنّ المحاسبةَ تَحتاجُ أن تَعرفَ **لِمَ** نقصَ المبلغُ، وهذا ما لم يكن
/// معروضاً في أيِّ شاشة.
const Map<String, String> kCouponRejectReasons = <String, String>{
  'not_found': 'كود الكوبون غير موجود',
  'inactive': 'الكوبون معطَّل',
  'expired': 'الكوبون منتهي الصلاحية',
  'exhausted': 'الكوبون استُنفد عدد استخداماته',
  'other_user': 'كوبون مخصَّص لعميلة أخرى',
  'other_zone': 'الكوبون لا يشمل منطقة الطلب',
};

/// قراءةُ حالةِ مراجعةِ السعرِ من مستندِ طلبٍ (أو طلبِ متجر).
class PriceReview {
  const PriceReview({
    required this.kind,
    this.paid,
    this.expected,
    this.ratio,
    this.couponRejectedReason,
    this.reviewedAtPresent = false,
  });

  final PriceReviewKind kind;

  /// المبلغُ المخصومُ فعلاً كما سجّلَه الخادمُ لحظةَ الفحص (`price_paid`).
  final double? paid;

  /// المتوقَّعُ الذي قامت عليه المقارنة — الصافي متى وُجد (انظر رأسَ الملف).
  final double? expected;

  final double? ratio;

  /// سببُ رفضِ الكوبونِ خادميّاً إن وُجد — قد يُوجَدُ بلا وسمٍ أصلاً (كوبونُ
  /// 10% يُنتجُ نسبةَ 0.9 فلا يَبلغُ عتبةَ النصف).
  final String? couponRejectedReason;

  /// هل اعتمدَت الإدارةُ المبلغَ سابقاً.
  final bool reviewedAtPresent;

  /// خصمٌ يَبلغُ السعرَ كاملاً مع دفعٍ موجب — `suspiciousZero` خادميّاً.
  /// لا تُحسَبُ له نسبة: القسمةُ على صفر.
  bool get suspiciousZero =>
      kind == PriceReviewKind.underpaid &&
      expected != null &&
      expected == 0 &&
      (paid ?? 0) > 0;

  /// الفارقُ الذي قد يُستردّ — `null` متى تعذّر حسابُه.
  double? get shortfall {
    final double? p = paid;
    final double? e = expected;
    if (p == null || e == null || e <= 0) return null;
    final double diff = e - p;
    return diff > 0 ? diff : null;
  }

  /// هل تَستحقُّ البطاقةُ الظهور.
  ///
  /// يَشملُ **المُعتمَدَ سابقاً** عمداً: الاعتمادُ يُبطِلُ علمَ الاستعلامِ،
  /// فلو كان الظهورُ معلَّقاً على العلمِ وحدَه لاختفى القرارُ وصاحبُه من
  /// الشاشةِ لحظةَ اتّخاذِه — وهو الصمتُ نفسُه من الجهةِ الأخرى.
  bool get needsCard =>
      kind != PriceReviewKind.none ||
      couponRejectedReason != null ||
      reviewedAtPresent;

  /// هل ما زالَ على المستندِ وسمٌ يَنتظرُ قراراً (زرُّ الاعتمادِ يَظهرُ به).
  bool get actionable => kind != PriceReviewKind.none;
}

double? _num(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

/// يَقرأُ الأعلامَ الخادميّةَ من [order] ويُعيدُ حالةً قابلةً للعرضِ والاختبار
/// بلا Firebase.
///
/// الأولويّةُ لـ`price_mismatch`: هو بيانٌ عن مبلغٍ ناقصٍ بأرقام، و
/// `price_unverifiable` بيانُ جهلٍ — ولا يَكتبُهما مسارٌ واحدٌ معاً.
PriceReview priceReviewOf(Map<String, dynamic> order) {
  final bool mismatch = order['price_mismatch'] == true;
  final bool unverifiable = order['price_unverifiable'] == true;
  final Object? rawReason = order['coupon_rejected_reason'];
  final String? reason = rawReason is String && rawReason.trim().isNotEmpty
      ? rawReason.trim()
      : null;

  final PriceReviewKind kind = mismatch
      ? PriceReviewKind.underpaid
      : unverifiable
          ? PriceReviewKind.unverifiable
          : PriceReviewKind.none;

  return PriceReview(
    kind: kind,
    paid: _num(order['price_paid']),
    // الصافي أوّلاً — انظر رأسَ الملف.
    expected:
        _num(order['price_expected_net']) ?? _num(order['price_expected']),
    ratio: _num(order['price_shadow_ratio']),
    couponRejectedReason: reason,
    reviewedAtPresent: order['price_reviewed_at'] != null,
  );
}

/// حِمْلُ «اعتمدتُ المبلغ»: يُبطِلُ علمَي الاستعلامِ ويُسجّلُ القرار.
///
/// لا يَمحو حقولَ الشاهد: الرقمُ الذي بُني عليه القرارُ يَبقى على المستند.
/// والطابعُ الزمنيُّ يُضيفُه موضعُ النداءِ (`FieldValue.serverTimestamp()`)
/// كي يَبقى هذا الملفُّ نقيّاً قابلاً للاختبارِ بلا Firebase.
Map<String, Object?> priceReviewApprovalPayload(String by) => <String, Object?>{
      for (final String f in kPriceReviewQueryFlags) f: false,
      'price_review_decision': 'approved',
      'price_reviewed_by': by,
    };
