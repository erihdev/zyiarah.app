import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ZyiarahCommService {
  // Configuration constants
  static const String _fallbackAdminEmail = 'admin@zyiarah.com';

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

  /// Sends an email using a Resend Template
  Future<void> sendTemplatedEmail({
    required String recipient,
    required String subject,
    required String templateId,
    required Map<String, dynamic> variables,
    List<String>? attachmentUrls,
  }) async {
    await _queueNotification(
      action: 'SEND_TEMPLATED_EMAIL',
      payload: {
        'to': recipient,
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
        .header { background: #5d1b5e; padding: 40px 20px; text-align: center; }
        .header h1 { color: #ffffff; margin: 0; font-size: 24px; }
        .content { padding: 40px 30px; line-height: 1.8; color: #1e293b; text-align: right; }
        .greeting { font-size: 18px; font-weight: bold; margin-bottom: 20px; }
        .footer { background: #f8fafc; padding: 20px; text-align: center; color: #64748b; font-size: 12px; }
        .btn { display: inline-block; padding: 12px 24px; background: #5d1b5e; color: white; text-decoration: none; border-radius: 12px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 style="color: #ffffff;">زيارة | ZYIARAH</h1>
        </div>
        <div class="content">
            <div class="greeting">$greeting</div>
            <h2 style="color: #5d1b5e;">$title</h2>
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
      await FirebaseFirestore.instance.collection('notification_triggers').add({
        'toUid': payload['to_uid'], // Optional, if we want to target a specific user's tokens too
        'recipientEmail': payload['to'],
        'title': payload['subject'],
        'body': payload['html_body'],
        'template': payload['template'], // Support for Resend Templates
        'attachmentUrls': payload['attachmentUrls'], // Support for PDF Attachments
        'type': 'email', // Cloud Function will detect this and use Resend/SMTP
        'action': action,
        'app': 'ZYIARAH_LUXE',
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
