import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class ZyiarahAuditService {
  static final ZyiarahAuditService _instance = ZyiarahAuditService._internal();
  factory ZyiarahAuditService() => _instance;
  ZyiarahAuditService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Logs an administrative action to Firestore.
  /// [action] - The type of action (e.g., 'CREATE_COUPON', 'DELETE_DRIVER')
  /// [details] - A map of descriptive data related to the action
  /// [targetId] - The ID of the document being modified (if any)
  Future<void> logAction({
    required String action,
    required Map<String, dynamic> details,
    String? targetId,
  }) async {
    try {
      final user = _auth.currentUser;
      final email = user?.email ?? 'Unknown Admin';
      
      await _db.collection('audit_logs').add({
        'admin_email': email,
        'action': action,
        'details': details,
        'target_id': targetId,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': 'Admin Dashboard (Mobile/Native)',
      });
    } catch (e) {
      // التدقيق أفضل-جهد: لا يُسقط التدفّق الرئيسي أبداً.
      // قواعد Firestore تقصر إنشاء audit_logs على الأدمن، والاستدعاءات من تدفّقات
      // العميل (توقيع العقد/تفعيل تمارا/استبدال قطرات...) تُرفَض بشكل متوقَّع —
      // نتخطّاها بصمت كي لا تُلوّث السجلات بأخطاء وهمية، ونُبقي وسماً مميّزاً
      // لغير الرفض حتى لا يضيع خلل حقيقي (شبكة/تهيئة).
      if (e is FirebaseException && e.code == 'permission-denied') {
        debugPrint('AUDIT_SKIPPED_NON_ADMIN: $action');
      } else {
        debugPrint('AUDIT_LOG_ERROR: $action — $e');
      }
    }
  }

  // Pre-defined action types for consistency
  static const String actionCreateStaff = 'CREATE_STAFF';
  static const String actionUpdateStaff = 'UPDATE_STAFF';
  static const String actionDeleteStaff = 'DELETE_STAFF';
  
  static const String actionCreateCoupon = 'CREATE_COUPON';
  static const String actionUpdateCoupon = 'UPDATE_COUPON';
  static const String actionDeleteCoupon = 'DELETE_COUPON';
  
  static const String actionUpdateServicePrice = 'UPDATE_SERVICE_PRICE';
  static const String actionToggleService = 'TOGGLE_SERVICE_STATUS';
  
  static const String actionRegisterDriver = 'REGISTER_DRIVER';
  static const String actionUpdateDriver = 'UPDATE_DRIVER';
  static const String actionDeleteDriver = 'DELETE_DRIVER';
  static const String actionToggleDriver = 'TOGGLE_DRIVER_STATUS';

  static const String actionCreateZone = 'CREATE_ZONE';
  static const String actionUpdateZone = 'UPDATE_ZONE';
  static const String actionDeleteZone = 'DELETE_ZONE';

  static const String actionAdminLogin = 'ADMIN_LOGIN_SUCCESS';
  static const String actionAdminLoginFailed = 'ADMIN_LOGIN_FAILED';

  static const String actionUpdateOrderStatus = 'UPDATE_ORDER_STATUS';
  static const String actionAssignDriver = 'ASSIGN_DRIVER';

  /// اعتمادُ مبلغٍ وسَمَه تحقّقُ السعرِ الخادميّ — قرارٌ ماليٌّ بشريٌّ
  /// يُبطِلُ علمَ المكنسةِ، فلا بدَّ من أثرٍ باسمِ من اتّخذَه.
  static const String actionReviewOrderPrice = 'REVIEW_ORDER_PRICE';

  /// اعتمادُ عقدٍ وحذفُه — أكبرُ مبلغٍ في التطبيق. كانت تسميةُ الاعتمادِ
  /// موجودةً في شاشةِ السجلِّ ولا كاتبَ لها، وحذفُ العقدِ محصورٌ بالمدير
  /// العامِّ في القواعدِ (عمليّةٌ مدمّرة) وكان بلا أثرٍ إطلاقاً.
  static const String actionApproveContract = 'APPROVE_CONTRACT';
  static const String actionDeleteContract = 'DELETE_CONTRACT';

  /// تنفيذُ طلبِ حذفِ حساب — يَحذفُ حسابَ المصادقةِ ومستنداتِه خادميّاً،
  /// ويَترُكُ رصيدَ المحفظةِ دَيناً مكتوباً. لا رجعةَ فيه.
  static const String actionProcessAccountDeletion = 'PROCESS_ACCOUNT_DELETION';

  /// تعديلُ إعداداتِ النظام — وضعُ الصيانةِ (يُقفِلُ التطبيقَ على كلِّ
  /// عميلة)، وبوّابةُ الإصدارِ، والسعةُ اليوميّة، وسياسةُ الخصوصيّةِ
  /// المنشورةُ. نظيرُه `AUDIT.UPDATE_SETTINGS` في اللوحة.
  static const String actionUpdateSettings = 'UPDATE_SETTINGS';
}
