# Moyasar Full Payment Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace EdfaPay entirely with Moyasar SDK + add Tabby BNPL + Google Pay + STC Pay while keeping Tamara and all existing payment methods (Wallet, COD, Subscription) untouched.

**Architecture:** Moyasar Flutter SDK v3.0.3 handles Credit Card / Apple Pay / STC Pay. Tabby gets its own `TabbyService` wrapper around `tabby_flutter_inapp_sdk`. Google Pay uses the existing `pay` package to get a token, then sends it to Moyasar's REST API. `PaymentSummaryScreen` orchestrates all methods via `_selectedPaymentMethod` string.

**Tech Stack:** `moyasar: ^3.0.3` · `tabby_flutter_inapp_sdk: ^1.11.0` · `pay: ^3.3.0` (existing) · Firebase Cloud Functions (existing) · `flutter_dotenv` (existing)

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| **DELETE** | `lib/services/edfapay_service.dart` | حُذف بالكامل |
| **REWRITE** | `lib/services/moyasar_service.dart` | Google Pay token → Moyasar API + verifyPayment |
| **CREATE** | `lib/services/tabby_service.dart` | Tabby SDK wrapper |
| **CREATE** | `lib/screens/moyasar_card_screen.dart` | شاشة بطاقة ميسر (Moyasar CreditCard widget) |
| **CREATE** | `lib/screens/moyasar_stc_screen.dart` | شاشة STC Pay (رقم الجوال + OTP) |
| **CREATE** | `assets/google_pay_config.json` | إعدادات Google Pay للـ pay package |
| **MODIFY** | `pubspec.yaml` | إضافة moyasar + tabby_flutter_inapp_sdk + asset |
| **MODIFY** | `.env` | إضافة MOYASAR_PUBLISHABLE_KEY + TABBY_PUBLIC_KEY |
| **MODIFY** | `lib/main.dart` | تهيئة Tabby SDK |
| **MODIFY** | `lib/screens/payment_summary_screen.dart` | حذف EdfaPay، إضافة Tabby/Google Pay/STC/Apple Pay |

---

## Task 1: تحديث `pubspec.yaml` وتثبيت الحزم

**Files:**
- Modify: `pubspec.yaml`

- [ ] **الخطوة 1: إضافة الحزم الجديدة والأصول**

في `pubspec.yaml` أضف تحت `dependencies:` (بعد `crypto: ^3.0.3`):

```yaml
  moyasar: ^3.0.3
  tabby_flutter_inapp_sdk: ^1.11.0
```

وفي قسم `flutter → assets:` أضف السطر:

```yaml
    - assets/google_pay_config.json
```

الحالة النهائية لقسم assets:

```yaml
flutter:
  uses-material-design: true
  assets:
    - .env
    - assets/apple_pay_config.json
    - assets/google_pay_config.json
```

- [ ] **الخطوة 2: تثبيت الحزم**

```bash
flutter pub get
```

المخرج المتوقع: يظهر `moyasar 3.0.3` و `tabby_flutter_inapp_sdk 1.11.0` في القائمة.

- [ ] **الخطوة 3: تزامن iOS (مطلوب لـ Moyasar SDK)**

```bash
cd ios && pod install && cd ..
```

المخرج المتوقع: `Pod installation complete!`

- [ ] **الخطوة 4: commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add moyasar and tabby_flutter_inapp_sdk dependencies"
```

---

## Task 2: إضافة متغيرات البيئة

**Files:**
- Modify: `.env`

- [ ] **الخطوة 1: إضافة مفاتيح API (placeholders)**

افتح `.env` وأضف في النهاية:

```env
# Moyasar Payment Gateway
MOYASAR_PUBLISHABLE_KEY=pk_live_REPLACE_WITH_YOUR_KEY

# Tabby BNPL
TABBY_PUBLIC_KEY=pk_REPLACE_WITH_YOUR_KEY
```

> ⚠️ لا تضف `.env` إلى git — هو gitignored بالفعل.  
> ⚠️ استبدل القيم بالمفاتيح الحقيقية من لوحة تحكم ميسر وتابي عند الحصول عليها.

- [ ] **الخطوة 2: التحقق أن .env في .gitignore**

```bash
grep ".env" .gitignore
```

المخرج المتوقع: يظهر `.env` في القائمة. إذا لم يكن موجوداً أضفه يدوياً.

---

## Task 3: إنشاء `assets/google_pay_config.json`

**Files:**
- Create: `assets/google_pay_config.json`

- [ ] **الخطوة 1: إنشاء ملف إعدادات Google Pay**

أنشئ الملف `assets/google_pay_config.json` بالمحتوى التالي:

```json
{
  "provider": "google_pay",
  "data": {
    "environment": "PRODUCTION",
    "apiVersion": 2,
    "apiVersionMinor": 0,
    "allowedPaymentMethods": [
      {
        "type": "CARD",
        "parameters": {
          "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"],
          "allowedCardNetworks": ["MASTERCARD", "VISA"]
        },
        "tokenizationSpecification": {
          "type": "PAYMENT_GATEWAY",
          "parameters": {
            "gateway": "moyasar",
            "gatewayMerchantId": "REPLACE_WITH_MOYASAR_MERCHANT_ID"
          }
        }
      }
    ],
    "merchantInfo": {
      "merchantName": "Zyiarah - زيارة",
      "merchantId": "REPLACE_WITH_GOOGLE_MERCHANT_ID"
    },
    "transactionInfo": {
      "totalPriceStatus": "NOT_CURRENTLY_KNOWN",
      "currencyCode": "SAR",
      "countryCode": "SA"
    }
  }
}
```

> ⚠️ `gatewayMerchantId` = Moyasar publishable key  
> ⚠️ `merchantId` = Google Pay merchant ID (من Google Pay & Wallet Console)

- [ ] **الخطوة 2: commit**

```bash
git add assets/google_pay_config.json
git commit -m "feat: add google_pay_config.json for Android Google Pay"
```

---

## Task 4: إعادة كتابة `lib/services/moyasar_service.dart`

**Files:**
- Rewrite: `lib/services/moyasar_service.dart`

- [ ] **الخطوة 1: استبدال محتوى الملف بالكامل**

```dart
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
```

- [ ] **الخطوة 2: التحقق من الـ analyze**

```bash
flutter analyze lib/services/moyasar_service.dart
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 3: commit**

```bash
git add lib/services/moyasar_service.dart
git commit -m "refactor: rewrite MoyasarService — Google Pay token + verifyPayment only"
```

---

## Task 5: إنشاء `lib/services/tabby_service.dart`

**Files:**
- Create: `lib/services/tabby_service.dart`

- [ ] **الخطوة 1: إنشاء الملف**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:tabby_flutter_inapp_sdk/tabby_flutter_inapp_sdk.dart';

/// Tabby Buy Now, Pay Later service.
/// يُستخدم لتقسيم الدفع على 4 أقساط عبر Tabby.
/// تهيئة: استدعِ TabbyService.initialize() في main.dart بعد dotenv.load().
class TabbyService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    final apiKey = dotenv.env['TABBY_PUBLIC_KEY'] ?? '';
    if (apiKey.isEmpty) {
      debugPrint('[TabbyService] TABBY_PUBLIC_KEY not set — skipping init');
      return;
    }
    await TabbySDK().setup(withApiKey: apiKey);
    _initialized = true;
    debugPrint('[TabbyService] initialized');
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

  /// يفتح Tabby WebView ويُعيد النتيجة.
  /// [onSuccess]: استُدعي عند الموافقة.
  /// [onFailure]: استُدعي عند الرفض أو الانتهاء.
  static Future<void> showCheckout({
    required BuildContext context,
    required String webUrl,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
  }) async {
    final result = await TabbyWebView.showWebView(
      context: context,
      webUrl: webUrl,
      onResult: (res) {},
    );

    switch (result) {
      case WebViewResult.authorized:
        onSuccess();
      case WebViewResult.rejected:
      case WebViewResult.expired:
      case WebViewResult.close:
        onFailure();
    }
  }
}
```

- [ ] **الخطوة 2: التحقق من الـ analyze**

```bash
flutter analyze lib/services/tabby_service.dart
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 3: commit**

```bash
git add lib/services/tabby_service.dart
git commit -m "feat: add TabbyService wrapper for Tabby BNPL"
```

---

## Task 6: إنشاء `lib/screens/moyasar_card_screen.dart`

**Files:**
- Create: `lib/screens/moyasar_card_screen.dart`

هذه الشاشة تعرض Moyasar SDK's `CreditCard` widget وتُعيد payment ID عند النجاح.

- [ ] **الخطوة 1: إنشاء الملف**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moyasar/moyasar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// شاشة دفع البطاقة عبر Moyasar SDK.
/// تستدعي [onSuccess] مع payment ID عند نجاح الدفع.
/// تستدعي [onFailure] مع رسالة الخطأ عند الفشل.
class MoyasarCardScreen extends StatelessWidget {
  final double amountSAR;
  final String description;
  final String orderId;
  final void Function(String paymentId) onSuccess;
  final void Function(String error) onFailure;

  const MoyasarCardScreen({
    super.key,
    required this.amountSAR,
    required this.description,
    required this.orderId,
    required this.onSuccess,
    required this.onFailure,
  });

  PaymentConfig get _config => PaymentConfig(
        publishableApiKey: dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '',
        amount: (amountSAR * 100).round(), // Halala
        description: description,
        metadata: {'order_id': orderId},
        creditCard: CreditCardConfig(saveCard: false, manual: false),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          title: Text(
            'الدفع بالبطاقة',
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        backgroundColor: const Color(0xFFF1F5F9),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // شعار الأمان
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'دفع آمن ومشفر عبر ميسر',
                      style: GoogleFonts.tajawal(
                          fontSize: 13, color: Colors.green.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Moyasar SDK Credit Card Widget
              CreditCard(
                config: _config,
                onPaymentResult: (result) {
                  if (result.status == PaymentStatus.paid) {
                    Navigator.of(context).pop();
                    onSuccess(result.id ?? orderId);
                  } else {
                    final msg =
                        result.message ?? 'فشل الدفع — يرجى المحاولة مجدداً';
                    onFailure(msg);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **الخطوة 2: التحقق من الـ analyze**

```bash
flutter analyze lib/screens/moyasar_card_screen.dart
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 3: commit**

```bash
git add lib/screens/moyasar_card_screen.dart
git commit -m "feat: add MoyasarCardScreen with Moyasar CreditCard widget"
```

---

## Task 7: إنشاء `lib/screens/moyasar_stc_screen.dart`

**Files:**
- Create: `lib/screens/moyasar_stc_screen.dart`

- [ ] **الخطوة 1: إنشاء الملف**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moyasar/moyasar.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// شاشة STC Pay عبر Moyasar SDK.
/// المستخدم يُدخل رقم الجوال → يستلم OTP → يُدخله للتأكيد.
class MoyasarStcScreen extends StatefulWidget {
  final double amountSAR;
  final String description;
  final String orderId;
  final void Function(String paymentId) onSuccess;
  final void Function(String error) onFailure;

  const MoyasarStcScreen({
    super.key,
    required this.amountSAR,
    required this.description,
    required this.orderId,
    required this.onSuccess,
    required this.onFailure,
  });

  @override
  State<MoyasarStcScreen> createState() => _MoyasarStcScreenState();
}

class _MoyasarStcScreenState extends State<MoyasarStcScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _otpSent = false;
  String? _transactionUrl;

  PaymentConfig get _config => PaymentConfig(
        publishableApiKey: dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '',
        amount: (widget.amountSAR * 100).round(),
        description: widget.description,
        metadata: {'order_id': widget.orderId},
      );

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى إدخال رقم جوال صحيح'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await Moyasar.pay(
        apiKey: _config.publishableApiKey,
        paymentRequest: PaymentRequest(
          config: _config,
          source: StcRequestSource(mobile: phone),
        ),
      );

      if (result.status == PaymentStatus.initiated &&
          result.transactionUrl != null) {
        setState(() {
          _otpSent = true;
          _transactionUrl = result.transactionUrl;
          _isLoading = false;
        });
      } else if (result.status == PaymentStatus.paid) {
        Navigator.of(context).pop();
        widget.onSuccess(result.id ?? widget.orderId);
      } else {
        throw Exception(result.message ?? 'فشل إرسال OTP');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      widget.onFailure(e.toString().replaceAll('Exception: ', ''));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يرجى إدخال رمز OTP الصحيح'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_transactionUrl == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await Moyasar.verifyOTP(
        _transactionUrl!,
        OtpRequestSource(otp: otp),
      );

      if (result.status == PaymentStatus.paid) {
        Navigator.of(context).pop();
        widget.onSuccess(result.id ?? widget.orderId);
      } else {
        throw Exception(result.message ?? 'رمز OTP غير صحيح');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          title: Text('STC Pay',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        backgroundColor: const Color(0xFFF1F5F9),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // STC Pay logo hint
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      color: Color(0xFF5D1B5E), size: 40),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _otpSent ? 'أدخل رمز OTP' : 'رقم جوال STC Pay',
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'مثال: 0501234567',
                    hintStyle: GoogleFonts.tajawal(),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.phone),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5D1B5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('إرسال رمز OTP',
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ] else ...[
                Text(
                  'تم إرسال رمز OTP إلى رقم جوالك المرتبط بـ STC Pay',
                  style: GoogleFonts.tajawal(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'أدخل رمز OTP',
                    hintStyle: GoogleFonts.tajawal(),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5D1B5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('تأكيد الدفع',
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **الخطوة 2: التحقق من الـ analyze**

```bash
flutter analyze lib/screens/moyasar_stc_screen.dart
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 3: commit**

```bash
git add lib/screens/moyasar_stc_screen.dart
git commit -m "feat: add MoyasarStcScreen for STC Pay OTP flow"
```

---

## Task 8: تحديث `lib/main.dart` — تهيئة Tabby

**Files:**
- Modify: `lib/main.dart`

- [ ] **الخطوة 1: إضافة import وتهيئة TabbyService**

في أعلى الملف، أضف بعد `import 'package:zyiarah/services/geofence_service.dart';`:

```dart
import 'package:zyiarah/services/tabby_service.dart';
```

في دالة `main()` أضف **بعد** `GeofenceService.initialize();`:

```dart
  await TabbyService.initialize(); // تهيئة Tabby BNPL
```

الكود النهائي لـ `main()` في هذا القسم:

```dart
  ZyiarahNotificationService().initialize();
  ZyiarahDeepLinkService().initialize(navigatorKey);
  GeofenceService.initialize();
  await TabbyService.initialize(); // تهيئة Tabby BNPL
```

- [ ] **الخطوة 2: التحقق من الـ analyze**

```bash
flutter analyze lib/main.dart
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 3: commit**

```bash
git add lib/main.dart
git commit -m "feat: initialize TabbyService in main.dart"
```

---

## Task 9: تحديث `lib/screens/payment_summary_screen.dart`

**Files:**
- Modify: `lib/screens/payment_summary_screen.dart`

### 9A: تحديث الـ imports

- [ ] **الخطوة 1: استبدال import EdfaPay بالجديد**

ابحث عن هذا السطر:
```dart
import 'package:zyiarah/services/edfapay_service.dart';
```

واحذفه. ثم أضف بعد `import 'package:zyiarah/services/moyasar_service.dart';`:

```dart
import 'package:zyiarah/services/tabby_service.dart';
import 'package:zyiarah/screens/moyasar_card_screen.dart';
import 'package:zyiarah/screens/moyasar_stc_screen.dart';
import 'package:moyasar/moyasar.dart';
import 'dart:io' show Platform;
```

> ملاحظة: `import 'dart:io';` موجود بالفعل — تأكد فقط من عدم التكرار.

### 9B: تحديث State class

- [ ] **الخطوة 2: حذف EdfaPayService من state**

ابحث عن:
```dart
  final EdfaPayService _edfaPayService = EdfaPayService();
```
واحذف هذا السطر بالكامل.

- [ ] **الخطوة 2b: إضافة `_pendingOrderId` للـ state**

أضف هذه المتغيرات في أعلى `_PaymentSummaryScreenState`:

```dart
  late String _pendingOrderId;
```

في `initState()` أضف **أول سطر** قبل `_loadUserData()`:

```dart
    _pendingOrderId = widget.maintenanceId ??
        FirebaseFirestore.instance.collection('orders').doc().id;
```

> هذا يضمن أن Apple Pay metadata وعملية إنشاء الطلب يستخدمان نفس `orderId`.

في `_handlePayment()` استبدل:
```dart
      final String finalOrderId = widget.maintenanceId ?? FirebaseFirestore.instance.collection('orders').doc().id;
```
بـ:
```dart
      final String finalOrderId = _pendingOrderId;
```

- [ ] **الخطوة 3: تحديث `_selectedPaymentMethod` الافتراضي**

ابحث عن:
```dart
  String _selectedPaymentMethod = 'card'; // 'card', 'tamara', 'wallet', 'subscription' or 'cod'
```

استبدله بـ:
```dart
  String _selectedPaymentMethod = 'card'; // 'card', 'apple_pay', 'google_pay', 'tamara', 'tabby', 'stc_pay', 'wallet', 'subscription', 'cod'
```

- [ ] **الخطوة 4: حذف `_applePayConfigFuture` من state**

احذف السطر:
```dart
  late final Future<PaymentConfiguration> _applePayConfigFuture;
```

وفي `initState()` احذف:
```dart
    _applePayConfigFuture =
        PaymentConfiguration.fromAsset('assets/apple_pay_config.json');
```

واستبدلهما بـ `_googlePayConfigFuture` لـ Android:

```dart
  late final Future<PaymentConfiguration>? _googlePayConfigFuture;
```

في `initState()` أضف:

```dart
    if (!Platform.isIOS) {
      _googlePayConfigFuture =
          PaymentConfiguration.fromAsset('assets/google_pay_config.json');
    } else {
      _googlePayConfigFuture = null;
    }
```

### 9C: تحديث `_handlePayment()`

- [ ] **الخطوة 5: استبدال case 'card' في `_handlePayment()`**

ابحث عن هذا الجزء (في `_handlePayment`):

```dart
      } else if (_selectedPaymentMethod == 'card') {
        // EDFA PAY (Card)
        const String paymentType = 'Card';
        final result = await _edfaPayService.processPayment(
          amount: totalWithVat,
          orderId: finalOrderId,
          customerEmail: _currentUser?.email ?? "customer@zyiarah.com",
          customerPhone: _currentUser?.phone ?? "500000000",
          customerName: _currentUser?.name ?? "عميل زيارة",
        );

        if (result['success'] == true && mounted) {
          await _processUnifiedSuccess(finalOrderId, _selectedPaymentMethod);
        } else {
          throw Exception(result['error'] ?? 'فشل عملية الدفع عبر $paymentType');
        }
      }
```

واستبدله بالكامل بـ:

```dart
      } else if (_selectedPaymentMethod == 'card') {
        // Moyasar SDK — Credit Card
        setState(() => _isLoading = false); // SDK يدير loading state داخلياً
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoyasarCardScreen(
              amountSAR: totalWithVat,
              description: 'خدمة زيارة - ${widget.serviceName}',
              orderId: finalOrderId,
              onSuccess: (paymentId) async {
                setState(() => _isLoading = true);
                await _processUnifiedSuccess(finalOrderId, 'card');
              },
              onFailure: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error, style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.red.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(15),
                  ));
                }
              },
            ),
          ),
        );
        return; // MoyasarCardScreen callbacks تتولى الباقي

      } else if (_selectedPaymentMethod == 'tabby') {
        // Tabby BNPL
        final webUrl = await TabbyService.createCheckoutUrl(
          amountSAR: totalWithVat,
          customerPhone: _phoneController.text.trim().isNotEmpty
              ? _phoneController.text.trim()
              : (_currentUser?.phone ?? '0500000000'),
          customerName: _currentUser?.name ?? 'عميل زيارة',
          customerEmail: _currentUser?.email ?? 'customer@zyiarah.com',
          orderId: finalOrderId,
        );

        if (webUrl == null) {
          setState(() => _isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تابي غير متاح لهذا الطلب حالياً'),
              backgroundColor: Colors.red,
            ));
          }
          return;
        }

        setState(() => _isLoading = false);
        if (!mounted) return;

        await TabbyService.showCheckout(
          context: context,
          webUrl: webUrl,
          onSuccess: () async {
            setState(() => _isLoading = true);
            await _processUnifiedSuccess(finalOrderId, 'tabby');
          },
          onFailure: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم إلغاء الدفع عبر تابي'),
                backgroundColor: Colors.orange,
              ));
            }
          },
        );
        return;

      } else if (_selectedPaymentMethod == 'stc_pay') {
        // Moyasar STC Pay
        setState(() => _isLoading = false);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MoyasarStcScreen(
              amountSAR: totalWithVat,
              description: 'خدمة زيارة - ${widget.serviceName}',
              orderId: finalOrderId,
              onSuccess: (paymentId) async {
                setState(() => _isLoading = true);
                await _processUnifiedSuccess(finalOrderId, 'stc_pay');
              },
              onFailure: (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(error, style: GoogleFonts.tajawal()),
                    backgroundColor: Colors.red.shade800,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    margin: const EdgeInsets.all(15),
                  ));
                }
              },
            ),
          ),
        );
        return;
      }
```

### 9D: استبدال `_handleApplePayResult()`

- [ ] **الخطوة 6: حذف `_handleApplePayResult` واستبداله**

احذف الدالة `_handleApplePayResult()` بالكامل (السطر 146 إلى 256 تقريباً).

أضف بدلاً منها هذه الدالة:

```dart
  /// Apple Pay via Moyasar SDK — يُستدعى من ApplePay widget callback
  Future<void> _onApplePayResult(PaymentResponse result) async {
    if (!mounted) return;

    if (result.status == PaymentStatus.paid) {
      setState(() => _isLoading = true);
      await _processUnifiedSuccess(_pendingOrderId, 'apple_pay');
    } else {
      final msg = result.message ?? 'فشل الدفع عبر Apple Pay';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(15),
        ));
      }
    }
  }
```

### 9E: تحديث `_buildPaymentMethods()`

- [ ] **الخطوة 7: استبدال `_buildPaymentMethods()` بالكامل**

ابحث عن `Widget _buildPaymentMethods()` واستبدل الدالة بأكملها بـ:

```dart
  Widget _buildPaymentMethods() {
    final int remainingVisits = _currentUser?.visitsRemaining ?? 0;
    final String publishableKey =
        dotenv.env['MOYASAR_PUBLISHABLE_KEY'] ?? '';
    final bool moyasarReady = publishableKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('اختر طريقة الدفع',
            style: GoogleFonts.tajawal(
                fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 15),

        // --- باقة جولد ---
        if (remainingVisits > 0 && widget.contractId == null) ...[
          _buildPaymentOption(
            id: 'subscription',
            title: 'باقة زيارة جولد',
            subtitle: 'سيتم خصم زيارة واحدة (المتبقي: $remainingVisits)',
            icon: Icons.workspace_premium,
            color: Colors.amber.shade700,
          ),
          const SizedBox(height: 12),
        ],

        // --- بطاقة ائتمانية (Moyasar) ---
        if (moyasarReady)
          _buildPaymentOption(
            id: 'card',
            title: 'بطاقة فيزا / مدى',
            subtitle: 'دفع آمن عبر ميسر',
            icon: Icons.credit_card,
          ),

        // --- Apple Pay (iOS فقط — Moyasar SDK) ---
        if (Platform.isIOS && moyasarReady) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('أو ادفع بـ',
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          ApplePay(
            config: PaymentConfig(
              publishableApiKey: publishableKey,
              amount: (totalWithVat * 100).round(),
              description: 'زيارة - ${widget.serviceName}',
              metadata: {
                'order_id': widget.maintenanceId ??
                    FirebaseFirestore.instance.collection('orders').doc().id,
              },
              applePay: ApplePayConfig(
                merchantId: 'merchant.com.zyiarah.app',
                label: 'زيارة',
                manual: false,
              ),
              metadata: {'order_id': _pendingOrderId},
            ),
            onPaymentResult: _onApplePayResult,
          ),
        ],

        // --- Google Pay (Android فقط) ---
        if (!Platform.isIOS && _googlePayConfigFuture != null) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('أو ادفع بـ',
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 12),
          FutureBuilder<PaymentConfiguration>(
            future: _googlePayConfigFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return GooglePayButton(
                paymentConfiguration: snapshot.data!,
                paymentItems: [
                  PaymentItem(
                    label: 'زيارة - ${widget.serviceName}',
                    amount: totalWithVat.toStringAsFixed(2),
                    status: PaymentItemStatus.final_price,
                  ),
                ],
                type: GooglePayButtonType.pay,
                margin: EdgeInsets.zero,
                onPaymentResult: (result) async {
                  setState(() => _isLoading = true);
                  try {
                    final String orderId = widget.maintenanceId ??
                        FirebaseFirestore.instance
                            .collection('orders')
                            .doc()
                            .id;
                    await MoyasarService.processGooglePayToken(
                      googlePayToken:
                          result as Map<String, dynamic>,
                      amountSAR: totalWithVat,
                      description:
                          'خدمة زيارة - ${widget.serviceName}',
                      orderId: _pendingOrderId,
                    );
                    if (mounted) {
                      await _processUnifiedSuccess(_pendingOrderId, 'google_pay');
                    }
                  } catch (e) {
                    setState(() => _isLoading = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          e.toString().replaceAll('Exception: ', ''),
                          style: GoogleFonts.tajawal(),
                        ),
                        backgroundColor: Colors.red.shade800,
                      ));
                    }
                  }
                },
                loadingIndicator: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            },
          ),
        ],

        // --- Tamara (بدون تغيير) ---
        if (_tamaraEnabled && totalWithVat >= 100) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'tamara',
            title: 'تمارا | Tamara',
            subtitle: 'قسم فاتورتك على 4 دفعات',
            icon: Icons.timer_outlined,
            color: const Color(0xFFE5A170),
          ),
        ],

        // --- Tabby ---
        if (TabbyService.isAvailable && totalWithVat >= 100) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'tabby',
            title: 'تابي | Tabby',
            subtitle: 'اشتري الآن وادفع لاحقاً',
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF3DBEA3),
          ),
        ],

        // --- STC Pay ---
        if (moyasarReady) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'stc_pay',
            title: 'STC Pay',
            subtitle: 'الدفع عبر محفظة STC',
            icon: Icons.phone_android_rounded,
            color: const Color(0xFF6A1B9A),
          ),
        ],

        // --- الدفع عند الاستلام ---
        if (_isCodAvailableForService()) ...[
          const SizedBox(height: 12),
          _buildPaymentOption(
            id: 'cod',
            title: 'الدفع عند الاستلام',
            subtitle: 'دفع نقدي لمقدم الخدمة عند الوصول',
            icon: Icons.money,
            color: Colors.green,
          ),
        ],

        // --- محفظة زيارة ---
        const SizedBox(height: 12),
        _buildWalletPaymentOption(),
      ],
    );
  }
```

- [ ] **الخطوة 8: إضافة `import 'package:pay/pay.dart';` إذا لم يكن موجوداً**

تحقق من أن هذا الـ import موجود في أعلى الملف:
```dart
import 'package:pay/pay.dart';
```

إذا لم يكن موجوداً أضفه. (كان موجوداً قبل للـ Apple Pay — ربما بقي)

- [ ] **الخطوة 9: إضافة `import 'package:flutter_dotenv/flutter_dotenv.dart';` إذا لم يكن موجوداً**

تحقق من أن هذا الـ import موجود — أضفه إن لم يكن:
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';
```

- [ ] **الخطوة 10: التحقق من الـ analyze**

```bash
flutter analyze lib/screens/payment_summary_screen.dart
```

إذا ظهرت أخطاء لـ `PaymentResponse`، `PaymentStatus`، `ApplePay`، `ApplePayConfig`، `GooglePayButton` — تأكد من وجود:
```dart
import 'package:moyasar/moyasar.dart';
```

- [ ] **الخطوة 11: commit**

```bash
git add lib/screens/payment_summary_screen.dart
git commit -m "feat: migrate payment_summary_screen from EdfaPay to Moyasar + Tabby + Google Pay + STC Pay"
```

---

## Task 10: حذف EdfaPay

**Files:**
- Delete: `lib/services/edfapay_service.dart`

- [ ] **الخطوة 1: التحقق أن الملف لا يُستخدم في أي مكان**

```bash
grep -r "edfapay" lib/ --include="*.dart"
```

المخرج المتوقع: **لا شيء** — إذا ظهر أي ملف عدا `edfapay_service.dart` نفسه فأزل الـ import منه أولاً.

- [ ] **الخطوة 2: حذف الملف**

```bash
rm lib/services/edfapay_service.dart
```

- [ ] **الخطوة 3: التحقق النهائي**

```bash
flutter analyze lib/
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 4: commit**

```bash
git add -A
git commit -m "chore: remove EdfaPayService — fully replaced by Moyasar SDK"
```

---

## Task 11: iOS — إضافة صلاحيات Tabby

**Files:**
- Modify: `ios/Runner/Info.plist`

- [ ] **الخطوة 1: إضافة صلاحيات الكاميرا والميكروفون لـ Tabby KYC**

في `ios/Runner/Info.plist` أضف قبل آخر `</dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>تابي يحتاج إلى الكاميرا للتحقق من هوية المستخدم</string>
<key>NSMicrophoneUsageDescription</key>
<string>تابي يحتاج إلى الميكروفون للتحقق من هوية المستخدم</string>
```

- [ ] **الخطوة 2: تحديث Podfile لـ Tabby**

في `ios/Podfile`، تأكد من وجود هذا المقطع بعد `target 'Runner' do`:

```ruby
config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
  '$(inherited)',
  'PERMISSION_CAMERA=1',
  'PERMISSION_MICROPHONE=1',
]
```

إذا لم يكن موجوداً أضفه داخل `post_install do |installer|`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_MICROPHONE=1',
      ]
    end
  end
end
```

- [ ] **الخطوة 3: إعادة تثبيت Pods**

```bash
cd ios && pod install && cd ..
```

- [ ] **الخطوة 4: commit**

```bash
git add ios/Runner/Info.plist ios/Podfile
git commit -m "feat: add camera/microphone permissions for Tabby KYC on iOS"
```

---

## Task 12: Android — إضافة صلاحيات Tabby

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **الخطوة 1: إضافة صلاحيات**

في `AndroidManifest.xml` أضف قبل `<application`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAPTURE_VIDEO_OUTPUT" />
<uses-permission android:name="android.permission.CAPTURE_AUDIO_OUTPUT" />
```

- [ ] **الخطوة 2: التحقق من minSdkVersion**

في `android/app/build.gradle` تحقق أن `minSdkVersion` ≥ 21 (Tabby يتطلب 17 كحد أدنى):

```groovy
minSdkVersion 21
```

- [ ] **الخطوة 3: commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/build.gradle
git commit -m "feat: add camera/audio permissions for Tabby KYC on Android"
```

---

## Task 13: اختبار البناء

- [ ] **الخطوة 1: بناء iOS (debug)**

```bash
flutter build ios --debug --no-codesign
```

المخرج المتوقع: `Build complete.` — أي خطأ في الـ Pod أو import يجب حله قبل المتابعة.

- [ ] **الخطوة 2: بناء Android (debug)**

```bash
flutter build apk --debug
```

المخرج المتوقع: `Built build/app/outputs/flutter-apk/app-debug.apk.`

- [ ] **الخطوة 3: تشغيل flutter analyze كامل**

```bash
flutter analyze
```

المخرج المتوقع: `No issues found!`

- [ ] **الخطوة 4: push للـ remote**

```bash
git push origin main
```

---

## Task 14: إضافة المفاتيح الحقيقية والاختبار النهائي

> هذه الخطوة تتم بعد الحصول على المفاتيح من ميسر وتابي.

- [ ] **الخطوة 1: الحصول على مفاتيح ميسر**

1. سجّل دخول إلى [dashboard.moyasar.com](https://dashboard.moyasar.com)
2. اذهب إلى Settings → API Keys
3. انسخ `Publishable Key` (يبدأ بـ `pk_live_`)
4. ضعه في `.env`: `MOYASAR_PUBLISHABLE_KEY=pk_live_...`

- [ ] **الخطوة 2: الحصول على مفاتيح تابي**

1. سجّل دخول إلى [partners.tabby.ai](https://partners.tabby.ai)
2. انسخ Public Key
3. ضعه في `.env`: `TABBY_PUBLIC_KEY=pk_...`

- [ ] **الخطوة 3: اختبار بطاقة ميسر (sandbox)**

استخدم بطاقة الاختبار: `4111 1111 1111 1111` / أي تاريخ مستقبلي / أي CVV

- [ ] **الخطوة 4: اختبار Apple Pay (على جهاز iOS حقيقي)**

Apple Pay لا يعمل على المحاكي — تحتاج جهاز فعلي مع بطاقة مضافة.

- [ ] **الخطوة 5: اختبار Google Pay (على جهاز Android حقيقي)**

Google Pay لا يعمل على المحاكي — تحتاج جهاز Android مع بطاقة مضافة في Google Wallet.

---

## ملاحظات مهمة

| الموضوع | التفصيل |
|---|---|
| **Moyasar Secret Key** | يجب حفظه في Firebase Secret Manager (ليس في .env) — يُستخدم في Cloud Function `verifyMoyasarPayment` فقط |
| **Google Pay gateway** | يتطلب تأكيد من ميسر أنهم processor معتمد لـ Google Pay — إذا لم يكن، تواصل مع دعم ميسر |
| **Apple Pay domain** | `merchant.com.zyiarah.app` — تأكد أن هذا هو نفس الـ merchant ID في Apple Developer Console |
| **Tabby minimum amount** | تابي يشترط عادةً حد أدنى 300 ريال — تحقق من اتفاقيتك مع تابي وعدّل الشرط في `_buildPaymentMethods()` |
| **Tamara** | لم يُمس أي كود في TamaraService أو TamaraCheckoutScreen |
