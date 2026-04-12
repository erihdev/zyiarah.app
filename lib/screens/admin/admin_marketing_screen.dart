import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/screens/admin/admin_coupons_screen.dart';
import 'package:zyiarah/screens/admin/admin_banners_screen.dart';

class AdminMarketingScreen extends StatefulWidget {
  const AdminMarketingScreen({super.key});

  @override
  State<AdminMarketingScreen> createState() => _AdminMarketingScreenState();
}

class _AdminMarketingScreenState extends State<AdminMarketingScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  bool _isSending = false;

  void _sendNotification() async {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال عنوان ونص الإشعار')));
      return;
    }
    
    setState(() => _isSending = true);
    try {
      await FirebaseFirestore.instance.collection('notifications_log').add({
        'title': _titleController.text,
        'body': _bodyController.text,
        'target': 'all',
        'created_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الإشعار لجميع المستخدمين بنجاح! ✅')));
      _titleController.clear();
      _bodyController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ جذري أثناء الإرسال: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("التسويق والإشعارات", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.campaign, size: 80, color: Color(0xFF1E293B)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCouponsScreen()));
              },
              icon: const Icon(Icons.local_offer, color: Color(0xFFE11D48)),
              label: Text("إدارة أكواد الخصم (Coupons)", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFFE11D48))),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFFE11D48), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 15),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBannersScreen()));
              },
              icon: const Icon(Icons.view_carousel, color: Color(0xFF2563EB)),
              label: Text("إدارة البنرات الإعلانية (Banners)", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF2563EB))),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFF2563EB), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 20),
            Text(
              "إرسال إشعار للجميع (Push Notification)",
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _titleController,
              enabled: !_isSending,
              decoration: const InputDecoration(labelText: "عنوان الإشعار", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bodyController,
              enabled: !_isSending,
              maxLines: 4,
              decoration: const InputDecoration(labelText: "نص العرض أو رسالة الإشعار", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 30),
            if (_isSending)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: LinearProgressIndicator(color: Color(0xFF1E293B)),
              ),
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendNotification,
              icon: const Icon(Icons.send),
              label: Text(_isSending ? "جاري الإرسال..." : "إرسال الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF1E293B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
