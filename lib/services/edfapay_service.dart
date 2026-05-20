import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// EdfaPay Payment Gateway Service
/// Implements direct REST API integration to avoid the edfapg_sdk/intl version
/// conflict with flutter_localizations. The SDK is simply a wrapper over these
/// exact same HTTP endpoints.
class EdfaPayService {
  // Read from .env — required keys:
  // EDFAPAY_MERCHANT_ID, EDFAPAY_TERMINAL_ID, EDFAPAY_PASSWORD_KEY
  static String get _mId => dotenv.env['EDFAPAY_MERCHANT_ID'] ?? '';
  static String get _tId => dotenv.env['EDFAPAY_TERMINAL_ID'] ?? '';
  static String get _pKw => dotenv.env['EDFAPAY_PASSWORD_KEY'] ?? '';

  // EdfaPay Production API endpoint
  static const String _apiUrl = 'https://api.edfapay.com/payment/sale';
  static const String _applePayApiUrl = 'https://api.edfapay.com/payment/applepay-sale';

  static bool get _isConfigured =>
      _mId.isNotEmpty && _tId.isNotEmpty && _pKw.isNotEmpty;

  Future<void> initialize() async {}

  /// Generate the required HMAC-MD5 hash signature for EdfaPay requests.
  /// Formula: md5(strtolower(md5(password)) + amount + currency + order_id + email)
  String _generateHash({
    required String amount,
    required String currency,
    required String orderId,
    required String email,
  }) {
    final passwordHash = md5
        .convert(utf8.encode(_pKw))
        .toString()
        .toLowerCase();
    final raw = '$passwordHash$amount$currency$orderId$email';
    return md5.convert(utf8.encode(raw)).toString();
  }

  /// Process a card payment via EdfaPay's hosted payment page.
  /// Returns a checkout redirect URL for the caller to present in a WebView.
  /// On success the EdfaPay gateway calls back the return_url.
  Future<Map<String, dynamic>> processPayment({
    required double amount,
    required String orderId,
    required String customerEmail,
    required String customerPhone,
    required String customerName,
  }) async {
    if (!_isConfigured) {
      return {
        'success': false,
        'error': 'بوابة الدفع غير مكوّنة — يرجى تحديث بيانات EDFAPAY في ملف .env',
      };
    }

    final String amountStr = amount.toStringAsFixed(2);
    const String currency = 'SAR';
    final String hash = _generateHash(
      amount: amountStr,
      currency: currency,
      orderId: orderId,
      email: customerEmail,
    );

    final nameParts = customerName.trim().split(' ');
    final firstName = nameParts.first;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : firstName;

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'merchant_id': _mId,
          'terminal_id': _tId,
          'hash': hash,
          'order_id': orderId,
          'order_amount': amountStr,
          'order_currency': currency,
          'order_description': 'خدمة زيارة - $orderId',
          'payer_first_name': firstName,
          'payer_last_name': lastName,
          'payer_email': customerEmail,
          'payer_phone': customerPhone,
          'payer_country': 'SA',
          'payer_city': 'Riyadh',
          'payer_address': 'Saudi Arabia',
          'payer_zip': '12345',
          'payer_ip': '127.0.0.1',
          'term_url_3ds': 'https://zyiarah.com/payment-success',
          'recurring_init': 'N',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] as String?)?.toLowerCase();

        // EdfaPay returns 'success', 'redirect' (3DS), or 'decline'
        if (status == 'success') {
          return {
            'success': true,
            'transactionId': data['trans_id'] ?? data['transaction_id'] ?? orderId,
          };
        } else if (status == 'redirect' && data['redirect_url'] != null) {
          // 3DS authentication required — return redirect URL for WebView
          return {
            'success': false,
            'requires_redirect': true,
            'redirect_url': data['redirect_url'],
            'transactionId': data['trans_id'] ?? orderId,
          };
        } else {
          final reason = data['decline_reason'] ?? data['message'] ?? 'Payment declined';
          return {'success': false, 'error': reason};
        }
      } else {
        final errorBody = response.body;
        debugPrint('[EDFAPAY] HTTP ${response.statusCode}: $errorBody');
        return {
          'success': false,
          'error': 'خطأ في الاتصال ببوابة الدفع (${response.statusCode})',
        };
      }
    } catch (e, stack) {
      await FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'EdfaPay processPayment failed',
        fatal: false,
      );
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Process an Apple Pay decrypted token via EdfaPay's Apple Pay sale endpoint.
  /// [paymentData] is the decoded Apple Pay PKPaymentToken payment data map.
  Future<Map<String, dynamic>> processApplePay({
    required Map<String, dynamic> paymentData,
    required double amount,
    required String orderId,
  }) async {
    if (!_isConfigured) {
      return {
        'success': false,
        'error': 'بوابة الدفع غير مكوّنة — يرجى تحديث بيانات EDFAPAY في ملف .env',
      };
    }

    final String amountStr = amount.toStringAsFixed(2);
    const String currency = 'SAR';

    // Extract the Apple Pay token components
    final paymentToken = paymentData['token'] as Map<String, dynamic>?;
    final paymentDataInner =
        paymentToken?['paymentData'] as Map<String, dynamic>? ?? paymentData;

    try {
      final response = await http.post(
        Uri.parse(_applePayApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'merchant_id': _mId,
          'terminal_id': _tId,
          'order_id': orderId,
          'order_amount': amountStr,
          'order_currency': currency,
          'order_description': 'زيارة - Apple Pay',
          'apple_pay_token': jsonEncode(paymentDataInner),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = (data['status'] as String?)?.toLowerCase();

        if (status == 'success') {
          return {
            'success': true,
            'transactionId': data['trans_id'] ?? data['transaction_id'] ?? orderId,
          };
        } else {
          final reason = data['decline_reason'] ?? data['message'] ?? 'Apple Pay declined';
          return {'success': false, 'error': reason};
        }
      } else {
        return {
          'success': false,
          'error': 'خطأ في معالجة Apple Pay (${response.statusCode})',
        };
      }
    } catch (e, stack) {
      await FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'EdfaPay processApplePay failed',
        fatal: false,
      );
      return {'success': false, 'error': e.toString()};
    }
  }
}
