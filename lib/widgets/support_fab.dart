import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/screens/support_screen.dart';

class ZyiarahSupportFab extends StatelessWidget {
  const ZyiarahSupportFab({super.key});

  void _showSupportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 25),
            Text("مركز العناية بالعملاء", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
            Text("نحن هنا لخدمتك على مدار الساعة", style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 30),
            
            _buildOption(
              icon: Icons.chat_bubble_outline_rounded,
              title: "تحدث معنا عبر الواتساب",
              color: const Color(0xFF25D366),
              onTap: () => launchUrl(Uri.parse('https://wa.me/966550000000'), mode: LaunchMode.externalApplication),
            ),
            _buildOption(
              icon: Icons.phone_in_talk_rounded,
              title: "اتصال هاتفي مباشر",
              color: const Color(0xFF3B82F6),
              onTap: () => launchUrl(Uri.parse('tel:+966550000000')),
            ),
            _buildOption(
              icon: Icons.support_agent_rounded,
              title: "فتح تذكرة دعم فني",
              color: const Color(0xFF5D1B5E),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()));
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.05),
          ),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 18)),
              const SizedBox(width: 15),
              Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showSupportOptions(context),
      backgroundColor: const Color(0xFF5D1B5E),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
      label: Text("مركز العناية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
