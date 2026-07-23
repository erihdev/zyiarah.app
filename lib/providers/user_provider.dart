import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/services/firebase_service.dart';

/// المزود المركزي لحالة المستخدم وصلاحياته
/// يعالج مشكلة الـ Redundant Reads ويعزز استقرار حالة التطبيق
class ZyiarahUserProvider extends ChangeNotifier {
  ZyiarahUser? _user;
  String? _role;
  bool _isLoading = true;
  StreamSubscription? _authSubscription;
  StreamSubscription? _profileSubscription;

  /// حالة المصادقة الحقيقية من Firebase — المرجع الوحيد لكون المستخدم مسجّلاً.
  User? _authUser;

  /// آخر خطأ في تحميل الملف الشخصي — تعرضه الواجهة بدل إسقاط الجلسة صامتاً.
  Object? _profileError;

  ZyiarahUser? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;
  Object? get profileError => _profileError;

  /// **تتبع Firebase Auth وحده — لا مستند Firestore.**
  ///
  /// كانت: `_user != null` أي أن الجلسة مرهونة بنجاح قراءة مستند users من Firestore.
  /// فأي تعثّر شبكي لحظي (وإكمال طلب = نشاط شبكي مكثّف) كان يترك ‎_user فارغاً فيعرض
  /// AuthWrapper شاشة الترحيب — أي «يُخرج» مستخدماً لم تنتهِ جلسته أصلاً. الآن: فشل
  /// تحميل البيانات لا يمسّ الجلسة إطلاقاً؛ يُعاد المحاولة وتبقى الجلسة قائمة.
  bool get isAuthenticated => _authUser != null;

  ZyiarahUserProvider() {
    _init();
  }

  void _init() {
    // الحالة الابتدائية قد تكون جاهزة قبل وصول أول حدث من البثّ (جلسة محفوظة).
    _authUser = FirebaseAuth.instance.currentUser;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? firebaseUser) async {
      _authUser = firebaseUser;
      if (firebaseUser == null) {
        // خروج حقيقي فقط (Firebase قال ذلك) — هنا وحده تُمسح البيانات.
        _user = null;
        _role = null;
        _profileError = null;
        _isLoading = false;
        _profileSubscription?.cancel();
        _profileSubscription = null;
        notifyListeners();
      } else {
        await refreshUser(firebaseUser.uid);
      }
    });
  }

  /// تحديث بيانات المستخدم بشكل يدوي أو عند التغيير.
  ///
  /// **قاعدة صارمة: لا يُخرج المستخدم أبداً عند فشل تحميل البيانات.** الجلسة تخصّ
  /// Firebase Auth؛ ما يفشل هنا هو *بيانات* فقط — تُعاد المحاولة والجلسة باقية.
  Future<void> refreshUser(String uid) async {
    _isLoading = true;
    _profileError = null;
    notifyListeners();

    try {
      // استرجاع الدور مرة واحدة (أو الاستماع له)
      _role = await ZyiarahFirebaseService().getUserRole(uid);
    } catch (e, s) {
      // كان هذا الفشل يقفز فوق تركيب المستمع أدناه — فيبقى التطبيق بلا ملف شخصي
      // ولا تعافي حتى إعادة التشغيل، ويظهر المستخدم كأنه «غير مسجّل». الآن: نُسجّل
      // الخطأ (لا debugPrint صامت) ونواصل لتركيب المستمع الذي يجلب الدور أيضاً.
      _profileError = e;
      _reportSilent('getUserRole failed for $uid', e, s);
    }

    // يُركَّب دائماً — حتى لو فشل جلب الدور أعلاه — فهو مصدر التعافي.
    _profileSubscription?.cancel();
    _profileSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      try {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          // فرض الحظر: مستخدم محظور يُسجَّل خروجه فوراً (كان الحظر شكلياً لا يُفحص).
          // يغطي كلا العلمين: is_blocked (القاعدة) و status:'banned' (لوحة React).
          if (data['is_blocked'] == true || data['status'] == 'banned') {
            debugPrint('User $uid is blocked — signing out');
            // خروج مركزي: يحذف رمز FCM ويلغي اشتراكات topics قبل إنهاء الجلسة — كان
            // signOut المباشر يترك الجهاز مشتركاً فيستقبل إشعارات/بثوث الدور بعد الحظر.
            ZyiarahFirebaseService().signOut();
            return;
          }
          _user = ZyiarahUser.fromMap(uid, data);
          _role = _user!.role;
          _profileError = null;
        }
      } catch (e, s) {
        // تلف حقل في المستند (نوع غير متوقّع) كان يرمي داخل المستمع فيتحوّل إلى خطأ
        // غير ملتقَط — «كراش صامت». الآن يُلتقط ويُبلَّغ ولا يُسقط الجلسة.
        _profileError = e;
        _reportSilent('user profile parse failed for $uid', e, s);
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (e, s) {
      // خطأ بثّ (شبكة/صلاحيات) — الجلسة تبقى، والبيانات تُعاد محاولتها.
      _profileError = e;
      _reportSilent('user profile stream error for $uid', e, s);
      _isLoading = false;
      notifyListeners();
    });
  }

  /// يمنع «الكراش الصامت»: كل فشل هنا يصل Crashlytics بدل أن يُبتلع في debugPrint.
  void _reportSilent(String reason, Object e, StackTrace s) {
    debugPrint('[UserProvider] $reason: $e');
    if (!kIsWeb) {
      FirebaseCrashlytics.instance
          .recordError(e, s, reason: reason, fatal: false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
