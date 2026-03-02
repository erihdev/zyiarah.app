import 'package:cloud_firestore/cloud_firestore.dart';

/// خدمة إدارة دورة حياة الطلب - تطبيق زيارة
class ZyiarahOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // إنشاء طلب جديد بعد نجاح دفع تمارا
  Future<String> createOrder({
    required String clientId,
    required String serviceType,
    required double amount,
    required GeoPoint location,
  }) async {
    DocumentReference doc = await _db.collection('orders').add({
      'client_id': clientId,
      'service_type': serviceType,
      'amount': amount,
      'status': 'pending',
      'location': location,
      'created_at': FieldValue.serverTimestamp(),
      'hours_contracted': 4, // افتراضي
    });
    return doc.id;
  }

  // تحديث حالة الطلب (للسائق)
  Future<void> updateOrderStatus(String orderId, String status) async {
    await _db.collection('orders').doc(orderId).update({
      'status': status,
      if (status == 'in_progress') 'start_time': FieldValue.serverTimestamp(),
      if (status == 'completed') 'end_time': FieldValue.serverTimestamp(),
    });
  }

  // الاستماع للطلبات النشطة للسائق
  Stream<QuerySnapshot> streamAvailableOrders() {
    return _db.collection('orders')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // الاستماع لتحديثات طلب معين (للتتبع على الخريطة)
  Stream<DocumentSnapshot> streamOrderTracking(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots();
  }
}
