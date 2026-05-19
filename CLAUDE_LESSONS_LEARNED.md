# CLAUDE_LESSONS_LEARNED.md
# سجل المسارات الحساسة والقواعد الصارمة — تطبيق زيارة

---

## القواعد الصارمة (Safety Protocol)

قبل أي تعديل في الكود يجب اتباع هذه المراحل بالترتيب:

### المرحلة 1 — فحص النطاق
هل الملف المستهدف يُستخدم مباشرةً من `ZyiarahUserProvider` أو `ZyiarahFirebaseService` أو `main.dart` أو `router.dart`؟
- إذا **نعم** → خطر عالٍ، ابدأ المرحلة 2 كاملة
- إذا **لا** → استخدم Grep لتحديد نقاط الاستخدام

### المرحلة 2 — Grep قبل اللمس
ابحث عن كل استخدام للدالة أو الحقل الذي ستغيّره:
```
Grep pattern=اسم_الدالة_أو_الحقل path=lib/
```
إذا كانت نقاط الاستخدام > 5 ملفات → أبلغ المستخدم أولاً قبل التنفيذ.

### المرحلة 3 — فحص أسماء حقول Firestore
أي تغيير في اسم حقل Firestore (مثل `'role'`, `'status'`, `'client_id'`) يستوجب تحديثاً في:
- قواعد Firestore Security Rules
- البيانات الموجودة (migration)
**لا تغيّر أسماء الحقول بدون تنبيه صريح للمستخدم.**

### المرحلة 4 — Non-Breaking Change Check
| التغيير | التقييم |
|---------|---------|
| إضافة حقل جديد | آمن (يحتاج default value) |
| حذف حقل موجود | خطر — تحقق من كل استخدام |
| تغيير signature دالة | تحديث كل استدعاء |
| تغيير collection name | يوقف التطبيق — ممنوع بدون إذن |

### المرحلة 5 — الإشارة الصريحة قبل الدمج
قبل أي اقتراح دمج، اكتب:
```
⚠️ Breaking Risk: [وصف الخطر]
✅ Safe if: [الشرط الذي يجعله آمناً]
🔄 Rollback plan: [كيف نرجع إذا حدث خطأ]
```

---

## المسارات الحساسة (Critical Paths)

### CP-1: ZyiarahUserProvider → Role Routing ⚡ خطر أقصى
**الملفات:** `lib/providers/user_provider.dart`, `lib/router.dart:15`

**المشكلة الأصلية:** `router.dart` كان يقرأ `FirebaseAuth.instance.currentUser` مباشرةً بدون انتظار `UserProvider`. هذا يعني مسارات دور خاطئة عند التنقل المباشر.

**الإصلاح المطبّق (2026-05-19):**
- أُضيف `GoRouterRefreshStream` يستمع لـ `authStateChanges()`
- أُضيف `refreshListenable` للـ GoRouter
- أُضيف redirect يتحقق من الدور قبل الوصول لـ `/client`, `/driver`, `/admin`

**قاعدة:** لا تمسّ `UserProvider._init()` أو `router.dart:redirect` بدون مراجعة الـ race condition بين Auth state وتحميل الدور.

---

### CP-2: ZyiarahFirebaseService Singleton ⚡ خطر أقصى
**الملف:** `lib/services/firebase_service.dart:11`

Singleton يُنشأ مرة واحدة. أي خطأ في:
- `getUserRole()` تُعيد `null` → يُجمِّد التطبيق على SplashScreen
- اسم collection Firestore → crash عند أول استخدام

**قاعدة:** دائماً تحقق من أن `getUserRole()` تُعيد `String` وليس `null` قبل أي تعديل فيها.

---

### CP-3: createOrder() — ذرية العداد والطلب ⚡ خطر عالٍ
**الملف:** `lib/services/order_service.dart:18`

**المشكلة الأصلية:** `getNextOrderNumber()` تعمل في Transaction منفصل. إذا نجح العداد وفشل `orders.add()` → فجوة في أرقام الطلبات.

**الإصلاح المطبّق (2026-05-19):**
- الآن: pre-generate `orderRef = _db.collection('orders').doc()`
- Transaction واحد يضم: قراءة العداد + تحديثه + إنشاء الطلب بـ `transaction.set()`
- `ZyiarahCounterService` محذوف من `order_service.dart` (استُبدل بمنطق مضمّن)

**⚠️ تحذير مفتوح:** نفس النمط الخطير موجود في:
- `lib/services/store_service.dart:88`
- `lib/screens/payment_summary_screen.dart:190`
- `lib/screens/maintenance_request_screen.dart`
- `lib/screens/checkout_screen.dart`
**هذه تحتاج نفس الإصلاح في جلسة منفصلة.**

---

### CP-4: Deep Links + Notification Navigation 🟡 خطر متوسط
**الملفات:** `lib/services/deep_link_service.dart`, `lib/services/notification_service.dart`

يعتمدان على `navigatorKey` العالمي من `main.dart:26`. إذا وصل deep link قبل اكتمال Widget tree → `navigatorKey.currentState == null` → المستخدم لا يصل للشاشة المطلوبة.

**قاعدة:** لا تستدعِ `navigatorKey.currentState!.pushNamed()` أو ما شابهها بدون فحص `navigatorKey.currentState != null` أولاً.

---

### CP-5: EDFAPAY — بيانات الدفع ⚡ خطر أمني
**الملف:** `lib/services/edfapay_service.dart`

**المشكلة الأصلية:** credentials مكتوبة كـ hardcoded constants داخل الكود.

**الإصلاح المطبّق (2026-05-19):**
- الآن تُقرأ من `.env` عبر `flutter_dotenv`
- مفاتيح `.env` المطلوبة: `EDFAPAY_MERCHANT_ID`, `EDFAPAY_TERMINAL_ID`, `EDFAPAY_PASSWORD_KEY`

**قاعدة:** لا تضع أي credentials في الكود مباشرةً. استخدم دائماً `.env` + `dotenv.env['KEY']`.

---

## تاريخ التغييرات

| التاريخ | الملف | التغيير | السبب |
|---------|-------|---------|-------|
| 2026-05-19 | `router.dart` | إضافة GoRouterRefreshStream + role redirect | إصلاح Race Condition CP-1 |
| 2026-05-19 | `order_service.dart` | Atomic Transaction لـ counter + order | إصلاح CP-3 |
| 2026-05-19 | `edfapay_service.dart` | قراءة credentials من .env | إصلاح CP-5 |
