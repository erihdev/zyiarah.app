import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  <div style="background:linear-gradient(135deg,#660033,#8E2B5C);padding:32px;text-align:center">
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
      <a href="zyiarah://app/order/$orderId" style="background:#660033;color:#fff;padding:14px 32px;border-radius:10px;text-decoration:none;font-weight:bold;font-size:15px;display:inline-block">افتح التطبيق الآن</a>
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
      type: 'order_assignment',
      data: {
        'orderId': orderId,
        'deepLink': 'zyiarah://app/order/$orderId',
        'type': 'new_order_driver',
      },
    );

    // إذا وجد إيميل — أرسل trigger منفصل للإيميل بـ HTML كامل
    if (driverEmail != null) {
      try {
        await _db.collection('notification_triggers').add({
          'toUid': driverId,
          'title': 'مهمة جديدة مسندة إليك 🚀 — طلب #$orderId',
          'body': emailHtml,
          'type': 'email',
          'recipientEmail': driverEmail,
          'data': {'orderId': orderId},
          'createdBy': _uid,
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
      } catch (e) {
        debugPrint("Defensive: Error queueing driver assignment email: $e");
      }
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

  /// تنبيه العميل بموافقة الإدارة على طلب المتجر ودعوته لإتمام الدفع
  Future<void> notifyClientStoreOrderApproved(String clientId, String orderCode,
      double amount, {String? customerEmail, String? clientName}) async {
    await triggerNotification(
      toUid: clientId,
      title: "تمت الموافقة على طلب المتجر! ✅",
      body:
          "وافقت الإدارة على طلبك #$orderCode بمبلغ ${amount.toStringAsFixed(2)} ر.س. يرجى إتمام الدفع لتجهيز منتجاتك.",
      type: 'store_approved',
      data: {
        'code': orderCode,
        'amount': amount,
        'customerEmail': customerEmail,
        'deepLink': 'zyiarah://app/orders'
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

  /// Sends a Luxurious Email to one or more recipients
  Future<void> sendPremiumEmail({
    required String recipient,
    required String subject,
    required String title,
    required String bodyHtml,
    String? greeting,
  }) async {
    final fullHtml = _wrapInLuxuriousTemplate(
      title: title,
      contentHtml: bodyHtml,
      greeting: greeting ?? "مرحباً بكم في زيارة",
    );

    await _queueNotification(
      action: 'SEND_EMAIL',
      payload: {
        'to': recipient,
        'subject': subject,
        'html_body': fullHtml,
      },
    );
  }

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

  /// Specialized: Maintenance Quote (Customer Alert)
  Future<void> notifyMaintenanceQuote({
    required String recipient,
    required String clientName,
    required String serviceType,
    required double amount,
    required String requestId,
  }) async {
    await sendTemplatedEmail(
      recipient: recipient,
      subject: "تم تحديث عرض السعر لطلب الصيانة الخاص بك 🛠️",
      templateId: "maintenance-quote",
      variables: {
        "clientName": clientName,
        "serviceType": serviceType,
        "amount": "$amount ر.س",
        "paymentUrl": "https://zyiarah.com/maintenance/pay/$requestId",
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

  /// The "Fakhma" Wrapper
  String _wrapInLuxuriousTemplate({required String title, required String contentHtml, required String greeting}) {
    return """
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Arial', sans-serif; background-color: #f1f5f9; margin: 0; padding: 0; }
        .container { max-width: 600px; margin: 40px auto; background: #ffffff; border-radius: 24px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.05); }
        .header { background: #660033; padding: 40px 20px; text-align: center; }
        .header h1 { color: #ffffff; margin: 0; font-size: 24px; }
        .content { padding: 40px 30px; line-height: 1.8; color: #1e293b; text-align: right; }
        .greeting { font-size: 18px; font-weight: bold; margin-bottom: 20px; }
        .footer { background: #f8fafc; padding: 20px; text-align: center; color: #64748b; font-size: 12px; }
        .btn { display: inline-block; padding: 12px 24px; background: #660033; color: white; text-decoration: none; border-radius: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 style="color: #ffffff;">زيارة | ZYIARAH</h1>
        </div>
        <div class="content">
            <div class="greeting">$greeting</div>
            <h2 style="color: #660033;">$title</h2>
            $contentHtml
        </div>
        <div class="footer">
            <p>© ${DateTime.now().year} شركة زيارة للتشغيل والصيانة. جميع الحقوق محفوظة.</p>
            <p>هذا البريد مرسل تلقائياً، يرجى عدم الرد عليه.</p>
        </div>
    </div>
</body>
</html>
    """;
  }

  Future<String> _getAdminEmail() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
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
