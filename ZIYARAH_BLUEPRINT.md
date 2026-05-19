# ZIYARAH BLUEPRINT — العقل المدبر للمشروع

> آخر تحديث: 2026-05-19  
> الغرض: مرجع معماري شامل لأي جلسة عمل مستقبلية على مشروع Zyiarah

---

## ⚠️ قاعدة إلزامية

> **في أي جلسة عمل قادمة، يُمنع منعاً باتاً اقتراح أو تعديل أي كود قبل قراءة ملف `ZIYARAH_BLUEPRINT.md` أولاً لضمان عدم كسر المعمارية العامة للمشروع.**

---

## 1. معمارية النظام (System Architecture)

### نمط التصميم العام

المشروع يتبع نمطاً شبيهاً بـ **MVVM** مع تحويرات:

```
View (Screens)
    ↓ reads/calls
ViewModel (Providers — ChangeNotifier)
    ↓ delegates to
Repository+Model (Services)
    ↓ reads/writes
Firebase (Firestore + Auth + Storage + FCM)
```

- **لا توجد طبقة Repository منفصلة** — الـ Services تلعب دوري Repository و Business Logic معاً
- **لا يوجد BLoC أو Riverpod** — كل الحالة عبر `ChangeNotifierProvider`
- **الـ Screens يقرأون الـ Providers مباشرة** عبر `context.watch<T>()` أو `context.read<T>()`

### نقطة الدخول

```
main.dart
├── Firebase.initializeApp()
├── dotenv.load()  ← .env للـ Mapbox و EDFAPAY
├── FirebaseFirestore.instance.settings (unlimited cache)
├── Crashlytics error handlers
├── MultiProvider:
│   ├── ZyiarahUserProvider
│   ├── ZyiarahConfigProvider
│   └── ZyiarahOrderProvider
└── MaterialApp.router (GoRouter)
```

### إدارة الحالة (State Management)

| Provider | المسؤولية | يستمع إلى |
|---|---|---|
| `ZyiarahUserProvider` | المستخدم الحالي + الدور + حالة التحميل | `authStateChanges()` + stream على `users/{uid}` |
| `ZyiarahConfigProvider` | إعدادات A/B Testing | stream على `config/ux_experiments` |
| `ZyiarahOrderProvider` | طلبات المستخدم النشطة | auth state + stream على `orders` where `client_id==uid` |

### التوجيه (Routing)

```dart
// router.dart — GoRouter
refreshListenable: _GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges())

// المسارات الرئيسية:
/                    → SplashScreen
/onboarding          → OnboardingScreen
/login               → LoginScreen
/guest               → GuestDashboard
/client              → ClientDashboard  [requires role=='client']
/driver              → DriverDashboard  [requires role=='driver']
/admin               → AdminDashboardScreen [requires admin role]
/track/:orderId      → OrderTrackingScreen
```

**منطق إعادة التوجيه الحرج:**  
GoRouter يعيد التشغيل عند كل `authStateChanges()`. إذا كان `UserProvider.isLoading == true`، الـ redirect يُرجع `null` والـ `AuthWrapper` يعرض SplashScreen. هذا يمنع race condition حيث يتم توجيه المستخدم قبل اكتمال تحميل الدور.

### هيكل واجهة المستخدم

```
lib/
├── screens/         ← شاشات العميل
│   ├── client_dashboard_screen.dart    ← الصفحة الرئيسية للعميل
│   ├── payment_summary_screen.dart     ← ملخص الدفع (الأعقد)
│   ├── checkout_screen.dart            ← WebView تمارا
│   ├── invoice_screen.dart             ← فاتورة ما بعد الدفع
│   ├── maintenance_request_screen.dart ← طلب الصيانة
│   └── order_success_screen.dart       ← شاشة النجاح
├── admin/           ← شاشات الإدارة (5 أدوار)
│   ├── admin_dashboard.dart
│   ├── admin_orders_screen.dart
│   ├── admin_drivers_screen.dart
│   ├── admin_analytics_screen.dart
│   └── ...
└── widgets/         ← مكونات مشتركة
```

---

## 2. خريطة قاعدة البيانات (Firebase Data Model)

### Collections الرئيسية

```
Firestore
├── users/                    ← عملاء + مشرفون
│   └── {uid}/
│       ├── name, email, phone, role
│       ├── has_active_subscription (bool)
│       ├── visits_remaining (int)
│       ├── subscription_expiry (Timestamp)
│       ├── subscription_type (string)
│       ├── house_rules (string)
│       └── subscription_total_visits (int)
│
├── admins/                   ← مشرفون فقط
│   └── {uid}/
│       ├── role / staff_role
│       └── name, email
│
├── drivers/                  ← مقدمو الخدمة
│   └── {driverId}/
│       ├── name, phone, email
│       ├── is_available (bool)
│       ├── current_order_id (string|null)
│       ├── rating (double)
│       └── rating_count (int)
│
├── orders/                   ← طلبات التنظيف الأساسية
│   └── {orderId}/
│       ├── code (ZY-XXXX)
│       ├── client_id, client_name, client_phone, user_phone
│       ├── driver_id (string|null)
│       ├── service_type, service_name
│       ├── amount (double)
│       ├── is_paid (bool)
│       ├── status: pending → accepted → in_progress → completed | cancelled
│       ├── payment_method: cash | online | tamara
│       ├── location (GeoPoint)
│       ├── created_at (Timestamp)
│       ├── hours_contracted (int)
│       ├── service_date (Timestamp|null)
│       ├── zone_name (string)
│       ├── worker_count (int)
│       ├── coupon_code (string|null)
│       ├── discount_amount (double)
│       └── invoice_pdf_url (string|null)
│
├── maintenance_requests/     ← طلبات الصيانة
│   └── {reqId}/
│       ├── requestId, code (ZY-XXXX)
│       ├── userId, userName, userPhone
│       ├── serviceType, quantity, floor
│       ├── location (GeoPoint)
│       ├── scheduledAt (Timestamp)
│       ├── status: under_review → paid → completed
│       ├── paymentMethod (بعد التسعير)
│       ├── totalAmountPaid (double)
│       └── createdAt (Timestamp)
│
├── contracts/                ← عقود الاشتراك
│   └── {contractId}/
│       ├── status: pending_payment → active → expired
│       ├── paymentMethod
│       ├── activatedAt (Timestamp)
│       └── plan, visits, amount
│
├── store_orders/             ← طلبات المتجر (منتجات)
│   └── {orderId}/
│       ├── code (ZY-XXXX)
│       ├── client_id, client_name, client_phone
│       ├── items (List<Map>)
│       ├── total_amount (double)
│       ├── payment_method
│       └── status: pending → shipped → delivered
│
├── products/                 ← منتجات المتجر
│   └── {productId}/
│       ├── name, price, image_url, description
│       └── is_hidden (bool)
│
├── promo_codes/              ← أكواد الخصم
│   └── {codeId}/
│       ├── code (string — searchable)
│       ├── discount_type: percentage | fixed
│       ├── discount_value (double)
│       ├── uses (int — يزيد atomically)
│       └── max_uses, expiry
│
├── metadata/
│   └── order_counter/
│       └── last_id (int)    ← ← ← CRITICAL: عداد الطلبات الذري
│
├── notification_triggers/   ← قائمة انتظار Cloud Functions
│   └── {triggerId}/
│       ├── type: fcm | email
│       ├── target_uid (string|'ADMIN_BROADCAST')
│       ├── title, body (FCM)
│       └── templateId, data (email)
│
├── fcm_tokens/              ← رموز FCM للإشعارات المباشرة
│   └── {uid}/
│       ├── token, role, platform
│       └── updatedAt
│
├── audit_logs/              ← سجل التدقيق الإداري
│   └── {logId}/
│       ├── action (string)
│       ├── details (Map)
│       ├── target_id (string)
│       ├── admin_email (string)
│       └── timestamp
│
├── coverage_zones/          ← مناطق التغطية الجغرافية
│   └── {zoneId}/
│       ├── name (string)
│       ├── center (GeoPoint)
│       └── radiusKm (double)
│
├── config/
│   └── ux_experiments/      ← إعدادات A/B Testing
│       ├── checkoutButtonColor
│       └── checkoutVariantName
│
├── system_configs/
│   └── main_settings/       ← إعدادات النظام
│       └── admin_email
│
└── services/                ← قائمة الخدمات المتاحة
    └── {serviceId}/
        ├── title, subtitle, priceText, basePrice
        ├── isActive (bool)
        ├── iconName, imagePath, routeName
        └── orderIndex (int)
```

### دورة حياة الطلب (Order Lifecycle)

```
[عميل] اختار خدمة
    ↓
payment_summary_screen.dart
    ↓
┌─────────────────────────────────────┐
│  طريقة الدفع؟                        │
├─────────┬───────────┬───────────────┤
│  COD    │  Online   │    تمارا      │
│ (نقدي)  │ (EDFAPAY) │  (أقساط)      │
└────┬────┴─────┬─────┴───────┬───────┘
     │          │              │
     ↓          ↓              ↓
_processUnified  _processUnified  tamara_service
Success()       Success()      createCheckout()
                                   ↓
                            TamaraCheckoutScreen
                            (WebView)
                                   ↓
                            onPageStarted: payment-success
                                   ↓
                            _processUnifiedSuccess()
     ↓
Firestore Transaction:
  metadata/order_counter → last_id++
  orders/{orderId} → {code: ZY-XXXX, status: pending, ...}
     ↓
notifyOrderCreated() → notification_triggers
     ↓
ZatcaService.generateZatcaQrCode()
     ↓
InvoicePdfService.generateAndUploadInvoice() [خلفية]
     ↓
ZyiarahCommService.notifyNewOrder() [بريد إلكتروني]
     ↓
ZyiarahInvoiceScreen [نجاح]
     ↓
[سائق] يقبل الطلب → order.status = accepted
     ↓
[سائق] يبدأ العمل → order.status = in_progress
     ↓
[سائق] ينهي العمل → order.status = completed
     ↓
[عميل] يقيّم → driver.rating يُحدَّث atomically
```

---

## 3. شجرة الاعتماديات (Dependency Graph)

### الخدمات الأساسية (Core Services)

```
ZyiarahFirebaseService (singleton)
├── يعتمد عليه: كل الـ Screens و Services تقريباً
├── يوفر: Auth, Firestore CRUD, getUserRole()
└── CRITICAL: أي تغيير هنا يؤثر على 20+ ملف

ZyiarahOrderService
├── يعتمد على: ZyiarahFirebaseService, ZyiarahCounterService
├── يعتمد عليه: ClientDashboard, DriverDashboard, AdminOrders
└── CRITICAL: يحتوي على Transaction الأكثر تعقيداً في المشروع

ZyiarahNotificationTriggerService
├── يعتمد على: FirebaseFirestore مباشرة
├── يعتمد عليه: payment_summary_screen, checkout_screen,
│              maintenance_request_screen, order_service
└── WARNING: الإخفاق هنا لا يوقف الطلب (non-fatal by design)

ZyiarahCommService
├── يعتمد على: FirebaseFirestore (notification_triggers)
├── يعتمد عليه: نفس الملفات أعلاه
└── WARNING: نفس المبدأ — non-fatal

ZatcaService (static)
├── لا يعتمد على أي خدمة
├── يعتمد عليه: payment_summary_screen, checkout_screen
└── PURE: دالة رياضية بحتة (TLV encoding)

InvoicePdfService (static)
├── يعتمد على: FirebaseFirestore, FirebaseStorage
├── يعتمد عليه: payment_summary_screen, checkout_screen
└── WARNING: يعمل في الخلفية (.then) — الإخفاق لا يكسر التدفق
```

### الملفات الأكثر خطورة (Most Dangerous Files)

| الملف | الخطورة | السبب |
|---|---|---|
| `lib/providers/user_provider.dart` | 🔴 عالية جداً | أي خطأ → كل المستخدمين غير موجَّهين |
| `lib/router.dart` | 🔴 عالية جداً | أي خطأ → التطبيق لا يعمل من الأساس |
| `lib/services/firebase_service.dart` | 🔴 عالية جداً | Singleton مشترك في 20+ ملف |
| `lib/services/order_service.dart` | 🔴 عالية جداً | Transaction معقد — الخطأ = ضياع طلبات |
| `lib/screens/payment_summary_screen.dart` | 🟠 عالية | أعقد شاشة — 4 مسارات دفع × 3 أنواع طلبات |
| `lib/screens/checkout_screen.dart` | 🟠 عالية | WebView + Transaction + navigation |
| `metadata/order_counter` (Firestore) | 🟠 عالية | بيانات — تلف العداد = أكواد مكررة |
| `lib/services/notification_trigger_service.dart` | 🟡 متوسطة | يؤثر على تجربة المستخدم لكن غير fatal |

---

## 4. المنطق التجاري الأساسي (Core Business Logic)

### محرك الحجز (Booking Engine)

```
1. العميل يختار خدمة من services/ collection (Firestore-driven)
2. يحدد: التاريخ، الوقت، عدد العمال، ساعات العمل
3. ZyiarahOrderService.checkHourlySlotAvailability():
   - يقرأ كل السائقين المتاحين
   - يقرأ الطلبات المتعارضة
   - يُرجع قائمة السائقين المتاحين للوقت المطلوب
4. إذا متاح → يكمل للدفع
5. payment_summary_screen يحسب:
   - السعر الأساسي × الساعات × العمال
   - خصم الكوبون (إن وجد)
   - المبلغ النهائي
```

### تدفق بوابات الدفع (Payment Gateway Flow)

```
┌────────────────────────────────────────────────────────┐
│                   4 طرق دفع                            │
├────────────┬──────────────┬──────────────┬─────────────┤
│   COD      │  EDFAPAY     │   تمارا      │  مجاني       │
│ (نقداً)    │ (بطاقة)      │ (أقساط)      │ (اشتراك)    │
├────────────┼──────────────┼──────────────┼─────────────┤
│ لا انتظار  │ TODO: SDK    │ Cloud Fn     │ visits--    │
│ مباشر →   │ غير مفعّل   │ createTamara │             │
│ Firestore  │ حتى الآن    │ Checkout()   │             │
│            │              │ → WebView    │             │
│            │              │ → onSuccess  │             │
└────────────┴──────────────┴──────────────┴─────────────┘
     ↓              ↓              ↓              ↓
     └──────────────┴──────────────┴──────────────┘
                           ↓
              _processUnifiedSuccess()
                           ↓
          Firestore Transaction (atomic):
          - metadata/order_counter → last_id++
          - orders/{id} → {code: ZY-XXXX, ...}
```

### منطق الاشتراكات (Subscription Logic)

```
users/{uid}/
  has_active_subscription: true
  visits_remaining: N
  subscription_type: 'monthly' | 'annual'
  subscription_expiry: Timestamp

عند الدفع المجاني:
  visits_remaining-- (atomic Transaction)
  
عند تفعيل عقد جديد (contracts):
  users/{uid}/visits_remaining += planVisits
  contracts/{id}/status = 'active'
```

### نظام إشعارات (Notification System)

```
App → notification_triggers/{id} → Cloud Functions → FCM/Email

أنواع المستقبلين:
1. target_uid = '{uid}'           → مستخدم محدد
2. target_uid = 'ADMIN_BROADCAST' → كل المشرفين
3. FCM Topics: all_users, clients, drivers, admins

مراحل الإشعار في دورة الطلب:
- إنشاء طلب → notifyOrderCreated() → drivers topic + admin
- قبول سائق → notifyDriverOfAssignment() → السائق
- تغيير حالة → notifyClientOfDriverStatus() → العميل
- تقييم منخفض → notifyAdminOfLowRating() → admin email
```

### قواعد الأدوار (Role System)

```
getUserRole(uid, {phone}) — 3 مراحل:
  1. admins/{uid} → staff_role أو role
     (super_admin, orders_manager, accountant_admin, marketing_admin)
  2. users/{uid} → role
     ('client')
  3. drivers where phone == X → register in users → 'driver'

AuthWrapper:
  role == 'client' → ClientDashboard
  role == 'driver' → DriverDashboard
  role in adminRoles → AdminDashboardScreen
```

### نظام الفواتير والضرائب (ZATCA)

```
بعد كل دفع ناجح:
1. ZatcaService.generateZatcaQrCode():
   - يحسب VAT: amount - (amount / 1.15)
   - يُنشئ TLV Base64 مع:
     * اسم المنشأة: "مؤسسة معاذ يحي محمد المالكي"
     * رقم ضريبي: 310885360200003
     * السجل التجاري: 7030376342

2. InvoicePdfService.generateAndUploadInvoice():
   - يولّد PDF بالعربي (arabic_reshaper + bidi)
   - يرفعه على Firebase Storage
   - يحفظ الرابط في orders/{id}/invoice_pdf_url
```

---

## 5. بروتوكول العمل المستقبلي (Future Workflow Protocol)

### الخطوات الإلزامية قبل أي تعديل

```
المرحلة 1 — التحقق من النطاق:
□ اقرأ ZIYARAH_BLUEPRINT.md (هذا الملف)
□ اقرأ CLAUDE_LESSONS_LEARNED.md
□ حدد الملفات المتأثرة بالتغيير
□ تحقق من Dependency Graph — هل التغيير يمس ملفاً خطيراً؟

المرحلة 2 — تحليل المخاطر:
□ هل التغيير يمس Firestore Transaction؟ → اتبع النمط الذري الحالي
□ هل التغيير يمس التوجيه (router.dart)؟ → اختبر كل الأدوار
□ هل التغيير يمس Firebase Singleton؟ → تأكد من backward compatibility
□ هل التغيير يُنشئ طلباً/عقداً/صيانةً؟ → يجب استخدام Transaction الذري

المرحلة 3 — التنفيذ:
□ لا تُضف أي counter increment خارج Firestore Transaction
□ لا تكسر واجهة أي Service تُستخدم في 3+ ملفات
□ لا تُعدّل UserProvider أو router.dart بدون اختبار كل الأدوار

المرحلة 4 — التحقق:
□ flutter analyze → صفر errors
□ اختبر مسار الدفع الكامل (COD على الأقل)
□ اختبر تسجيل دخول بكل دور: client, driver, admin

المرحلة 5 — النشر:
□ git commit + git push
□ firebase deploy (functions إذا تأثرت)
□ تحقق من Crashlytics بعد 24 ساعة
```

### الأنماط المُعتمدة (Approved Patterns)

```dart
// ✅ إنشاء أي طلب — النمط الذري الإلزامي
final docRef = _db.collection('COLLECTION').doc();
final counterRef = _db.collection('metadata').doc('order_counter');
String orderCode = '';
await _db.runTransaction((transaction) async {
  final counterSnap = await transaction.get(counterRef);
  final lastId = counterSnap.exists
      ? ((counterSnap.data()?['last_id'] as num?)?.toInt() ?? 100)
      : 100;
  final nextId = lastId + 1;
  orderCode = ZyiarahOrderUtil.formatSmartCode(nextId);
  if (counterSnap.exists) {
    transaction.update(counterRef, {'last_id': nextId});
  } else {
    transaction.set(counterRef, {'last_id': nextId});
  }
  transaction.set(docRef, { /* all fields */ });
});

// ✅ الإشعارات — دائماً non-fatal
ZyiarahNotificationTriggerService().notifyXxx(...).catchError((_) {});

// ✅ البريد الإلكتروني — دائماً non-fatal
ZyiarahCommService().notifyNewOrder({...}).catchError((_) {});

// ✅ الفاتورة — دائماً في الخلفية
InvoicePdfService.generateAndUploadInvoice(...).then((url) {
  if (url != null) _db.collection('orders').doc(id).update({'invoice_pdf_url': url});
});

// ❌ ممنوع — counter منفصل عن إنشاء الوثيقة
final code = await ZyiarahCounterService().getNextOrderNumber(); // ❌
await _db.collection('orders').add({...}); // ❌
```

### الملفات المحمية (Protected Files)

التالية تستدعي مراجعة مزدوجة قبل أي تعديل:

| الملف | السبب |
|---|---|
| `lib/router.dart` | قلب التطبيق — خطأ يوقف كل المستخدمين |
| `lib/providers/user_provider.dart` | يتحكم في تجربة auth كاملة |
| `lib/services/firebase_service.dart` | Singleton مشترك في كل المشروع |
| `lib/services/order_service.dart` | يحتوي Transactions الحيوية |
| `lib/screens/payment_summary_screen.dart` | أعقد شاشة — 4×3 مسارات |
| `firestore.rules` | الأمان — أي خطأ = ثغرة أمنية |
| `functions/index.js` | FCM + Email — يؤثر على تجربة المستخدم |

---

## 6. ملخص سريع (Quick Reference)

### أكواد الطلبات
- الصيغة: `ZY-XXXX` (مثال: `ZY-0101`)
- الدالة: `ZyiarahOrderUtil.formatSmartCode(int id)`
- العداد: `metadata/order_counter/last_id` — يُزاد دائماً atomically

### بيئات العمل
- `.env` — Mapbox token + EDFAPAY credentials
- `functions/` — Cloud Functions (Node.js v22)
- `admin_panel/` — React 19 + TypeScript (Vite)
- Firebase Project: `zyiarah-app`

### أوامر مهمة
```bash
flutter analyze          # تحقق من الكود
flutter pub get          # تثبيت التبعيات
cd ios && pod install    # مزامنة iOS بعد pubspec
firebase deploy          # نشر Cloud Functions
```

---

*هذا الملف تم إنشاؤه تلقائياً بعد تحليل شامل لمجلد `lib/` بالكامل. يجب تحديثه عند أي تغيير معماري جوهري.*
