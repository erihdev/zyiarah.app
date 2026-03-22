import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// خدمة إدارة Firebase لتطبيق زيارة
class ZyiarahFirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- التحقق برقم الجوال (Phone Auth) ---

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
