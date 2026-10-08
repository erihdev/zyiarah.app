/// أسماءُ إجراءاتِ سجلِّ التدقيقِ وتسمياتُها العربيّةُ في موضعٍ واحد.
///
/// **سببُ وجودِه:** خريطةُ التسمياتِ كانت `switch` داخلَ شاشةِ العرضِ
/// (`admin_audit_logs_screen._getActionLabel`) بفرعٍ جامعٍ `default: return
/// action;` — أي **تعداداً**، فكلُّ إجراءٍ أُضيفَ بعدَها سقطَ منها بصمت.
/// فمن ٤٩ اسماً يَكتبُها المستودعُ فعلاً كانت ١٧ مُسمّاةً و**٣٢ تُعرَضُ
/// بحرفِها اللاتينيِّ** في سجلٍّ عربيٍّ ترويستُه تَقول «هذا السجل يوثق كافة
/// التغييرات الجوهرية»: «BAN_USER» عنواناً لبطاقةِ حظرِ حساب،
/// و«DELETE_PRODUCT»، و«REVIEW_ORDER_PRICE» — وهذا الأخيرُ قرارٌ ماليٌّ
/// بشريٌّ يُبطِلُ علمَ المكنسةِ، يُكتَبُ من **أربعةِ** أسطح.
///
/// فالقاعدةُ: **كلُّ اسمٍ يُكتَبُ له تسميةٌ**، ومجموعةُ المفاتيحِ هنا تُساوي
/// مجموعةَ ما يُكتَبُ في المستودعِ زائداً المُعلَنَ بلا كاتب — يَشدُّها
/// `test/audit_coverage_test.dart` اشتقاقاً، فاسمٌ جديدٌ يَسقطُ الفحصَ يومَ
/// كتابتِه لا يومَ قراءتِه.
library;

/// تسمياتُ الإجراءاتِ كما تُعرَضُ للمالك.
const Map<String, String> kAuditActionLabels = {
  // الموظّفون والإدارة
  'CREATE_STAFF': 'إضافة موظف جديد',
  'UPDATE_STAFF': 'تعديل بيانات موظف',
  'DELETE_STAFF': 'حذف موظف',
  'TOGGLE_ADMIN_STATUS': 'تغيير حالة موظف إداري',

  // الكوادر
  'REGISTER_DRIVER': 'تسجيل كادر/عامل جديد',
  'UPDATE_DRIVER': 'تعديل بيانات كادر',
  'DELETE_DRIVER': 'حذف كادر نهائياً',
  'TOGGLE_DRIVER_STATUS': 'تغيير حالة كادر',

  // أكواد الخصم
  'CREATE_COUPON': 'إنشاء كود خصم',
  'UPDATE_COUPON': 'تعديل كود خصم',
  'DELETE_COUPON': 'حذف كود خصم',

  // الطلبات
  'UPDATE_ORDER_STATUS': 'تحديث حالة الطلب',
  'ADVANCE_MANAGED_ORDER': 'تقديم حالة طلب مُدار إدارياً',
  'ASSIGN_DRIVER': 'تعيين كادر للطلب',
  'CANCEL_ORDER': 'إلغاء طلب',
  'REVIEW_ORDER_PRICE': 'اعتماد مبلغ طلب بعد مراجعة السعر',

  // المتجر
  'CREATE_STORE_ORDER': 'إنشاء طلب متجر',
  'UPDATE_STORE_ORDER_STATUS': 'تحديث حالة طلب متجر',
  'CREATE_PRODUCT': 'إضافة منتج للمتجر',
  'UPDATE_PRODUCT': 'تعديل منتج في المتجر',
  'DELETE_PRODUCT': 'حذف منتج من المتجر',

  // مناطق التغطية والأسعار
  'CREATE_ZONE': 'إضافة منطقة تغطية',
  'UPDATE_ZONE': 'تعديل منطقة تغطية',
  'DELETE_ZONE': 'حذف منطقة تغطية',
  'ENABLE_ZONE': 'تشغيل منطقة تغطية',
  'DISABLE_ZONE': 'تعطيل منطقة تغطية',
  'APPLY_PRICES_TO_ZONES': 'نسخ الأسعار إلى مناطق أخرى',
  'UPDATE_SERVICE_PRICE': 'تغيير سعر خدمة',
  'TOGGLE_SERVICE_STATUS': 'تغيير حالة خدمة',

  // العقود والباقات
  'CLIENT_SIGN_CONTRACT': 'توقيع عقد إلكتروني جديد',
  'APPROVE_CONTRACT': 'اعتماد عقد بانتظار الدفع',
  'DELETE_CONTRACT': 'حذف سجل عقد نهائياً',
  'ACTIVATE_CONTRACT': 'تفعيل عقد واحتساب رصيد',
  'ACTIVATE_CONTRACT_TAMARA': 'تفعيل عقد مدفوع بالتقسيط',
  'CREATE_SUBSCRIPTION': 'إضافة باقة اشتراك',
  'UPDATE_SUBSCRIPTION': 'تعديل باقة اشتراك',
  'DELETE_SUBSCRIPTION': 'حذف باقة اشتراك',
  'CREATE_EVENT_WORKER_PACKAGE': 'إضافة باقة عاملات مناسبات',
  'UPDATE_EVENT_WORKER_PACKAGE': 'تعديل باقة عاملات مناسبات',
  'DELETE_EVENT_WORKER_PACKAGE': 'حذف باقة عاملات مناسبات',

  // الحسابات
  'BAN_USER': 'حظر حساب',
  'UNBAN_USER': 'رفع الحظر عن حساب',
  'DELETE_USER': 'حذف حساب مستخدم',
  'PROCESS_ACCOUNT_DELETION': 'تنفيذ طلب حذف حساب',

  // المحتوى والإشعارات والإعدادات
  'CREATE_BANNER': 'إضافة بانر إعلاني',
  'UPDATE_BANNER': 'تعديل بانر إعلاني',
  'DELETE_BANNER': 'حذف بانر إعلاني',
  'CREATE_POLICY': 'إضافة سياسة',
  'UPDATE_POLICY': 'تعديل سياسة',
  'DELETE_POLICY': 'حذف سياسة',
  'ENABLE_POLICY': 'تشغيل سياسة',
  'DISABLE_POLICY': 'تعطيل سياسة',
  'SEND_BROADCAST': 'إرسال بث للمستخدمين',
  'UPDATE_SETTINGS': 'تعديل إعدادات النظام',

  // المحفظة
  'W_QATRAT_REDEEM_SUCCESS': 'استبدال نقاط قطرات',

  // الدخول
  'ADMIN_LOGIN_SUCCESS': 'دخول ناجح للوحة الإدارة',
  'ADMIN_LOGIN_FAILED': 'محاولة دخول فاشلة للمسؤول',
};

/// أسماءٌ مُسمّاةٌ أعلاه **ولا كاتبَ لها في المستودع**، كلٌّ بسببِه — فمفتاحٌ
/// بلا كاتبٍ وبلا سببٍ هنا يَسقطُ الفحصَ بدلَ أن يَتعفّنَ في الخريطة.
const Set<String> kAuditActionsWithoutWriter = {
  // تَولّاها `exports.activateContractOnPaid` خادميّاً، ولا يَكتبُ الخادمُ
  // سجلَّ تدقيقٍ لها (لا فاعلَ بشريّاً) — والتسميةُ تَبقى لمستنداتٍ قديمة.
  'ACTIVATE_CONTRACT',
  // لم يُوصَلْ قطّ: لا شاشةُ الدخولِ في التطبيقِ ولا `Login.tsx` تَكتبُ قيداً.
  // والفاشلُ **لا يَستطيعُ** كتابتَه أصلاً: قاعدةُ `audit_logs` تَشترطُ
  // `isAdmin()`، ومحاولةُ دخولٍ فاشلةٌ بلا هُويّةِ أدمن.
  'ADMIN_LOGIN_SUCCESS',
  'ADMIN_LOGIN_FAILED',
  // خَلَفَها `UPDATE_ZONE` و`APPLY_PRICES_TO_ZONES`: الأسعارُ تَسكنُ مستندَ
  // المنطقةِ، فتعديلُها تعديلُ منطقةٍ لا «سعرُ خدمةٍ» مستقلّ.
  'UPDATE_SERVICE_PRICE',
};

/// تسميةُ الإجراءِ، أو اسمُه الخامُّ متى لم يُعرَفْ — الفرعُ الجامعُ يَبقى
/// لأنّ مساراً خادميّاً لاحقاً قد يَكتبُ اسماً لا تَعرفُه نسخةُ التطبيقِ
/// المُثبَّتةُ، وعرضُ الاسمِ أصدقُ من إخفاءِ القيد.
String auditActionLabel(String action) => kAuditActionLabels[action] ?? action;
