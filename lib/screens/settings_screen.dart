import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/screens/support_screen.dart';

class ZyiarahSettingsScreen extends StatelessWidget {
  const ZyiarahSettingsScreen({super.key});

  static const Color _brand = Color(0xFF5D1B5E);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F0F7),
        appBar: AppBar(
          title: Text('الإعدادات والدعم',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader('الدعم والتواصل'),
              const SizedBox(height: 8),
              _buildCard([
                _settingsTile(
                  context,
                  icon: Icons.support_agent_rounded,
                  color: _brand,
                  title: 'تذاكر الدعم الفني',
                  subtitle: 'متابعة طلباتك أو فتح تذكرة جديدة',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()),
                    );
                  },
                ),
                _divider(),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('system_configs')
                      .doc('main_settings')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                    final whatsapp = data?['support_whatsapp'] ?? '966500000000';
                    final phone = data?['support_phone'] ?? '920000000';
                    return Column(
                      children: [
                        _settingsTile(
                          context,
                          icon: Icons.chat_rounded,
                          color: const Color(0xFF25D366),
                          title: 'الدعم عبر WhatsApp',
                          subtitle: 'تواصل معنا لأي استفسار أو مشكلة',
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final url = 'https://wa.me/$whatsapp';
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                        _divider(),
                        _settingsTile(
                          context,
                          icon: Icons.phone_in_talk_rounded,
                          color: const Color(0xFF2563EB),
                          title: 'الاتصال المباشر',
                          subtitle: 'تواصل هاتفياً مع خدمة العملاء',
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final url = 'tel:$phone';
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url));
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ]),
              const SizedBox(height: 20),
              _sectionHeader('القانوني والخصوصية'),
              const SizedBox(height: 8),
              _buildCard([
                _settingsTile(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  color: _brand,
                  title: 'سياسة الخصوصية',
                  subtitle: 'كيفية استخدامنا للموقع الجغرافي والبيانات',
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    const url = 'https://zyiarah.com/privacy';
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ]),
              const SizedBox(height: 20),
              _sectionHeader('منطقة الخطر'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: _settingsTile(
                  context,
                  icon: Icons.delete_forever_rounded,
                  color: Colors.red,
                  title: 'حذف الحساب نهائياً',
                  subtitle: 'مطلوب من قبل Apple لحذف بياناتك بالكامل',
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _showDeleteConfirmation(context);
                  },
                  showChevron: false,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 2),
      child: Text(
        title,
        style: GoogleFonts.tajawal(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: children),
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showChevron = true,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                  Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            if (showChevron) Icon(Icons.chevron_left, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 58, endIndent: 16);

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Text('حذف الحساب نهائياً',
                  style: GoogleFonts.tajawal(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من رغبتك في حذف حسابك؟ سيتم مسح كافة سجلاتك وطلباتك ولا يمكن التراجع عن هذا الإجراء.',
            style: GoogleFonts.tajawal(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.tajawal(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  try {
                    await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                    await user.delete();
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('تم حذف الحساب بالكامل من أنظمتنا', style: GoogleFonts.tajawal())),
                      );
                      Navigator.of(ctx).popUntil((route) => route.isFirst);
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text('يرجى تسجيل الخروج ثم الدخول مرة أخرى قبل الحذف', style: GoogleFonts.tajawal()),
                        ),
                      );
                      Navigator.pop(ctx);
                    }
                  }
                }
              },
              child: Text('نعم، احذف حسابي', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
