import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ZyiarahOrderProvider extends ChangeNotifier {
  List<DocumentSnapshot> recentOrders = [];
  bool isLoading = true;
  StreamSubscription? _ordersSub;

  ZyiarahOrderProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
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
        .orderBy('created_at', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      recentOrders = snapshot.docs;
      isLoading = false;
      notifyListeners();
    }, onError: (e) {
      isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
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
  
  List<DocumentSnapshot> get trackingOrders {
    return recentOrders.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] ?? 'pending';
      return ['accepted', 'in_progress'].contains(status);
    }).toList();
  }
}
