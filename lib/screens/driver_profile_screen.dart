import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverProfileScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const DriverProfileScreen({super.key, this.onLogout});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  static const Color _brand = Color(0xFF5D1B5E);
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('حسابي',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: uid == null
            ? const Center(child: Text('يرجى تسجيل الدخول'))
            : FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(uid)
                    .get(),
                builder: (context, snap) {
                  final data =
                      snap.data?.data() as Map<String, dynamic>? ?? {};
                  final name = data['name'] as String? ?? 'سائق زيارة';
                  final phone = data['phone'] as String? ??
                      _auth.currentUser?.phoneNumber ??
                      'غير محدد';
                  final email = _auth.currentUser?.email ?? 'غير محدد';
                  final totalTasks =
                      (data['rides'] as num?)?.toInt() ?? 0;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildProfileHeader(name, totalTasks),
                        const SizedBox(height: 16),
                        _buildInfoCard(phone, email),
                        const SizedBox(height: 16),
                        _buildAchievementCard(totalTasks),
                        const SizedBox(height: 16),
                        _buildMenuCard(context),
                        const SizedBox(height: 16),
                        _buildLogoutButton(context),
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildProfileHeader(String name, int totalTasks) {
    String rank = 'عامل جديد';
    Color rankColor = Colors.grey;
    if (totalTasks >= 100) {
      rank = 'عامل ماسي';
      rankColor = Colors.blue;
    } else if (totalTasks >= 50) {
      rank = 'عامل ذهبي';
      rankColor = Colors.amber;
    } else if (totalTasks >= 10) {
      rank = 'عامل فضي';
      rankColor = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5D1B5E), Color(0xFF7E3080)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white30, width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 46),
          ),
          const SizedBox(height: 14),
          Text(name,
              style: GoogleFonts.tajawal(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22)),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: rankColor.withValues(alpha: 0.4)),
            ),
            child: Text(rank,
                style: GoogleFonts.tajawal(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text('$totalTasks مهمة منجزة',
                    style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String phone, String email) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('معلومات الحساب',
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 14),
          _infoRow(Icons.phone_rounded, 'رقم الجوال', phone),
          const Divider(height: 20),
          _infoRow(Icons.email_rounded, 'البريد الإلكتروني', email),
          const Divider(height: 20),
          _infoRow(Icons.badge_outlined, 'نوع الحساب', 'سائق معتمد'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: _brand, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.tajawal(
                    color: Colors.grey[500], fontSize: 11)),
            Text(value,
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildAchievementCard(int totalTasks) {
    final badges = [
      {'icon': Icons.verified, 'label': 'مبتدئ', 'required': 1},
      {'icon': Icons.workspace_premium, 'label': 'نشط', 'required': 10},
      {'icon': Icons.auto_awesome, 'label': 'محترف', 'required': 50},
      {'icon': Icons.diamond, 'label': 'نخبة', 'required': 100},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('أوسمة التميز',
              style: GoogleFonts.tajawal(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: badges.map((b) {
              final earned = totalTasks >= (b['required'] as int);
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: earned
                          ? _brand.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      b['icon'] as IconData,
                      color: earned ? _brand : Colors.grey[300],
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    b['label'] as String,
                    style: GoogleFonts.tajawal(
                      fontSize: 11,
                      fontWeight:
                          earned ? FontWeight.bold : FontWeight.normal,
                      color: earned ? Colors.black87 : Colors.grey[400],
                    ),
                  ),
                  if (!earned)
                    Text(
                      '${b['required']}+',
                      style: GoogleFonts.tajawal(
                          fontSize: 9, color: Colors.grey[400]),
                    ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          _menuItem(
            icon: Icons.support_agent_rounded,
            label: 'الدعم الفني',
            color: Colors.blue,
            onTap: _openWhatsApp,
          ),
          const Divider(height: 1, indent: 56),
          _menuItem(
            icon: Icons.shield_outlined,
            label: 'سياسة الخصوصية',
            color: Colors.teal,
            onTap: () => launchUrl(Uri.parse('https://zyiarah.com/privacy'),
                mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: GoogleFonts.tajawal(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 14, color: Colors.grey),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: _confirmLogout,
        icon: const Icon(Icons.logout_rounded, color: Colors.red),
        label: Text('تسجيل الخروج',
            style: GoogleFonts.tajawal(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('تسجيل الخروج',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text('هل تريد بالتأكيد تسجيل الخروج؟',
              style: GoogleFonts.tajawal()),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء', style: GoogleFonts.tajawal())),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('نعم، خروج',
                    style: GoogleFonts.tajawal(color: Colors.red))),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.lightImpact();
    if (widget.onLogout != null) {
      widget.onLogout!();
    } else {
      // الخروج المركزي (B3): تنظيف كامل للذاكرة بدل _auth.signOut() المباشرة
      await ZyiarahFirebaseService().signOut();
      if (!mounted) return;
      context.go('/login');
    }
  }

  Future<void> _openWhatsApp() async {
    String adminPhone = '966500000000';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_configs')
          .doc('main_settings')
          .get();
      adminPhone = doc.data()?['admin_whatsapp'] ?? adminPhone;
    } catch (_) {}
    final url =
        'https://wa.me/$adminPhone?text=${Uri.encodeComponent("استفسار من سائق زيارة")}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}
