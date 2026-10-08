/// **سجلُّ حذفِ الحساب: مَن حُذف، وهل بقي له مال.**
///
/// `account_deletions/{uid}` يُنشَأُ في موضعَين — العميلةُ من «حسابي»
/// (`profile_screen`) والأدمنُ من شاشةِ المستخدمين (`admin_users_screen`) —
/// ويُكمِلُه الخادمُ (`processAccountDeletion`). ويُعرَضُ في سطحَين:
/// `admin_deletions_screen` و`AccountDeletion.tsx`.
///
/// **والدَّينُ كان مكتوباً في حقلٍ لا يَقرؤه سطح.** الخادمُ يَقرأُ رصيدَ
/// المحفظةِ **قبل** حذفِ هويّةِ المصادقة ويَكتبُه
/// `wallet_balance_at_deletion` على طلبِ الحذف، وتعليقُه يَقولُ السببَ
/// نصّاً: «كي يبقى الدَّينُ مكتوباً **في مكانٍ يَقرؤه البشرُ** لا في وثيقةِ
/// محفظةٍ يتيمة». وكان الحقلُ **مكتوباً في موضعٍ ومقروءاً في صفر** — فالنصفُ
/// الدائمُ من ذلك الإصلاحِ لم يَصِلْ عيناً. (الدفعةُ إلى
/// `super_admin`/`accountant_admin` قائمةٌ، لكنّها عابرة.)
///
/// **والهويّةُ كانت تُقرَأُ من حقلَين لا يَكتبُهما أحد.** اللوحةُ تَعرِضُ
/// `name` فوقَ `phone`: و`name` لا يَكتبُه كاتبٌ قطّ، و`phone` يَكتبُه
/// مسارُ العميلةِ من `user?.phoneNumber` — والمصادقةُ **بالبريدِ وحدَه**
/// (لا دخولَ بالجوّال، قرارٌ في الجذر) فهو `null` دائماً. فكلُّ صفٍّ في
/// سجلِّ امتثالِ آبل يُقرأُ «— / —». و`email` **مكتوبٌ** ولا تَقرؤه اللوحةُ
/// إطلاقاً، بينما شاشةُ التطبيقِ تَقرؤه صحيحاً — فالقاعدةُ مُنفَّذةٌ في
/// سطحٍ من اثنَين.
library;

import 'package:zyiarah/utils/home_packages.dart';

/// الهويّةُ المعروضةُ للطلب: البريدُ ثمّ الاسمُ ثمّ الجوّالُ، وإلّا فلا
/// ادّعاء. (الترتيبُ يَتبعُ ما يُكتَبُ فعلاً: البريدُ هو ما يَكتبُه مسارُ
/// العميلة.)
String deletionRowIdentity(Map<String, dynamic>? d) {
  for (final k in const ['email', 'name', 'phone']) {
    final Object? v = d?[k];
    final String s = (v ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return 'حساب مجهول';
}

/// الرصيدُ المحجوزُ عند الحذفِ — `null` متى لم يُكتَبْ بعدُ (الطلبُ لم
/// يُعالَجْ خادميّاً) أو لم يَكن موجباً. **لا رقمَ قبل أن نعرفه:** صفرٌ
/// ليس دَيناً، وغيابُ الحقلِ ليس صفراً.
double? deletionStrandedBalance(Map<String, dynamic>? d) {
  final Object? raw = d?['wallet_balance_at_deletion'];
  if (raw == null) return null;
  final double? v = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

/// سطرُ الدَّينِ كما يُعرَضُ للأدمن، أو `null` فلا سطر.
String? deletionStrandedNotice(Map<String, dynamic>? d) {
  final double? v = deletionStrandedBalance(d);
  if (v == null) return null;
  return 'رصيد محجوز: ${formatSar(v)} ر.س — التسوية يدوية';
}

/// حالةُ طلبِ الحذف — القاعدةُ في موضعٍ واحدٍ للسطحَين.
///
/// **والسطحانِ كانا يَقرآنِ القيمةَ الواحدةَ على وجهَين.** `'deleted'` يَعني
/// «سُجِّلَ الطلبُ والخادمُ يَعملُ عليه»: شاشةُ التطبيقِ تَقولُ «جاري
/// المسح…» بالبرتقاليّ (صحيح) واللوحةُ كانت تَرسمُه **«تم الحذف نهائياً»
/// بعلامةٍ خضراءَ** مع `deleted_fully_processed` — دعوى إتمامٍ على حالةٍ قد
/// تَكونُ عالقةً: لو ماتَ الحاوي بين `getAuth().deleteUser` وتحديثِ الحالة
/// بقيَ المستندُ `'deleted'` **إلى الأبد** واللوحةُ تَقولُ إنّ الحذفَ تمَّ.
/// وهذا سطحُ امتثالِ آبل.
enum DeletionRequestState {
  /// سُجِّلَ، والخادمُ يُنفّذُ (`deleted`).
  inProgress,

  /// اكتملَ التنظيفُ الخادميُّ (`deleted_fully_processed`).
  completed,

  /// حاولَ الخادمُ وفشل (`failed_deletion`) — ومعه سببٌ في `error`.
  failed,

  /// `rejected` — لا يَكتبُه سطحٌ بعدَ اليوم (انظر [deletionRetryAllowed])،
  /// والتسميةُ باقيةٌ لمستنداتٍ قائمةٍ في الإنتاج.
  rejected,

  /// قيمةٌ لا يَكتبُها شيءٌ في المستودع، أو غائبة. **لا ندّعي عنها:**
  /// `'pending'` كانت تُقرأُ هكذا — افتراضُ السطحَين القديمُ — ولا كاتبَ
  /// لها (المساراتُ الأربعةُ كلُّها تَكتبُ `'deleted'` مباشرةً).
  unknown,
}

/// حالةُ الطلبِ من حقلِ `status` الخامّ.
DeletionRequestState deletionRequestState(Object? status) {
  switch ((status ?? '').toString().trim()) {
    case 'deleted':
      return DeletionRequestState.inProgress;
    case 'deleted_fully_processed':
      return DeletionRequestState.completed;
    case 'failed_deletion':
      return DeletionRequestState.failed;
    case 'rejected':
      return DeletionRequestState.rejected;
    default:
      return DeletionRequestState.unknown;
  }
}

/// تسميةُ الحالةِ للأدمن.
String deletionStateLabel(DeletionRequestState s) {
  switch (s) {
    case DeletionRequestState.inProgress:
      return 'جاري الحذف…';
    case DeletionRequestState.completed:
      return 'تم الحذف نهائياً';
    case DeletionRequestState.failed:
      return 'فشل الحذف — يتطلب مراجعة';
    case DeletionRequestState.rejected:
      return 'مرفوض (طلب قديم)';
    case DeletionRequestState.unknown:
      return 'حالة غير معروفة — راجِعْ المستند';
  }
}

/// مُهلةُ عدِّ `'deleted'` عالقاً. التنظيفُ الخادميُّ ثوانٍ، فساعةٌ هامشٌ
/// واسعٌ يَمنعُ إعادةَ تشغيلٍ فوقَ تنفيذٍ جارٍ (وهي لا تَضُرّ — الحذفُ
/// عديمُ الأثرِ التكراريِّ — لكنّها تُكرّرُ دفعةَ الرصيدِ المحجوز).
const Duration kDeletionStuckGrace = Duration(hours: 1);

/// أتُعرَضُ إعادةُ المحاولة؟
///
/// **الفشلُ كان بلا إجراءٍ في السطحَين معاً.** الخادمُ يَكتبُ
/// `failed_deletion` ويَقولُ السطحانِ «يتطلب مراجعة» — ولا زرَّ: الأزرارُ
/// كانت محصورةً بـ`status == 'pending'` **ولا كاتبَ لها في المستودع**، فكلُّ
/// إجراءٍ إداريٍّ على هذه المجموعةِ غيرُ قابلِ الوصول. والمَخرَجُ الوحيدُ
/// كان تعديلَ Firestore بيدٍ، على مسارٍ يَلزمُه متطلّبُ آبل.
///
/// وإعادةُ الكتابةِ `'deleted'` هي المُشغِّلُ نفسُه:
/// `onAccountDeletionStatusChanged` شرطُه `before.status !== 'deleted'`،
/// وهو مُستوفًى من `failed_deletion` — فلا آليّةَ جديدة.
///
/// و`unknown` **لا** تُعرَضُ له إعادة: لا نَعرفُ ما هو، وكتابةُ `'deleted'`
/// فوقَه حذفٌ لا رجعةَ فيه بناءً على جهل.
bool deletionRetryAllowed({
  required DeletionRequestState state,
  required DateTime? requestedAt,
  required DateTime now,
}) {
  if (state == DeletionRequestState.failed) return true;
  if (state != DeletionRequestState.inProgress) return false;
  if (requestedAt == null) return false;
  return now.difference(requestedAt) >= kDeletionStuckGrace;
}

/// سببُ الفشلِ كما كتبَه الخادمُ، أو `null`.
///
/// **كان بلا قارئٍ في أيِّ سطح.** `processAccountDeletion` يَكتبُ
/// `error: error.message` ليُقرَأ، وتعليقُه يَقولُ «Record the failure so it
/// can be retried/inspected by an admin» — فالسطحانِ يَقولانِ «يتطلب
/// مراجعة» ولا يُظهرانِ ما يُراجَع. والنصُّ الخامُّ مقصودٌ هنا: الجمهورُ
/// المالكُ، وهو قرارٌ قائمٌ في شاشاتِ الإدارة.
String? deletionFailureReason(Map<String, dynamic>? d) {
  final String s = (d?['error'] ?? '').toString().trim();
  return s.isEmpty ? null : s;
}
