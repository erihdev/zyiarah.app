import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahOrder {
  final String id;
  final String clientId;
  final String? driverId;
  final String serviceType;
  final double amount;
  final String status;
  final String paymentStatus;
  final GeoPoint location;
  final DateTime createdAt;
  final int? hours;
  final DateTime? serviceDate;
  final int workerCount;
  final String? couponCode;
  final double discountAmount;

  ZyiarahOrder({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.serviceType,
    required this.amount,
    required this.status,
    required this.paymentStatus,
    required this.location,
    required this.createdAt,
    this.hours,
    this.serviceDate,
    this.workerCount = 1,
    this.couponCode,
    this.discountAmount = 0.0,
  });

  factory ZyiarahOrder.fromMap(String id, Map<String, dynamic> data) {
    // تحويل دفاعي: مستند واحد بنوع خاطئ (amount نصّ، worker_count/hours عدد عشري،
    // service_date ليس Timestamp) كان يرمي استثناءً داخل .map() فيُعطّل شاشة القائمة
    // كاملةً — لا صفّاً واحداً فقط.
    double toD(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    int toI(dynamic v, int fallback) =>
        v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
    return ZyiarahOrder(
      id: id,
      clientId: data['client_id'] ?? '',
      driverId: data['driver_id'],
      serviceType: data['service_type'] ?? data['service_name'] ?? '',
      amount: toD(data['amount']),
      status: data['status'] ?? 'pending',
      paymentStatus: data['payment_method'] ?? 'unpaid',
      location: data['location'] is GeoPoint ? data['location'] : const GeoPoint(0, 0),
      createdAt: data['created_at'] is Timestamp ? (data['created_at'] as Timestamp).toDate() : DateTime.now(),
      hours: data['hours_contracted'] == null ? null : toI(data['hours_contracted'], 0),
      serviceDate: data['service_date'] is Timestamp
          ? (data['service_date'] as Timestamp).toDate()
          : null,
      workerCount: toI(data['worker_count'], 1),
      couponCode: data['coupon_code'],
      discountAmount: toD(data['discount_amount']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'client_id': clientId,
      'driver_id': driverId,
      'service_type': serviceType,
      'amount': amount,
      'status': status,
      'payment_method': paymentStatus,
      'location': location,
      'created_at': Timestamp.fromDate(createdAt),
      'hours_contracted': hours,
      'service_date': serviceDate != null ? Timestamp.fromDate(serviceDate!) : null,
      'worker_count': workerCount,
      'coupon_code': couponCode,
      'discount_amount': discountAmount,
    };
  }
}
