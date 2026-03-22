import 'dart:convert';
import 'package:http/http.dart' as http;

/// خدمة الربط مع بوابة تمارا - تطبيق زيارة
class TamaraService {
  final String _baseUrl = "https://api-sandbox.tamara.co"; // تغير لـ api-sandbox للاختبار
  final String _apiToken = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhY2NvdW50SWQiOiIyZmIwMDMwNi04MjNmLTQzYWItOGYyMi1iN2RjNTRmMzE4ZTgiLCJ0eXBlIjoibWVyY2hhbnQiLCJzYWx0IjoiNjM5ZjBmOWQtMjYzNS00NTYxLWJmM2UtYzZmYzIyYTdkZWQ4Iiwicm9sZXMiOlsiUk9MRV9NRVJDSEFOVCJdLCJpc010bHMiOmZhbHNlLCJpYXQiOjE3NzI0ODQ2ODMsImlzcyI6IlRhbWFyYSBQUCJ9.akqqij2I3sZ6jPWUJqqsVE-53EZeujXvDin1TUxj7Ix6_whvGXEeemcnam-AypPev8kStxgu51zFNUd__oeCkxuQFlFDaSopaNqnD9wJMX6SxLnek7k0Ovk5kQfTd85oi2v-rR1x8JA7Q3G59Ifn_DnD1AixzxUb03j1kbpff2OLWSbvtvNH6bknNgMqgiJHK2OULWlTprIvlyQsZOiJbEXLQY48cZI0td3Zdn639uCc17X3QZecwXyTEzavDrfECZ1pV-CpsHYW6HNFPYbKT4XoXapCpKIRjlSVfI54SVaFiKKKlXnkYRrfsgQ5dvcz9DDEBZOxqKrBLqG9ibacKg";

  Future<String?> createCheckoutSession({
    required String orderId,
    required double amount,
    required String customerPhone,
    required String customerName,
  }) async {
    // Mock logic for testing if token is missing or placeholder
    if (_apiToken == "YOUR_TAMARA_TOKEN" || _apiToken.isEmpty) {
      return "https://zyiarah.com/payment-success-mock?order_id=$orderId";
    }

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
