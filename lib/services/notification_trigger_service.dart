import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ZyiarahNotificationTriggerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// يرسل بلاغ تذكير لنظام الإشعارات (Clound Functions) لإرسال Payload الـ FCM
  Future<void> triggerNotification({
    required String toUid,
    required String title,
    required String body,
    required String type, // 'order_assignment', 'maintenance_quote', 'support_reply'
    Map<String, dynamic>? data,
  }) async {
    try {
      await _db.collection('notification_triggers').add({
        'toUid': toUid,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'isProcessed': false, // المبرمج سيعتمد على Cloud Function لتغييرها لـ true
      });
    } catch (e) {
      debugPrint("Error triggering notification: $e");
    }
  }

  // Helper methodologies for common triggers
  Future<void> notifyDriverOfAssignment(String driverId, String orderId) async {
    await triggerNotification(
      toUid: driverId,
      title: "مهمة جديدة مسندة إليك 🚀",
      body: "تم تعيينك لتنفيذ الطلب رقم #$orderId. يرجى الاطلاع على التفاصيل وبدء المهمة.",
      type: 'order_assignment',
      data: {
        'orderId': orderId,
        'deepLink': 'zyiarah://app/order/$orderId'
      },
    );
  }

  Future<void> notifyClientOfMaintenanceQuote(String clientId, String requestId, double price) async {
    await triggerNotification(
      toUid: clientId,
      title: "عرض سعر جديد 💰",
      body: "تم تحديد تكلفة طلب الصيانة الخاص بك بمبلغ $price ر.س. يرجى الدفع للمتابعة.",
      type: 'maintenance_quote',
      data: {
        'requestId': requestId, 
        'price': price,
        'deepLink': 'zyiarah://app/maintenance/$requestId'
      },
    );
  }

  Future<void> notifyUserOfSupportReply(String userId, String ticketId) async {
    await triggerNotification(
      toUid: userId,
      title: "رد جديد من الدعم الفني 🎧",
      body: "لديك رد جديد بخصوص التذكرة رقم #$ticketId. اضغط للمتابعة.",
      type: 'support_reply',
      data: {
        'ticketId': ticketId,
        'deepLink': 'zyiarah://app/ticket/$ticketId'
      },
    );
  }
}
