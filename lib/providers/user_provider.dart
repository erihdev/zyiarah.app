import 'dart:async';
import 'package:flutter/material.dart';
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

  ZyiarahUser? get user => _user;
  String? get role => _role;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  ZyiarahUserProvider() {
    _init();
  }

  void _init() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? firebaseUser) async {
      if (firebaseUser == null) {
        _user = null;
        _role = null;
        _isLoading = false;
        _profileSubscription?.cancel();
        notifyListeners();
      } else {
        await refreshUser(firebaseUser.uid);
      }
    });
  }

  /// تحديث بيانات المستخدم بشكل يدوي أو عند التغيير
  Future<void> refreshUser(String uid) async {
    _isLoading = true;
    notifyListeners();

    try {
      // استرجاع الدور مرة واحدة (أو الاستماع له)
      _role = await ZyiarahFirebaseService().getUserRole(uid);

      // الاستماع لتغييرات الملف الشخصي (رصيد الزيارات، إلخ)
      _profileSubscription?.cancel();
      _profileSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((doc) {
        if (doc.exists && doc.data() != null) {
          _user = ZyiarahUser.fromMap(uid, doc.data()!);
        }
        _isLoading = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("Error in UserProvider: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
