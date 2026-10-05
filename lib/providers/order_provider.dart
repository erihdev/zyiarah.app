import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/utils/net_timeout.dart';

class ZyiarahOrderProvider extends ChangeNotifier {
  List<DocumentSnapshot> recentOrders = [];
  bool isLoading = true;
  StreamSubscription? _ordersSub;
  StreamSubscription? _authSub;

  ZyiarahOrderProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _subscribeToOrders(user.uid);
      } else {
        _ordersSub?.cancel();
        recentOrders = [];
        isLoading = false;
        notifyListeners();
      }
    });
  }

  void _subscribeToOrders(String uid) {
    isLoading = true;
    notifyListeners();

    _ordersSub?.cancel();
    _ordersSub = FirebaseFirestore.instance
        .collection('orders')
        .where('client_id', isEqualTo: uid)
        .limit(20)
        .snapshots()
        .firstEventTimeout()
        .listen((snapshot) {
      recentOrders = snapshot.docs.toList()
        ..sort((a, b) {
          final aT = (a.data() as Map?)?['created_at'] as Timestamp?;
          final bT = (b.data() as Map?)?['created_at'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });
      isLoading = false;
      notifyListeners();
    }, onError: (e) {
      isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _ordersSub?.cancel();
    super.dispose();
  }

  List<DocumentSnapshot> get activeOrders {
    return recentOrders.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'pending';
      return status != 'completed' && status != 'cancelled';
    }).toList();
  }

  // `trackingOrders` أُزيل: جالبٌ لا قارئَ له — شاشةُ التتبّعِ تَستعلمُ
  // Firestore مباشرةً بمعرّفِ الطلب — وكان نسخةً سادسةً من تعدادِ الحالات.
}
