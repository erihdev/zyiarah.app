import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/utils/order_util.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/counter_service.dart';

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // إنشاء طلب جديد
  Future<String> createOrder({
    required String clientId,
    required String serviceType,
    required double amount,
    required GeoPoint location,
    String paymentMethod = 'card',
    int? hours,
    DateTime? serviceDate,
    String? zoneName,
    int workerCount = 1,
    String? couponCode,
    double discountAmount = 0.0,
  }) async {
    // جلب اسم العميل لتسهيل العرض في لوحة التحكم
    String clientName = 'عميل زيارة';
    String clientPhone = '000000000';
    try {
      final userDoc = await _db.collection('users').doc(clientId).get();
      if (userDoc.exists) {
        clientName = userDoc.data()?['name'] ?? 'عميل زيارة';
        clientPhone = userDoc.data()?['phone'] ?? '000000000';
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }

    // Generate Smart Sequential Code
    final seq = await ZyiarahCounterService().getNextOrderNumber();
    final orderCode = ZyiarahOrderUtil.formatSmartCode(seq);

    DocumentReference doc = await _db.collection('orders').add({
      'code': orderCode,
      'client_id': clientId,
      'client_name': clientName,
      'client_phone': clientPhone,
      'service_type': serviceType,
      'service_name': serviceType, // Ensuring service_name is present for UI consistency
      'amount': amount,
      'status': 'pending',
      'location': location,
      'payment_method': paymentMethod,
      'created_at': FieldValue.serverTimestamp(),
      'hours_contracted': hours ?? 4,
      'service_date': serviceDate != null ? Timestamp.fromDate(serviceDate) : null,
      'zone_name': zoneName,
      'worker_count': workerCount,
      'coupon_code': couponCode,
      'discount_amount': discountAmount,
    });

    // Log the order creation in audit trail
    ZyiarahAuditService().logAction(
      action: 'CREATE_CLEANING_ORDER',
      details: {
        'code': orderCode,
        'amount': amount,
        'client': clientName,
        'service': serviceType,
      },
      targetId: doc.id,
    );

    // إذا كان هناك كود خصم، نحدث عدد مرات استخدامه
    if (couponCode != null) {
      await _incrementCouponUsage(couponCode);
    }

    return orderCode;
  }

  // التحقق من كود الخصم
  Future<Map<String, dynamic>?> validateCoupon(String code) async {
    try {
      final snapshot = await _db
          .collection('promo_codes')
          .where('code', isEqualTo: code.toUpperCase())
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final data = snapshot.docs.first.data();
      final expiry = data['expiry'] as String;
      final maxUses = data['maxUses'] as int;
      final uses = data['uses'] as int;

      // تحقق من التاريخ
      if (DateTime.parse(expiry).isBefore(DateTime.now())) {
        return null;
      }

      // تحقق من عدد مرات الاستخدام
      if (uses >= maxUses) {
        return null;
      }

      return data;
    } catch (e) {
      debugPrint('Error validating coupon: $e');
      return null;
    }
  }

  // زيادة عداد استخدام الكود
  Future<void> _incrementCouponUsage(String code) async {
    try {
      final snapshot = await _db
          .collection('promo_codes')
          .where('code', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        await snapshot.docs.first.reference.update({
          'uses': FieldValue.increment(1),
        });
      }
    } catch (e) {
      debugPrint('Error incrementing coupon usage: $e');
    }
  }

  // منح كاش باك 5%
  Future<void> _applyCashback(String userId, double orderAmount) async {
    // Cashback disabled for now
    await _db.collection('users').doc(userId).update({
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
    // التحقق من الحالة الحالية لمنع التكرار (مثل خصم الزيارات مرتين)
    final docSnap = await _db.collection('orders').doc(orderId).get();
    final currentStatus = docSnap.data()?['status'] as String?;
    
    if (currentStatus == status) return;

    final batch = _db.batch();
    final orderRef = _db.collection('orders').doc(orderId);

    final Map<String, dynamic> updates = {
      'status': status,
      if (driverId != null) 'driver_id': driverId,
      if (status == 'accepted') 'accepted_at': FieldValue.serverTimestamp(),
      if (status == 'arrived') 'arrived_at': FieldValue.serverTimestamp(),
      if (status == 'in_progress') 'start_time': FieldValue.serverTimestamp(),
      if (status == 'completed') 'end_time': FieldValue.serverTimestamp(),
    };

    batch.update(orderRef, updates);

    // تحديث حالة السائق بالتزامن مع الطلب (Atomic Update) في Batch واحد
    if (driverId != null) {
      final driverRef = _db.collection('drivers').doc(driverId);
      String driverStatus = 'available';
      if (status == 'accepted' || status == 'arrived') driverStatus = 'en_route';
      if (status == 'in_progress') driverStatus = 'in_service';
      
      batch.update(driverRef, {
        'status': driverStatus,
        'current_order_id': status == 'completed' ? null : orderId,
        'is_available': status == 'completed',
      });
    }

    await batch.commit();

    // معالجة المكافآت والاشتراكات عند اكتمال الطلب
    if (status == 'completed' && currentStatus != 'completed') {
      final orderData = docSnap.data() as Map<String, dynamic>;
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
  }

  // قبول الطلب باستخدام Transaction لمنع التعارض المزدوج (Race Condition)
  Future<bool> acceptOrder(String orderId, String driverId) async {
    return await _db.runTransaction((transaction) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final driverRef = _db.collection('drivers').doc(driverId);
      
      final orderSnap = await transaction.get(orderRef);
      
      // 1. التحقق من أن الطلب ما زال متاحاً (قيد الانتظار)
      if (!orderSnap.exists || orderSnap.data()?['status'] != 'pending') {
        return false;
      }

      // 2. التحقق من عدم وجود طلبات نشطة للسائق
      bool hasActive = await hasActiveOrder(driverId);
      if (hasActive) return false;

      // 3. جلب بيانات السائق لمزامنتها داخل الطلب (لضمان عمل زر الاتصال)
      final driverSnap = await transaction.get(driverRef);
      final driverData = driverSnap.data() as Map<String, dynamic>;

      // 4. تنفيذ التحديث بشكل ذري (Atomic)
      transaction.update(orderRef, {
        'status': 'accepted',
        'driver_id': driverId,
        'driver_phone': driverData['phone'] ?? '000000000', // مزامنة الرقم
        'assigned_driver': driverData['name'] ?? 'سائق', // مزامنة الاسم
        'accepted_at': FieldValue.serverTimestamp(),
      });

      transaction.update(driverRef, {
        'status': 'en_route',
        'current_order_id': orderId,
        'is_available': false,
      });

      return true;
    });
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
  // تحديث موقع السائق اللحظي للطلب (للمتابعة من قبل العميل)
  Future<void> updateDriverLocation(String orderId, GeoPoint location) async {
    await _db.collection('orders').doc(orderId).update({
      'driver_location': location,
      'last_location_update': FieldValue.serverTimestamp(),
    });
  }

  // الاستماع لتتبع طلب معين (للمتابعة من قبل العميل)
  Stream<DocumentSnapshot> streamOrderTracking(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots();
  }
}
