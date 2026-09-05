import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/screens/support_screen.dart';

/// يُنقّي رقم الدعم المخزَّن في اللوحة إلى أرقام فقط (مع + اختيارية في البداية).
/// القيمة الحيّة كانت «+966 53 048 9016» بعلامات اتجاه (U+202D/U+202C)
/// ومسافات، فصار الرابط `wa.me/%E2%80%AD+966%2053…` ويرفضه واتساب والهاتف معاً.
/// [forWhatsapp] يُسقط علامة + أيضاً لأن wa.me يقبل الأرقام الدولية العارية فقط.
String supportContactDigits(String? raw, {bool forWhatsapp = false}) {
  if (raw == null) return '';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final plus = !forWhatsapp && raw.trim().contains('+') ? '+' : '';
  return '$plus$digits';
}

class ZyiarahSupportFab extends StatelessWidget {
  const ZyiarahSupportFab({super.key});

  // canLaunchUrl + SnackBar: بدونهما غياب واتساب/تطبيق الهاتف يجعل الضغطة صامتة تماماً.
  Future<void> _launchSupportUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await canLaunchUrl(uri) &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر فتح تطبيق التواصل — تأكد من تثبيته على جهازك'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر الاتصال بالدعم: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

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
            
            // الرقم الثابت القديم كان placeholder لا يصل لأحد — نقرأ من نفس مفاتيح
            // settings_screen (system_configs/main_settings) ليكون مصدر الرقم واحداً ويُحدَّث من اللوحة.
            // StatefulBuilder ليتاح «إعادة المحاولة» عند فشل البث (يعيد الاشتراك بالاستعلام).
            StatefulBuilder(
              builder: (context, setSheetState) => StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('system_configs')
                    .doc('main_settings')
                    .snapshots(),
                builder: (context, snapshot) {
                  // فشل قراءة الإعدادات: لا أزرار بأرقام placeholder ميتة —
                  // صف خطأ مع إعادة محاولة، والتذكرة أدناه تبقى المسار المضمون.
                  if (snapshot.hasError) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('تعذّر تحميل أرقام التواصل',
                                style: GoogleFonts.tajawal(fontSize: 12, color: Colors.red)),
                          ),
                          TextButton(
                            onPressed: () => setSheetState(() {}),
                            child: Text('إعادة المحاولة',
                                style: GoogleFonts.tajawal(
                                    fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF660033))),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    );
                  }
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  // لا قيم افتراضية بعد اليوم: زر غائب خير من رقم يتصل بلا أحد.
                  // toString لا cast: لو خُزّن الرقم كـ num من اللوحة لا نريد استثناء cast.
                  final whatsapp = supportContactDigits(
                      data?['support_whatsapp']?.toString(),
                      forWhatsapp: true);
                  final phone =
                      supportContactDigits(data?['support_phone']?.toString());
                  return Column(
                    children: [
                      if (whatsapp.isNotEmpty)
                        _buildOption(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: "تحدث معنا عبر الواتساب",
                          color: const Color(0xFF25D366),
                          onTap: () => _launchSupportUrl(ctx, 'https://wa.me/$whatsapp'),
                        ),
                      if (phone.isNotEmpty)
                        _buildOption(
                          icon: Icons.phone_in_talk_rounded,
                          title: "اتصال هاتفي مباشر",
                          color: const Color(0xFF3B82F6),
                          onTap: () => _launchSupportUrl(ctx, 'tel:$phone'),
                        ),
                    ],
                  );
                },
              ),
            ),
            _buildOption(
              icon: Icons.support_agent_rounded,
              title: "فتح تذكرة دعم فني",
              color: const Color(0xFF660033),
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
      backgroundColor: const Color(0xFF660033),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      icon: const Icon(Icons.support_agent_rounded, color: Colors.white),
      label: Text("مركز العناية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
