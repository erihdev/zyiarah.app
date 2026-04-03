import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signature/signature.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ZyiarahContractSigningScreen extends StatefulWidget {
  final String planName;
  const ZyiarahContractSigningScreen({super.key, required this.planName});

  @override
  State<ZyiarahContractSigningScreen> createState() => _ZyiarahContractSigningScreenState();
}

class _ZyiarahContractSigningScreenState extends State<ZyiarahContractSigningScreen> {
  final SignatureController _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  final Color brandPurple = const Color(0xFF5D1B5E);
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitContract() async {
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى التوقيع أولاً')));
      return;
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    try {
      final user = auth.currentUser;
      await _controller.toPngBytes();
      
      // Note: In a production app, you'd upload signatureData to Firebase Storage here
      // and get a download URL. For this TestFlight version, we proceed with identifying
      // the contract in Firestore so the Admin can see it.

      await firestore.collection('contracts').add({
        'userId': user?.uid,
        'userPhone': user?.phoneNumber,
        'planName': widget.planName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تم توقيع العقد'),
            content: const Text('تم إرسال عقدك للإدارة. ستجد النسخة الموقعة في قسم "عقودي" بعد اعتمادها.'),
            actions: [
              TextButton(onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                Navigator.pop(context);
              }, child: const Text('حسناً'))
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('توقيع العقد الإلكتروني', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: brandPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('عقد تقديم خدمات منزلية - ${widget.planName}', 
                      style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(
                        'يتعهد الطرف الثاني (العميل) بالالتزام ببنود الاتفاقية ومواعيد الزيارة المحددة في الباقة المختارة. '
                        'يحق للطرف الأول (زيارة) تعديل المواعيد بالتنسيق مع العميل. '
                        'يتم تفعيل العقد بعد سداد القيمة واعتماده من الإدارة.',
                        style: GoogleFonts.tajawal(height: 2.0, color: Colors.blueGrey[700]),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text('التوقيع الإلكتروني:', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: brandPurple.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Signature(
                          controller: _controller,
                          backgroundColor: Colors.grey[50]!,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _controller.clear(),
                          icon: const Icon(Icons.clear, color: Colors.red, size: 18),
                          label: Text('مسح التوقيع', style: GoogleFonts.tajawal(color: Colors.red)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitContract,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('اعتماد وتوقيع العقد', style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
