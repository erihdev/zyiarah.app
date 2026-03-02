import 'dart:convert';
import 'package:http/http.dart' as http;

/// خدمة الربط مع بوابة تمارا - تطبيق زيارة
class TamaraService {
  final String _baseUrl = "https://api-sandbox.tamara.co"; // تغير لـ api-sandbox للاختبار
  final String _apiToken = "YOUR_TAMARA_TOKEN"; // استبدله من api_keys_checklist.md

  /// إنشاء جلسة دفع جديدة
  Future<String?> createCheckoutSession({
    required String orderId,
    required double amount,
    required String customerPhone,
    required String customerName,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/checkout'),
      headers: {
        'Authorization': 'Bearer $_apiToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "order_reference_id": orderId,
        "total_amount": {"amount": amount, "currency": "SAR"},
        "consumer": {
          "first_name": customerName,
          "phone_number": customerPhone,
        },
        "merchant_url": {
          "success": "https://zyiarah.com/payment-success",
          "failure": "https://zyiarah.com/payment-failure",
          "cancel": "https://zyiarah.com/payment-cancel"
        },
        "description": "خدمات منزلية - مؤسسة معاذ يحي محمد المالكي",
      }),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['checkout_url'];
    }
    return null;
  }
}
