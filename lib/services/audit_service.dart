import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      // We don't want to crash the main app if logging fails, 
      // but in a production environment, you might want to log this error to a crash reporter.
      // print('Audit Log Error: $e');
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
}
