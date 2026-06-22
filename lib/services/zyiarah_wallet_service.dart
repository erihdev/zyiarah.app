import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:zyiarah/models/wallet_model.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/zyiarah_messaging_service.dart';

class ZyiarahWalletService {
  // Singleton Pattern
  static final ZyiarahWalletService _instance = ZyiarahWalletService._internal();
  factory ZyiarahWalletService() => _instance;
  ZyiarahWalletService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahAuditService _audit = ZyiarahAuditService();
  final ZyiarahMessagingService _messaging = ZyiarahMessagingService();

  /// جلب محفظة المستخدم أو إنشائها تلقائياً إذا لم تكن موجودة (Safe Guard)
  Future<ZyiarahWallet> getOrCreateWallet(String userId) async {
    final walletRef = _db.collection('wallets').doc(userId);
    final doc = await walletRef.get();

    if (doc.exists) {
      return ZyiarahWallet.fromFirestore(doc);
    } else {
      // إنشاء محفظة افتتاحية صفرية جديدة للعميل الجديد
      final newWallet = {
        'balance': 0.0,
        'qatrat_points': 0,
        'last_updated': FieldValue.serverTimestamp(),
      };
      await walletRef.set(newWallet);
      return ZyiarahWallet(
        userId: userId,
        balance: 0.0,
        qatratPoints: 0,
        lastUpdated: DateTime.now(),
      );
    }
  }

  /// معالجة المرتجعات محلياً محصورة داخل المحفظة (In-App Secure Refund)
  Future<void> processRefund({
    required String userId,
    required double amount,
    required String orderId,
    required String orderCode,
  }) async {
    if (amount <= 0) return;

    final walletRef = _db.collection('wallets').doc(userId);
    final txRef = walletRef.collection('transactions').doc();

    await _db.runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      
      double currentBalance = 0.0;
      int currentPoints = 0;
      
      if (walletSnap.exists) {
        currentBalance = (walletSnap.data()?['balance'] ?? 0.0).toDouble();
        currentPoints = (walletSnap.data()?['qatrat_points'] ?? 0).toInt();
      }

      final newBalance = currentBalance + amount;

      // تحديث محفظة العميل ذرياً
      transaction.set(walletRef, {
        'balance': newBalance,
        'qatrat_points': currentPoints,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // تسجيل وثيقة المعاملة المالية في طابور المحفظة
      transaction.set(txRef, {
        'amount': amount,
        'points': 0,
        'type': 'refund',
        'description': 'إعادة رصيد للطلب الملغي رقم #$orderCode',
        'order_id': orderId,
        'created_at': FieldValue.serverTimestamp(),
      });
    });

    // سياق أتمتة الإجراءات الجانبية (Side Effects خارج الـ Transaction لسرعة الاستجابة)
    await _audit.logAction(
      action: 'WALLET_REFUND_CREDIT',
      targetId: userId,
      details: {'order_code': orderCode, 'refund_amount': amount},
    );

    // تنبيه العميل لحظياً عبر خدمة الرسائل الموحدة بنجاح شحن المحفظة
    await _messaging.triggerNotification(
      toUid: userId,
      title: "تم إعادة رصيد لمحفظتك 💰",
      body: "تم إيداع مبلغ $amount ر.س في محفظتك بنجاح للطلب رقم #$orderCode.",
      type: 'wallet_credit',
      data: {'orderId': orderId},
    );
  }

  /// منح مكافآت نقاط قطرات عند اكتمال الطلب (1 ريال = 1 نقطة قطرات)
  Future<void> grantQatratReward({
    required String userId,
    required String orderId,
    required String orderCode,
    required double orderValue,
  }) async {
    if (orderValue <= 0) return;
    
    // احتساب النقاط بناءً على الريالات (1 ريال يمنح 1 نقطة كاملة)
    final int pointsEarned = orderValue.round();

    final walletRef = _db.collection('wallets').doc(userId);
    final txRef = walletRef.collection('transactions').doc();

    await _db.runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      
      double currentBalance = 0.0;
      int currentPoints = 0;
      
      if (walletSnap.exists) {
        currentBalance = (walletSnap.data()?['balance'] ?? 0.0).toDouble();
        currentPoints = (walletSnap.data()?['qatrat_points'] ?? 0).toInt();
      }

      transaction.set(walletRef, {
        'balance': currentBalance,
        'qatrat_points': currentPoints + pointsEarned,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(txRef, {
        'amount': 0.0,
        'points': pointsEarned,
        'type': 'qatrat_reward',
        'description': 'نقاط زيارة مكتسبة من الطلب المكتمل #$orderCode',
        'order_id': orderId,
        'created_at': FieldValue.serverTimestamp(),
      });
    });

    await _messaging.triggerNotification(
      toUid: userId,
      title: "حصلت على نقاط زيارة جديدة! ✨🎈",
      body: "تهانينا! أضيفت $pointsEarned نقطة زيارة لرصيدك مكافأة على الطلب #$orderCode.",
      type: 'qatrat_credit',
      data: {'orderId': orderId},
    );
  }

  /// استبدال نقاط قطرات وتحويلها لرصيد مالي حقيقي (كل 50 نقطة = 1 ريال).
  /// تحوّل المنطق إلى Cloud Function (redeemQatratPoints) ليكون التحقق والتحويل
  /// خادميَّيْن — لا يمكن للعميل تزوير النقاط/الرصيد عبر هذا المسار. الخادم يستخدم
  /// هوية المصادقة (auth.uid) ويتجاهل [userId] الممرَّر، فلا يمكن الاستبدال لحساب آخر.
  Future<bool> redeemQatratPoints({required String userId, required int pointsToRedeem}) async {
    if (pointsToRedeem < 50) return false; // الحد الأدنى للاستبدال 50 نقطة
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('redeemQatratPoints');
      final res = await callable.call<Map<String, dynamic>>(
        {'pointsToRedeem': pointsToRedeem},
      );
      final bool success = res.data['success'] == true;
      if (success) {
        await _audit.logAction(
          action: 'W_QATRAT_REDEEM_SUCCESS',
          targetId: userId,
          details: {'points_redeemed': pointsToRedeem},
        );
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  /// بث تيار لحظي لسجل المعاملات والتحصيلات الخاصة بمحفظة المستخدم (Real-time Stream)
  Stream<List<WalletTransaction>> streamTransactions(String userId) {
    return _db
        .collection('wallets')
        .doc(userId)
        .collection('transactions')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WalletTransaction.fromFirestore(doc))
            .toList());
  }
}
