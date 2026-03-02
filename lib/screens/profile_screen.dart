import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ZyiarahProfileScreen extends StatelessWidget {
  const ZyiarahProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firebaseService = ZyiarahFirebaseService();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("الملف الشخصي", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // رأس الصفحة (Header)
              _buildHeader(user?.phoneNumber ?? "مستخدم زيارة"),
              
              const SizedBox(height: 20),
              
              // خيارات الحساب
              _buildMenuTile(Icons.history, "سجل الطلبات", () {}),
              _buildMenuTile(Icons.wallet, "المحفظة والفواتير", () {}),
              _buildMenuTile(Icons.shield_outlined, "سياسة الخصوصية", () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم فتح رابط سياسة الخصوصية لاحقاً')),
                );
              }),
              _buildMenuTile(Icons.support_agent, "الدعم الفني", () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم تحويلك إلى خدمة العملاء')),
                );
              }),
              
              const Divider(height: 40),
              
              // خيارات الخروج والحذف (متطلبات أبل)
              _buildMenuTile(Icons.logout, "تسجيل الخروج", () async {
                await firebaseService.signOut();
                Navigator.of(context).popUntil((route) => route.isFirst);
              }, color: Colors.orange),
              
              _buildMenuTile(Icons.delete_forever, "حذف الحساب نهائياً", () {
                _showDeleteConfirmation(context);
              }, color: Colors.red),
              
              const SizedBox(height: 40),
              GestureDetector(
                onTap: () => _launchErithWebsite('https://erihdev.com'),
                onLongPress: () => _showThankYouMessage(context),
                child: Text.rich(
                  TextSpan(
                    text: 'إصدار التطبيق 1.0.0 (Build 1)\nمؤسسة معاذ يحي محمد المالكي\nتم التطوير بواسطة\n',
                    style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey),
                    children: [
                      TextSpan(
                        text: 'إرث',
                        style: GoogleFonts.tajawal(
                          fontSize: 22,
                          color: const Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w900, // Black weight proxy
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String phone) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("أهلاً بك،", style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 14)),
              Text(phone, style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap, {Color color = const Color(0xFF1E3A8A)}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: GoogleFonts.tajawal(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text("حذف الحساب", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text("هل أنت متأكد من رغبتك في حذف الحساب؟ سيتم مسح كافة بياناتك وفواتيرك نهائياً ولا يمكن استعادتها.", style: GoogleFonts.tajawal()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("تراجع")),
            ElevatedButton(
              onPressed: () {
                // منطق الحذف النهائي من Firebase
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الحساب وتسجيل الخروج بنجاح')),
                );
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchErithWebsite(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  void _showThankYouMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'نفخر في (إرث) بأن نكون شركاء النجاح لمؤسسة معاذ المالكي 💙',
          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
