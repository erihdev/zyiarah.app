import 'package:flutter/material.dart';

class ZyiarahSettingsScreen extends StatelessWidget {
  const ZyiarahSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الإعدادات والدعم", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Color(0xFF1E3A8A)),
              title: const Text("سياسة الخصوصية"),
              subtitle: const Text("كيفية استخدامنا للموقع الجغرافي والبيانات"),
              onTap: () {
                // هنا سيتم فتح رابط سياسة الخصوصية عبر url_launcher
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم فتح رابط سياسة الخصوصية لاحقاً')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.support_agent, color: Colors.green),
              title: const Text("الدعم الفني (WhatsApp)"),
              subtitle: const Text("تواصل معنا لأي استفسار أو مشكلة"),
              onTap: () {
                // هنا سيتم فتح واتساب المؤسسة
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم تحويلك إلى خدمة العملاء')),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("حذف الحساب نهائياً", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text("مطلوب من قبل Apple لحذف بياناتك بالكامل"),
              onTap: () {
                _showDeleteConfirmation(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("تأكيد حذف الحساب", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: const Text("هل أنت متأكد من رغبتك في حذف حسابك؟ سيتم مسح كافة سجلاتك وطلباتك ولا يمكن التراجع عن هذا الإجراء استناداً لسياسات الخصوصية."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الحساب وتسجيل الخروج بنجاح')),
                );
                // هنا يفترض المناداة لـ FirebaseAuth.instance.currentUser?.delete()
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: const Text("نعم، احذف حسابي"),
            ),
          ],
        ),
      ),
    );
  }
}
