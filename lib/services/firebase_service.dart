import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:zyiarah/firebase_options.dart';
import 'dart:math';
/// خدمة إدارة Firebase لتطبيق زيارة
class ZyiarahFirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
      await saveUserToRegistry(
        uid: userCredential.user!.uid,
        name: name,
        role: 'client',
      );
      // حفظ بيانات الجوال والإيميل
      await _db.collection('users').doc(userCredential.user!.uid).update({
        'phone': phone,
        'email': email,
      });
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

  // تحويل رقم الجوال إلى بريد إلكتروني وهمي لـ Firebase Auth
  String _phoneToEmail(String phone) {
    String clean = phone.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('966')) clean = clean.substring(3);
    if (clean.startsWith('0')) clean = clean.substring(1);
    return '$clean@zyiarah.com';
  }

  Future<UserCredential> signUpWithPhoneAndPassword({
    required String phone,
    required String password,
    required String name,
    required String email,
  }) async {
    final firebaseEmail = _phoneToEmail(phone);
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: firebaseEmail,
      password: password,
    );

    if (userCredential.user != null) {
      await saveUserToRegistry(
        uid: userCredential.user!.uid,
        name: name,
        role: 'client',
      );
      // حفظ بيانات إضافية
      await _db.collection('users').doc(userCredential.user!.uid).update({
        'phone': phone,
        'real_email': email,
      });
    }
    return userCredential;
  }

  Future<UserCredential> signInWithPhoneAndPassword(String phone, String password) async {
    final firebaseEmail = _phoneToEmail(phone);
    return await _auth.signInWithEmailAndPassword(
      email: firebaseEmail,
      password: password,
    );
  }

  // تحديث كلمة المرور للمستخدمين القدامى (Migration)
  Future<void> updatePassword(String phone, String newPassword) async {
    User? user = _auth.currentUser;
    if (user != null) {
      final firebaseEmail = _phoneToEmail(phone);
      // Linking the current Phone-auth user with an Email-auth credential
      AuthCredential credential = EmailAuthProvider.credential(
        email: firebaseEmail,
        password: newPassword,
      );
      
      try {
        await user.linkWithCredential(credential);
      } catch (e) {
        // If already linked or other error, try updating password directly
        await user.updatePassword(newPassword);
      }
      
      // Update the user profile in Firestore to ensure it's marked as set up
      await _db.collection('users').doc(user.uid).update({
        'has_password': true,
        'phone': phone,
      });
    }
  }

  // --- التحقق برقم الجوال (Phone Auth - OTP) ---

  Future<void> verifyPhoneNumber(
      String phone, Function(String) onCodeSent, Function(String) onError) async {
    try {
      if (kDebugMode) {
        await _auth.setSettings(appVerificationDisabledForTesting: true);
      }
    } catch (_) {}
    await _auth.verifyPhoneNumber(
      phoneNumber: '+966$phone',
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'حدث خطأ غير معروف في التحقق');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // --- التحقق من الكود (Verify OTP) ---

  Future<UserCredential> verifyOTP(String verificationId, String smsCode) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return await _auth.signInWithCredential(credential);
  }

  // --- تسجيل الخروج ---
  Future<void> signOut() async {
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
  Future<String> getUserRole(String uid, {String? phone}) async {
    try {
      // 1. التحقق أولاً من مجموعة المديرين (UID-based)
      DocumentSnapshot adminDoc = await _db.collection('admins').doc(uid).get();
      if (adminDoc.exists && adminDoc.data() != null) {
        final adminData = adminDoc.data() as Map<String, dynamic>;
        // العودة بالدور الإداري التفصيلي (مثل accountant_admin, marketing_admin)
        return adminData['staff_role'] ?? adminData['role'] ?? 'admin';
      }

      // 2. التحقق من مجموعة المستخدمين العامة
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return data['role'] ?? 'client';
      }

      // 2. إذا لم يوجد، وكان هناك رقم جوال، نتحقق من مجموعة السائقين
      if (phone != null) {
        // تنظيف رقم الجوال (التأكد من الصيغة: 5XXXXXXXX)
        String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
        
        // التعامل مع مفتاح الدولة والصفريين
        if (cleanPhone.startsWith('966')) {
          cleanPhone = cleanPhone.substring(3);
        }
        if (cleanPhone.startsWith('00966')) {
           cleanPhone = cleanPhone.substring(5);
        }
        if (cleanPhone.startsWith('0')) {
          cleanPhone = cleanPhone.substring(1);
        }
        
        // استخراج آخر 9 أرقام إذا كان الرقم طويلاً
        if (cleanPhone.length > 9) {
          cleanPhone = cleanPhone.substring(cleanPhone.length - 9);
        }

        if (kDebugMode) {
          print("Attempting to find driver with cleaned phone: $cleanPhone");
        }

        QuerySnapshot driverDoc = await _db
            .collection('drivers')
            .where('phone', isEqualTo: cleanPhone)
            .limit(1)
            .get();

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
      if (kDebugMode) {
        print("Error fetching role: $e");
      }
    }
    return 'client'; // في حالة الخطأ أو عدم وجود بيانات، نعتبره عميل
  }

  // --- رفع ملفات للعمالة ---
  Future<String?> uploadWorkerPhoto(Uint8List fileData, String fileName) async {
    try {
      final ref = FirebaseStorage.instance.ref().child('worker_photos/$fileName');
      final uploadTask = await ref.putData(fileData);
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
          'is_active': isActive,
          'created_at': FieldValue.serverTimestamp(),
          ...extraData ?? {},
        });

        await secondaryAuth.sendPasswordResetEmail(email: email);
        return uid;
      }
      throw Exception("فشل إنشاء الحساب");
    } finally {
      if (secondaryApp != null) await secondaryApp.delete();
    }
  }

  // Backward compatibility
  Future<String> createDriverAccountViaAdmin({
    required String name,
    required String phone,
    required String email,
    required String carInfo,
    required String licenseInfo,
    required String role, 
    required bool isActive,
    String? photoUrl,
  }) => createAccountViaAdmin(
    name: name,
    phone: phone,
    email: email,
    role: role,
    isActive: isActive,
    extraData: {
      'car_info': carInfo,
      'license_info': licenseInfo,
      'photo_url': photoUrl,
    }
  );

  String _generateRandomPassword() {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890!@#\$%^&*';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }
}
