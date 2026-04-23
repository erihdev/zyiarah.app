import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ZyiarahNotificationTriggerService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// يرسل بلاغ تذكير لنظام الإشعارات (Clound Functions) لإرسال Payload الـ FCM و/أو البريد الإلكتروني
  Future<void> triggerNotification({
    required String toUid,
    required String title,
    required String body,
    required String type, // 'order_assignment', 'maintenance_quote', 'support_reply', 'hybrid'
    Map<String, dynamic>? data,
    Map<String, dynamic>? template, // اختيار لتفعيل قوالب Resend
  }) async {
    try {
      await _db.collection('notification_triggers').add({
        'toUid': toUid,
        'title': title,
        'body': body,
        'type': type,
        'data': data ?? {},
        if (template != null) 'template': template,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
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

  Future<void> notifyClientOfMaintenanceQuote(String clientId, String requestId, double price, {String? customerEmail, String? clientName}) async {
    await triggerNotification(
      toUid: clientId,
      title: "عرض سعر جديد 💰",
      body: "تم تحديد تكلفة طلب الصيانة الخاص بك بمبلغ $price ر.س. يرجى الدفع للمتابعة.",
      type: 'hybrid', // إشعار دفع + بريد إلكتروني
      data: {
        'requestId': requestId, 
        'price': price,
        'customerEmail': customerEmail,
        'deepLink': 'zyiarah://app/maintenance/$requestId'
      },
      template: {
        'id': 'maintenance-quote',
        'variables': {
          'clientName': clientName ?? 'عميلنا العزيز',
          'serviceType': 'صيانة',
          'amount': '$price ر.س',
          'paymentUrl': 'https://zyiarah.com/maintenance/pay/$requestId',
        }
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

  Future<void> notifyContractApproved(String userId, String planName, {String? customerEmail, String? clientName}) async {
    await triggerNotification(
      toUid: userId,
      title: "تمت الموافقة على طلبك بنجاح! 📄",
      body: "تم اعتماد عقد باقة ($planName) من قبل الإدارة. يرجى إتمام الدفع لتفعيل الباقة.",
      type: 'hybrid',
      data: {
        'planName': planName,
        'customerEmail': customerEmail,
        'deepLink': 'zyiarah://app/contracts'
      },
      template: {
        'id': 'contract-approved',
        'variables': {
          'clientName': clientName ?? 'عميلنا العزيز',
          'planName': planName,
          'actionUrl': 'https://zyiarah.com/contracts',
        }
      },
    );
  }

  Future<void> notifyContractActivated(String userId, String planName, int visits, {String? customerEmail, String? clientName}) async {
    await triggerNotification(
      toUid: userId,
      title: "تم تفعيل باقتك! ✨",
      body: "أهلاً بك في باقة ($planName). تمت إضافة $visits زيارة لرصيدك بنجاح.",
      type: 'hybrid',
      data: {
        'planName': planName,
        'visits': visits,
        'customerEmail': customerEmail,
        'deepLink': 'zyiarah://app/home'
      },
      template: {
        'id': 'contract-activated',
        'variables': {
          'clientName': clientName ?? 'عميلنا العزيز',
          'planName': planName,
          'visits': visits.toString(),
        }
      },
    );
  }

  /// يرسل تنبيه مزدوج (للعميل وللإدارة) عند إنشاء طلب جديد
  Future<void> notifyOrderCreated({
    required String clientId,
    required String orderCode,
    required String type, // 'cleaning', 'store', 'maintenance'
    required String serviceName,
  }) async {
    // 1. تنبيه العميل
    await triggerNotification(
      toUid: clientId,
      title: "تم استلام طلبك بنجاح! 🎉",
      body: "طلبك رقم #$orderCode ($serviceName) قيد التنفيذ الآن. شكراً لاختيارك زيارة.",
      type: 'order_update',
      data: {'code': orderCode, 'type': type},
    );

    // 2. تنبيه الإدارة (سيتم معالجتها في الـ Cloud Function لإرسالها لجميع المشرفين)
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST', // معرف خاص تلتقطه الـ Cloud Function
      title: "طلب جديد وارد 🔔",
      body: "وصل طلب $serviceName جديد برقم #$orderCode. اضغط للمراجعة.",
      type: 'admin_order_alert',
      data: {'code': orderCode, 'type': type},
    );
  }

  /// يجدول إشعار ليتم إرساله في وقت لاحق
  Future<void> scheduleBroadcast({
    required String title,
    required String body,
    required String target,
    required DateTime scheduledAt,
    String? createdBy,
  }) async {
    try {
      await _db.collection('scheduled_notifications').add({
        'title': title,
        'body': body,
        'target': target,
        'scheduled_at': Timestamp.fromDate(scheduledAt),
        'created_at': FieldValue.serverTimestamp(),
        'created_by': createdBy ?? 'Admin',
        'processed': false,
        'status': 'pending',
      });
    } catch (e) {
      debugPrint("Error scheduling broadcast: $e");
    }
  }
}
