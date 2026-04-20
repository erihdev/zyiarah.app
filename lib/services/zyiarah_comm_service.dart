import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ZyiarahCommService {
  // CONFIGURATION
  static const String _webhookUrl = 'https://n8n.zyiarah.com/webhook/zyiarah-comm';
  static const String _adminEmail = 'admin@zyiarah.com'; // Official app email

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

    await _triggerWebhook(
      action: 'SEND_EMAIL',
      payload: {
        'to': recipient,
        'subject': subject,
        'html_body': fullHtml,
      },
    );
  }

  /// Specialized: New Order Confirmation (Customer + Admin)
  Future<void> notifyNewOrder(Map<String, dynamic> orderData, {String? customerEmail}) async {
    final orderCode = orderData['code'];
    final clientName = orderData['client_name'];
    
    // 1. Notify Admin (Internal Alert)
    await sendPremiumEmail(
      recipient: _adminEmail,
      subject: "🔔 طلب جديد - رقم #$orderCode",
      title: "تم استلام طلب جديد بنجاح",
      bodyHtml: """
        <div style="background: #f8fafc; padding: 20px; border-radius: 12px; margin-bottom: 20px;">
          <p><strong>كود الطلب:</strong> $orderCode</p>
          <p><strong>العميل:</strong> $clientName</p>
          <p><strong>نوع الخدمة:</strong> ${orderData['service_type']}</p>
          <p><strong>المبلغ:</strong> ${orderData['amount']} ر.س</p>
        </div>
        <p style="text-align: center;">
          <a href="https://admin.zyiarah.com/orders/$orderCode" style="background: #1e293b; color: white; padding: 12px 25px; text-decoration: none; border-radius: 8px; font-weight: bold;">فتح تفاصيل الطلب</a>
        </p>
      """,
    );

    // 2. Notify Customer (Fakhma Customer Experience)
    if (customerEmail != null && customerEmail.isNotEmpty) {
      await sendPremiumEmail(
        recipient: customerEmail,
        subject: "شكراً لثقتكم بزيارة - تم تأكيد طلبكم #$orderCode",
        title: "طلبكم قيد التجهيز الآن",
        greeting: "عزيزنا $clientName،",
        bodyHtml: """
          <p>تم استلام طلبكم رقم <strong>#$orderCode</strong> بنجاح. نحن نعمل الآن على تخصيص أفضل كادر لخدمتكم.</p>
          <div style="border-top: 1px solid #eee; margin: 20px 0; padding-top: 20px;">
            <p style="color: #64748b; font-size: 14px;">تفاصيل الخدمة:</p>
            <p><strong>${orderData['service_type']}</strong></p>
            <p>سيسعدنا التواصل معكم قريباً عبر التطبيق لمتابعة حالة وصول الكادر.</p>
          </div>
        """,
      );
    }
  }

  /// Specialized: Low Rating Escalation
  Future<void> alertReputationRisk({
    required String orderCode,
    required double rating,
    required String? reason,
    required String? comment,
    required String? evidenceUrl,
    required String clientName,
  }) async {
    final String severityColor = rating <= 1.0 ? "#ef4444" : "#f59e0b";
    
    await sendPremiumEmail(
      recipient: _adminEmail,
      subject: "⚠️ تنبيه جودة: تقييم منخفض للطلب #$orderCode",
      title: "بلاغ متعثر في جودة الخدمة",
      greeting: "تنبيه إداري عاجل،",
      bodyHtml: """
        <div style="border: 2px solid $severityColor; padding: 20px; border-radius: 12px;">
          <h2 style="color: $severityColor; margin-top: 0;">التقييم: $rating / 5.0</h2>
          <p><strong>العميل:</strong> $clientName</p>
          <p><strong>السبب المذكور:</strong> ${reason ?? 'غير محدد'}</p>
          <p><strong>ملاحظات العميل:</strong> ${comment ?? 'لا يوجد تعليق'}</p>
          ${evidenceUrl != null ? '<p><a href="$evidenceUrl" style="color: #2563eb; font-weight: bold;">🔗 معاينة صورة الدليل</a></p>' : ''}
        </div>
        <p style="margin-top: 20px; color: #64748b; font-size: 12px;">يرجى التواصل مع العميل فوراً لاحتواء الموقف.</p>
      """,
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

  Future<void> _triggerWebhook({required String action, required Map<String, dynamic> payload}) async {
    try {
      // 1. Fetch dynamic webhook from Firestore config
      String dynamicUrl = 'https://n8n.zyiarah.com/webhook/zyiarah-comm'; // Safe Fallback
      try {
        final doc = await FirebaseFirestore.instance.collection('system_configs').doc('main_settings').get();
        if (doc.exists && doc.data()?['webhook_url'] != null) {
          dynamicUrl = doc.data()!['webhook_url'];
        }
      } catch (e) {
        debugPrint('Config fetch error, using fallback: $e');
      }

      // 2. Execute the request
      await http.post(
        Uri.parse(dynamicUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'app': 'ZYIARAH_LUXE',
          'data': payload,
        }),
      );
    } catch (e) {
      debugPrint('Webhook error: $e');
    }
  }
}
