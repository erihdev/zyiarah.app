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
import 'package:zyiarah/utils/net_timeout.dart';
import 'package:zyiarah/utils/stream_combine.dart';
import 'package:zyiarah/utils/error_report.dart';
import 'package:zyiarah/utils/banner_destination.dart';

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
  /// **كان `Future<String?>` بـ`.catchError((_) => null)` — فشلٌ يُبتلَع
  /// بلا أثرٍ في أيِّ مكان (2026-10-07).** انظر التعليقَ في
  /// `_referralCard` أدناه.
  String? _referralCode;
  bool _referralLoaded = false;
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
                .toList())
            .firstEventTimeout();

    final uid = _uid;
    if (uid != null) {
      _coupons = widget.coupons ?? _listableCoupons(uid);
      _loadReferral(uid);
    }
  }

  /// يَجلبُ كودَ الإحالةِ إلى الحالةِ — **ويَقولُ الفشلَ ويُبلِّغُ عنه.**
  /// (مرآةُ `_loadReferralCode` في `profile_screen`، ومنها إعادةُ حالةِ
  /// التحميلِ عند الإعادةِ وإلّا بَدت الإعادةُ بلا أثر.)
  Future<void> _loadReferral(String uid) async {
    if (mounted && _referralLoaded && _referralCode == null) {
      setState(() => _referralLoaded = false);
    }
    try {
      final String? code = widget.referralCode != null
          ? await widget.referralCode!
          : await ZyiarahReferralService().getOrCreateReferralCode(uid);
      if (!mounted) return;
      setState(() {
        _referralCode = (code != null && code.isNotEmpty) ? code : null;
        _referralLoaded = true;
      });
    } catch (e, st) {
      // مالٌ واستمرارُ خدمة: الصمتُ عنها خطأٌ، والصمتُ عنّا كذلك.
      reportSilent(e, st, reason: 'referral_code_fetch_failed');
      if (mounted) setState(() => _referralLoaded = true);
    }
  }

  /// **استعلامانِ يُثبِتانِ ما تَشترطُه القاعدة، لا استعلامٌ يَقرأُ الكلّ.**
  ///
  /// كان هذا استعلاماً واحداً `where('status','==','active')` على
  /// `promo_codes` ثمّ تَرشيحٌ **في العميل** بـ`show_in_offers` و
  /// `target_user_id` (في `PromoCoupon.isListableFor`). وقاعدةُ المجموعةِ
  /// كانت `allow read: if isLoggedIn()` — فأيُّ عميلةٍ مسجَّلةٍ تَقرأُ كلَّ
  /// كودِ خصمٍ في المستودعِ من الـSDK، ومنها ما وسَمَته الإدارةُ
  /// `show_in_offers: false` **كي لا يُكشَف**: تعليقُ `PromoCoupon` يَقولُه
  /// نصّاً («كي لا يُكشَفَ كودُ قناةٍ خاصّة… لعمومِ العملاء»). قرارٌ
  /// مُنفَّذٌ في الواجهةِ وحدَها والبياناتُ مكشوفةٌ خلفَها.
  ///
  /// قواعدُ Firestore تُجيزُ استعلامَ قائمةٍ متى **أثبتَ** مُرشِّحُه شرطَ
  /// الأمان، فالاستعلامُ صار اثنَين — المُعلَنُ، والموجَّهُ إليها — وكلٌّ
  /// يُثبِتُ أحدَ فرعَي القاعدةِ الجديدة. والتَرشيحُ المحلّيُّ يَبقى كما هو
  /// (انتهاءٌ وسقفُ استخدامٍ وترتيب): هو عن العرضِ لا عن الصلاحيّة.
  ///
  /// والدمجُ «آخرُ ما وصلَ من كلٍّ» لا تَتابعاً — ولماذا، في
  /// `lib/utils/stream_combine.dart`.
  Stream<List<PromoCoupon>> _listableCoupons(String uid) {
    final col = FirebaseFirestore.instance.collection(PromoCoupon.collectionPath);
    final advertised = col
        .where('show_in_offers', isEqualTo: true)
        .snapshots()
        .map(PromoCoupon.fromQuery);
    final personal = col
        .where('target_user_id', isEqualTo: uid)
        .snapshots()
        .map(PromoCoupon.fromQuery);
    return combineLatestById<PromoCoupon>(
      advertised,
      personal,
      (c) => c.id,
    ).firstEventTimeout();
  }

  /// **التصنيفُ في `lib/utils/banner_destination.dart`، والفالُّ لم يَكن
  /// هنا أصلاً.** كان هذا تعداداً لِـ`routeType` بلا `default`، فوجهةٌ لا
  /// يُطابِقُها فرعٌ تُبقي `dest` على `null` فتَمُرُّ الضغطةُ بلا نقلٍ ولا
  /// كلمة — بينما بنرُ اللوحةِ الرئيسيّةِ على المستندِ **نفسِه** يَقولُ
  /// «غير متاح». والحالةُ قابلةُ الوصول: «رابط واتساب» بحقلِ رابطٍ فارغٍ
  /// يُنشَرُ من المُحرِّرِ (كان الحقلُ «اختياري» ولا يُتحقَّقُ منه).
  Future<void> _handleTap(BuildContext context, Map<String, dynamic> data) async {
    final BannerTap tap = bannerTapOf(data);
    switch (tap.kind) {
      case BannerTapKind.externalUrl:
        await _openBannerUrl(context, tap.url);
      case BannerTapKind.service:
        if (!context.mounted) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => _bannerScreen(tap.service!)));
      case BannerTapKind.silent:
        return;
      case BannerTapKind.unavailable:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(kBannerUnavailableText)));
    }
  }

  /// مُبدِّلٌ **شامل** على التعداد: وجهةٌ تُضافُ بلا شاشةٍ هنا خطأُ ترجمةٍ
  /// لا سقوطٌ صامت.
  Widget _bannerScreen(BannerServiceTarget target) => switch (target) {
        BannerServiceTarget.hourlyCleaning =>
          const HourlyCleaningDetailsScreen(serviceName: 'تنظيف منزلي'),
        BannerServiceTarget.sofaRug =>
          const SofaRugCleaningDetailsScreen(serviceName: 'تنظيف الكنب والزل'),
        BannerServiceTarget.acService => const AcServiceDetailsScreen(),
        BannerServiceTarget.subscriptions =>
          const ZyiarahSubscriptionPlansScreen(),
        BannerServiceTarget.store => const ZyiarahStoreScreen(),
        BannerServiceTarget.support => const ZyiarahSupportScreen(),
      };

  /// بلا بوّابةِ `canLaunchUrl`: تُعيدُ `false` **زائفاً** على iOS لمُخطَّطٍ
  /// غيرِ مُعلَنٍ في `LSApplicationQueriesSchemes` (وهو غيرُ موجودٍ في
  /// `Info.plist`)، فرابطُ `whatsapp://` صالحٌ كان يُقابَلُ بـ«تعذّر فتح
  /// الرابط». نفسُ إصلاحِ `driver_dashboard._openExternalUrl`: نَعتمدُ على
  /// عائدِ `launchUrl` نفسِه. و`Uri.parse` داخلَ `try` لأنّ النصَّ يَكتبُه
  /// الأدمنُ حرّاً.
  Future<void> _openBannerUrl(BuildContext context, String url) async {
    bool ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('offers banner url: $e');
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر فتح الرابط')));
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
        if (b.hasError) _inlineError('تعذّر تحميل العروض، تحقّقي من الاتصال'),
        for (final data in banners) _bannerCard(data),
        if (banners.isEmpty && !b.hasError && coupons.isEmpty && !(k?.hasError ?? false))
          _emptyOffers(),
        _sectionHeader(
          icon: Icons.confirmation_number_outlined,
          title: 'كوبونات الخصم المعتمدة',
          subtitle: 'انقري لنسخ الكوبون ثم أدخليه عند الدفع',
        ),
        if (_uid == null)
          _hintCard(Icons.login_rounded, 'سجّلي الدخول لرؤية كوبوناتك وكود الإحالة')
        else if (k?.hasError ?? false)
          _inlineError('تعذّر تحميل الكوبونات، تحقّقي من الاتصال')
        else if (couponsWaiting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _brand)),
          )
        else if (coupons.isEmpty)
          _hintCard(Icons.local_offer_outlined, 'لا توجد كوبونات متاحة حالياً')
        else
          for (final c in coupons) _couponCard(c),
        if (_uid != null) _referralCard(),
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
                      fontWeight: FontWeight.w900,
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
    final String? code = _referralCode;
    final bool failed = _referralLoaded && code == null;
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
            'شاركي كودك مع أهلك وأصدقائك: تحصلين على $reward ر.س في محفظتك عند '
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
              // **ثلاثُ حالاتٍ لا حالتان**: جارٍ (نقاط) ≠ تعذّر (نصٌّ وإعادة)
              // ≠ كودٌ (يُنسَخ). كان الفشلُ يُبتلَعُ إلى `null` فيُرسَمُ «…»
              // كالتحميلِ تماماً، وزرُّ النسخِ معطَّلٌ بلا كلمةٍ ولا سبيلَ
              // إلى إعادةِ المحاولة — على السطحِ الذي يَبدأُ به برنامجُ
              // الإحالة. والشكلُ الصحيحُ في `profile_screen` على بُعدِ ملفّ.
              Expanded(
                child: Text(failed ? 'تعذّر التحميل' : (code ?? '…'),
                    textDirection:
                        failed ? TextDirection.rtl : TextDirection.ltr,
                    style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: failed ? 12.5 : 16,
                        fontWeight: failed ? FontWeight.bold : FontWeight.w900,
                        letterSpacing: failed ? 0 : 2)),
              ),
              if (failed)
                IconButton(
                  tooltip: 'إعادة المحاولة',
                  onPressed: () {
                    final uid = _uid;
                    if (uid != null) _loadReferral(uid);
                  },
                  icon: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 18),
                )
              else
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
  }
}
