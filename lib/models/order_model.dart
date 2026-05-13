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
    return ZyiarahOrder(
      id: id,
      clientId: data['client_id'] ?? '',
      driverId: data['driver_id'],
      serviceType: data['service_type'] ?? data['service_name'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      status: data['status'] ?? 'pending',
      paymentStatus: data['payment_method'] ?? 'unpaid',
      location: data['location'] as GeoPoint,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      hours: data['hours_contracted'],
      serviceDate: data['service_date'] != null
          ? (data['service_date'] as Timestamp).toDate()
          : null,
      workerCount: data['worker_count'] ?? 1,
      couponCode: data['coupon_code'],
      discountAmount: (data['discount_amount'] ?? 0.0).toDouble(),
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
