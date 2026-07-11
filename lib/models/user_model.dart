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
  final String? houseRules;
  final int subscriptionTotalVisits;

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
    this.houseRules,
    this.subscriptionTotalVisits = 4,
  });

  factory ZyiarahUser.fromMap(String id, Map<String, dynamic> data) {
    // تحويل دفاعي: قيمة بنوع خاطئ (rating نصّ، visits عدد عشري، expiry ليس
    // Timestamp) كانت ترمي استثناءً يُعطّل أي شاشة تقرأ هذا المستخدم.
    double toD(dynamic v, double fallback) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
    int toI(dynamic v, int fallback) =>
        v is num ? v.toInt() : int.tryParse('$v') ?? fallback;
    return ZyiarahUser(
      uid: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? 'client',
      rating: toD(data['rating'], 4.9),
      hasActiveSubscription: data['has_active_subscription'] ?? false,
      visitsRemaining: toI(data['visits_remaining'], 0),
      subscriptionExpiry: data['subscription_expiry'] is Timestamp
          ? (data['subscription_expiry'] as Timestamp).toDate()
          : null,
      subscriptionType: data['subscription_type'],
      houseRules: data['house_rules'],
      subscriptionTotalVisits: toI(data['subscription_total_visits'], 4),
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
      'house_rules': houseRules,
      'subscription_total_visits': subscriptionTotalVisits,
    };
  }
}
