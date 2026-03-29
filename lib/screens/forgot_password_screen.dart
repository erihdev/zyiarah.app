import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ZyiarahForgotPasswordScreen extends StatefulWidget {
  const ZyiarahForgotPasswordScreen({super.key});

  @override
  State<ZyiarahForgotPasswordScreen> createState() => _ZyiarahForgotPasswordScreenState();
}

class _ZyiarahForgotPasswordScreenState extends State<ZyiarahForgotPasswordScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  final Color brandColor = const Color(0xFF4A0E0E);

  void _resetPassword() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('الرجاء إدخال رقم الجوال');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. البحث عن إيميل العميل الحقيقي في Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final userData = snapshot.docs.first.data();
        final realEmail = userData['real_email'] as String?;

        if (realEmail != null && realEmail.isNotEmpty) {
          // 2. إرسال رابط إعادة تعيين كلمة المرور
          await FirebaseAuth.instance.sendPasswordResetEmail(email: realEmail);
          
          if (!mounted) return;
          _showSuccess('تم إرسال رابط إعادة تعيين كلمة المرور إلى إيميلك المسجل: $realEmail');
          Future.delayed(const Duration(seconds: 3), () => Navigator.pop(context));
        } else {
          _showError('لم يتم العثور على بريد إلكتروني مسجل لهذا الرقم');
        }
      } else {
        _showError('رقم الجوال غير مسجل لدينا');
      }
    } catch (e) {
      _showError('حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.tajawal()), backgroundColor: Colors.green),
    );
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
                "أدخل رقم الجوال المسجل وسنقوم بإرسال رابط استعادة كلمة المرور إلى بريدك الإلكتروني",
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 40),
              
              Text(
                "رقم الجوال",
                style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: "5XXXXXXXX",
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
