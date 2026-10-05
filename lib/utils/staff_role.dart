/// «ما دورُ هذا المستخدمِ فعلاً، وهل حسابُه مُفعَّل؟» — قاعدةٌ واحدةٌ تُطابقُ
/// ما تَقرؤه `firestore.rules` بعينِه.
///
/// **العطل (2026-10-05):** `firebase_service.getUserRole` كان يَقرأُ
/// `admins/{uid}` **أوّلاً** ويُعيدُ `staff_role` منه، ولا يَلمسُ `users` إلّا
/// إن غابَ مستندُ `admins`. والقواعدُ تَقرأُ `users/{uid}` وحدَه:
/// `getUserRole()` فيها هو `getUserData().get('staff_role', … 'role' …)`،
/// و`getUserData()` هو `get(/users/$(uid)).data`. فسؤالٌ واحدٌ له **مصدرانِ**،
/// والأثرُ أنّ ما تَعرضُه الواجهةُ قد يُخالِفُ ما يُجيزُه الخادم:
///
///  * `_saveStaff` كان يَكتبُ `users` ثمّ `admins` بلا ذرّيّة، ففشلُ الثانيةِ
///    يَترُكُ القواعدَ على الدورِ الجديدِ والتطبيقَ على القديم. ترقيةٌ ⇒ يَملكُ
///    صلاحيّةً لا يَرى واجهتَها؛ **تنزيلٌ ⇒ يَرى واجهةَ صلاحيّةٍ تَرفضُها
///    القواعدُ في كلِّ كتابة**، وهو بعينُه ما وُجد `panel_role_rules_sync_test`
///    لمنعِه، واصلاً من البياناتِ لا من الجدول.
///  * وأيُّ تغييرٍ لـ`users.staff_role` من سطحٍ لا يَكتبُ `admins` — ومنه
///    **الكونسولُ**، وهو مسارٌ موثَّقٌ في هذا المشروع — يُجمّدُ دورَ الواجهةِ
///    على القديمِ **إلى الأبد**، لا في نافذةِ فشلٍ فحسب. وهو نفسُ ما وُجدَ
///    `syncRoleToPushToken` لأجلِه في `fcm_tokens`: `users` هو المصدرُ،
///    والنُّسَخُ تَتبعُه.
///
/// فالترتيبُ هنا هو ترتيبُ القواعدِ: `users.staff_role` ثمّ `users.role`، و
/// `admins` **احتياطاً فقط** حين لا يَحملُ `users` دوراً أصلاً — وذاك حسابٌ
/// أُنشئ بيدٍ في الكونسولِ أو حسابُ تأسيسٍ قديم، فحجبُه كان سيُقفِلُ الإدارةَ.
library;

/// أدوارُ الموظّفينَ كما تَعرفُها `firestore.rules`.
const Set<String> kStaffRoles = {
  'admin',
  'super_admin',
  'orders_manager',
  'accountant_admin',
  'marketing_admin',
};

/// الدورُ المُعتَبَرُ من مستندِ `users`، أو `null` إن لم يَحملْ دوراً.
String? roleFromUsersDoc(Map<String, dynamic>? u) {
  if (u == null) return null;
  final staff = (u['staff_role'] as String?)?.trim();
  if (staff != null && staff.isNotEmpty) return staff;
  final role = (u['role'] as String?)?.trim();
  if (role != null && role.isNotEmpty) return role;
  return null;
}

/// الدورُ من مستندِ `admins` — **احتياطٌ** لحسابٍ لا يَحملُ `users` دوراً.
String? roleFromAdminsDoc(Map<String, dynamic>? a) {
  if (a == null) return null;
  final staff = (a['staff_role'] as String?)?.trim();
  if (staff != null && staff.isNotEmpty) return staff;
  final role = (a['role'] as String?)?.trim();
  if (role != null && role.isNotEmpty) return role;
  return 'admin';
}

/// هل الحسابُ مُوقَفٌ — يُقرأُ من **`users`** وحدَه، وهو المستندُ الذي
/// تَقرؤه القواعدُ، فلا قراءةَ ثانيةً في كلِّ دخول.
///
/// الغيابُ يَعني **مُفعَّلاً**: مستنداتُ الإنتاجِ القائمةُ لا تَحملُ الحقلَ،
/// فاعتبارُ غيابِه إيقافاً كان سيُقفِلُ الإدارةَ كلَّها. ولا يُقرأُ إلّا لدورِ
/// موظّف: `is_active` على مستندِ عميلةٍ لا معنى له اليومَ، فقراءتُه هناك
/// كانت ستَطرُدَ عميلاتٍ لحقلٍ كُتبَ لسببٍ آخر.
bool staffAccountDisabled(Map<String, dynamic>? u, String? resolvedRole) {
  if (resolvedRole == null || !kStaffRoles.contains(resolvedRole)) return false;
  return (u?['is_active']) == false;
}
