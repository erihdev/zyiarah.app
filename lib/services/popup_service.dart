import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zyiarah/screens/subscription_plans_screen.dart';
import 'package:zyiarah/screens/ac_service_details_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/screens/hourly_details_screen.dart';

class ZyiarahPopupService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static void checkAndShowPopup(BuildContext context) {
    // Listen for the latest popup notification
    _db.collection('notifications_log')
        .where('type', isEqualTo: 'popup')
        .orderBy('sent_at', descending: true)
        .limit(1)
        .get()
        .then((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final sentAt = (data['sent_at'] as Timestamp?)?.toDate();

        // Only show if sent in the last 24 hours (or adjust as needed)
        if (sentAt != null && DateTime.now().difference(sentAt).inHours < 24) {
          if (!context.mounted) return;
          _showRahaStylePopup(context, data);
        }
      }
    }).catchError((e) {
      debugPrint('POPUP_SERVICE_ERROR: $e');
    });
  }

  static void _showRahaStylePopup(BuildContext context, Map<String, dynamic> data) {
    final title = data['title'] ?? '';
    final body = data['body'] ?? '';
    final imageUrl = data['popup_image'] as String?;
    final List<dynamic> buttons = data['popup_buttons'] ?? [];

    showDialog(
      context: context,
      barrierDismissible: true,
      // سياق الحوار باسم مستقل: التنقّل وSnackBar يستخدمان سياق الشاشة الأم (context)
      // لأن سياق الحوار يُغلَق قبل التنقّل.
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Main Modal Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF660033), Color(0xFF3B0A3B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 5),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Logo
                    Image.asset('assets/logo.png', height: 60, color: Colors.white, errorBuilder: (_, __, ___) => const Icon(Icons.star, color: Colors.white, size: 40)),
                    const SizedBox(height: 20),
                    
                    // Headline
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Body text if any
                    if (body.isNotEmpty)
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 14),
                      ),
                    const SizedBox(height: 25),

                    // Image if provided
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
                          errorWidget: (context, url, error) => const SizedBox.shrink(),
                        ),
                      ),
                    if (imageUrl != null && imageUrl.isNotEmpty) const SizedBox(height: 25),

                    // Buttons (Raha Style)
                    ...buttons.map((btn) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            // نغلق الحوار أولاً: Navigator.push يُدرج الوجهة فوق الحوار فوراً،
                            // فكان pop اللاحق يزيل الشاشة الهدف بدل الحوار — والزر يبدو ميتاً.
                            Navigator.pop(dialogContext); // Close Popup
                            // 1. Handle External Links
                            if (btn['link'] != null && btn['link'].toString().isNotEmpty) {
                              final uri = Uri.tryParse(btn['link'].toString());
                              try {
                                // نتحقق من نتيجة launchUrl: الرابط نص حر من اللوحة،
                                // وفشله بصمت يعني وجهة موعودة تضيع بلا أي تنبيه.
                                final ok = uri != null &&
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('تعذّر فتح الرابط المُرفق بالإعلان'),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('تعذّر فتح الرابط: $e'),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            }
                            // 2. Handle Internal Sections
                            else if (data['targetSection'] != null) {
                              final section = data['targetSection'];
                              if (!context.mounted) return;
                              _navigateBySection(context, section);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF660033),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            elevation: 0,
                          ),
                          child: Text(
                            btn['label'] ?? '',
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    )),
                    
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              
              // Close Button (Overlay)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _navigateBySection(BuildContext context, String section) {
    switch (section) {
      case 'home':
        // Stay on home/dashboard
        break;
      // نفس قاعدة 'maintenance' أدناه: بانر لا يفعل شيئاً = فشل صامت،
      // والشاشة حيّة ومستخدمة من client_dashboard بنفس الاستدعاء.
      case 'hourly':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const HourlyCleaningDetailsScreen(serviceName: "نظافة بالساعة")));
        break;
      case 'family_basket':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahSubscriptionPlansScreen()));
        break;
      // 'maintenance' يعني المكيفات في هذا النشاط — صيانة الأجهزة المنزلية حُذفت.
      // نوجّهه للشاشة الحيّة بدل تركه بلا وجهة: بانر لا يفعل شيئاً = فشل صامت.
      case 'maintenance':
      case 'ac':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const AcServiceDetailsScreen()));
        break;
      case 'contracts':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahContractsListScreen()));
        break;
      default:
        break;
    }
  }
}
