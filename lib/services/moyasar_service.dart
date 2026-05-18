import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Moyasar payment gateway service.
/// API key is loaded from MOYASAR_PUBLISHABLE_KEY in .env.
/// Add this key once you receive your Moyasar credentials.
class MoyasarService {
  static String get _publishableKey =>
      dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '';

  static const String _baseUrl = 'https://api.moyasar.com/v1';

  static String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$_publishableKey:'))}';

  /// Sends the Apple Pay token received from the native sheet to Moyasar
  /// to complete the payment. Returns the Moyasar payment ID on success.
  static Future<String> processApplePayToken({
    required Map<String, dynamic> applePayToken,
    required double amountSAR,
    required String description,
    required String orderId,
  }) async {
    final amountHalala = (amountSAR * 100).round();

    final response = await http.post(
      Uri.parse('$_baseUrl/payments'),
      headers: {
        'Authorization': _authHeader,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'amount': amountHalala,
        'currency': 'SAR',
        'description': description,
        'metadata': {'order_id': orderId},
        'source': {
          'type': 'applepay',
          'token': applePayToken,
          'company': 'zyiarah',
          'name': 'زيارة',
        },
        'callback_url': 'https://zyiarah-app.web.app/moyasar-callback',
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status == 'paid') {
        return data['id'] as String;
      }
      throw Exception(
          'حالة الدفع: $status — ${data['message'] ?? 'خطأ غير متوقع'}');
    }

    String message = 'فشل معالجة الدفع عبر Apple Pay';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      message = error['message']?.toString() ?? message;
    } catch (_) {
      // Non-JSON error body (e.g. gateway HTML page) — keep generic message.
    }
    throw Exception(message);
  }

  /// Verifies a payment by ID — useful for server-side double-check.
  static Future<bool> verifyPayment(String paymentId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/payments/$paymentId'),
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['status'] == 'paid';
      }
      return false;
    } catch (e, stack) {
      debugPrint('MoyasarService.verifyPayment error: $e');
      FirebaseCrashlytics.instance.recordError(e, stack, fatal: false);
      return false;
    }
  }
}
