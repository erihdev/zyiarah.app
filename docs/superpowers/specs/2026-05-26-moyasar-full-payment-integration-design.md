# تصميم: تكامل ميسر الكامل للمدفوعات

**التاريخ:** 2026-05-26  
**المشروع:** Zyiarah — تطبيق خدمات تنظيف  
**الحالة:** مُعتمد للتنفيذ

---

## ملخص

استبدال EdfaPay الكامل بمنظومة دفع موحدة تعتمد على:
- **Moyasar Flutter SDK** (v3.0.3) → بطاقة + Apple Pay + STC Pay
- **Tabby SDK** (v1.11.0) → تقسيط Tabby
- **TamaraService الحالية** → تبقى كما هي بدون تغيير
- **Google Pay** → عبر `pay` package + Moyasar API (Android)

---

## الحالة الحالية

| الملف | الدور | القرار |
|---|---|---|
| `lib/services/edfapay_service.dart` | بوابة الدفع الرئيسية | **يُحذف** |
| `lib/services/moyasar_service.dart` | Apple Pay فقط (stub) | **يُعاد كتابته** |
| `lib/services/tamara_service.dart` | تمارا | **يبقى بدون تغيير** |
| `lib/screens/payment_summary_screen.dart` | شاشة الدفع | **يُحدَّث** |

---

## طرق الدفع بعد التكامل

| طريقة الدفع | iOS | Android | المكتبة |
|---|---|---|---|
| بطاقة (فيزا / مدى / ماستر / UnionPay) | ✅ | ✅ | Moyasar Flutter SDK |
| Apple Pay | ✅ | ❌ | Moyasar Flutter SDK |
| Google Pay | ❌ | ✅ | `pay` package + Moyasar API |
| Tamara (تقسيط) | ✅ | ✅ | TamaraService الحالية |
| Tabby (تقسيط) | ✅ | ✅ | tabby_flutter_inapp_sdk |
| STC Pay | ✅ | ✅ | Moyasar Flutter SDK |
| محفظة زيارة | ✅ | ✅ | موجود — لا تغيير |
| الدفع عند الاستلام | ✅ | ✅ | موجود — لا تغيير |
| باقة زيارة جولد (اشتراك) | ✅ | ✅ | موجود — لا تغيير |

---

## المتغيرات البيئية المطلوبة

```
# .env
MOYASAR_PUBLISHABLE_KEY=pk_live_xxxxxxxxxxxx
TABBY_PUBLIC_KEY=pk_xxxxxxxxxxxxxxxxxxxxxxxx

# Firebase Functions (Secret Manager)
MOYASAR_SECRET_KEY=sk_live_xxxxxxxxxxxx
```

> ملاحظة: المفاتيح تُضاف لاحقاً عند الحصول عليها من لوحة تحكم ميسر وتابي.

---

## الحزم المطلوبة

### إضافة إلى `pubspec.yaml`
```yaml
moyasar: ^3.0.3
tabby_flutter_inapp_sdk: ^1.11.0
```

### حزم موجودة وتُستخدم
```yaml
pay: ^3.3.0          # Google Pay — موجود
webview_flutter: ^4.10.1  # موجود
http: ^1.3.0          # موجود
```

### حزم تُحذف
- لا توجد حزمة EdfaPay مُثبَّتة في pubspec (كان EdfaPay يعمل عبر http مباشرة)

---

## معمارية المكونات

### 1. `lib/services/moyasar_service.dart` (يُعاد كتابته)

```dart
class MoyasarService {
  // Moyasar publishable key من .env
  // ثلاث طرق رئيسية:

  static Future<String> processGooglePayToken({...});
  // إرسال Google Pay token إلى Moyasar API مباشرة
  // يُعيد payment ID عند النجاح — يرمي Exception عند الفشل

  static Future<bool> verifyPayment(String paymentId, String orderId);
  // التحقق السيرفر عبر Cloud Function — موجود، يبقى
}
```

دفع البطاقة وApple Pay وSTC Pay → يتولاها **Moyasar Flutter SDK** مباشرة (لا تحتاج كود خاص في الـ service).

### 2. `lib/services/tabby_service.dart` (جديد)

```dart
class TabbyService {
  static Future<void> initialize();
  // TabbySDK().setup(withApiKey: TABBY_PUBLIC_KEY)

  static Future<String?> createCheckoutSession({
    required double amount,
    required String customerPhone,
    required String customerName,
    required String customerEmail,
  });
  // يُعيد webUrl أو null إذا فشل / رُفض

  static Future<void> showCheckout({
    required BuildContext context,
    required String webUrl,
    required VoidCallback onSuccess,
    required VoidCallback onFailure,
  });
  // TabbyWebView.showWebView(...)
}
```

### 3. `lib/screens/moyasar_payment_screen.dart` (جديد)

شاشة تحتوي على Moyasar SDK widgets:
- `CreditCard(config: ..., onPaymentResult: ...)` — بطاقة
- `ApplePay(config: ..., onPaymentResult: ...)` — iOS فقط
- `SamsungPay` / STC Pay — حسب الجهاز

الشاشة تستقبل:
- `PaymentConfig` المُعدّة
- callback `onSuccess(String paymentId)`
- callback `onFailure(String error)`

عند النجاح: تُغلق الشاشة وتُعيد payment ID للـ `PaymentSummaryScreen` ليكمل إنشاء الطلب.

### 4. `lib/screens/payment_summary_screen.dart` (يُحدَّث)

**التغييرات:**
- حذف `EdfaPayService` — import وإنشاء المتغير
- إضافة `TabbyService` و `MoyasarService`
- `_selectedPaymentMethod` يضيف: `'tabby'`, `'stc_pay'`, `'google_pay'`
- `_handlePayment()`: 
  - `'card'` → يفتح `MoyasarPaymentScreen`
  - `'tabby'` → يستدعي `TabbyService.createCheckoutSession()`
  - `'google_pay'` → يُفعّل Google Pay عبر `pay` package
  - `'tamara'` → بدون تغيير
- `_buildPaymentMethods()`: يضيف بطاقات Tabby و Google Pay (Android) وSTC Pay

---

## تدفق الدفع لكل طريقة

### بطاقة (فيزا / مدى)
```
PaymentSummaryScreen
  → يفتح MoyasarPaymentScreen
    → Moyasar SDK يعرض نموذج البطاقة
    → SDK يتولى 3DS تلقائياً (WebView داخلي)
    → onPaymentResult: paid → يُغلق ويُعيد paymentId
  → _processUnifiedSuccess(orderId, 'card')
```

### Apple Pay (iOS فقط)
```
PaymentSummaryScreen
  → MoyasarPaymentScreen يعرض ApplePay widget
    → Native Apple Pay sheet
    → SDK يرسل token إلى Moyasar
    → onPaymentResult: paid
  → _processUnifiedSuccess(orderId, 'apple_pay')
```

### Google Pay (Android فقط)
```
PaymentSummaryScreen
  → GooglePayButton (pay package)
    → Native Google Pay sheet
    → Token يُرسل إلى MoyasarService.processGooglePayToken()
    → Returns paymentId
  → _processUnifiedSuccess(orderId, 'google_pay')
```

### Tabby
```
PaymentSummaryScreen
  → TabbyService.createCheckoutSession()
    → إذا rejected: SnackBar "تابي غير متاح لهذا الطلب"
    → إذا متاح: TabbyService.showCheckout()
      → WebView داخل التطبيق
      → onResult: authorized → _processUnifiedSuccess(orderId, 'tabby')
      → onResult: rejected/expired → SnackBar خطأ
```

### Tamara (بدون تغيير)
```
PaymentSummaryScreen
  → TamaraService.createCheckoutSession() — موجود
  → TamaraCheckoutScreen (WebView) — موجود
```

### STC Pay
```
PaymentSummaryScreen
  → MoyasarPaymentScreen مع عرض STCPay widget
    → SDK يطلب رقم الجوال
    → OTP يصل للمستخدم
    → onPaymentResult: paid
  → _processUnifiedSuccess(orderId, 'stc_pay')
```

---

## معالجة الأخطاء

| الحالة | السلوك |
|---|---|
| مفتاح Moyasar غير موجود | SnackBar: "خدمة الدفع غير مُهيأة" |
| رفض البطاقة | Moyasar SDK يعرض رسالة الخطأ تلقائياً |
| Tabby session rejected | SnackBar: "تابي غير متاح لهذا الطلب حالياً" |
| Google Pay غير متاح | يُخفى الزر تلقائياً (pay package يتحقق) |
| فشل الشبكة | Exception تُعالج في GlobalErrorHandler |

---

## ملفات تُحذف

- `lib/services/edfapay_service.dart`

---

## ملفات تُنشأ

| الملف | الوصف |
|---|---|
| `lib/services/tabby_service.dart` | wrapper لـ Tabby SDK |
| `lib/screens/moyasar_payment_screen.dart` | شاشة دفع Moyasar (بطاقة + Apple Pay + STC) |
| `assets/google_pay_config.json` | إعدادات Google Pay |

---

## ملفات تُعدَّل

| الملف | التغييرات |
|---|---|
| `pubspec.yaml` | إضافة moyasar + tabby_flutter_inapp_sdk |
| `.env` | إضافة MOYASAR_PUBLISHABLE_KEY + TABBY_PUBLIC_KEY |
| `lib/services/moyasar_service.dart` | إعادة كتابة — Google Pay token فقط |
| `lib/screens/payment_summary_screen.dart` | حذف EdfaPay، إضافة Tabby + Google Pay + STC Pay |
| `lib/main.dart` | إضافة TabbySDK.setup() عند التهيئة |

---

## ترتيب التنفيذ

1. تحديث `pubspec.yaml` وتشغيل `flutter pub get`
2. إضافة placeholders في `.env`
3. حذف `edfapay_service.dart`
4. إعادة كتابة `moyasar_service.dart`
5. إنشاء `tabby_service.dart`
6. إنشاء `moyasar_payment_screen.dart`
7. إنشاء `assets/google_pay_config.json`
8. تحديث `payment_summary_screen.dart`
9. تحديث `main.dart` لتهيئة Tabby SDK
10. اختبار على iOS Simulator (Apple Pay + بطاقة)
11. اختبار على Android Emulator (Google Pay + بطاقة)
