import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahWallet {
  final String userId;
  final double balance;
  final int qatratPoints;
  final DateTime lastUpdated;

  ZyiarahWallet({
    required this.userId,
    required this.balance,
    required this.qatratPoints,
    required this.lastUpdated,
  });

  factory ZyiarahWallet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ZyiarahWallet(
      userId: doc.id,
      // التأمين ضد أخطاء الـ Casting (int vs double) القادمة من Firestore
      balance: (data['balance'] ?? 0.0).toDouble(),
      qatratPoints: (data['qatrat_points'] ?? 0).toInt(),
      lastUpdated: (data['last_updated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'balance': balance,
      'qatrat_points': qatratPoints,
      'last_updated': FieldValue.serverTimestamp(),
    };
  }
}

class WalletTransaction {
  final String id;
  final double amount; // القيمة المالية بالريال (موجب للإيداع، سالب للسحب)
  final int points;   // حركة النقاط (موجب للاكتساب، سالب للاستبدال)
  final String type;   // 'refund', 'qatrat_reward', 'qatrat_redeem', 'payment', 'deposit'
  final String description;
  final DateTime createdAt;
  final String? orderId;

  WalletTransaction({
    required this.id,
    required this.amount,
    required this.points,
    required this.type,
    required this.description,
    required this.createdAt,
    this.orderId,
  });

  factory WalletTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return WalletTransaction(
      id: doc.id,
      amount: (data['amount'] ?? 0.0).toDouble(),
      points: (data['points'] ?? 0).toInt(),
      type: data['type'] ?? 'deposit',
      description: data['description'] ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      orderId: data['order_id'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'points': points,
      'type': type,
      'description': description,
      'created_at': FieldValue.serverTimestamp(),
      if (orderId != null) 'order_id': orderId,
    };
  }
}
