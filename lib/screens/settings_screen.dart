import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/screens/support_screen.dart';

class ZyiarahSettingsScreen extends StatelessWidget {
  const ZyiarahSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الإعدادات والدعم", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ListTile(
              leading: const Icon(Icons.support_agent, color: Color(0xFF5D1B5E)),
              title: const Text("تذاكر الدعم الفني"),
              subtitle: const Text("متابعة طلباتك الحالية أو فتح تذكرة جديدة"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ZyiarahSupportScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.privacy_tip, color: Color(0xFF5D1B5E)),
              title: const Text("سياسة الخصوصية"),
              subtitle: const Text("كيفية استخدامنا للموقع الجغرافي والبيانات"),
              onTap: () {
                // هنا سيتم فتح رابط سياسة الخصوصية عبر url_launcher
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم فتح رابط سياسة الخصوصية لاحقاً')),
                );
              },
            ),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('system_configs').doc('main_settings').snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final whatsapp = data?['support_whatsapp'] ?? "966500000000";
                final phone = data?['support_phone'] ?? "920000000";

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.support_agent, color: Colors.green),
                      title: const Text("الدعم الفني (WhatsApp)"),
                      subtitle: const Text("تواصل معنا لأي استفسار أو مشكلة"),
                      onTap: () async {
                        final url = "https://wa.me/$whatsapp";
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.phone_in_talk_rounded, color: Colors.blue),
                      title: const Text("الاتصال المباشر"),
                      subtitle: const Text("تواصل هاتفياً مع خدمة العملاء"),
                      onTap: () async {
                        final url = "tel:$phone";
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(Uri.parse(url));
                        }
                      },
                    ),
                  ],
                );
              }
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
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  try {
                    // 1. Delete user record in Firestore (optional but recommended for ZATCA/Privacy)
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                    
                    // 2. Delete the actual Auth account
                    await user.delete();

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حذف الحساب بالكامل من أنظمتنا')),
                      );
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("خطأ: يرجى تسجيل الخروج ثم الدخول مرة أخرى قبل الحذف (متطلب أمني)")),
                      );
                      Navigator.pop(context);
                    }
                  }
                }
              },
              child: const Text("نعم، احذف حسابي"),
            ),
          ],
        ),
      ),
    );
  }
}
