import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/home_packages.dart';
import 'package:zyiarah/utils/broadcast_target.dart';

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

  Future<void> notifyContractApproved(String userId, String planName,
      {String? customerEmail, String? clientName, String? contractId}) async {
    await triggerNotification(
      toUid: userId,
      title: "تمت الموافقة على طلبك بنجاح! 📄",
      body: "تم اعتماد عقد باقة ($planName) من قبل الإدارة. يرجى إتمام الدفع لتفعيل الباقة.",
      type: 'hybrid',
      data: {
        'planName': planName,
        'customerEmail': customerEmail,
        // `deepLink` كان **لا يَقرؤه أحد**: `handleNotificationTap` يَقرأُ
        // مفاتيحَ المعرّفات، وقيمتُه (`zyiarah://app/contracts`) كان
        // `_handleUri` يَرفضُها مرّتَين — بلا معرّفٍ، وبموردٍ لا فرعَ له.
        // `contractId` هو ما تَفتحُ به القاعدةُ المشتركةُ «عقودي».
        if (contractId != null && contractId.isNotEmpty) 'contractId': contractId,
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
        // **القيمةُ التي يَعرفُها الخادمُ لا اسمُ موضوعِ FCM.** كان يُمرَّرُ
        // `_target` كما هو، فيُكتَبُ `all_users` في الحقلِ — والتسليمُ يَصِحُّ
        // بفالِّ `_deliverBroadcast` إلى «بلا مُرشِّح» لا بقرار، وسجلُّ اللوحةِ
        // يَطبعُ الرمزَ حرفيّاً. القاعدةُ في `utils/broadcast_target.dart`.
        'target': broadcastTargetOf(target),
        'scheduled_at': Timestamp.fromDate(scheduledAt),
        // **حاضرٌ `null` لا غائب**: سجلُّ اللوحةِ يُرتّبُ بـ`sent_at`
        // وFirestore تُستثني المستندَ الذي لا يَحملُ حقلَ الترتيب — فمجدولٌ
        // من التطبيقِ كان غائباً عن السجلِّ قبلَ الإرسالِ وبعدَه. و`null`
        // يُطابقُ الترتيبَ (ويَقعُ آخراً تنازليّاً) ولا يُطابقُ `<=` فلا
        // يُحرّكُ مكنسةَ الإفراجِ — وهو ما تَكتبُه اللوحةُ أصلاً.
        // و`_deliverBroadcast` يَملؤه لحظةَ الإرسالِ الفعليّ.
        'sent_at': null,
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
        "amount": "${formatSarAny(orderData['amount'])} ر.س",
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
