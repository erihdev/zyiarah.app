import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zyiarah/models/promo_coupon.dart';
import 'package:zyiarah/screens/hourly_details_screen.dart';
import 'package:zyiarah/screens/store_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/sofa_rug_details_screen.dart';
import 'package:zyiarah/screens/ac_service_details_screen.dart';
import 'package:zyiarah/screens/subscription_plans_screen.dart';
import 'package:zyiarah/services/zyiarah_referral_service.dart';
import 'package:zyiarah/theme/app_theme.dart';

/// قسم «العروض».
///
/// ثلاثة أقسام (تصميم Stitch، 2026-09-16):
/// 1. البانرات التي اختارت لها الإدارة `placement == 'offers'` — كما كان.
/// 2. كوبونات الخصم المعتمدة، بزرّ نسخ: من `promo_codes` وبالشروط نفسها التي
///    يفحصها validateCoupon عند الدفع، ولا يظهر منها إلا ما علّمته الإدارة
///    `show_in_offers` أو ما وُجِّه لهذا العميل شخصياً (إحالة/هدية).
/// 3. بطاقة برنامج الإحالة بكود العميل — الأرقام من ZyiarahReferralService
///    لا من نصّ ثابت كي لا تنفصل عمّا يدفعه الخادم فعلاً.
class ZyiarahOffersScreen extends StatefulWidget {
  /// للاختبارات: بثوث ووعود جاهزة بدل Firestore. حين يُحقن `coupons` يُؤخذ
  /// `currentUid` كما هو (null = زائر) بدل FirebaseAuth.
  final Stream<List<Map<String, dynamic>>>? banners;
  final Stream<List<PromoCoupon>>? coupons;
  final Future<String?>? referralCode;
  final String? currentUid;

  const ZyiarahOffersScreen({
    super.key,
    this.banners,
    this.coupons,
    this.referralCode,
    this.currentUid,
  });

  @override
  State<ZyiarahOffersScreen> createState() => _ZyiarahOffersScreenState();
}

class _ZyiarahOffersScreenState extends State<ZyiarahOffersScreen> {
  static const Color _brand = ZyiarahTheme.brand;

  late final Stream<List<Map<String, dynamic>>> _banners;
  Stream<List<PromoCoupon>>? _coupons;
  Future<String?>? _referral;
  String? _uid;

  @override
  void initState() {
    super.initState();
    final injected = widget.coupons != null;
    _uid = injected ? widget.currentUid : FirebaseAuth.instance.currentUser?.uid;

    _banners = widget.banners ??
        FirebaseFirestore.instance
            .collection('promo_banners')
            .where('isActive', isEqualTo: true)
            .snapshots()
            // التصفية محلية لأن Firestore لا يستعلم «= offers» مع بانرات بلا الحقل.
            .map((q) => q.docs
                .map((d) => d.data())
                .where((m) => m['placement'] == 'offers')
                .toList());

    final uid = _uid;
    if (uid != null) {
      _coupons = widget.coupons ??
          FirebaseFirestore.instance
              .collection(PromoCoupon.collectionPath)
              .where('status', isEqualTo: 'active')
              .snapshots()
              .map(PromoCoupon.fromQuery);
      _referral = widget.referralCode ??
          ZyiarahReferralService()
              .getOrCreateReferralCode(uid)
              .then<String?>((c) => c)
              .catchError((Object _) => null);
    }
  }

  Future<void> _handleTap(BuildContext context, Map<String, dynamic> data) async {
    final String routeType = data['routeType'] ?? 'none';
    final String actionUrl = data['actionUrl'] ?? '';
    if (routeType == 'whatsapp' && actionUrl.isNotEmpty) {
      final uri = Uri.parse(actionUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر فتح الرابط')));
      }
      return;
    }
    if (!context.mounted) return;
    Widget? dest;
    switch (routeType) {
      case '/hourly_cleaning':
        dest = const HourlyCleaningDetailsScreen(serviceName: 'تنظيف منزلي');
        break;
      case '/store':
        dest = const ZyiarahStoreScreen();
        break;
      case '/support':
        dest = const ZyiarahSupportScreen();
        break;
      case '/sofa_cleaning':
      case '/rug_cleaning':
        dest = const SofaRugCleaningDetailsScreen(serviceName: 'تنظيف الكنب والزل');
        break;
      case '/ac':
      case '/ac_service':
        dest = const AcServiceDetailsScreen();
        break;
      case '/subscriptions':
        dest = const ZyiarahSubscriptionPlansScreen();
        break;
    }
    if (dest != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => dest!));
    }
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
      backgroundColor: ZyiarahTheme.success,
    ));
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: Text('العروض',
              style: GoogleFonts.tajawal(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _banners,
          builder: (context, b) {
            final coupons = _coupons;
            if (coupons == null) return _content(b, null);
            return StreamBuilder<List<PromoCoupon>>(
              stream: coupons,
              builder: (context, k) => _content(b, k),
            );
          },
        ),
      ),
    );
  }

  Widget _content(AsyncSnapshot<List<Map<String, dynamic>>> b,
      AsyncSnapshot<List<PromoCoupon>>? k) {
    final bannersWaiting =
        b.connectionState == ConnectionState.waiting && !b.hasData;
    final couponsWaiting = k != null &&
        k.connectionState == ConnectionState.waiting &&
        !k.hasData;
    if (bannersWaiting && (k == null || couponsWaiting)) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }

    final banners = b.data ?? const <Map<String, dynamic>>[];
    final coupons = k?.hasData == true
        ? PromoCoupon.listableFor(k!.data!, _uid, DateTime.now())
        : const <PromoCoupon>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (b.hasError) _inlineError('تعذّر تحميل العروض، تحقّق من الاتصال'),
        for (final data in banners) _bannerCard(data),
        if (banners.isEmpty && !b.hasError && coupons.isEmpty && !(k?.hasError ?? false))
          _emptyOffers(),
        _sectionHeader(
          icon: Icons.confirmation_number_outlined,
          title: 'كوبونات الخصم المعتمدة',
          subtitle: 'انقر لنسخ الكوبون ثم أدخله عند الدفع',
        ),
        if (_uid == null)
          _hintCard(Icons.login_rounded, 'سجّل الدخول لرؤية كوبوناتك وكود الإحالة')
        else if (k?.hasError ?? false)
          _inlineError('تعذّر تحميل الكوبونات، تحقّق من الاتصال')
        else if (couponsWaiting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _brand)),
          )
        else if (coupons.isEmpty)
          _hintCard(Icons.local_offer_outlined, 'لا توجد كوبونات متاحة حالياً')
        else
          for (final c in coupons) _couponCard(c),
        if (_referral != null) _referralCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader(
      {required IconData icon, required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(children: [
        Icon(icon, color: _brand),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.tajawal(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            Text(subtitle,
                style: GoogleFonts.tajawal(
                    fontSize: 11.5, color: ZyiarahTheme.inkMuted)),
          ]),
        ),
      ]),
    );
  }

  Widget _inlineError(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: GoogleFonts.tajawal(color: Colors.red.shade700))),
      ]),
    );
  }

  Widget _hintCard(IconData icon, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Icon(icon, color: ZyiarahTheme.inkMuted),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: GoogleFonts.tajawal(color: ZyiarahTheme.inkMuted))),
      ]),
    );
  }

  Widget _emptyOffers() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Icon(Icons.local_offer_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('لا توجد عروض حالياً',
            style: GoogleFonts.tajawal(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 4),
        Text('تابعنا — عروضنا القادمة قريباً 🌿',
            style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey.shade400)),
      ]),
    );
  }

  Widget _bannerCard(Map<String, dynamic> data) {
    return GestureDetector(
      onTap: () => _handleTap(context, data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 2 / 1,
            child: CachedNetworkImage(
              imageUrl: data['imageUrl'] ?? '',
              fit: BoxFit.cover,
              placeholder: (c, u) => Container(color: Colors.grey.shade200),
              errorWidget: (c, u, e) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.image_not_supported, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: GoogleFonts.tajawal(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _couponCard(PromoCoupon c) {
    final personal = c.isPersonalFor(_uid);
    final color = personal ? const Color(0xFF0F766E) : _brand;
    final icon = personal
        ? Icons.card_giftcard_rounded
        : (c.isPercentage ? Icons.percent_rounded : Icons.payments_rounded);
    final tag = personal
        ? 'كوبون خاص بك'
        : (c.restrictedZones.isEmpty ? 'كل المناطق' : c.restrictedZones.join(' • '));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.headline,
                    style: GoogleFonts.tajawal(
                        fontSize: 17, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                _chip(tag, color),
              ]),
            ),
          ]),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(c.description,
                style: GoogleFonts.tajawal(
                    fontSize: 12.5, color: ZyiarahTheme.inkMuted, height: 1.6)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Text('الكود:',
                style: GoogleFonts.tajawal(
                    fontSize: 12, color: ZyiarahTheme.inkMuted)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(c.code,
                  textDirection: TextDirection.ltr,
                  style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: ZyiarahTheme.ink)),
            ),
            FilledButton.icon(
              onPressed: () => _copy(c.code, 'تم نسخ الكود بنجاح! ${c.code}'),
              icon: const Icon(Icons.content_copy_rounded, size: 16),
              label: const Text('نسخ الكود'),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: GoogleFonts.tajawal(
                    fontSize: 12, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          if (c.expiry != null) ...[
            const SizedBox(height: 6),
            Text('ينتهي في ${_fmtDate(c.expiry!)}',
                style: GoogleFonts.tajawal(
                    fontSize: 11, color: ZyiarahTheme.inkMuted)),
          ],
        ],
      ),
    );
  }

  Widget _referralCard() {
    final reward = ZyiarahReferralService.referrerRewardSar.toInt();
    final discount = ZyiarahReferralService.refereeDiscountPercent.toInt();
    return FutureBuilder<String?>(
      future: _referral,
      builder: (context, s) {
        final code = s.data;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [ZyiarahTheme.brandDark, _brand],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.redeem_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Text('برنامج سفراء زيارة',
                    style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Text(
                'شارك كودك مع أهلك وأصدقائك: تحصل على $reward ر.س في محفظتك عند '
                'اكتمال أول طلب لصديقك، ويحصل صديقك على خصم $discount% على أول طلب.',
                style: GoogleFonts.tajawal(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 12.5,
                    height: 1.6),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Text('كود الإحالة الخاص بك:',
                      style: GoogleFonts.tajawal(
                          color: Colors.white70, fontSize: 11.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(code ?? '…',
                        textDirection: TextDirection.ltr,
                        style: GoogleFonts.tajawal(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ),
                  IconButton(
                    tooltip: 'نسخ كود الإحالة',
                    onPressed: code == null
                        ? null
                        : () => _copy(code, 'تم نسخ كود الإحالة $code'),
                    icon: const Icon(Icons.content_copy_rounded,
                        color: Colors.white, size: 18),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
