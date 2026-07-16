import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/services/zyiarah_referral_service.dart';
import 'package:zyiarah/screens/terms_privacy_screens.dart';

class ZyiarahSignupScreen extends StatefulWidget {
  const ZyiarahSignupScreen({super.key});

  @override
  State<ZyiarahSignupScreen> createState() => _ZyiarahSignupScreenState();
}

class _ZyiarahSignupScreenState extends State<ZyiarahSignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _referralCodeController = TextEditingController();
  
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;

  final Color brandColor = const Color(0xFF5D1B5E);

  void _signup() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (name.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      _showError('الرجاء إكمال جميع الحقول');
      return;
    }

    // تحقق من رقم الجوال السعودي (05XXXXXXXX أو 5XXXXXXXX أو بمفتاح 966).
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final normalizedPhone =
        phoneDigits.startsWith('966') ? phoneDigits.substring(3) : phoneDigits;
    if (!RegExp(r'^0?5\d{8}$').hasMatch(normalizedPhone)) {
      _showError('رقم الجوال غير صحيح — أدخل رقماً سعودياً يبدأ بـ 05');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showError('البريد الإلكتروني غير صحيح');
      return;
    }

    if (password.length < 6) {
      _showError('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    if (password != confirm) {
      _showError('كلمتا المرور غير متطابقتين');
      return;
    }

    if (!_acceptTerms || !_acceptPrivacy) {
      _showError('يجب الموافقة على الشروط والخصوصية للمتابعة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await _firebaseService.signUpWithRealEmailAndPassword(
        phone: phone,
        password: password,
        name: name,
        email: email,
      );

      final referralCode = _referralCodeController.text.trim();
      if (referralCode.isNotEmpty && credential.user != null) {
        // فشل تطبيق كود الإحالة يجب ألا يُجهض حساباً أُنشئ فعلاً (وإلا يعلق المستخدم
        // بـ«فشل الإنشاء» ثم «البريد مسجّل مسبقاً»). نتجاهله بصمت.
        try {
          await ZyiarahReferralService().applyReferralCode(
            newUserId: credential.user!.uid,
            referralCode: referralCode,
          );
        } catch (_) {/* إحالة غير صالحة — لا يمنع المتابعة */}
      }

      if (!mounted) return;
      // كشاشة الدخول: نذهب للجذر ويوجّه AuthWrapper بعد أن يُحمّل المزوّد الدور —
      // بدل القفز إلى '/client' قبل أن يلحق المزوّد فيردّنا الحارس ونعود للترحيب.
      context.go('/');
    } on FirebaseAuthException catch (e) {
      // رسائل عربية واضحة بدل استثناء Firebase الإنجليزي الخام.
      final msg = switch (e.code) {
        'email-already-in-use' =>
          'هذا البريد مسجّل مسبقاً — سجّل الدخول بدلاً من إنشاء حساب جديد',
        'invalid-email' => 'صيغة البريد الإلكتروني غير صحيحة',
        'weak-password' => 'كلمة المرور ضعيفة — استخدم 6 أحرف أو أكثر',
        'network-request-failed' =>
          'تعذّر الاتصال — تحقّق من الإنترنت وأعد المحاولة',
        _ => 'تعذّر إنشاء الحساب، أعد المحاولة',
      };
      _showError(msg);
    } catch (_) {
      _showError('تعذّر إنشاء الحساب، أعد المحاولة');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 20),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        context.go('/');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "مرحباً بك",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: brandColor,
                  ),
                ),
                Text(
                  "إنشاء حساب جديد",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 40),
                
                _buildFieldLabel("الاسم"),
                _buildTextField(_nameController, "أدخل الاسم الكامل"),
                
                const SizedBox(height: 15),
                _buildFieldLabel("رقم الجوال"),
                _buildTextField(_phoneController, "5XXXXXXXX", keyboardType: TextInputType.phone),
                
                const SizedBox(height: 15),
                _buildFieldLabel("البريد الالكتروني"),
                _buildTextField(_emailController, "example@mail.com", keyboardType: TextInputType.emailAddress),
                
                const SizedBox(height: 15),
                _buildFieldLabel("كلمه المرور"),
                _buildTextField(
                  _passwordController, 
                  "********", 
                  isPassword: true, 
                  isVisible: _isPasswordVisible,
                  onToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                
                const SizedBox(height: 15),
                _buildFieldLabel("تاكيد كلمه المرور"),
                _buildTextField(
                  _confirmPasswordController, 
                  "********", 
                  isPassword: true, 
                  isVisible: _isConfirmVisible,
                  onToggle: () => setState(() => _isConfirmVisible = !_isConfirmVisible),
                ),
                
                const SizedBox(height: 15),
                _buildFieldLabel("كود الإحالة (اختياري)"),
                _buildTextField(
                  _referralCodeController,
                  "أدخل كود الإحالة إن وجد",
                  textCapitalization: TextCapitalization.characters,
                ),

                const SizedBox(height: 25),
                _buildLegalCheckbox(
                  "أوافق على الشروط والأحكام", 
                  _acceptTerms, 
                  (v) => setState(() => _acceptTerms = v!),
                  () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ZyiarahTermsScreen())),
                ),
                _buildLegalCheckbox(
                  "أوافق على سياسة الخصوصية", 
                  _acceptPrivacy, 
                  (v) => setState(() => _acceptPrivacy = v!),
                  () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ZyiarahPrivacyScreen())),
                ),
                
                const SizedBox(height: 40),
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A0E0E)))
                    : ElevatedButton(
                        onPressed: _signup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: Text(
                          "انشاء حساب",
                          style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                const SizedBox(height: 30),
              ],
            ),
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
    TextCapitalization textCapitalization = TextCapitalization.none,
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
        textCapitalization: textCapitalization,
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

  Widget _buildLegalCheckbox(String label, bool value, Function(bool?) onChanged, VoidCallback onLinkTap) {
    return Row(
      children: [
        Checkbox(
          value: value, 
          onChanged: onChanged,
          fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? brandColor : null),
        ),
        GestureDetector(
          onTap: onLinkTap,
          child: Text(
            label,
            style: GoogleFonts.tajawal(
              fontSize: 14, 
              color: Colors.blue[800],
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}
