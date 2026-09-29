import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tabby_flutter_inapp_sdk/tabby_flutter_inapp_sdk.dart';

/// Tabby Buy Now, Pay Later service.
/// يُستخدم لتقسيم الدفع على 4 أقساط عبر Tabby.
/// تهيئة: استدعِ TabbyService.initialize() في main.dart بعد dotenv.load().
class TabbyService {
  static bool _initialized = false;

  /// مهلة إقلاع SDK. منذ 2.0.0 صار `setup()` نداءً شبكياً (يجلب عناوين
  /// الخدمة المجزّأة من Tabby)، وهو يُنتظَر قبل `runApp` — فبلا مهلة قد يعلّق
  /// إقلاع التطبيق كلّه على استجابة طرف ثالث.
  static const Duration _setupTimeout = Duration(seconds: 8);

  /// تهيئة SDK. **لا ترمي أبداً**: منذ 2.0.0 يفشل `setup()` فشلاً صريحاً
  /// (ServerException عند غير 200، FormatException عند ردٍّ مشوَّه، وأخطاء
  /// النقل تمرّ كما هي) بلا إعادة محاولة ولا احتياطي. وهي تُنتظَر في main قبل
  /// `runApp`، فاستثناء غير ملتقَط = تطبيق لا يُقلع أصلاً لانقطاع شبكة عابر.
  /// الفشل هنا يعني إخفاء تابي وحدها (isAvailable=false) وبقية وسائل الدفع تعمل.
  static Future<void> initialize() async {
    final apiKey = dotenv.env['TABBY_PUBLIC_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('[TabbyService] TABBY_PUBLIC_KEY not set — skipping init');
      return;
    }
    try {
      await TabbySDK().setup(withApiKey: apiKey).timeout(_setupTimeout);
      _initialized = true;
      debugPrint('[TabbyService] initialized');
    } catch (e) {
      _initialized = false;
      debugPrint('[TabbyService] setup failed — Tabby hidden this session: $e');
    }
  }

  /// إعادة محاولة كسولة: فشلُ الإقلاع عابرٌ غالباً (شبكة العميل لحظة الفتح)،
  /// وبدون هذه لبقيت تابي مخفيّة طوال الجلسة. تُستدعى من شاشة الدفع.
  /// تُعيد true إن صارت جاهزة.
  static Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    await initialize();
    return _initialized;
  }

  static bool get isAvailable => _initialized;

  /// ينشئ جلسة دفع Tabby ويُعيد webUrl لفتحها في WebView.
  /// يُعيد null إذا رُفضت الجلسة من Tabby أو كان SDK غير مُهيأ.
  static Future<String?> createCheckoutUrl({
    required double amountSAR,
    required String customerPhone,
    required String customerName,
    required String customerEmail,
    required String orderId,
  }) async {
    if (!_initialized) return null;

    try {
      final session = await TabbySDK().createSession(
        TabbyCheckoutPayload(
          merchantCode: 'sa', // المملكة العربية السعودية
          lang: Lang.ar,
          payment: Payment(
            amount: amountSAR.toStringAsFixed(2),
            currency: Currency.sar,
            description: 'خدمة زيارة - $orderId',
            buyer: Buyer(
              email: customerEmail,
              phone: customerPhone,
              name: customerName,
            ),
            buyerHistory: BuyerHistory(
              registeredSince: '2019-08-24T14:15:22Z',
              loyaltyLevel: 0,
            ),
            shippingAddress: null,
            order: Order(
              referenceId: orderId,
              items: [
                OrderItem(
                  title: 'خدمة زيارة',
                  quantity: 1,
                  unitPrice: amountSAR.toStringAsFixed(2),
                  category: 'Services',
                ),
              ],
            ),
            orderHistory: [],
          ),
        ),
      );

      if (session.status == SessionStatus.rejected) {
        debugPrint('[TabbyService] session rejected');
        return null;
      }

      return session.availableProducts.installments?.webUrl;
    } catch (e) {
      debugPrint('[TabbyService] createCheckoutUrl error: $e');
      return null;
    }
  }

  /// يفتح Tabby WebView ويُعيد النتيجة عبر callbacks.
  /// [onSuccess]: استُدعي عند الموافقة.
  /// [onFailure]: استُدعي عند الرفض أو الانتهاء.
  static void showCheckout({
    required BuildContext context,
    required String webUrl,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
  }) {
    TabbyWebView.showWebView(
      context: context,
      webUrl: webUrl,
      onResult: (WebViewResult result) {
        switch (result) {
          case WebViewResult.authorized:
            onSuccess();
          case WebViewResult.rejected:
          case WebViewResult.expired:
          case WebViewResult.close:
            onFailure();
        }
      },
    );
  }
}
