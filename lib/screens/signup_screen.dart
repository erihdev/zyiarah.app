import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;

  final Color brandColor = const Color(0xFF4A0E0E);

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

    if (password != confirm) {
      _showError('كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _firebaseService.signUpWithPhoneAndPassword(
        phone: phone,
        password: password,
        name: name,
        email: email,
      );
      
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (context) => ClientDashboard()),
        (route) => false,
      );
    } catch (e) {
      _showError('خطأ في إنشاء الحساب: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.tajawal())));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                    onPressed: () => Navigator.pop(context),
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
