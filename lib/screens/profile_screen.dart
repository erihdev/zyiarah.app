import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/services/zyiarah_wallet_service.dart';
import 'package:zyiarah/services/zyiarah_referral_service.dart';

class ZyiarahProfileScreen extends StatefulWidget {
  const ZyiarahProfileScreen({super.key});

  @override
  State<ZyiarahProfileScreen> createState() => _ZyiarahProfileScreenState();
}

class _ZyiarahProfileScreenState extends State<ZyiarahProfileScreen> {
  static const Color _brand = Color(0xFF5D1B5E);
  static const Color _violet = Color(0xFF7C3AED);
  static const Color _deepPurple = Color(0xFF3B0764);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _firebaseService = ZyiarahFirebaseService();

  ZyiarahUser? _currentUser;
  bool _isLoading = true;
  int? _totalBookings; // عدد فعلي عبر count() بدل طول قائمة مقصوصة عند 20

  // Wallet & loyalty state
  double _walletBalance = 0.0;
  int _qatratPoints = 0;
  bool _walletLoaded = false;
  bool _isRedeeming = false;

  // Referral state
  String? _referralCode;
  bool _referralLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // ضيف: أوقف كل مؤشّرات التحميل (المحفظة/الإحالة) وإلا بقيت shimmer للأبد.
      setState(() {
        _isLoading = false;
        _walletLoaded = true;
        _referralLoaded = true;
      });
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (mounted && doc.exists) {
        setState(() {
          _currentUser = ZyiarahUser.fromMap(uid, doc.data()!);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
    // إجمالي الحجوزات — عدّ فعلي (aggregate) لا يتأثّر بسقف الـ20 في المزوّد
    try {
      final agg = await _firestore
          .collection('orders')
          .where('client_id', isEqualTo: uid)
          .count()
          .get();
      if (mounted) setState(() => _totalBookings = agg.count);
    } catch (_) {/* غير حرِج — تبقى — */}
    // Load wallet and referral in parallel after user data
    _loadWallet(uid);
    _loadReferralCode(uid);
  }

  Future<void> _loadWallet(String uid) async {
    try {
      final wallet = await ZyiarahWalletService().getOrCreateWallet(uid);
      if (mounted) {
        setState(() {
          _walletBalance = wallet.balance;
          _qatratPoints = wallet.qatratPoints;
          _walletLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _walletLoaded = true);
    }
  }

  Future<void> _loadReferralCode(String uid) async {
    try {
      final code = await ZyiarahReferralService().getOrCreateReferralCode(uid);
      if (mounted) {
        setState(() {
          _referralCode = code;
          _referralLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _referralLoaded = true);
    }
  }

  Future<void> _redeemQatrat() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _isRedeeming || _qatratPoints < 50) return;

    HapticFeedback.mediumImpact();
    setState(() => _isRedeeming = true);

    try {
      // Round down to nearest 50
      final toRedeem = (_qatratPoints ~/ 50) * 50;
      final success = await ZyiarahWalletService()
          .redeemQatratPoints(userId: uid, pointsToRedeem: toRedeem);

      if (mounted) {
        if (success) {
          final earned = toRedeem / 50.0;
          await _loadWallet(uid);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
              const SizedBox(width: 10),
              Text(
                'تم استبدال $toRedeem نقطة بـ ${earned.toStringAsFixed(2)} ر.س 🎉',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
              ),
            ]),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تحتاج 50 نقطة على الأقل للاستبدال',
                style: GoogleFonts.tajawal()),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل الاستبدال، حاول مجدداً',
              style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(
      text: _currentUser?.name.isNotEmpty == true ? _currentUser!.name : '',
    );
    final phoneController = TextEditingController(
      text: _currentUser?.phone.isNotEmpty == true
          ? _currentUser!.phone
          : (_auth.currentUser?.phoneNumber ?? ''),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تحديث البيانات',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'الاسم الشخصي',
                  labelStyle: GoogleFonts.tajawal(),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الجوال',
                  labelStyle: GoogleFonts.tajawal(),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.tajawal()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child:
                  Text('حفظ', style: GoogleFonts.tajawal(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        if (mounted) setState(() => _isLoading = true);
        try {
          await _firestore.collection('users').doc(uid).set({
            'name': nameController.text.trim(),
            'phone': phoneController.text.trim(),
          }, SetOptions(merge: true));
          await _loadUserData();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('خطأ في حفظ البيانات',
                      style: GoogleFonts.tajawal())),
            );
            setState(() => _isLoading = false);
          }
        }
      }
    }
    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _showHouseRulesDialog() async {
    final controller =
        TextEditingController(text: _currentUser?.houseRules ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تفضيلات الخدمة',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'سيتم عرض هذه التنبيهات للسائق عند وصوله لموقعك.',
                style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText:
                      'مثال: يرجى عدم رن الجرس، استخدم ملمع الخشب للكنب...',
                  hintStyle: GoogleFonts.tajawal(fontSize: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.tajawal()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('حفظ التفضيلات',
                  style: GoogleFonts.tajawal(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        if (mounted) setState(() => _isLoading = true);
        try {
          await _firestore
              .collection('users')
              .doc(uid)
              .update({'house_rules': controller.text.trim()});
          await _loadUserData();
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('فشل حفظ التفضيلات، تحقق من اتصالك',
                    style: GoogleFonts.tajawal()),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
    controller.dispose();
  }

  Future<void> _performLogout() async {
    HapticFeedback.lightImpact();
    // الخروج المركزي يتولى إيقاف مستمع الصيانة وتنظيف الإشعارات قبل تسجيل الخروج
    await _firebaseService.signOut();
    if (mounted) context.go('/');
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    final uid = user?.uid;
    if (uid == null) return;
    try {
      // المستخدم لا يملك صلاحية حذف وثيقته بنفسه (قاعدة users = isSuperAdmin).
      // نُسجّل الطلب بحالة "deleted"، وتتولى Cloud Function (onAccountDeletionRequested)
      // حذف حساب المصادقة + وثيقة المستخدم + رموز الإشعارات خادمياً، فلا تبقى بيانات يتيمة.
      await _firestore.collection('account_deletions').doc(uid).set({
        'uid': uid,
        'phone': user?.phoneNumber,
        'email': user?.email,
        'requested_at': FieldValue.serverTimestamp(),
        'status': 'deleted',
        'source': 'client_app',
      });
      await _firebaseService.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('تعذّر حذف الحساب، حاول لاحقاً', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F0F7),
        appBar: AppBar(
          title: Text('الملف الشخصي',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: _brand,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: _isLoading ? _buildShimmer() : _buildContent(user),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SHIMMER SKELETON
  // ─────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[200]!,
      highlightColor: Colors.grey[50]!,
      child: SingleChildScrollView(
        child: Column(
          children: [
            Container(height: 160, color: Colors.white),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Wallet hub shimmer
                  Container(
                    height: 140,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  // Referral shimmer
                  Container(
                    height: 110,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  ...List.generate(
                    4,
                    (_) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // MAIN CONTENT
  // ─────────────────────────────────────────────────────────

  Widget _buildContent(User? user) {
    final name = _currentUser?.name.isNotEmpty == true
        ? _currentUser!.name
        : 'عميل زيارة';
    final phone = _currentUser?.phone.isNotEmpty == true
        ? _currentUser!.phone
        : (user?.phoneNumber ?? '');
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(name, phone),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // ── Stats (نُقلت من الصفحة الرئيسية) ─────────
                _buildStatsRow(),
                const SizedBox(height: 14),
                // ── Premium Financial Hub ──────────────────
                _buildFinancialHub(),
                const SizedBox(height: 14),
                // ── Referral Engine ───────────────────────
                _buildReferralSection(),
                const SizedBox(height: 14),
                // ── Profile Info ──────────────────────────
                _buildInfoCard(user),
                const SizedBox(height: 12),
                _buildMenuCard(),
                const SizedBox(height: 12),
                _buildDangerCard(),
                const SizedBox(height: 32),
                _buildFooter(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // STATS (إجمالي الحجوزات + تقييمك) — منقولة من الرئيسية
  // ─────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    final double rating = _currentUser?.rating ?? 4.9;
    final String ratingText = rating == rating.roundToDouble()
        ? rating.toStringAsFixed(0)
        : rating.toStringAsFixed(1);
    final String totalBookings = _totalBookings?.toString() ?? '—';
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'إجمالي الحجوزات',
            totalBookings,
            Icons.calendar_today_rounded,
            const Color(0xFF3B82F6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'تقييمك',
            '$ratingText ★',
            Icons.star_rounded,
            const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // PROFILE HEADER
  // ─────────────────────────────────────────────────────────

  Widget _buildHeader(String name, String phone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: const BoxDecoration(
        color: _brand,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                style: GoogleFonts.tajawal(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أهلاً بك،',
                    style: GoogleFonts.tajawal(
                        color: Colors.white70, fontSize: 13)),
                Text(name,
                    style: GoogleFonts.tajawal(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: GoogleFonts.tajawal(
                          color: Colors.white60, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: _showEditProfileDialog,
            tooltip: 'تعديل البيانات',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ★ PREMIUM FINANCIAL HUB (Wallet + Qatrat)
  // ─────────────────────────────────────────────────────────

  Widget _buildFinancialHub() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_deepPurple, Color(0xFF5D1B5E), _violet],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _violet.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: _deepPurple.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white60, size: 16),
              const SizedBox(width: 6),
              Text(
                'محفظة زيارة الرقمية',
                style: GoogleFonts.tajawal(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── Left: Wallet Balance ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _walletLoaded
                          ? Text(
                              '${_walletBalance.toStringAsFixed(2)} ر.س',
                              key: ValueKey(_walletBalance),
                              style: GoogleFonts.tajawal(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                              ),
                            )
                          : _balanceShimmer(),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الرصيد المتاح',
                      style: GoogleFonts.tajawal(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 0.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // ── Right: Glassmorphic Qatrat Card ──
              _buildQatratCard(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _balanceShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.white12,
      highlightColor: Colors.white24,
      child: Container(
        key: const ValueKey('shimmer'),
        width: 140,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildQatratCard() {
    final canRedeem = _qatratPoints >= 50;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Floating particle indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFBBF24),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'نقاط زيارة',
                    style: GoogleFonts.tajawal(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: child),
                ),
                child: _walletLoaded
                    ? Text(
                        '$_qatratPoints',
                        key: ValueKey(_qatratPoints),
                        style: GoogleFonts.tajawal(
                          color: const Color(0xFFFBBF24),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('qshimmer'),
                        width: 60,
                        height: 30,
                      ),
              ),
              const SizedBox(height: 10),
              // Redeem button with AnimatedSwitcher loading state
              GestureDetector(
                onTap: canRedeem ? _redeemQatrat : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: canRedeem
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _isRedeeming
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black54,
                            ),
                          )
                        : Text(
                            canRedeem ? 'استبدال' : '${50 - _qatratPoints} نقطة',
                            key: ValueKey(canRedeem),
                            style: GoogleFonts.tajawal(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color:
                                  canRedeem ? Colors.black87 : Colors.white38,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ★ MODERN REFERRAL BENTO CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildReferralSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _violet.withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _brand.withValues(alpha: 0.07),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFF97316)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.card_giftcard_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'شارك عائلتك وأصدقائك واربح! 🎁',
                      style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'أحِل صديقاً واحصل على 50 ر.س، وصديقك يحصل على خصم 10%',
                style: GoogleFonts.tajawal(
                    fontSize: 11, color: Colors.grey.shade600, height: 1.4),
              ),
              const SizedBox(height: 16),
              // Code capsule + copy button
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: _referralLoaded
                          ? Container(
                              key: ValueKey(_referralCode),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.tag_rounded,
                                      color: Color(0xFFFBBF24), size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    _referralCode ?? '--------',
                                    style: GoogleFonts.tajawal(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Shimmer.fromColors(
                              key: const ValueKey('ref-shimmer'),
                              baseColor: Colors.grey[200]!,
                              highlightColor: Colors.grey[50]!,
                              child: Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Copy button
                  GestureDetector(
                    onTap: () {
                      if (_referralCode == null) return;
                      HapticFeedback.mediumImpact();
                      final message =
                          'سجّل في تطبيق زيارة للخدمات المنزلية باستخدام كودي '
                          'وبتحصل على خصم 10% على أول خدمة تنظيف لمنزلك! ✨ كودي: $_referralCode';
                      Clipboard.setData(ClipboardData(text: message));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'تم نسخ رسالة الإحالة بنجاح ✅',
                                style: GoogleFonts.tajawal(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]),
                          backgroundColor: const Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_brand, _violet],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _brand.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.copy_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // INFO, MENU, DANGER, FOOTER (preserved)
  // ─────────────────────────────────────────────────────────

  Widget _buildInfoCard(User? user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          _infoRow(Icons.person_outline, 'الاسم الشخصي',
              _currentUser?.name.isNotEmpty == true
                  ? _currentUser!.name
                  : 'غير متوفر'),
          _divider(),
          _infoRow(
              Icons.email_outlined,
              'البريد الإلكتروني',
              _currentUser?.email.isNotEmpty == true
                  ? _currentUser!.email
                  : (user?.email ?? 'غير متوفر')),
          _divider(),
          _infoRow(
              Icons.phone_outlined,
              'رقم الجوال',
              _currentUser?.phone.isNotEmpty == true
                  ? _currentUser!.phone
                  : (user?.phoneNumber ?? 'غير متوفر')),
          _divider(),
          _infoRow(Icons.badge_outlined, 'نوع الحساب',
              _currentUser?.role == 'driver' ? 'سائق' : 'عميل'),
        ],
      ),
    );
  }

  Widget _buildMenuCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          _menuRow(Icons.home_work_outlined, 'تفضيلات الخدمة / قوانين المنزل',
              _brand, _showHouseRulesDialog),
          _divider(),
          _menuRow(Icons.description_outlined, 'عقودي الإلكترونية', _brand,
              () {
            HapticFeedback.lightImpact();
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ZyiarahContractsListScreen()));
          }),
          _divider(),
          _menuRow(Icons.support_agent_rounded, 'الدعم الفني', _brand, () {
            HapticFeedback.lightImpact();
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()));
          }),
          _divider(),
          _menuRow(Icons.shield_outlined, 'سياسة الخصوصية', _brand, () {
            launchUrl(Uri.parse('https://zyiarah.com/privacy'),
                mode: LaunchMode.externalApplication);
          }),
          _divider(),
          _menuRow(Icons.logout_rounded, 'تسجيل الخروج', Colors.orange,
              _performLogout),
        ],
      ),
    );
  }

  Widget _buildDangerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: _menuRow(Icons.delete_forever_rounded, 'حذف الحساب نهائياً',
          Colors.red, () {
        HapticFeedback.mediumImpact();
        _showDeleteConfirmation(context);
      }),
    );
  }

  Widget _buildFooter() {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('https://erihdev.com'),
          mode: LaunchMode.externalApplication),
      onLongPress: () => _showThankYouMessage(context),
      child: Text.rich(
        TextSpan(
          text: 'إصدار التطبيق 1.2.23\nمؤسسة معاذ يحي محمد المالكي\nتم التطوير بواسطة\n',
          style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey),
          children: [
            TextSpan(
              text: 'إرث',
              style: GoogleFonts.tajawal(
                  fontSize: 22, color: _brand, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SHARED HELPERS
  // ─────────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _brand, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.tajawal(
                        fontSize: 11, color: Colors.grey[500])),
                Text(value,
                    style: GoogleFonts.tajawal(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(
      IconData icon, String title, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Text(title,
                    style: GoogleFonts.tajawal(
                        fontSize: 15, color: Colors.black87))),
            Icon(Icons.chevron_left, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 54, endIndent: 16);

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Text('حذف الحساب نهائياً',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'سيتم مسح كافة بياناتك، فواتيرك، وخدماتك السابقة نهائياً. لا يمكن التراجع عن هذا الإجراء.',
                style: GoogleFonts.tajawal(height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'حق النسيان: سيتم حذف كافة سجلات التتبع الخاصة بك.',
                        style:
                            GoogleFonts.tajawal(fontSize: 10, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  Text('تراجع', style: GoogleFonts.tajawal(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteAccount();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('تأكيد الحذف النهائي',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showThankYouMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'نفخر في (إرث) بأن نكون شركاء النجاح لمؤسسة معاذ المالكي 💙',
          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        backgroundColor: _brand,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
