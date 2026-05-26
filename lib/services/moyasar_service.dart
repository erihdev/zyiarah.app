import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Moyasar payment gateway service.
/// - Credit Card / Apple Pay / STC Pay → handled by Moyasar Flutter SDK (no code here)
/// - Google Pay → processGooglePayToken() sends token to Moyasar REST API
/// - Payment verification → verifyPayment() via Firebase Cloud Function
class MoyasarService {
  static String get _publishableKey =>
      dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '';

  static const String _baseUrl = 'https://api.moyasar.com/v1';

  static String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$_publishableKey:'))}';

  static bool get isConfigured => _publishableKey.isNotEmpty;

  /// Sends a Google Pay token (from the `pay` package) to Moyasar REST API.
  /// Returns the Moyasar payment ID on success.
  /// Throws Exception with Arabic message on failure.
  static Future<String> processGooglePayToken({
    required Map<String, dynamic> googlePayToken,
    required double amountSAR,
    required String description,
    required String orderId,
  }) async {
    if (!isConfigured) {
      throw Exception('خدمة الدفع غير مُهيأة — يرجى التواصل مع الدعم');
    }

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
          'type': 'googlepay',
          'token': googlePayToken,
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

    String message = 'فشل معالجة الدفع عبر Google Pay';
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      message = error['message']?.toString() ?? message;
    } catch (_) {}
    throw Exception(message);
  }

  /// Verifies a payment by ID via secure Cloud Function.
  static Future<bool> verifyPayment(String paymentId, String orderId) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyMoyasarPayment');
      final result = await callable.call({
        'paymentId': paymentId,
        'orderId': orderId,
      });
      return result.data['success'] == true;
    } catch (e, stack) {
      debugPrint('MoyasarService.verifyPayment error: $e');
      await FirebaseCrashlytics.instance
          .recordError(e, stack, fatal: false);
      return false;
    }
  }
}
