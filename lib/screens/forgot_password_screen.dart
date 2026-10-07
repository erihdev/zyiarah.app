import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/utils/net_timeout.dart';

class ZyiarahForgotPasswordScreen extends StatefulWidget {
  const ZyiarahForgotPasswordScreen({super.key});

  @override
  State<ZyiarahForgotPasswordScreen> createState() => _ZyiarahForgotPasswordScreenState();
}

class _ZyiarahForgotPasswordScreenState extends State<ZyiarahForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();
  bool _isLoading = false;
  final Color brandColor = const Color(0xFF660033);

  void _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('الرجاء إدخال البريد الإلكتروني');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // **نداءٌ معلّقٌ ليس خطأً — والدوّارُ كان بلا مخرج (2026-10-07).**
      //
      // كان `FirebaseAuth.instance.sendPasswordResetEmail` **بلا مهلة**، فإن
      // بدا الاتّصالُ قائماً والحزمُ لا تَنفُذ (بوّابةُ فندقٍ، وكيلٌ شفّاف،
      // واي-فاي بلا مسار) لم يَرمِ النداءُ ولم يَعُدْ: `_isLoading` يَبقى
      // `true` والزرُّ دوّاراً إلى الأبد، ولا رسالةَ ولا مخرج.
      //
      // **والدليلُ مسحُ المصدرِ لا تشغيلُ التطبيق، ويُقالُ بحدِّه:** مسحُ
      // نداءاتِ المصادقةِ الثمانيةِ في `lib/` أعطى **مُمهَلَين اثنين**
      // (الدخولُ والتسجيل) وستّةً بلا مهلة، وهذا وحدَه المُستعمَلُ في شاشةٍ
      // بزرٍّ دوّار. (شُغّلَ التطبيقُ وخادمٌ غيرُ قابلِ الوصول، ولم يَظهرْ
      // شريطٌ — **لكنّ ذلك ليس برهاناً**: فحصُ ضبطٍ بحقلٍ فارغٍ، وهو مسارٌ
      // يَعرضُ شريطاً فوراً وبلا شبكة، لم يُظهِرْ شريطاً كذلك — فالمِرفَقُ
      // لا يَلتقطُ الأشرطةَ قبلَ انقضائها، لا أنّ النداءَ عَلِق.)
      //
      // وشقيقتاها (الدخولُ والتسجيل) تُمهِلانِ منذ المسحِ السابق — فهذه
      // «قاعدةٌ عامّةٌ مُنفَّذةٌ في سطحَين من ثلاثة»، وحارسُها كان مشدوداً
      // إلى الملفَّين بأسمائهما.
      //
      // والنداءُ يَمُرُّ بـ`ZyiarahFirebaseService` كشقيقتَيه: المصادقةُ
      // **نطاقُ تلك الخدمةِ** بنصِّ قرارِ المشروع، وكان هذا الموضعُ وحدَه
      // يَتخطّاها إلى الـSDK مباشرةً — فبَقيت `sendPasswordResetEmail`
      // فيها **بلا مُنادٍ** (ولم يَرَها `no_dead_code_test` لأنّ اسمَها
      // اسمُ دالّةِ الحزمةِ، وهو العمى الموثَّقُ هناك).
      await _firebaseService.sendPasswordResetEmail(email).timeout(kAuthTimeout);

      if (!mounted) return;
      _showSuccess('تم إرسال رابط استعادة كلمة المرور إلى بريدك الإلكتروني بنجاح.');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.pop(context);
      });
    } on TimeoutException {
      // «لا نعرف» ليست «فشلاً»: قد يَكونُ البريدُ أُرسِلَ فعلاً، فلا نَقولُ
      // «لم يُرسَل» ولا «أُرسِل» — نَقولُ ما نَعرفُه ونَدلُّها على الصندوق.
      if (mounted) {
        _showError('تعذّر الاتصال — تحقّقي من الإنترنت. إن وصلكِ الرابط '
            'فاستعمليه، وإلّا أعيدي المحاولة.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showError(switch (e.code) {
          'invalid-email' => 'صيغة البريد الإلكتروني غير صحيحة',
          'user-not-found' => 'لا يوجد حساب بهذا البريد الإلكتروني',
          'network-request-failed' => 'تعذّر الاتصال — تحقّقي من الإنترنت',
          _ => 'تعذّر إرسال الرابط، حاولي لاحقاً',
        });
      }
    } catch (_) {
      if (mounted) _showError('تعذّر إرسال الرابط، حاولي لاحقاً');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.tajawal()), backgroundColor: Colors.green),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('نسيت كلمة المرور', style: GoogleFonts.tajawal()),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                "أدخلي البريد الإلكتروني المسجل وسنقوم بإرسال رابط استعادة كلمة المرور",
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 40),
              
              Text(
                "البريد الإلكتروني",
                style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: "example@mail.com",
                    hintStyle: GoogleFonts.tajawal(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A0E0E)))
                  : ElevatedButton(
                      onPressed: _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text(
                        "إرسال الرابط",
                        style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
