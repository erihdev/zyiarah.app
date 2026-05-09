import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/firebase_service.dart';

class ZyiarahAccountActivationScreen extends StatefulWidget {
  const ZyiarahAccountActivationScreen({super.key});

  @override
  State<ZyiarahAccountActivationScreen> createState() => _ZyiarahAccountActivationScreenState();
}

class _ZyiarahAccountActivationScreenState extends State<ZyiarahAccountActivationScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _verificationId;
  bool _otpSent = false;
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  final Color brandColor = const Color(0xFF5D1B5E);

  void _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showError('الرجاء إدخال رقم الجوال');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: '+966$phone', // Adjust country code as needed
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification handled elsewhere or if needed
        },
        verificationFailed: (FirebaseAuthException e) {
          _showError('فشل إرسال الرمز: ${e.message}');
          setState(() => _isLoading = false);
        },
        codeSent: (String verId, int? resendToken) {
          setState(() {
            _verificationId = verId;
            _otpSent = true;
            _isLoading = false;
          });
        },
        codeAutoRetrievalTimeout: (String verId) {
          _verificationId = verId;
        },
      );
    } catch (e) {
      _showError('خطأ: $e');
      setState(() => _isLoading = false);
    }
  }

  void _verifyAndSetPassword() async {
    final otp = _otpController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (otp.isEmpty || password.isEmpty) {
      _showError('الرجاء إكمال جميع الحقول');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Verify OTP
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      // We don't want to sign in permanently yet, just verify
      // But Firebase requires sign-in to link or manage.
      // So we sign in, set password, then we're good.
      final userCredential = await _auth.signInWithCredential(credential);
      
      if (userCredential.user != null) {
        // 2. Update Password (and link Email-Phone if needed)
        // Our service handles creating the Email-Alias if it doesn't exist
        await _firebaseService.updatePassword(phone, password);
        
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل الحساب وتعيين كلمة المرور بنجاح!')),
        );
      }
    } catch (e) {
      _showError('خطأ في التفعيل: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('تفعيل الحساب', style: GoogleFonts.tajawal()),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                _otpSent ? "أدخل رمز التحقق وكلمة المرور الجديدة" : "أدخل رقم جوالك لتصلك رسالة التفعيل",
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(fontSize: 16, color: Colors.blueGrey),
              ),
              const SizedBox(height: 40),
              
              if (!_otpSent) ...[
                _buildFieldLabel("رقم الجوال"),
                _buildTextField(_phoneController, "5XXXXXXXX", keyboardType: TextInputType.phone),
                const SizedBox(height: 40),
                _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A0E0E)))
                  : ElevatedButton(
                      onPressed: _sendOTP,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text("إرسال رمز التحقق", style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
              ] else ...[
                _buildFieldLabel("رمز التحقق (OTP)"),
                _buildTextField(_otpController, "XXXXXX", keyboardType: TextInputType.number),
                const SizedBox(height: 20),
                _buildFieldLabel("كلمة المرور الجديدة"),
                _buildTextField(
                  _passwordController, 
                  "********", 
                  isPassword: true, 
                  isVisible: _isPasswordVisible,
                  onToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                const SizedBox(height: 40),
                _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A0E0E)))
                  : ElevatedButton(
                      onPressed: _verifyAndSetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: Text("تفعيل الحساب الآن", style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                TextButton(
                  onPressed: () => setState(() => _otpSent = false),
                  child: Text("تغيير الرقم", style: GoogleFonts.tajawal(color: brandColor)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, right: 4.0),
      child: Text(
        label,
        style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String hint, {
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isPassword && !isVisible,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.tajawal(color: Colors.grey[400]),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(isVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }
}
