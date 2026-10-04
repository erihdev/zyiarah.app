import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/utils/net_timeout.dart';

class ZyiarahMessagingService {
  // Singleton Implementation
  ZyiarahMessagingService._privateConstructor();
  static final ZyiarahMessagingService _instance = ZyiarahMessagingService._privateConstructor();
  factory ZyiarahMessagingService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _fallbackAdminEmail = 'admin@zyiarah.com';

  // يختم كل بلاغ بهوية منشئه ليتمكّن الخادم/القواعد من التحقق من الصلاحية لاحقاً.
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ==========================================
  // NOTIFICATION TRIGGER METHODS (FROM ZyiarahNotificationTriggerService)
  // ==========================================

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
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });
    } catch (e) {
      debugPrint("Error triggering notification: $e");
    }
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

  /// يرسل تنبيه مزدوج (للعميل وللإدارة) عند إنشاء طلب جديد
  Future<void> notifyOrderCreated({
    required String clientId,
    required String orderCode,
    required String type, // 'cleaning', 'store', 'maintenance'
    required String serviceName,
    String? orderId, // معرّف المستند — يجعل النقر على الإشعار يفتح الطلب
  }) async {
    // 1. تنبيه العميل
    await triggerNotification(
      toUid: clientId,
      title: "تم استلام طلبك بنجاح! 🎉",
      body: "طلبك رقم #$orderCode ($serviceName) قيد التنفيذ الآن. شكراً لاختيارك زيارة.",
      type: 'order_update',
      data: {'code': orderCode, 'type': type, if (orderId != null) 'orderId': orderId},
    );

    // (2) تنبيه الإدارة يتولّاه المُشغّل الخادمي sendNotificationToAdminsOnNewOrder عند
    // تأكيد الدفع (مرّة واحدة). أُزيل تنبيه العميل المكرّر (admin_order_alert) الذي كان
    // يُنتج تنبيهاً إدارياً ثانياً لكل طلب — والخادمي أوثق (لا يعتمد بقاء التطبيق حيّاً)،
    // ويقلّل كتابة العميل لـ ADMIN_BROADCAST عبر notification_triggers.
  }

  /// تنبيه العميل بحركات السائق — أُلغي الإرسال عمداً.
  ///
  /// تغيّر حالة الطلب (accepted/in_progress/completed/cancelled) يُشعِر العميل
  /// خادميّاً عبر sendNotificationOnOrderStatusChange بنص مؤنّث ومخصّص باسمه + سجل
  /// داخل التطبيق. الإبقاء على هذا الإرسال كان يُنتج إشعاراً ثانياً مكرّراً بنص
  /// مذكّر/عام. أُبقيت الدالة كـ no-op لتفادي كسر مواضع النداء.
  Future<void> notifyClientOfDriverStatus({
    required String clientId,
    required String status,
    required String orderCode,
    String? driverName,
    String? orderId,
  }) async {
    // no-op — المصدر الوحيد هو المُشغّل الخادمي (منعاً للتكرار).
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

  /// يجدول إشعار ليتم إرساله في وقت لاحق
  Future<void> scheduleBroadcast({
    required String title,
    required String body,
    required String target,
    required DateTime scheduledAt,
    String? createdBy,
    // (تفضيلات التنبيهات) تشغيلي = يصل حتى لمن أوقف «العروض والتسويق».
    bool operational = false,
  }) async {
    try {
      // يجب أن تُكتب في notifications_log بحالة 'scheduled' — releaseScheduledNotifications
      // يستعلم هذه المجموعة فقط. كانت تُكتب في scheduled_notifications التي لا يقرؤها
      // أي دالة، فالبثّ المجدول من تطبيق الإدارة لم يكن يُرسَل أبداً.
      await _db.collection('notifications_log').add({
        'title': title,
        'body': body,
        'target': target,
        'scheduled_at': Timestamp.fromDate(scheduledAt),
        'created_at': FieldValue.serverTimestamp(),
        'created_by': createdBy ?? 'Admin',
        'processed': false,
        'status': 'scheduled',
        'operational': operational,
      });
    } catch (e) {
      debugPrint("Error scheduling broadcast: $e");
      // لا نبتلع الخطأ: الابتلاع كان يجعل شاشة البث تعرض «تم جدولة البث بنجاح»
      // رغم أن الكتابة فشلت (permission-denied/App Check/quota) ولم يُجدول شيء.
      rethrow;
    }
  }


  // ==========================================
  // EMAIL COMM METHODS (FROM ZyiarahCommService)
  // ==========================================

  /// Specialized: New Order Confirmation (Customer + Admin)
  Future<void> notifyNewOrder(Map<String, dynamic> orderData, {String? customerEmail, String? invoiceUrl}) async {
    final orderCode = orderData['code'];
    final clientName = orderData['client_name'];
    final String targetAdmin = await _getAdminEmail();
    
    // 1. Notify Admin (Internal Alert)
    await sendTemplatedEmail(
      recipient: targetAdmin,
      subject: "🔔 طلب جديد - رقم #$orderCode",
      templateId: "admin-order-alert",
      variables: {
        "orderCode": orderCode,
        "clientName": clientName,
        "clientPhone": orderData['client_phone'] ?? 'غير متوفر',
        "serviceType": orderData['service_type'],
        "zone": orderData['zone'] ?? 'غير محدد',
        "serviceDate": orderData['date_time'] ?? 'غير محدد',
        "workerCount": orderData['worker_count']?.toString() ?? '1',
        "coupon": orderData['coupon'] ?? 'لا يوجد',
        "amount": "${orderData['amount']} ر.س",
        "adminUrl": "https://admin.zyiarah.com/orders/$orderCode",
      },
      attachmentUrls: invoiceUrl != null ? [invoiceUrl] : null,
    );

    // 2. Notify Customer (Fakhma Customer Experience)
    if (customerEmail != null && customerEmail.isNotEmpty) {
      await sendTemplatedEmail(
        recipient: customerEmail,
        subject: "شكراً لثقتكم بزيارة - تم تأكيد طلبكم #$orderCode",
        templateId: "order-confirmation",
        variables: {
          "orderCode": orderCode,
          "clientName": clientName,
          "serviceType": orderData['service_type'],
          "greeting": "عزيزنا $clientName،",
        },
        attachmentUrls: invoiceUrl != null ? [invoiceUrl] : null,
      );
    }
  }

  /// Specialized: Low Rating Escalation (Admin Alert)
  Future<void> alertReputationRisk({
    required String orderCode,
    required double rating,
    required String? reason,
    required String? comment,
    required String? evidenceUrl,
    required String clientName,
  }) async {
    final String targetAdmin = await _getAdminEmail();
    
    await sendTemplatedEmail(
      recipient: targetAdmin,
      subject: "⚠️ تنبيه جودة: تقييم منخفض للطلب #$orderCode",
      templateId: "reputation-risk-alert",
      variables: {
        "orderCode": orderCode,
        "rating": rating.toString(),
        "reason": reason ?? 'غير محدد',
        "comment": comment ?? 'لا يوجد تعليق',
        "evidenceUrl": evidenceUrl ?? '',
        "clientName": clientName,
        "severity": rating <= 1.0 ? "CRITICAL" : "WARNING",
      },
    );
  }

  /// يُنقّي بريداً أدخله المستخدم: يُسقط علامات الاتجاه/التحكم (U+200F…) والمسافات
  /// التي تلتصق باللصق من واتساب، ويُصغّر الحروف. Resend كان يرفض «‏user@x.com»
  /// بـ «Invalid to field: non-ASCII» فيضيع الترحيب وتأكيد الطلب بصمت.
  static String cleanEmail(String raw) =>
      raw.replaceAll(RegExp(r'[^\x21-\x7E]'), '').toLowerCase();

  /// Sends an email using a Resend Template
  Future<void> sendTemplatedEmail({
    required String recipient,
    required String subject,
    required String templateId,
    required Map<String, dynamic> variables,
    List<String>? attachmentUrls,
  }) async {
    final to = cleanEmail(recipient);
    if (to.isEmpty || !to.contains('@')) {
      debugPrint('[Messaging] skipped templated email: invalid recipient');
      return;
    }
    await _queueNotification(
      action: 'SEND_TEMPLATED_EMAIL',
      payload: {
        'to': to,
        'subject': subject,
        'template': {
          'id': templateId,
          'variables': variables,
        },
        'attachmentUrls': attachmentUrls,
      },
    );
  }

  /// Specialized: Welcome Email for New Users
  Future<void> sendWelcomeEmail({
    required String recipient,
    required String name,
  }) async {
    await sendTemplatedEmail(
      recipient: recipient,
      subject: "مرحباً بكم في عائلة زيارة! ✨",
      templateId: "welcome-to-zyiarah", // Alias from Resend
      variables: {
        "name": name,
      },
    );
  }

  Future<String> _getAdminEmail() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get().timeout(kNetCallTimeout);
      if (doc.exists && doc.data()?['admin_email'] != null) {
        return doc.data()!['admin_email'];
      }
    } catch (e) {
      debugPrint('Error fetching admin email: $e');
    }
    return _fallbackAdminEmail;
  }

  Future<void> _queueNotification({required String action, required Map<String, dynamic> payload}) async {
    try {
      // THE ROOT FIX: Instead of direct HTTP, we write to a Firestore Queue.
      // This ensures the email is sent even if the app closes immediately.
      await _db.collection('notification_triggers').add({
        'toUid': payload['to_uid'], // Optional, if we want to target a specific user's tokens too
        'recipientEmail': payload['to'],
        'title': payload['subject'],
        'body': payload['html_body'],
        'template': payload['template'], // Support for Resend Templates
        'attachmentUrls': payload['attachmentUrls'], // Support for PDF Attachments
        'type': 'email', // Cloud Function will detect this and use Resend/SMTP
        'action': action,
        'app': 'ZYIARAH_LUXE',
        'createdBy': _uid,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
        'data': {
          ...payload,
          'environment': kReleaseMode ? 'production' : 'development',
        },
      });
      
      debugPrint('Email queued successfully in Firestore');
    } catch (e) {
      debugPrint('Error queueing email trigger: $e');
    }
  }
}
