import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:zyiarah/utils/moyasar_util.dart';
import 'package:zyiarah/utils/error_report.dart';

/// Moyasar payment gateway service.
/// - Credit Card / Apple Pay / STC Pay → handled by Moyasar Flutter SDK (no code here)
/// - Google Pay → processGooglePayToken() sends token to Moyasar REST API
/// - Payment verification → verifyPayment() via Firebase Cloud Function
/// **فشلُ دفعٍ مفهوم: رسالةٌ عربيّةٌ للعميلة، وتشخيصٌ للسجلّ، وبيانُ هل
/// سجّلت ميسر الدفعةَ أم لا.**
///
/// مسارُ Google Pay يَمُرُّ بـ`http.post` مباشرةً لا بحزمةِ ميسر، فلا
/// `ApiError`/`NetworkError` فيه — وكان يَرمي `Exception(نص)` عارياً،
/// فالشاشةُ تَطبعُ `e.toString()` **كما هو**: فمهلةُ الثلاثينَ ثانيةً تُقرأُ
/// «TimeoutException after 0:00:30.000000: Future not completed» وانقطاعُ
/// الشبكةِ «ClientException with SocketException: Failed host lookup» —
/// لاتينيّةٌ في شريطٍ عربيٍّ على شاشةِ الدفع. و`replaceAll('Exception: ','')`
/// لا يَمَسُّ أيّاً منهما (لا يَبدأُ بها).
///
/// و[recorded] هو ما يَحتاجُه قرارُ **تجديدِ المعرّف**: دفعةٌ **سجّلتها
/// ميسر** تَستهلكُ `given_id`، فإعادةُ المحاولةِ به تُعيدُ الفشلَ نفسَه
/// (نفسُ قرارِ Apple/Samsung Pay المكتوبِ في `payment_summary_screen`). وما
/// لم تُسجَّلْ — أو ما لا نَعرفُ نتيجتَه — يُبقي المعرّفَ، منعاً للشحنِ
/// المزدوج.
class MoyasarPayFailure implements Exception {
  /// سطرٌ عربيٌّ يُعرَضُ كما هو.
  final String message;

  /// هل أنشأت ميسر دفعةً فعلاً (فاستُهلك `given_id`)؟
  final bool recorded;

  /// تشخيصٌ للسجلِّ لا للعميلة (حالةُ ميسر ونصُّها الإنجليزيّ).
  final String? detail;

  const MoyasarPayFailure(this.message, {this.recorded = false, this.detail});

  @override
  String toString() => 'MoyasarPayFailure($message, recorded: $recorded, '
      'detail: $detail)';
}

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
    Map<String, String>? metadata,
  }) async {
    if (!isConfigured) {
      throw const MoyasarPayFailure(
          'خدمة الدفع غير مُهيأة — يرجى التواصل مع الدعم');
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
        // Moyasar تشترط UUID صالحاً — نشتقّه ثابتاً من معرّف الطلب (منع الشحن المزدوج).
        'given_id': MoyasarUtil.givenIdFromOrder(orderId),
        // بيانات وصفية كاملة كي يتمكّن الخادم (verify/reconcile) من إنشاء الطلب من
        // الدفعة لو مات التطبيق بعد الشحن — بدونها يبقى الدفع يتيماً على أندرويد.
        'metadata': {'order_id': orderId, ...?metadata},
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
      // دفعةٌ **سجّلتها** ميسر ولم تُكتمَل: `given_id` استُهلك. والنصُّ
      // عربيٌّ وحدَه — كان يَعرضُ حالةَ ميسر ورسالتَها الإنجليزيّةَ للعميلة
      // («حالة الدفع: failed — Insufficient funds»)، فصارت في [detail].
      throw MoyasarPayFailure('لم تُكتمل عمليّة الدفع عبر Google Pay',
          recorded: true,
          detail: 'status=$status msg=${data['message'] ?? ''}');
    }

    // غيرُ 201: لم تُنشَأْ دفعةٌ، فالمعرّفُ لم يُستهلَك.
    String message = 'فشل معالجة الدفع عبر Google Pay';
    String? detail;
    try {
      final error = jsonDecode(response.body) as Map<String, dynamic>;
      final type = error['type']?.toString() ?? '';
      detail = 'http=${response.statusCode} type=$type '
          'msg=${error['message'] ?? ''}';
      message = switch (type) {
        'account_inactive_error' => 'حساب الدفع قيد التفعيل — يرجى المحاولة لاحقاً',
        'authentication_error' => 'خطأ في مفاتيح بوابة الدفع — تواصلي مع الدعم',
        'rate_limit_error' => 'كثرة الطلبات — يرجى الانتظار قليلاً والمحاولة مجدداً',
        // رسالةُ ميسر إنجليزيّةٌ، فلا تُعرَض: تَذهبُ إلى [detail].
        'invalid_request_error' => 'بيانات الطلب غير صحيحة — تواصلي مع الدعم',
        _ => message,
      };
    } catch (_) {
      detail = 'http=${response.statusCode} body_not_json';
    }
    throw MoyasarPayFailure(message, detail: detail);
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
      // كان يُبلّغ بلا `reason`، فيصل Crashlytics بلا تجميع — تختفي الإشارة.
      // والسبب هنا ثابت ومُسمّى: فشلُ التحقّق من دفعةٍ مسار مال.
      reportSilent(e, stack,
          reason: 'moyasar_verify_payment_failed',
          info: {'orderId': orderId, 'paymentId': paymentId});
      return false;
    }
  }
}
