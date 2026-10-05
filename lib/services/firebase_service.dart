import 'package:zyiarah/services/zyiarah_messaging_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:zyiarah/firebase_options.dart';
import 'package:zyiarah/services/notification_service.dart';
import 'dart:math';
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/upload_content_type.dart';
import 'package:zyiarah/utils/staff_role.dart';

/// خدمة إدارة Firebase لتطبيق زيارة
class ZyiarahFirebaseService {
  // Singleton Pattern
  static final ZyiarahFirebaseService _instance = ZyiarahFirebaseService._internal();
  factory ZyiarahFirebaseService() => _instance;
  ZyiarahFirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ZyiarahMessagingService _commService = ZyiarahMessagingService();

  // --- التحقق بالبريد الإلكتروني وكلمة المرور (Email & Password) ---

  Future<UserCredential> signUpWithRealEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (userCredential.user != null) {
      final user = userCredential.user!;
      try {
        await saveUserToRegistry(uid: user.uid, name: name, role: 'client');
        // حفظ بيانات الجوال والإيميل
        await _db.collection('users').doc(user.uid).update({
          'phone': phone,
          'email': email,
        });
      } catch (e) {
        // فشل كتابة المستند بعد إنشاء حساب Auth → نحذف الحساب اليتيم كي لا يعلق المستخدم
        // بـ email-already-in-use بمستندٍ ناقص، فتنجح إعادة المحاولة نظيفةً.
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }
      // بريد الترحيب ليس حرجاً لإنشاء الحساب — فشله (شبكة/طابور) لا يُجهض التسجيل.
      try {
        await _commService.sendWelcomeEmail(recipient: email, name: name);
      } catch (e) {
        debugPrint('sendWelcomeEmail failed (non-fatal): $e');
      }
    }
    return userCredential;
  }

  Future<UserCredential> signInWithRealEmailAndPassword(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // --- التحقق برقم الجوال وكلمة المرور (Phone & Password - Legacy) ---

  // --- التحقق برقم الجوال (Phone Auth - OTP) ---

  // --- التحقق من الكود (Verify OTP) ---

  // --- تسجيل الخروج المركزي (B1) ---
  /// نقطة الخروج الموحّدة الوحيدة لكل الأدوار (عميل/سائق/إدارة).
  /// تضمن تنظيف الذاكرة بالكامل قبل تبديل الحساب لمنع تسرب بيانات/Streams الحساب السابق.
  /// تستدعيها جميع الشاشات بدل FirebaseAuth.signOut() المباشرة.
  Future<void> signOut() async {

    // (B2) تنظيف الإشعارات: حذف توكن FCM للمستخدم الحالي + إلغاء الاشتراك في الـ Topics
    // يُنفّذ قبل _auth.signOut() لأنه يحتاج uid الحالي
    try {
      await ZyiarahNotificationService().cleanupOnSignOut();
    } catch (e) {
      debugPrint("⚠️ cleanupOnSignOut (notifications) failed: $e");
    }

    // (B4) تسجيل الخروج فعلياً — يُطلق authStateChanges(null) فتُلغي
    // ZyiarahUserProvider و ZyiarahOrderProvider اشتراكاتهما الخاصة بالمستخدم تلقائياً.
    await _auth.signOut();
  }

  // --- إدارة بيانات المستخدمين في Firestore ---

  Future<void> saveUserToRegistry({
    required String uid,
    required String name,
    required String role, // 'client' or 'driver'
  }) async {
    await _db.collection('users').doc(uid).set({
      'name': name,
      'role': role,
      'created_at': FieldValue.serverTimestamp(),
      'is_verified': true,
      'entity': 'مؤسسة معاذ يحي محمد المالكي',
    });
  }
  // --- استرجاع دور المستخدم وتوجيهه ---
  Future<String?> getUserRole(String uid, {String? phone}) async {
    try {
      // 1. **`users` أوّلاً — وهو المستندُ الذي تَقرؤه القواعد.**
      //
      //    كان هذا الترتيبُ مقلوباً: `admins/{uid}` أوّلاً و`staff_role` منه،
      //    و`users` لا يُقرأُ إلّا إن غابَ مستندُ `admins`. والقواعدُ
      //    (`getUserData()` = `get(/users/$uid).data`) لا تَعرفُ `admins`
      //    إطلاقاً — فسؤالٌ واحدٌ بمصدرَين، وما تَعرضُه الواجهةُ قد يُخالِفُ
      //    ما يُجيزُه الخادم. والقاعدةُ ومُبرِّرُها في `lib/utils/staff_role.dart`.
      //
      //    والكلفةُ كما كانت: مستندُ موظّفٍ يَحملُ `role` و`staff_role` معاً
      //    (`createAccountViaAdmin` يَكتبُهما و`_saveStaff` يُحدّثُهما)، فقراءةٌ
      //    واحدةٌ تَكفي، و`admins` لا يُقرأُ إلّا لحسابٍ لا يَحملُ `users` دوراً.
      DocumentSnapshot doc = await _db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(kNetCallTimeout);
      final Map<String, dynamic>? userData =
          doc.exists ? doc.data() as Map<String, dynamic>? : null;
      final String? fromUsers = roleFromUsersDoc(userData);
      if (fromUsers != null) {
        // مفتاحُ الإيقافِ كان يُكتَبُ في `admins` ولا يَقرؤه **شيء**: لا
        // القواعدُ ولا الدوالُّ ولا هذا الموضع — فموظّفٌ «معطَّل» يَدخلُ
        // ويَعملُ كأنّ شيئاً لم يَكن. يُقرأُ الآن من `users` (حيث تَقرأُ
        // القواعدُ)، والإنفاذُ الكاملُ ينتظرُ نشرَ القواعدِ بيدٍ بشريّة.
        if (staffAccountDisabled(userData, fromUsers)) return null;
        return fromUsers;
      }

      // 2. احتياطٌ: حسابٌ لا يَحملُ `users` دوراً (أُنشئ بيدٍ في الكونسولِ أو
      //    حسابُ تأسيسٍ قديم) — حجبُه كان سيُقفِلُ الإدارةَ.
      DocumentSnapshot adminDoc = await _db
          .collection('admins')
          .doc(uid)
          .get()
          .timeout(kNetCallTimeout);
      if (adminDoc.exists && adminDoc.data() != null) {
        return roleFromAdminsDoc(adminDoc.data() as Map<String, dynamic>?);
      }
      if (userData != null) return 'client';

      // 3. إذا لم يوجد، وكان هناك رقم جوال، نتحقق من مجموعة السائقين
      if (phone != null) {
        // تنظيف رقم الجوال (التأكد من الصيغة: 5XXXXXXXX)
        String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
        
        // التعامل مع مفتاح الدولة والصفريين
        if (cleanPhone.startsWith('00966')) {
          cleanPhone = cleanPhone.substring(5);
        } else if (cleanPhone.startsWith('966')) {
          cleanPhone = cleanPhone.substring(3);
        }
        if (cleanPhone.startsWith('0')) {
          cleanPhone = cleanPhone.substring(1);
        }
        
        // استخراج آخر 9 أرقام إذا كان الرقم طويلاً
        if (cleanPhone.length > 9) {
          cleanPhone = cleanPhone.substring(cleanPhone.length - 9);
        }

        if (kDebugMode) {
          debugPrint("Attempting to find driver with cleaned phone: $cleanPhone");
        }

        QuerySnapshot driverDoc = await _db
            .collection('drivers')
            .where('phone', isEqualTo: cleanPhone)
            .limit(1)
            .get().timeout(kNetCallTimeout);

        if (driverDoc.docs.isNotEmpty) {
          // حفظ الدور في مجموعة المستخدمين للمستقبل برقم الجوال الموحد
          await saveUserToRegistry(
            uid: uid,
            name: driverDoc.docs.first.get('name') ?? 'سائق جديد',
            role: 'driver',
          );
          return 'driver';
        }
      }
    } catch (e) {
      // خطأ قراءةٍ صلب (شبكة): **لا نُخمّن الدور**. كان يرجع 'client' فيصل السائق/
      // الأدمن لوحة العميل بصمت، ويُبطِل شاشة إعادة المحاولة (RoleUnavailable) في
      // main.dart التي تنتظر null. نرجع null: المستخدم لا يُسجَّل خروجه (يرى إعادة
      // محاولة)، ومستمع اللقطة في UserProvider يعافي الدور فور تحميل المستند.
      debugPrint("Error fetching role: $e");
      return null;
    }
    // قراءةٌ ناجحة بلا مستند مطابق: عميل فعلاً (افتراضي مشروع).
    return 'client';
  }

  // --- رفع ملفات للعمالة ---
  Future<String?> uploadWorkerPhoto(Uint8List fileData, String fileName) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('worker_photos/$fileName');
      // النوعُ يُصرَّحُ: `putData` بلا بياناتٍ وصفيّةٍ يَرفعُ
      // octet-stream، وقاعدةُ المخزنِ تَحصرُ المسارَ في `image/*`.
      final uploadTask = await ref.putData(fileData,
          SettableMetadata(contentType: imageContentTypeFor(fileName)));
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) print("Error uploading photo: $e");
      return null;
    }
  }

  /// إنشاء حساب جديد من قِبل الإدارة (سائق أو مدير) بشكل آمن
  Future<String> createAccountViaAdmin({
    required String name,
    required String phone,
    required String email,
    required String role,
    required bool isActive,
    Map<String, dynamic>? extraData,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryApp_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final randomPassword = _generateRandomPassword();
      
      UserCredential userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email, 
        password: randomPassword,
      );

      if (userCredential.user != null) {
        final uid = userCredential.user!.uid;

        try {
          // 1. إضافة للمجموعة العامة
          await _db.collection('users').doc(uid).set({
            'name': name,
            'role': role,
            'phone': phone,
            'email': email,
            'created_at': FieldValue.serverTimestamp(),
            'is_verified': true,
            'entity': 'مؤسسة معاذ يحي محمد المالكي',
            ...extraData ?? {},
          }, SetOptions(merge: true));

          // 2. إضافة لمجموعة التخصص (سائقين أو مديرين)
          final String collection = role == 'admin' ? 'admins' : 'drivers';
          await _db.collection(collection).doc(uid).set({
            'name': name,
            'phone': phone,
            'email': email,
            'role': role,
            // type: يقرؤه عدّاد السائقين وكشف الرواتب — بدونه يُصنَّف الجميع افتراضياً.
            'type': role,
            'is_active': isActive,
            'created_at': FieldValue.serverTimestamp(),
            ...extraData ?? {},
          });
        } catch (e) {
          // فشلت كتابة Firestore (رفض قواعد/شبكة) بعد إنشاء حساب Auth: كان الحساب
          // يبقى يتيماً فيُحرق البريد نهائياً — كل إعادة محاولة تفشل بـ
          // email-already-in-use. نتراجع: نحذف مستند users (إن كُتب) وحساب Auth
          // عبر جلسة التطبيق الثانوي، ثم نعيد رمي الخطأ الأصلي ليظهر للأدمن.
          try {
            await _db.collection('users').doc(uid).delete();
          } catch (_) {
            // المستند لم يُكتب أصلاً (الرفض حدث في الكتابة الأولى) — نتجاهل.
          }
          try {
            await userCredential.user!.delete();
          } catch (_) {
            // فشل حذف التعويض نفسه — نُبقي الخطأ الأصلي هو الظاهر للمستخدم.
          }
          rethrow;
        }

        await secondaryAuth.sendPasswordResetEmail(email: email);
        return uid;
      }
      throw Exception("فشل إنشاء الحساب");
    } finally {
      if (secondaryApp != null) await secondaryApp.delete();
    }
  }

  Future<String> createDriverAccountViaAdmin({
    required String name,
    required String phone,
    required String email,
    // مركبات المؤسسة لا السائق — الحقل اختياري ولا يُكتب حين يغيب.
    String carInfo = '',
    required String licenseInfo,
    required String role,
    required bool isActive,
    String? nationality,
    String? idNumber,
    String? idExpiry,
    String? photoUrl,
    double monthlySalary = 0,
  }) => createAccountViaAdmin(
    name: name,
    phone: phone,
    email: email,
    role: role,
    isActive: isActive,
    extraData: {
      if (carInfo.trim().isNotEmpty) 'car_info': carInfo,
      'license_info': licenseInfo,
      'photo_url': photoUrl,
      'monthly_salary': monthlySalary,
      if (nationality != null) 'nationality': nationality,
      if (idNumber != null) 'id_number': idNumber,
      if (idExpiry != null) 'id_expiry': idExpiry,
    }
  );

  String _generateRandomPassword() {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890!@#\$%^&*';
    Random rnd = Random.secure();
    return String.fromCharCodes(Iterable.generate(
        16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }
}
