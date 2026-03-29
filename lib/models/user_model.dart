import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role;
  final double rating;
  final bool hasActiveSubscription;
  final int visitsRemaining;
  final DateTime? subscriptionExpiry;
  final String? subscriptionType;

  ZyiarahUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.rating = 4.9,
    this.hasActiveSubscription = false,
    this.visitsRemaining = 0,
    this.subscriptionExpiry,
    this.subscriptionType,
  });

  factory ZyiarahUser.fromMap(String id, Map<String, dynamic> data) {
    return ZyiarahUser(
      uid: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'client',
      rating: (data['rating'] ?? 4.9).toDouble(),
      hasActiveSubscription: data['has_active_subscription'] ?? false,
      visitsRemaining: data['visits_remaining'] ?? 0,
      subscriptionExpiry: data['subscription_expiry'] != null 
          ? (data['subscription_expiry'] as Timestamp).toDate() 
          : null,
      subscriptionType: data['subscription_type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'rating': rating,
      'has_active_subscription': hasActiveSubscription,
      'visits_remaining': visitsRemaining,
      'subscription_expiry': subscriptionExpiry != null ? Timestamp.fromDate(subscriptionExpiry!) : null,
      'subscription_type': subscriptionType,
    };
  }
}
