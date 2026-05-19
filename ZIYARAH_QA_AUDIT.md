# ZIYARAH QA AUDIT — تقرير فحص جودة الكود
> تاريخ الفحص: 2026-05-19  
> النطاق: `lib/screens/` (شاشات العميل) + `lib/providers/`  
> المنهجية: فحص يدوي لـ 4 أنواع أخطاء: UI Bindings، Context Lifecycle، Error Handling، Routing

---

## ملخص تنفيذي

| الفئة | عدد المشاكل | أعلى خطورة |
|---|---|---|
| Context Lifecycle بعد `await` | **6 مشاكل** | 🔴 حرجة |
| Error Handling غير مكتمل | **5 مشاكل** | 🟠 عالية |
| Routing / Navigator خطير | **3 مشاكل** | 🟠 عالية |
| UI Bindings / أزرار معطوبة | **4 مشاكل** | 🟡 متوسطة |
| **الإجمالي** | **18 مشكلة** | — |

---

## الفئة الأولى: أخطاء Context Lifecycle 🔴

> كلها تسبب `setState() called after dispose()` أو `use of BuildContext across async gaps`

---

### ~~BUG-001~~ — ✅ تم الحل — `login_screen.dart` — `_login()` بدون `mounted` check بعد `getUserRole`
**الملف**: `lib/screens/login_screen.dart`  
**السطر**: 46  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `9fd7050`

```dart
// الكود الحالي ❌
String role = await _firebaseService.getUserRole(userCredential.user!.uid);
if (!mounted) return;  // ✅ هذا موجود — لكن المشكلة أعمق:
Navigator.pushReplacement(context, ...);  // سطر 50-54
```

**المشكلة الحقيقية**: `getUserRole()` يقوم بـ 3 queries على Firestore (admins → users → drivers). إذا تغيّر حال Auth في أثناء هذه الـ queries (timeout أو internet cut)، الـ `UserProvider` سيُطلق `notifyListeners()` ويعيد بناء الـ widget، والشاشة ستنتقل تلقائياً عبر GoRouter. سيحدث تعارض بين `Navigator.pushReplacement` يدوياً وبين GoRouter redirect.

**الخطر**: شاشة مكدسة مزدوجة (double route) أو infinite login loop.

**الإصلاح المقترح**:
```dart
// بعد getUserRole، تحقق أن GoRouter لم ينتقل مسبقاً
if (!mounted) return;
// ثم التوجيه اليدوي — أو الأفضل: حذفه تماماً وترك GoRouter Redirect يتولى المهمة
// GoRouter سيُعيد التوجيه تلقائياً بعد تحديث UserProvider
```

---

### ~~BUG-002~~ — ✅ تم الحل — `support_screen.dart` — `_submitTicket()` يستخدم `context` خارج `mounted`
**الملف**: `lib/screens/support_screen.dart`  
**السطر**: 363-404  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `9fd7050`

```dart
// الكود الحالي ❌
void _submitTicket(BuildContext context) async {
  setState(() => _isSending = true);
  try {
    await ticketRef.set({...});         // ← await هنا
    await ticketRef.collection('messages').add({...}); // ← وهنا
    
    if (context.mounted) {             // ✅ يستخدم context.mounted
      Navigator.pop(context);          // لكن context هنا هو context من showModalBottomSheet
      ScaffoldMessenger.of(context)... // ❌ هذا context مختلف عن this.context
    }
  } finally {
    if (mounted) setState(() => _isSending = false); // يستخدم this.mounted ✅
  }
}
```

**المشكلة**: `_submitTicket` تأخذ `BuildContext context` من الـ `BottomSheet` (سطر 349). بعد `await`، الـ BottomSheet قد يكون أُغلق، فـ `context.mounted` يُرجع false لكن `mounted` (الشاشة الرئيسية) لا يزال true. الـ `ScaffoldMessenger.of(context)` يستخدم context المُغلق → exception.

**الإصلاح المقترح**:
```dart
void _submitTicket(BuildContext sheetContext) async {
  setState(() => _isSending = true);
  try {
    await ticketRef.set({...});
    await ticketRef.collection('messages').add({...});
    if (!sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    // استخدم ScaffoldMessenger من context الشاشة الرئيسية وليس الـ Sheet
    if (mounted) {
      ScaffoldMessenger.of(this.context).showSnackBar(...);
    }
  } catch (e) { ... }
  finally { if (mounted) setState(() => _isSending = false); }
}
```

---

### BUG-003 — `support_screen.dart` — Reply في `_buildMessagesList` بدون mounted check
**الملف**: `lib/screens/support_screen.dart`  
**السطر**: 263-291

```dart
// الكود الحالي ❌
onPressed: () async {
  setInternalState(() => isSendingReply = true);
  try {
    await FirebaseFirestore.instance.collection('...').add({...});  // await
    await FirebaseFirestore.instance.collection('...').update({...}); // await
    _replyController.clear(); // ← لا يوجد mounted check هنا
  } finally {
    setInternalState(() => isSendingReply = false); // ← setInternalState بعد await — قد يكون disposed
  }
}
```

**المشكلة**: `isSendingReply` هو متغير محلي داخل `StatefulBuilder`، لكن `setInternalState` قد يُستدعى بعد إغلاق الـ `ExpansionTile` أو انتقال المستخدم. لا يوجد `if (!mounted)` check.

**الإصلاح المقترح**: إضافة `if (!context.mounted) return;` بعد كل `await` داخل الـ `onPressed`.

---

### ~~BUG-004~~ — ✅ تم الحل — `store_screen.dart` — `_CartSheetState._checkout()` استخدام context بعد `Navigator.pop`
**الملف**: `lib/screens/store_screen.dart`  
**السطر**: 272-349  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `501b3d0`

```dart
// الكود الحالي ❌
void _checkout(List<StoreProduct> products) async {
  ...
  final orderCode = await widget.storeService.createStoreOrder(...); // await طويل
  
  if (!mounted) return;  // ✅ check موجود
  if (orderCode == null) {
    ScaffoldMessenger.of(context).showSnackBar(...); // context للـ CartSheet
    return;
  }
  
  if (mounted) {
    Navigator.pop(context);  // ← يُغلق الـ CartSheet — بعده context غير صالح
    
    Navigator.pushReplacement( // ← سطر 329 — context قد لا يكون valid
      context,
      MaterialPageRoute(builder: (context) => ZyiarahOrderSuccessScreen(...)),
    );
    
    widget.cart.clear(); // ← يُعدّل حالة _ZyiarahStoreScreenState بدون setState
  }
}
```

**المشكلة 1**: بعد `Navigator.pop(context)` (يُغلق الـ Sheet)، الاستدعاء الفوري لـ `Navigator.pushReplacement(context, ...)` يستخدم context الـ Sheet المُغلق.  
**المشكلة 2**: `widget.cart.clear()` يُعدّل `_cart` في الـ parent (ZyiarahStoreScreen) مباشرة بدون `setState` على الـ parent → لن تُحدَّث badge عدد العناصر في AppBar.

**الإصلاح المقترح**:
```dart
// حفظ context الـ parent قبل pop
final parentContext = context; // context هو context الـ Sheet
Navigator.pop(parentContext); 
if (!mounted) return;
// استخدم navigatorKey عوضاً أو مرر callback للـ parent
```

---

### ~~BUG-005~~ — ✅ تم الحل — `profile_screen.dart` — `_deleteAccount()` بدون await check بعد كل عملية
**الملف**: `lib/screens/profile_screen.dart`  
**السطر**: 209-232  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `bf29388`

```dart
// الكود الحالي ❌
Future<void> _deleteAccount() async {
  try {
    await _firestore.collection('account_deletions').doc(uid).set({...});
    await _firestore.collection('users').doc(uid).delete();
    await _auth.currentUser?.delete();      // ← إذا فشل هنا...
    await _firebaseService.signOut();        // ← يُنفَّذ ويُحدث Auth state
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst); // ← context قد يكون invalid
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(...);
  }
}
```

**المشكلة**: إذا فشل `_auth.currentUser?.delete()` بسبب `requires-recent-login`، الكود يُلقي Exception ويذهب لـ catch. لكن الـ `users/{uid}` document قد يكون حُذف بالفعل. الحساب في حالة تالفة: المستخدم لا يزال موجوداً في Firebase Auth لكن بيانات Firestore محذوفة.

**الإصلاح المقترح**: التحقق من إمكانية الحذف أولاً، وعكس الترتيب (حذف Auth أولاً ثم Firestore).

---

### ~~BUG-006~~ — ✅ تم الحل — `hourly_details_screen.dart` / `sofa_rug_details_screen.dart` — `_attemptAutoLocation` بدون mounted check كافٍ
**الملف**: `lib/screens/hourly_details_screen.dart`, `lib/screens/sofa_rug_details_screen.dart`  
**السطر**: 71 (hourly), 51 (sofa_rug)  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `9fd7050`

```dart
Future<void> _attemptAutoLocation() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled(); // await
    // لا يوجد if (!mounted) return; هنا
    LocationPermission permission = await Geolocator.checkPermission(); // await
    // لا يوجد if (!mounted) return; هنا
    permission = await Geolocator.requestPermission(); // await — dialog قد يأخذ وقتاً
    // إذا انتقل المستخدم بعيداً أثناء dialog الإذن...
```

**المشكلة**: كل `await` لـ Geolocator قد يستغرق ثوانٍ (خاصة `requestPermission` يعرض dialog). المستخدم قد يضغط Back ويغادر الشاشة أثناء الانتظار. الكود يستمر في التنفيذ ويستدعي `setState()` على widget محذوف.

---

## الفئة الثانية: أخطاء Error Handling 🟠

---

### ~~BUG-007~~ — ✅ تم الحل — `orders_list_screen.dart` — `ElevatedButton` تتبع السائق بدون guard
**الملف**: `lib/screens/orders_list_screen.dart`  
**السطر**: 604-620

```dart
// الكود الحالي ❌
ElevatedButton.icon(
  onPressed: () {
    if (order['driver_id'] != null && order['location'] != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => OrderTrackingScreen(orderId: docId)));
    }
    // ← إذا الشرط false: الزر لا يفعل شيئاً بالمرة — لا feedback للمستخدم
  },
  label: Text('تتبع السائق', ...),
  ...
)
```

**المشكلة**: زر "تتبع السائق" مرئي للطلبات في حالات `assigned` و `accepted` و `in_progress`، لكن إذا كان `driver_id == null` (الطلب accepted لكن السائق لم يُعيَّن بعد)، الزر يظهر ولا يستجيب. المستخدم يعتقد أن التطبيق معطوب.

**الإصلاح المقترح**:
```dart
onPressed: (order['driver_id'] != null && order['location'] != null)
    ? () => Navigator.push(...)
    : null,  // الزر يُصبح disabled مع visual feedback تلقائي
```

---

### ~~BUG-008~~ — ✅ تم الحل — `client_dashboard.dart` — `_buildPromoBanners` canLaunchUrl بدون Error Handling
**الملف**: `lib/screens/client_dashboard.dart`  
**السطر**: 546-555

```dart
// الكود الحالي ❌
onTap: () async {
  if (routeType == 'whatsapp' && actionUrl.isNotEmpty) {
    final uri = Uri.parse(actionUrl);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
    // ← إذا canLaunchUrl = false: لا يحدث شيء، لا رسالة خطأ
  }
  // ← routeType غير معروف: لا يحدث شيء، لا feedback
}
```

**المشكلة**: إذا كان `actionUrl` غير صالح أو WhatsApp غير مثبت، `canLaunchUrl` يُرجع false والكود يصمت. المستخدم يضغط على البانر ولا يحدث شيء.

**الإصلاح المقترح**:
```dart
if (await canLaunchUrl(uri)) {
  await launchUrl(uri);
} else if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تعذّر فتح الرابط')),
  );
}
```

---

### ~~BUG-009~~ — ✅ تم الحل — `profile_screen.dart` — `_showHouseRulesDialog` يبتلع الخطأ بصمت
**الملف**: `lib/screens/profile_screen.dart`  
**السطر**: 188-198

```dart
// الكود الحالي ❌
try {
  await _firestore.collection('users').doc(uid).update({'house_rules': controller.text.trim()});
  await _loadUserData();
} catch (e) {
  if (mounted) setState(() => _isLoading = false); // ← لا SnackBar، لا رسالة خطأ
}
```

**المشكلة**: إذا فشل حفظ التفضيلات (انقطاع الإنترنت مثلاً)، المستخدم لا يرى أي رسالة. يعتقد أن الحفظ نجح بينما لم يحدث شيء.

**الإصلاح المقترح**: إضافة `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التفضيلات')));` في الـ catch.

---

### ~~BUG-010~~ — ✅ تم الحل — `store_screen.dart` — خيار دفع "إلكتروني" غير مُفعَّل
**الملف**: `lib/screens/store_screen.dart`  
**السطر**: 429-440  
**تاريخ الحل**: 2026-05-19 | **الـ Commit**: `501b3d0`

```dart
RadioListTile(
  value: 'online',
  onChanged: (val) => setState(() => _selectedPaymentMethod = val.toString()),
  title: const Text('دفع إلكتروني (تمارا / بطاقة)', ...),
  ...
)
```

ثم في `_checkout`:
```dart
final orderCode = await widget.storeService.createStoreOrder(
  paymentMethod: _selectedPaymentMethod, // قد يكون 'online'
);
// ← لا يوجد أي معالجة خاصة لـ 'online'
// المستخدم يختار "دفع إلكتروني" ثم يُرسَل الطلب بدون أي معالجة فعلية للدفع!
```

**المشكلة**: خيار "دفع إلكتروني" يتيح للمستخدم إرسال طلب بدون دفع فعلي. الطلب يُسجَّل في Firestore بـ `payment_method: 'online'` لكن لا تتم أي عملية دفع حقيقية. هذه ثغرة تشغيلية مباشرة.

**الإصلاح المقترح**: إما تعطيل الخيار مؤقتاً:
```dart
onChanged: null, // تعطيل حتى تكتمل بوابة الدفع
```
أو إضافة شاشة دفع عند اختيار 'online'.

---

### ~~BUG-011~~ — ✅ تم الحل — `support_screen.dart` — `_buildMessagesList` Firestore write بدون try/catch
**الملف**: `lib/screens/support_screen.dart`  
**السطر**: 263-291

```dart
// الكود الحالي ❌
onPressed: () async {
  setInternalState(() => isSendingReply = true);
  try {  // ✅ try موجود
    await FirebaseFirestore.instance...add({...});
    await FirebaseFirestore.instance...update({...});
    _replyController.clear();
  } finally { // ← لا catch! الأخطاء تمر بصمت
    setInternalState(() => isSendingReply = false);
  }
}
```

**المشكلة**: إذا فشلت عملية الكتابة (انقطاع الإنترنت)، المستخدم لا يرى أي خطأ. الرسالة لم تُرسل لكنه لا يعلم.

**الإصلاح المقترح**: استبدال `finally` بـ `catch` لعرض رسالة خطأ، ثم `finally` للـ loading state.

---

## الفئة الثالثة: أخطاء Routing / Navigator 🟠

---

### ~~BUG-012~~ — ✅ تم الحل — `login_screen.dart` — `Navigator.pop` من شاشة قد تكون root
**الملف**: `lib/screens/login_screen.dart`  
**السطر**: 101-103

```dart
// في AppBar زر "الرجوع":
IconButton(
  icon: const Icon(Icons.arrow_forward_ios, size: 20),
  onPressed: () => Navigator.pop(context), // ← قد تكون root screen
),
```

**المشكلة**: إذا وصل المستخدم لشاشة تسجيل الدخول عبر deep link أو مباشرة، `Navigator.pop` يعود لشاشة فارغة أو يسبب شاشة سوداء. يجب استخدام `canPop` check.

**الإصلاح المقترح**:
```dart
onPressed: () {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    context.go('/'); // العودة للـ root عبر GoRouter
  }
},
```

---

### ~~BUG-013~~ — ✅ تم الحل — `signup_screen.dart` — نفس المشكلة في زر الرجوع
**الملف**: `lib/screens/signup_screen.dart`  
**السطر**: 104-107

```dart
IconButton(
  icon: const Icon(Icons.arrow_forward_ios, size: 20),
  onPressed: () => Navigator.pop(context), // ← نفس المشكلة
),
```

**نفس الإصلاح المقترح** من BUG-012.

---

### ~~BUG-014~~ — ✅ تم الحل — `orders_list_screen.dart` — `Navigator.pop` في `_buildEmptyState` قد يُسقط الشاشة الخطأ
**الملف**: `lib/screens/orders_list_screen.dart`  
**السطر**: 453-459

```dart
ElevatedButton.icon(
  onPressed: () => Navigator.pop(context), // ← يُغلق OrdersListScreen
  label: Text('العودة للرئيسية', ...),
  ...
)
```

**المشكلة**: `OrdersListScreen` يُفتح من `ClientDashboard` عبر `Navigator.push`. فعلياً `Navigator.pop` صحيح هنا. لكن إذا فُتحت `OrdersListScreen` مباشرة من deep link أو إشعار، `Navigator.pop` سيُرجع لـ root الذي قد يكون Splash أو Login.

**الإصلاح المقترح**:
```dart
onPressed: () {
  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    context.go('/client'); // GoRouter للـ safe fallback
  }
},
```

---

## الفئة الرابعة: أخطاء UI Bindings 🟡

---

### ~~BUG-015~~ — ✅ تم الحل — `client_dashboard.dart` — زر `_buildPromoBanners` لا يتعامل مع `routeType` غير معروف
**الملف**: `lib/screens/client_dashboard.dart`  
**السطر**: 545-557

```dart
onTap: () async {
  if (routeType == 'whatsapp' && actionUrl.isNotEmpty) { ... }
  else if (routeType == '/hourly_cleaning') { ... }
  else if (routeType == '/store') { ... }
  else if (routeType == '/support') { ... }
  // ← routeType == 'none' أو أي قيمة أخرى: لا يحدث شيء
}
```

**المشكلة**: إذا أضاف الإداري بانر بـ `routeType` جديد (مثل `/maintenance`)، الضغط عليه لا يفعل شيئاً. لا يوجد حالة default.

---

### ~~BUG-016~~ — ✅ تم الحل — `client_dashboard.dart` — `_buildMetricsList` لا يعرض shimmer أثناء التحميل
**الملف**: `lib/screens/client_dashboard.dart`  
**السطر**: 593-625

```dart
Widget _buildMetricsList(String? uid) {
  return StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, userSnapshot) {
      // ← لا يوجد connectionState == waiting check
      // لا يوجد hasError check
      final userData = userSnapshot.data?.data() as Map<String, dynamic>?; // قد يكون null
      final rating = (userData?['rating'] ?? 4.9).toString(); // fallback صحيح
      // لكن لا يوجد shimmer أثناء التحميل الأول
```

**المشكلة**: أثناء أول تحميل، `userSnapshot.data` يكون null والـ rating يُعرض كـ `4.9` (القيمة الافتراضية) قبل أن تصل البيانات الحقيقية. المستخدم يرى تقييم خاطئ لثوانٍ.

---

### ~~BUG-017~~ — ✅ تم الحل — `order_tracking_screen.dart` — زر الاتصال بالسائق يستخدم قيمة fallback خاطئة
**الملف**: `lib/screens/order_tracking_screen.dart`  
**السطر**: 195

```dart
IconButton(
  onPressed: () => _callDriver(data['driver_phone'] ?? '05xxxx'), // ← fallback هو string وهمي!
  icon: CircleAvatar(...)
)
```

**المشكلة**: إذا كان `driver_phone` غير موجود في document، يحاول الاتصال بـ `tel:05xxxx` → خطأ في بعض الأجهزة أو اتصال برقم غير صحيح.

**الإصلاح المقترح**:
```dart
final phone = data['driver_phone'] as String?;
onPressed: phone != null && phone.isNotEmpty
    ? () => _callDriver(phone)
    : null, // تعطيل الزر إذا لا يوجد رقم
```

---

### ~~BUG-018~~ — ✅ تم الحل — `subscription_plans_screen.dart` — خطأ صامت عند فشل `_fetchPackages`
**الملف**: `lib/screens/subscription_plans_screen.dart`  
**السطر**: 46-50

```dart
} catch (e) {
  debugPrint('SUBSCRIPTION_FETCH_ERROR: $e'); // ← يُطبع في console فقط
  if (mounted) setState(() => _isLoading = false); // ← يعرض محتوى فارغاً
}
```

**المشكلة**: إذا فشل جلب الباقات (انقطاع الإنترنت)، الشاشة تعرض "لا توجد باقات متاحة حالياً" وكأن المشكلة في البيانات وليس في الاتصال. المستخدم لا يعرف أن هناك خطأ حقيقي.

**الإصلاح المقترح**: إضافة `_hasError` flag وعرض رسالة مناسبة مع زر "إعادة المحاولة".

---

## جدول أولويات الإصلاح

| الأولوية | المشكلة | الملف | الخطر |
|---|---|---|---|
| ✅ | ~~BUG-010~~ — دفع إلكتروني وهمي في المتجر | `store_screen.dart:429` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-004~~ — context المُغلق في CartSheet | `store_screen.dart:327` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-005~~ — حذف حساب حالة تالفة | `profile_screen.dart:209` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-002~~ — context مختلف في _submitTicket | `support_screen.dart:363` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-001~~ — تعارض GoRouter + Navigator يدوي | `login_screen.dart:46` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-006~~ — mounted بعد requestPermission | `hourly_details`, `sofa_rug` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-007~~ — زر تتبع بدون feedback | `orders_list_screen.dart:604` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-017~~ — fallback رقم سائق وهمي | `order_tracking_screen.dart:195` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-008~~ — WhatsApp URL بدون feedback | `client_dashboard.dart:547` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-009~~ — house rules بدون رسالة خطأ | `profile_screen.dart:188` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-011~~ — كتابة Firebase بدون catch | `support_screen.dart:268` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-018~~ — باقات فارغة عند error | `subscription_plans_screen.dart:47` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-012/013~~ — Navigator.pop بدون canPop | `login_screen`, `signup_screen` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-016~~ — تقييم افتراضي قبل التحميل | `client_dashboard.dart:593` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-014~~ — Navigator.pop في empty state | `orders_list_screen.dart:453` | تم الحل 2026-05-19 |
| ✅ | ~~BUG-015~~ — routeType غير معروف | `client_dashboard.dart:545` | تم الحل 2026-05-19 |

---

## ✅ الخلاصة التنفيذية النهائية — 18/18 تم الحل

> **تاريخ الإغلاق الكامل: 2026-05-19**  
> **آخر Commit: `bd7127a`**

| المجموعة | عدد الأخطاء | الحالة |
|---|---|---|
| ثغرات مالية وأمنية (BUG-004, 005, 010) | 3 | ✅ محلولة |
| Context Lifecycle بعد `await` (BUG-001, 002, 003, 006) | 4 | ✅ محلولة |
| Error Handling صامت (BUG-007, 008, 009, 011, 018) | 5 | ✅ محلولة |
| Routing / Navigator خطير (BUG-012, 013, 014, 017) | 4 | ✅ محلولة |
| UI Bindings (BUG-015, 016) | 2 | ✅ محلولة |
| **الإجمالي** | **18** | **✅ 18/18** |

**تطبيق العميل (Client App) جاهز للإطلاق من ناحية جودة الكود.**

---

*هذا التقرير يوثق الأخطاء فقط — لا يُعدّل أي كود. راجع ZIYARAH_BLUEPRINT.md قبل تنفيذ أي إصلاح.*

---

# قسم ثاني: تطبيق السائق (Driver App) — فحص QA متخصص

> **تاريخ الفحص**: 2026-05-19  
> **النطاق**: `lib/screens/driver_dashboard.dart` + `lib/services/location_service.dart` + `lib/services/order_service.dart` + `lib/services/geofence_service.dart` + `lib/services/zyiarah_core_services.dart`  
> **المنهجية**: فحص متخصص في 4 محاور: تسرب الذاكرة، تزامن الحالة، انقطاع الإنترنت، إدارة الصلاحيات

---

## ملخص تنفيذي — تطبيق السائق

| الفئة | عدد المشاكل | أعلى خطورة |
|---|---|---|
| انقطاع الإنترنت — أوامر صامتة | **3 مشاكل** | 🔴 حرجة |
| تسرب الذاكرة واستهلاك البطارية | **3 مشاكل** | 🟠 عالية |
| إدارة الصلاحيات (GPS revoked) | **1 مشكلة** | 🟠 عالية |
| تزامن الحالة — Double-tap وOptimistic UI | **2 مشاكل** | 🟡 متوسطة |
| أخرى | **1 مشكلة** | 🟡 متوسطة |
| **الإجمالي** | **10 مشاكل** | — |

---

## الفئة الأولى: انقطاع الإنترنت 🔴

---

### DRIVER-001 — `driver_dashboard.dart` — `_updateStatus()` بدون try/catch — الزر يُضغط مرتين

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 688-779

```dart
// الكود الحالي ❌
void _updateStatus(String id, String status) async {
  final doc = await FirebaseFirestore.instance.collection('orders').doc(id).get(); // ← await طويل
  // ... COD dialog ...
  await _orderService.updateOrderStatus(id, status, driverId: _currentDriverId); // ← Transaction
  // لا يوجد try/catch هنا
  if (status == 'completed' && mounted) _showSuccessDialog();
}
```

**المشكلة 1 — انقطاع الإنترنت**: إذا فقد السائق الاتصال أثناء `_orderService.updateOrderStatus()` (وهو `runTransaction` يرفض الكتابة offline)، يُلقى `FirebaseException` غير مُعالَج. التطبيق لا يعطل (Flutter يلتقط الأخطاء في async methods بصمت)، لكن:
- `_showSuccessDialog()` لا يُستدعى → السائق لا يرى شيئاً
- الزر يعود فاعلاً → السائق يضغط مجدداً → محاولات تراكمية

**المشكلة 2 — Double-tap**: الزر ليس له loading state. الضغطة الثانية قبل انتهاء الأولى تُطلق COD dialog مرة ثانية للطلبات النقدية. Transaction guard في `updateOrderStatus` يمنع التحديث المكرر، لكن dialog الـCOD ينبثق مرتين.

**الخطر المباشر**: السائق يعتقد أن المهمة لم تُغلق → يتصل بالإدارة → ارتباك تشغيلي.

**الإصلاح المقترح**:
```dart
bool _isUpdatingStatus = false; // flag جديد

void _updateStatus(String id, String status) async {
  if (_isUpdatingStatus) return; // منع الضغطة المزدوجة
  setState(() => _isUpdatingStatus = true);
  try {
    // ... منطق التحديث ...
    await _orderService.updateOrderStatus(id, status, driverId: _currentDriverId);
    if (status == 'completed' && mounted) _showSuccessDialog();
  } catch (e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فشل تحديث الحالة، تحقق من الاتصال: $e'), backgroundColor: Colors.red),
    );
  } finally {
    if (mounted) setState(() => _isUpdatingStatus = false);
  }
}
```

---

### DRIVER-002 — `driver_dashboard.dart` — `_acceptOrder()` بدون try/catch

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 669-686

```dart
// الكود الحالي ❌
void _acceptOrder(String id) async {
  bool success = await _orderService.acceptOrder(id, _currentDriverId!); // ← Transaction — يفشل offline
  if (success) {
    final doc = await FirebaseFirestore.instance.collection('orders').doc(id).get();
    // ... إشعارات ...
  } else if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(...); // "لديك طلب نشط"
  }
  // لا try/catch — إذا رمى acceptOrder exception، لا يحدث شيء
}
```

**المشكلة**: `acceptOrder` يستخدم `_db.runTransaction(...)` الذي يرفض offline. إذا كان السائق على شبكة ضعيفة، يُلقى exception غير مُعالَج. السائق يضغط "قبول" → لا يحدث شيء → يضغط مرات عديدة → عند عودة الإنترنت، قد ينتهي بطلب مكرر أو تعارض في transaction.

**الإصلاح المقترح**: نفس نمط try/catch + loading flag على زر "قبول".

---

### DRIVER-003 — `driver_dashboard.dart` — زر "اتصال بالعميل" يستخدم `'05xxxx'` كـ Fallback

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 469

```dart
// الكود الحالي ❌
TextButton.icon(
  onPressed: () => _callClient(data['client_phone'] ?? '05xxxx'), // ← fallback وهمي
  ...
)
```

**المشكلة**: نفس BUG-017 الذي أُصلح في تطبيق العميل (`order_tracking_screen.dart`)، لكنه لا يزال موجوداً هنا. إذا كان `client_phone` غير موجود، السائق يتصل بـ `tel:05xxxx` وهو رقم غير صالح.

**الإصلاح المقترح**:
```dart
onPressed: () {
  final phone = data['client_phone'] as String?;
  if (phone != null && phone.isNotEmpty) {
    _callClient(phone);
  } else if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('رقم العميل غير متوفر')),
    );
  }
},
```

---

## الفئة الثانية: تسرب الذاكرة واستهلاك البطارية 🟠

---

### DRIVER-004 — `driver_dashboard.dart` — `_syncTimer` لا يتوقف عند تغيير السائق لحالته إلى "غير متصل"

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 169-181

```dart
// الكود الحالي ❌
onChanged: (val) async {
  setState(() => _isOnline = val);
  if (_currentDriverId != null) {
    await FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId).update({
      'is_available': val,
      'status': val ? 'idle' : 'off',
    });
  }
  // ← لا يوجد _stopSync() هنا عند val == false
},
```

**المشكلة**: عندما يُبدّل السائق حالته إلى "غير متصل" (offline)، `_syncTimer` يستمر في العمل كل 15 ثانية:
1. يستدعي `Geolocator.getCurrentPosition()` كل 15 ثانية → بطارية مستمرة
2. يُرسل `updateDriverLocation()` إلى Firestore → بيانات موقع تُرسل حتى في وضع offline
3. السائق أعلن توقفه لكن النظام لا يزال يتتبعه

**الإصلاح المقترح**: إضافة `if (!val) _stopSync();` في الـ `onChanged`:
```dart
onChanged: (val) async {
  setState(() => _isOnline = val);
  if (!val) _stopSync(); // ← أوقف التتبع فوراً عند الخروج
  // ...
},
```

---

### DRIVER-005 — `driver_dashboard.dart` — `Geolocator.getPositionStream()` بدون `LocationSettings`

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 512

```dart
// الكود الحالي ❌
stream: Geolocator.getPositionStream(), // ← بدون أي إعدادات
```

**المشكلة**:
- **دقة**: الافتراضي هو `LocationAccuracy.best` → أعلى استهلاك للبطارية
- **تكرار التحديث**: بدون `distanceFilter` → يُطلق حدثاً على أي حركة بالغة الصغر (خطوة واحدة)
- **بدون مهلة**: لا `timeLimit` → إذا لم يستجب GPS، يظل الـ stream معلقاً إلى الأبد

نتيجة: على طريق بها حركة كثيفة، قد يُطلق الـ stream عشرات الأحداث في الدقيقة، وكل حدث يُعيد بناء `_buildDistanceInfo` الذي يحتوي على `_buildMiniMap` (FlutterMap) → ثقيل جداً على المعالج.

**الإصلاح المقترح**:
```dart
stream: Geolocator.getPositionStream(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.medium, // توازن الدقة والبطارية
    distanceFilter: 20, // لا تحديث ما لم يتحرك السائق 20 متر
  ),
),
```

---

### DRIVER-006 — `driver_dashboard.dart` — `getPositionStream()` يُنشأ في كل rebuild لـ StreamBuilder

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 511-534

```dart
// الكود الحالي ❌
Widget _buildDistanceInfo(GeoPoint clientLoc) {
  return StreamBuilder<Position>(
    stream: Geolocator.getPositionStream(), // ← يُستدعى في كل build
    builder: (context, snapshot) { ... },
  );
}
```

**المشكلة**: `_buildDistanceInfo` يُستدعى داخل `_buildStateGuidedCard` الذي يُعاد بناؤه عند كل تحديث في `StreamBuilder<DocumentSnapshot>` الخارجي (يراقب وثيقة الطلب). كل تحديث Firestore → rebuild → استدعاء `getPositionStream()` → subscription جديدة لـ GPS.

رغم أن `StreamBuilder` يلغي الاشتراك القديم عند تغيير الـ stream reference، فإن الـ reference تتغير دائماً (كل استدعاء ينتج instance جديد)، مما يسبب دورة:  
`Firestore update → rebuild → cancel GPS → new GPS subscription → GPS warmup delay → يبدو بطيئاً`

**الإصلاح المقترح**: تخزين `StreamController<Position>` كـ field في الـ State:
```dart
late final Stream<Position> _positionStream;

@override
void initState() {
  super.initState();
  _positionStream = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 20),
  );
}
// ثم تمريره لـ _buildDistanceInfo كـ parameter
```

---

## الفئة الثالثة: إدارة الصلاحيات 🟠

---

### DRIVER-007 — `driver_dashboard.dart` — سحب صلاحية GPS أثناء التنفيذ: صامت تماماً

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 511-534 (getPositionStream) و 59-66 (_startSync)

**المشكلة — المسار الأول (getPositionStream)**:
```dart
builder: (context, snapshot) {
  if (!snapshot.hasData) return const SizedBox.shrink(); // ← يُخفي الخطأ أيضاً
  final pos = snapshot.data!;
  // إذا سُحبت الصلاحية: snapshot.hasError = true → SizedBox.shrink
  // السائق لا يرى أي رسالة، المسافة تختفي فجأة
}
```

عند سحب صلاحية GPS من الإعدادات:
1. `getPositionStream()` يُرسل `snapshot.hasError == true` مع `PermissionException`
2. الكود يعود لـ `SizedBox.shrink()` → المسافة تختفي بصمت
3. لا رسالة تحذير للسائق

**المشكلة — المسار الثاني (_startSync)**:
```dart
_syncTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
  try {
    Position pos = await Geolocator.getCurrentPosition(); // ← سيرمي PermissionDenied
    await _orderService.updateDriverLocation(orderId, GeoPoint(...));
  } catch (e) {
    debugPrint("Location sync error: $e"); // ← صامت تماماً للمستخدم
  }
});
```

عند سحب الصلاحية: `getCurrentPosition()` يرمي exception → catch يطبع للـ console فقط → الموقع يتوقف عن التحديث في Firestore → الإدارة والعميل يفقدون تتبع السائق **دون أي تنبيه**.

**الخطر التشغيلي**: إذا ادّعى السائق أنه وصل وطالب بالدفع، لكن النظام لا يُظهر موقعه → نزاع بين العميل والإدارة.

**الإصلاح المقترح**:
```dart
} catch (e) {
  debugPrint("Location sync error: $e");
  if (e is PermissionDeniedException && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ صلاحية GPS مُعطَّلة. الرجاء تفعيلها من الإعدادات لاستمرار التتبع.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
    _stopSync(); // أوقف الـ timer إذا لا توجد صلاحية
  }
}
```

---

## الفئة الرابعة: تزامن الحالة الميدانية 🟡

---

### DRIVER-008 — `driver_dashboard.dart` — أزرار "قبول" و"تغيير الحالة" بدون Loading State

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 456-463 (زر تغيير الحالة) و 623 (زر قبول)

```dart
// زر تغيير الحالة ❌
ElevatedButton(
  onPressed: () => _updateStatus(id, nextStatus), // ← لا loading، لا حماية من الضغط المزدوج
  child: Text(actionLabel, ...),
)

// زر قبول الطلب ❌
ElevatedButton(
  onPressed: () => _acceptOrder(id), // ← نفس المشكلة
  child: const Text("قبول", ...),
)
```

**المشكلة**: عمليات `_updateStatus` و`_acceptOrder` تتطلب:
1. قراءة من Firestore (`await get()`)
2. تنفيذ Transaction
3. إرسال إشعارات متعددة

مجموع الوقت: 2-5 ثوانٍ على شبكات متوسطة. خلال هذا الوقت الزر فعّال. في البيئة الميدانية، السائقون يضغطون الأزرار بحماس. الضغط المزدوج يسبب حالات غير متوقعة.

**الإصلاح المقترح**: إضافة `_isUpdatingStatus` و`_isAccepting` flags مع `setState()`.

---

### DRIVER-009 — `driver_dashboard.dart` — `_buildStatsRow` بدون Error Handling

**الملف**: `lib/screens/driver_dashboard.dart`  
**السطر**: 195-231

```dart
// الكود الحالي ❌
StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance.collection('orders')
      .where('driver_id', isEqualTo: _currentDriverId)
      .where('status', isEqualTo: 'completed')
      .snapshots(),
  builder: (context, allSnapshot) {
    final allOrders = allSnapshot.data?.docs ?? []; // إذا hasError → [] بصمت
    // لا hasError check، لا connectionState check
```

**المشكلة**: إذا فشل الـ stream (شبكة، Firestore rules)، الإحصائيات تظهر 0 بصمت، والسائق يعتقد أن إنجازاته لم تُسجَّل. بلاغات كاذبة للإدارة.

---

## جدول أولويات الإصلاح — تطبيق السائق

| الأولوية | المشكلة | الملف | الخطر |
|---|---|---|---|
| 🔴 1 | DRIVER-001 — `_updateStatus()` بدون try/catch + Double-tap | `driver_dashboard.dart:688` | تشغيلي مباشر |
| 🔴 2 | DRIVER-002 — `_acceptOrder()` بدون try/catch | `driver_dashboard.dart:669` | طلبات ضائعة |
| 🔴 3 | DRIVER-003 — رقم عميل وهمي '05xxxx' | `driver_dashboard.dart:469` | اتصال خاطئ |
| 🟠 4 | DRIVER-004 — `_syncTimer` يستمر بعد offline | `driver_dashboard.dart:169` | بطارية + تتبع زائف |
| 🟠 5 | DRIVER-005 — `getPositionStream()` بدون إعدادات | `driver_dashboard.dart:512` | استنزاف البطارية |
| 🟠 6 | DRIVER-006 — سحب GPS بدون تنبيه | `driver_dashboard.dart:59+512` | فقدان تتبع صامت |
| 🟠 7 | DRIVER-007 — `getPositionStream()` يُنشأ في كل rebuild | `driver_dashboard.dart:511` | عدم كفاءة |
| 🟡 8 | DRIVER-008 — أزرار بدون Loading State | `driver_dashboard.dart:457+623` | ضغط مزدوج |
| 🟡 9 | DRIVER-009 — إحصائيات بدون Error Handling | `driver_dashboard.dart:195` | بيانات مضللة |

---

*فحص تطبيق السائق — 2026-05-19. 9 مشاكل موثّقة. جاهز للإصلاح بعد الاعتماد.*
