import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/main.dart'; // To access messengerKey

class MaintenanceListenerService {
  static final MaintenanceListenerService _instance = MaintenanceListenerService._internal();
  factory MaintenanceListenerService() => _instance;
  MaintenanceListenerService._internal();

  StreamSubscription<QuerySnapshot>? _subscription;
  final Map<String, String> _lastStatusMap = {};
  bool _isFirstLoad = true;

  void startListening() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _subscription?.cancel();
    _lastStatusMap.clear();
    _isFirstLoad = true;

    _subscription = FirebaseFirestore.instance
        .collection('maintenance_requests')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) {
      if (_isFirstLoad) {
        // Initial load: just populate the map without notifying
        for (var doc in snapshot.docs) {
          final data = doc.data();
          _lastStatusMap[doc.id] = data['status'] ?? 'under_review';
        }
        _isFirstLoad = false;
        return;
      }

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data() as Map<String, dynamic>;
          final String docId = change.doc.id;
          final String newStatus = data['status'] ?? 'under_review';
          final String oldStatus = _lastStatusMap[docId] ?? '';

          if (newStatus != oldStatus) {
            _lastStatusMap[docId] = newStatus;
            _notifyUser(data, newStatus);
          }
        } else if (change.type == DocumentChangeType.added) {
           final data = change.doc.data() as Map<String, dynamic>;
           _lastStatusMap[change.doc.id] = data['status'] ?? 'under_review';
        }
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _lastStatusMap.clear();
    _isFirstLoad = true;
  }

  void _notifyUser(Map<String, dynamic> data, String status) {
    String message = "تحديث جديد لطلب الصيانة الخاص بك";
    Color bgColor = Colors.blue;
    IconData icon = Icons.notifications_active;

    if (status == 'waiting_payment') {
      message = "تم قبول طلبك بـ (${data['serviceType'] ?? 'صيانة'}). يرجى الدفع للمتابعة.";
      bgColor = Colors.orange;
      icon = Icons.payment;
    } else if (status == 'approved' || status == 'paid') {
      message = "تم استلام الدفعة! جاري البدء في أعمال الصيانة لـ (${data['serviceType'] ?? 'طلبك'}).";
      bgColor = Colors.green;
      icon = Icons.build;
    } else if (status == 'completed') {
      message = "تهانينا! تم إنجاز طلب الصيانة الخاص بك بنجاح.";
      bgColor = Colors.indigo;
      icon = Icons.verified;
    } else if (status == 'rejected') {
      message = "تم رفض طلب الصيانة: (${data['serviceType'] ?? 'طلبك'}). نعتذر عن ذلك.";
      bgColor = Colors.red;
      icon = Icons.cancel;
    }

    _showGlobalSnackBar(message, bgColor, icon);
  }

  void _showGlobalSnackBar(String message, Color color, IconData icon) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 5),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("تنبيه زيارة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
                    Text(message, style: GoogleFonts.tajawal(color: Colors.black87, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
              IconButton(onPressed: () => messengerKey.currentState?.hideCurrentSnackBar(), icon: const Icon(Icons.close, size: 18, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
