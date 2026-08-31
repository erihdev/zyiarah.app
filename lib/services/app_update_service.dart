import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// إشعار توفّر تحديث للتطبيق — متحكَّم به بالكامل من الإدارة عبر Firestore.
///
/// مستند الإعداد: system_configs/app_update
/// {
///   "enabled": true,                 // تفعيل/تعطيل الإشعار
///   "latest_build_android": 208,     // آخر بناء أندرويد منشور (عدّاد مستقل)
///   "latest_build_ios": 261,         // آخر بناء iOS منشور (عدّاد مستقل)
///   "latest_build": 208,             // احتياطي قديم — يُقرأ عند غياب حقل المنصة
///   "force": false,                  // true = إجباري (لا يمكن تجاهله)
///   "message": "نص الرسالة...",       // اختياري
///   "ios_url": "https://...",        // اختياري (افتراضي متجر آبل)
///   "android_url": "https://..."     // اختياري (افتراضي Google Play)
/// }
///
/// ⚠️ عدّادا البناء منفصلان بين المنصتين (iOS بلغ 261 بينما أندرويد 208) —
/// حقل latest_build الموحّد القديم ضُبط مرة على رقم iOS فرأى **كل** مختبري
/// أندرويد على أحدث نسخة مطالبة تحديث إجبارية زائفة لأسابيع (اكتُشفت
/// 2026-08-31). لذلك يقرأ الفحص حقل منصته أولاً ولا يسقط للموحّد إلا عند غيابه.
class ZyiarahAppUpdateService {
  static const String _defaultIosUrl =
      'https://apps.apple.com/app/id6760955777';
  static const String _defaultAndroidUrl =
      'https://play.google.com/store/apps/details?id=com.zyiarah.zyiarah';

  /// يفحص توفّر تحديث ويعرض إشعاراً مركزياً للعميل عند الحاجة فقط.
  /// صامت تماماً عند أي خطأ — لا يُعطّل الواجهة.
  static Future<void> checkAndPrompt(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_configs')
          .doc('app_update')
          .get();
      if (!doc.exists || doc.data() == null) return;
      final d = doc.data()!;
      if (d['enabled'] != true) return;

      final String platformField = defaultTargetPlatform == TargetPlatform.iOS
          ? 'latest_build_ios'
          : 'latest_build_android';
      final int latestBuild =
          ((d[platformField] ?? d['latest_build']) as num?)?.toInt() ?? 0;
      final info = await PackageInfo.fromPlatform();
      final int currentBuild = int.tryParse(info.buildNumber) ?? 0;

      // يظهر للنسخ الأقدم فقط — من حدّث لا يراه
      if (currentBuild >= latestBuild) return;

      final bool force = d['force'] == true;
      final String message =
          ((d['message'] as String?)?.trim().isNotEmpty ?? false)
              ? d['message'] as String
              : 'يتوفّر إصدار جديد من التطبيق بمزايا وتحسينات مهمة. '
                  'يرجى التحديث للاستمرار بأفضل تجربة.';

      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: !force,
        builder: (_) => _UpdateDialog(
          message: message,
          storeUrl: _storeUrl(d),
          force: force,
        ),
      );
    } catch (_) {
      // صامت
    }
  }

  static String _storeUrl(Map<String, dynamic> d) {
    final iosUrl = (d['ios_url'] as String?)?.trim();
    final androidUrl = (d['android_url'] as String?)?.trim();
    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (isIos) {
      return (iosUrl != null && iosUrl.isNotEmpty) ? iosUrl : _defaultIosUrl;
    }
    return (androidUrl != null && androidUrl.isNotEmpty)
        ? androidUrl
        : _defaultAndroidUrl;
  }
}

class _UpdateDialog extends StatelessWidget {
  final String message;
  final String storeUrl;
  final bool force;
  const _UpdateDialog({
    required this.message,
    required this.storeUrl,
    required this.force,
  });

  static const Color _brand = Color(0xFF660033);

  /// يفتح المتجر بشكل مضمون. لا يعتمد على canLaunchUrl لأنه يُرجع false زائفاً على
  /// أندرويد 11+ حين لا تُعلَن حزمة الاستهداف — ما كان يجعل الزر ميتاً ويحبس المستخدم
  /// في وضع الإجبار. يجرّب عدة أنماط، وإن تعذّر كلها ينسخ الرابط فلا يعلق المستخدم أبداً.
  Future<void> _openStore(BuildContext context) async {
    // التقط الـ messenger قبل أي await حتى لا نستخدم context عبر فجوة غير متزامنة.
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(storeUrl);
    for (final mode in [LaunchMode.externalApplication, LaunchMode.platformDefault]) {
      try {
        if (await launchUrl(uri, mode: mode)) return;
      } catch (_) {/* جرّب النمط التالي */}
    }
    // مخرج احتياطي دائم: انسخ الرابط واعرض رسالة (لا تحبس المستخدم في وضع الإجبار).
    await Clipboard.setData(ClipboardData(text: storeUrl));
    messenger.showSnackBar(SnackBar(
      content: Text('تعذّر فتح المتجر تلقائياً — نُسِخ الرابط، الصقه في المتصفح:\n$storeUrl',
          style: GoogleFonts.tajawal()),
      duration: const Duration(seconds: 8),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !force, // الإجباري لا يمكن إغلاقه بزر الرجوع
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.system_update, color: _brand, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'يتوفّر تحديث جديد',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    fontSize: 14, color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openStore(context),
                icon: const Icon(Icons.download_rounded),
                label: Text('تحديث الآن',
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('لاحقاً',
                    style: GoogleFonts.tajawal(color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }
}
