import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  // جلب دور المستخدم ('client' أو 'driver')
  Future<String> getUserRole(String uid, [String? phone]) async {
    try {
      // 1. التحقق أولاً من مجموعة المستخدمين العامة
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return data['role'] ?? 'client';
      }

      // 2. إذا لم يوجد، وكان هناك رقم جوال، نتحقق من مجموعة السائقين
      if (phone != null) {
        // تنظيف رقم الجوال (التأكد من الصيغة: 5XXXXXXXX)
        String cleanPhone = phone.replaceAll(RegExp(r'\D'), ''); // إزالة أي رموز غير أرقام
        
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
}
