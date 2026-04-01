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
      clientId: data['clientId'] ?? '',
      driverId: data['driverId'],
      serviceType: data['serviceType'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      status: data['status'] ?? 'pending',
      paymentStatus: data['paymentStatus'] ?? 'unpaid',
      location: data['location'] as GeoPoint,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      hours: data['hours'],
      serviceDate: data['serviceDate'] != null 
          ? (data['serviceDate'] as Timestamp).toDate() 
          : null,
      workerCount: data['worker_count'] ?? 1,
      couponCode: data['coupon_code'],
      discountAmount: (data['discount_amount'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'driverId': driverId,
      'serviceType': serviceType,
      'amount': amount,
      'status': status,
      'paymentStatus': paymentStatus,
      'location': location,
      'createdAt': Timestamp.fromDate(createdAt),
      'hours': hours,
      'serviceDate': serviceDate != null ? Timestamp.fromDate(serviceDate!) : null,
      'worker_count': workerCount,
      'coupon_code': couponCode,
      'discount_amount': discountAmount,
    };
  }
}
