import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:zyiarah/screens/driver_dashboard.dart';
import 'package:zyiarah/screens/client_dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ZyiarahLoginScreen extends StatefulWidget {
  const ZyiarahLoginScreen({super.key});

  @override
  State<ZyiarahLoginScreen> createState() => _ZyiarahLoginScreenState();
}

class _ZyiarahLoginScreenState extends State<ZyiarahLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final ZyiarahFirebaseService _firebaseService = ZyiarahFirebaseService();

  bool _isLoading = false;
  bool _codeSent = false;
  String? _verificationId;

  void _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رقم جوال صحيح')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _firebaseService.verifyPhoneNumber(phone, (String verificationId) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال رمز التحقق')),
        );
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: ${e.toString()}')),
      );
    }
  }

  void _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length < 6 || _verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رمز صحيح')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await _firebaseService.verifyOTP(
        _verificationId!,
        otp,
      );

      if (userCredential.user != null) {
        // التحقق من دور المستخدم
        String role = await _firebaseService.getUserRole(userCredential.user!.uid);

        if (!mounted) return;
        
        // التوجيه بناءً على الدور
        if (role == 'driver') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DriverDashboard()),
          );
        } else {
          // الافتراضي (client)
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ClientDashboard()),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('رمز التحقق غير صحيح: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  const Icon(Icons.flash_on, size: 100, color: Color(0xFF1E3A8A)),
                  const SizedBox(height: 40),
                  Text(
                    "مرحباً بك في زيارة",
                    style: GoogleFonts.tajawal(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E3A8A),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _codeSent 
                        ? "أدخل رمز التحقق المرسل لجوالك"
                        : "أدخل رقم جوالك للبدء في طلب الخدمات",
                    style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 50),
                  
                  if (!_codeSent)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Text("+966", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                hintText: "5xxxxxxxx",
                                border: InputBorder.none,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: "X X X X X X",
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(letterSpacing: 8),
                      ),
                    ),

                  const SizedBox(height: 30),
                  
                  _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF1E3A8A)))
                    : ElevatedButton(
                    onPressed: _codeSent ? _verifyOTP : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text(
                      _codeSent ? "تأكيد والتحقق" : "إرسال الرمز",
                      style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  if (_codeSent && !_isLoading) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _codeSent = false;
                        });
                      },
                      child: Text(
                        "تعديل رقم الجوال",
                        style: GoogleFonts.tajawal(
                          color: const Color(0xFF1E3A8A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
