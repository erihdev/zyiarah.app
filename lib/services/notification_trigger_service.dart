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
  Future<void> notifyDriverOfAssignment(
    String driverId,
    String orderId, {
    String? driverEmail,
    String? driverName,
    String? serviceType,
    String? serviceDate,
  }) async {
    final emailHtml = '''
<div dir="rtl" style="font-family:Tajawal,Arial,sans-serif;max-width:600px;margin:auto;background:#fff;border-radius:16px;overflow:hidden;border:1px solid #e2e8f0">
  <div style="background:linear-gradient(135deg,#5D1B5E,#7E3080);padding:32px;text-align:center">
    <h1 style="color:#fff;margin:0;font-size:24px">مهمة جديدة مسندة إليك 🚀</h1>
    <p style="color:#e9d5ea;margin:8px 0 0">تطبيق زيارة للخدمات المنزلية</p>
  </div>
  <div style="padding:32px">
    <p style="font-size:16px;color:#334155">مرحباً ${driverName ?? 'السائق الكريم'}،</p>
    <p style="font-size:15px;color:#475569;line-height:1.7">تم تعيينك لتنفيذ طلب خدمة جديد. يرجى فتح التطبيق والاطلاع على التفاصيل والتوجه فوراً.</p>
    <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:20px;margin:20px 0">
      <table style="width:100%;border-collapse:collapse">
        <tr><td style="padding:8px 0;color:#64748b;font-size:14px">رقم الطلب</td><td style="padding:8px 0;font-weight:bold;color:#1e293b;text-align:left">#$orderId</td></tr>
        ${serviceType != null ? '<tr><td style="padding:8px 0;color:#64748b;font-size:14px">نوع الخدمة</td><td style="padding:8px 0;font-weight:bold;color:#1e293b;text-align:left">$serviceType</td></tr>' : ''}
        ${serviceDate != null ? '<tr><td style="padding:8px 0;color:#64748b;font-size:14px">التاريخ والوقت</td><td style="padding:8px 0;font-weight:bold;color:#1e293b;text-align:left">$serviceDate</td></tr>' : ''}
      </table>
    </div>
    <div style="text-align:center;margin-top:24px">
      <a href="zyiarah://app/order/$orderId" style="background:#5D1B5E;color:#fff;padding:14px 32px;border-radius:10px;text-decoration:none;font-weight:bold;font-size:15px;display:inline-block">افتح التطبيق الآن</a>
    </div>
  </div>
  <div style="background:#f8fafc;padding:16px;text-align:center;color:#94a3b8;font-size:12px">
    زيارة للخدمات المنزلية — لا ترد على هذا الإيميل
  </div>
</div>''';

    await triggerNotification(
      toUid: driverId,
      title: "مهمة جديدة مسندة إليك 🚀",
      body: "تم تعيينك لتنفيذ الطلب رقم #$orderId. يرجى الاطلاع على التفاصيل وبدء المهمة فوراً.",
      type: 'hybrid',
      data: {
        'orderId': orderId,
        'deepLink': 'zyiarah://app/order/$orderId',
        if (driverEmail != null) 'customerEmail': driverEmail,
        'type': 'new_order_driver',
      },
      template: driverEmail != null ? null : null,
    );

    // إذا وجد إيميل — أرسل trigger منفصل للإيميل بـ HTML كامل
    if (driverEmail != null) {
      await _db.collection('notification_triggers').add({
        'toUid': driverId,
        'title': 'مهمة جديدة مسندة إليك 🚀 — طلب #$orderId',
        'body': emailHtml,
        'type': 'email',
        'recipientEmail': driverEmail,
        'data': {'orderId': orderId},
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    }
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

  /// تنبيه الإدارة عند استلام دفعة مالية
  Future<void> notifyAdminOfPayment({
    required String orderCode,
    required double amount,
    required String type, // 'maintenance', 'contract', 'store'
    String? clientName,
  }) async {
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "تم استلام دفعة مالية 💸",
      body: "قام العميل ${clientName ?? 'عميل'} بدفع $amount ر.س للطلب #$orderCode ($type).",
      type: 'admin_payment_alert',
      data: {'code': orderCode, 'amount': amount, 'type': type},
    );
  }

  /// تنبيه العميل بحركات السائق
  Future<void> notifyClientOfDriverStatus({
    required String clientId,
    required String status, // 'accepted', 'in_progress', 'completed'
    required String orderCode,
    String? driverName,
  }) async {
    String title = "";
    String body = "";

    switch (status) {
      case 'accepted':
        title = "تم قبول طلبك! 🚚";
        body = "السائق ${driverName ?? ''} في الطريق إليك الآن لتنفيذ الطلب #$orderCode.";
        break;
      case 'in_progress':
        title = "وصل السائق وبدأ العمل! 🏠🛠️";
        body = "السائق ${driverName ?? ''} وصل وبدأ تنفيذ خدمتك للطلب #$orderCode.";
        break;
      case 'completed':
        title = "تم الإنجاز! ✨";
        body = "انتهى العمل على الطلب #$orderCode بنجاح. شكراً لثقتك بنا، ننتظر تقييمك.";
        break;
    }

    if (title.isNotEmpty) {
      await triggerNotification(
        toUid: clientId,
        title: title,
        body: body,
        type: 'driver_update',
        data: {'code': orderCode, 'status': status},
      );
    }
  }

  /// تنبيه الإدارة بحركات السائق الميدانية
  Future<void> notifyAdminOfDriverUpdate({
    required String driverName,
    required String status, // 'accepted', 'started', 'completed'
    required String orderCode,
  }) async {
    String action = "";
    switch (status) {
      case 'accepted': action = "قبل المهمة 🚚"; break;
      case 'started': action = "بدأ العمل 🛠️"; break;
      case 'completed': action = "أتم المهمة ✨"; break;
    }

    if (action.isNotEmpty) {
      await triggerNotification(
        toUid: 'ADMIN_BROADCAST',
        title: "تحديث ميداني 📡",
        body: "السائق $driverName $action للطلب #$orderCode.",
        type: 'admin_driver_update',
        data: {'code': orderCode, 'status': status, 'driver': driverName},
      );
    }
  }

  /// تنبيه الإدارة عند تحصيل مبلغ نقدًا (COD)
  Future<void> notifyAdminOfCashCollection({
    required String driverName,
    required String orderCode,
    required double amount,
  }) async {
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "تم استلام نقدًا 💰",
      body: "أكد السائق $driverName استلام $amount ر.س نقدًا للطلب #$orderCode.",
      type: 'admin_cash_collected',
      data: {'code': orderCode, 'amount': amount, 'driver': driverName},
    );
  }

  /// تنبيه الإدارة بوجود تقييم منخفض (لرقابة الجودة)
  Future<void> notifyAdminOfLowRating({
    required String orderCode,
    required double rating,
    required String clientName,
    String? comment,
  }) async {
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "تحذير: تقييم منخفض ⚠️",
      body: "قام العميل $clientName بتقييم الطلب #$orderCode بـ $rating نجوم. يرجى المراجعة.",
      type: 'admin_security_alert',
      data: {'code': orderCode, 'rating': rating, 'comment': comment},
    );
  }

  /// تنبيه الإدارة بطلب عقد جديد (بانتظار المراجعة)
  Future<void> notifyAdminOfNewContractRequest({
    required String clientName,
    required String planName,
    required String contractId,
  }) async {
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "طلب باقة جديد 📜",
      body: "العميل $clientName تقدم بطلب للاشتراك في ($planName). بانتظار موافقتك.",
      type: 'admin_contract_request',
      data: {'contractId': contractId, 'client': clientName, 'plan': planName},
    );
  }

  /// تنبيه الإدارة بطلب صيانة جديد (بانتظار التسعير)
  Future<void> notifyAdminOfNewMaintenanceRequest({
    required String clientName,
    required String serviceType,
    required String requestId,
  }) async {
    await triggerNotification(
      toUid: 'ADMIN_BROADCAST',
      title: "طلب صيانة جديد 🛠️",
      body: "العميل $clientName رفع طلب صيانة ($serviceType). يرجى معاينة الطلب وتحديد السعر.",
      type: 'admin_maintenance_request',
      data: {'requestId': requestId, 'client': clientName, 'service': serviceType},
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
