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
