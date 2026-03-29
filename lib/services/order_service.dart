import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // إنشاء طلب جديد بعد نجاح دفع تمارا
  Future<String> createOrder({
    required String clientId,
    required String serviceType,
    required double amount,
    required GeoPoint location,
    String paymentMethod = 'card',
    int? hours,
    DateTime? serviceDate,
  }) async {
    // جلب اسم العميل لتسهيل العرض في لوحة التحكم
    String clientName = 'عميل زيارة';
    try {
      final userDoc = await _db.collection('users').doc(clientId).get();
      if (userDoc.exists) {
        clientName = userDoc.data()?['name'] ?? 'عميل زيارة';
      }
    } catch (e) {
      debugPrint('Error fetching user name: $e');
    }

    DocumentReference doc = await _db.collection('orders').add({
      'client_id': clientId,
      'client_name': clientName,
      'service_type': serviceType,
      'amount': amount,
      'status': 'pending',
      'location': location,
      'payment_method': paymentMethod,
      'created_at': FieldValue.serverTimestamp(),
      'hours_contracted': hours ?? 4,
      'service_date': serviceDate != null ? Timestamp.fromDate(serviceDate) : null,
    });
    return doc.id;
  }

  // منح كاش باك 5%
  Future<void> _applyCashback(String userId, double orderAmount) async {
    final cashback = orderAmount * 0.05;
    await _db.collection('users').doc(userId).update({
      // 'wallet_balance': FieldValue.increment(cashback), (Wallet Removed)
    });
  }

  // خصم زيارة من الاشتراك
  Future<void> _deductSubscriptionVisit(String userId) async {
    await _db.collection('users').doc(userId).update({
      'visits_remaining': FieldValue.increment(-1),
    });
  }

  // تحديث حالة الطلب مع إضافة بيانات السائق والمنطق الزمني
  Future<void> updateOrderStatus(String orderId, String status, {String? driverId}) async {
    final Map<String, dynamic> updates = {
      'status': status,
      if (driverId != null) 'driver_id': driverId,
      if (status == 'accepted') 'accepted_at': FieldValue.serverTimestamp(),
      if (status == 'arrived') 'arrived_at': FieldValue.serverTimestamp(),
      if (status == 'in_progress') 'start_time': FieldValue.serverTimestamp(),
      if (status == 'completed') 'end_time': FieldValue.serverTimestamp(),
    };

    await _db.collection('orders').doc(orderId).update(updates);

    // معالجة المكافآت والاشتراكات عند اكتمال الطلب
    if (status == 'completed') {
      final orderDoc = await _db.collection('orders').doc(orderId).get();
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final clientId = orderData['client_id'];
      final amount = (orderData['amount'] ?? 0.0).toDouble();
      final isSubscriptionOrder = orderData['payment_method'] == 'subscription';

      if (clientId != null) {
        if (isSubscriptionOrder) {
          // خصم زيارة من الاشتراك
          await _deductSubscriptionVisit(clientId);
        } else {
          // منح كاش باك 5% للطلبات المدفوعة
          await _applyCashback(clientId, amount);
        }
      }
    }

    // تحديث حالة السائق أيضاً للمتابعة اللحظية في لوحة التحكم
    if (driverId != null) {
      String driverStatus = 'idle';
      if (status == 'accepted' || status == 'arrived') driverStatus = 'en_route';
      if (status == 'in_progress') driverStatus = 'in_service';
      if (status == 'completed') driverStatus = 'idle';

      await _db.collection('drivers').doc(driverId).update({
        'status': driverStatus,
        'current_order_id': status == 'completed' ? null : orderId,
        'is_available': status == 'completed',
      });
    }
  }

  // قبول الطلب بشكل مباشر مع منع التعارض (منع قبول أكثر من طلب نشط)
  Future<bool> acceptOrder(String orderId, String driverId) async {
    // 1. التحقق من عدم وجود طلبات نشطة للسائق
    bool hasActive = await hasActiveOrder(driverId);
    if (hasActive) return false;

    // 2. تحديث الطلب وتخصيصه للسائق
    await updateOrderStatus(orderId, 'accepted', driverId: driverId);
    return true;
  }

  // التحقق مما إذا كان السائق لديه طلب نشط حالياً
  Future<bool> hasActiveOrder(String driverId) async {
    final activeSnap = await _db
        .collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['accepted', 'arrived', 'in_progress'])
        .limit(1)
        .get();
    return activeSnap.docs.isNotEmpty;
  }

  // الاستماع للطلبات المتاحة (التي لم يقبلها أحد بعد)
  Stream<QuerySnapshot> streamAvailableOrders() {
    return _db.collection('orders')
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  // الاستماع للطلبات الخاصة بسائق معين (نشطة)
  Stream<QuerySnapshot> streamDriverActiveOrders(String driverId) {
    return _db.collection('orders')
        .where('driver_id', isEqualTo: driverId)
        .where('status', whereIn: ['accepted', 'arrived', 'in_progress'])
        .snapshots();
  }

  // الاستماع لتحديثات طلب معين
  Stream<DocumentSnapshot> streamOrderTracking(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots();
  }
}
