import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminMarketingScreen extends StatefulWidget {
  const AdminMarketingScreen({super.key});

  @override
  State<AdminMarketingScreen> createState() => _AdminMarketingScreenState();
}

class _AdminMarketingScreenState extends State<AdminMarketingScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  void _sendNotification() {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال عنوان ونص الإشعار')));
      return;
    }
    // TODO: Trigger Cloud Function to broadcast push notification
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم جدولة إرسال الإشعار لجميع المستخدمين')));
    _titleController.clear();
    _bodyController.clear();
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
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.campaign, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Text(
              "إرسال إشعار للجميع (Push Notification)",
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: "عنوان الإشعار", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bodyController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: "نص العرض أو رسالة الإشعار", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _sendNotification,
              icon: const Icon(Icons.send),
              label: Text("إرسال الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
