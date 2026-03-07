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
    };
  }
}
