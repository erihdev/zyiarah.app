import 'dart:math' show cos, sqrt, asin;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/services.dart';

/// خدمة إدارة العمليات الجوهرية (قفل الوقت والجيوفنسينج)
/// تم التطوير بواسطة: إرث (erihdev.com)
class ZyiarahCoreService {
  
  // --- 1. نظام قفل الوقت (Time Lock) ---
  
  /// دالة إنشاء تيار زمني للمهمة (Countdown)
  /// تمنع هذه الدالة إنهاء المهمة برمجياً قبل انتهاء العقد
  Stream<Duration> taskTimerStream(int hours) {
    int totalSeconds = hours * 3600;
    return Stream.periodic(const Duration(seconds: 1), (count) {
      return Duration(seconds: totalSeconds - count);
    }).take(totalSeconds + 1);
  }

  // --- 2. نظام الجيوفنسينج (Geofencing) ---

  /// حساب المسافة بالمتر بين السائق والعميل باستخدام معادلة Haversine
  double getDistanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000; // النتيجة بالمتر
  }

  /// التحقق من الوجود الفعلي (نطاق 100 متر)
  bool isDriverOnSite(double dLat, double dLon, double cLat, double cLon) {
    return getDistanceInMeters(dLat, dLon, cLat, cLon) <= 100.0;
  }

  /// حساب المسافة وعرضها بتنسيق مقروء (مثلاً: 2.5 كم)
  String getFormattedDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return "${distanceInMeters.toStringAsFixed(0)} متر";
    } else {
      double distanceInKm = distanceInMeters / 1000;
      return "${distanceInKm.toStringAsFixed(1)} كم";
    }
  }

  // --- 3. التوقيع الرقمي (Digital Signature) ---

  Map<String, dynamic> generateSecureSignature(String orderId, String userId) {
    return {
      "sig_id": "SIG-${DateTime.now().millisecondsSinceEpoch}",
      "signed_at": DateTime.now().toIso8601String(),
      "metadata": "مؤسسة معاذ يحي محمد المالكي - سجل 7030376342",
      "order_ref": orderId,
      "user_ref": userId
    };
  }

  // --- 4. التحليلات (Business Analytics) ---
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logEvent(String name, Map<String, dynamic>? parameters) async {
    await _analytics.logEvent(name: name, parameters: parameters?.cast<String, Object>());
  }

  Future<void> logOrderSuccess(String orderId, double amount, String type) async {
    await _analytics.logEvent(
      name: 'order_success',
      parameters: {
        'order_id': orderId,
        'value': amount,
        'currency': 'SAR',
        'service_type': type
      },
    );
  }

  Future<void> logPaymentComplete(String orderId, String method) async {
    await _analytics.logEvent(
      name: 'payment_complete',
      parameters: {
        'order_id': orderId,
        'method': method,
      },
    );
  }

  Future<void> logSupportOpen(String ticketId, String category) async {
    await _analytics.logEvent(
      name: 'support_ticket_open',
      parameters: {
        'ticket_id': ticketId,
        'category': category,
      },
    );
  }

  // --- 5. نظام التفاعل الحسي (Sensory UI) ---

  /// اهتزاز خفيف للتفاعلات العادية (مثل اختيار خيار)
  static Future<void> triggerHapticSelection() async {
    await HapticFeedback.selectionClick();
  }

  /// اهتزاز قوي للنجاح (مثل إتمام الحجز)
  static Future<void> triggerHapticSuccess() async {
    await HapticFeedback.heavyImpact();
  }

  /// اهتزاز تحذيري (مثل وجود خطأ)
  static Future<void> triggerHapticWarning() async {
    await HapticFeedback.vibrate();
  }

  /// تأثير خفيف للمس الأزرار
  static Future<void> triggerHapticLight() async {
    await HapticFeedback.lightImpact();
  }
}
