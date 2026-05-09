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
import 'package:zyiarah/screens/orders_list_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/services/maintenance_listener_service.dart';

class ZyiarahProfileScreen extends StatefulWidget {
  const ZyiarahProfileScreen({super.key});

  @override
  State<ZyiarahProfileScreen> createState() => _ZyiarahProfileScreenState();
}

class _ZyiarahProfileScreenState extends State<ZyiarahProfileScreen> {
  static const Color _brand = Color(0xFF5D1B5E);

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _firebaseService = ZyiarahFirebaseService();

  ZyiarahUser? _currentUser;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تحديث البيانات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'الاسم الشخصي',
                  labelStyle: GoogleFonts.tajawal(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الجوال',
                  labelStyle: GoogleFonts.tajawal(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('حفظ', style: GoogleFonts.tajawal(color: Colors.white)),
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
              SnackBar(content: Text('خطأ في حفظ البيانات', style: GoogleFonts.tajawal())),
            );
            setState(() => _isLoading = false);
          }
        }
      }
    }
  }

  Future<void> _showHouseRulesDialog() async {
    final controller = TextEditingController(text: _currentUser?.houseRules ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تفضيلات الخدمة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                  hintText: 'مثال: يرجى عدم رن الجرس، استخدم ملمع الخشب للكنب...',
                  hintStyle: GoogleFonts.tajawal(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('حفظ التفضيلات', style: GoogleFonts.tajawal(color: Colors.white)),
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
          await _firestore.collection('users').doc(uid).update({'house_rules': controller.text.trim()});
          await _loadUserData();
        } catch (e) {
          if (mounted) setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _performLogout() async {
    HapticFeedback.lightImpact();
    MaintenanceListenerService().stopListening();
    await _firebaseService.signOut();
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _deleteAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore.collection('account_deletions').doc(uid).set({
        'uid': uid,
        'phone': _auth.currentUser?.phoneNumber,
        'requested_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      await _firestore.collection('users').doc(uid).delete();
      await _auth.currentUser?.delete();
      await _firebaseService.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف الحساب: $e', style: GoogleFonts.tajawal()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F0F7),
        appBar: AppBar(
          title: Text('الملف الشخصي', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                children: List.generate(4, (_) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 60,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(User? user) {
    final name = _currentUser?.name.isNotEmpty == true ? _currentUser!.name : 'عميل زيارة';
    final phone = _currentUser?.phone.isNotEmpty == true
        ? _currentUser!.phone
        : (user?.phoneNumber ?? '');
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(name, phone),
          const SizedBox(height: 16),
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
    );
  }

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
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'Z',
                style: GoogleFonts.tajawal(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أهلاً بك،', style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13)),
                Text(name, style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (phone.isNotEmpty)
                  Text(phone, style: GoogleFonts.tajawal(color: Colors.white60, fontSize: 13)),
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

  Widget _buildInfoCard(User? user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            _infoRow(Icons.person_outline, 'الاسم الشخصي',
                _currentUser?.name.isNotEmpty == true ? _currentUser!.name : 'غير متوفر'),
            _divider(),
            _infoRow(Icons.email_outlined, 'البريد الإلكتروني',
                _currentUser?.email.isNotEmpty == true ? _currentUser!.email : (user?.email ?? 'غير متوفر')),
            _divider(),
            _infoRow(Icons.phone_outlined, 'رقم الجوال',
                _currentUser?.phone.isNotEmpty == true ? _currentUser!.phone : (user?.phoneNumber ?? 'غير متوفر')),
            _divider(),
            _infoRow(Icons.badge_outlined, 'نوع الحساب',
                _currentUser?.role == 'driver' ? 'سائق' : 'عميل'),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            _menuRow(Icons.home_work_outlined, 'تفضيلات الخدمة / قوانين المنزل', _brand, _showHouseRulesDialog),
            _divider(),
            _menuRow(Icons.history_rounded, 'سجل الطلبات', _brand, () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersListScreen()));
            }),
            _divider(),
            _menuRow(Icons.description_outlined, 'عقودي الإلكترونية', _brand, () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahContractsListScreen()));
            }),
            _divider(),
            _menuRow(Icons.support_agent_rounded, 'الدعم الفني', _brand, () {
              HapticFeedback.lightImpact();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ZyiarahSupportScreen()));
            }),
            _divider(),
            _menuRow(Icons.shield_outlined, 'سياسة الخصوصية', _brand, () {
              launchUrl(Uri.parse('https://zyiarah.com/privacy'), mode: LaunchMode.externalApplication);
            }),
            _divider(),
            _menuRow(Icons.logout_rounded, 'تسجيل الخروج', Colors.orange, _performLogout),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: _menuRow(Icons.delete_forever_rounded, 'حذف الحساب نهائياً', Colors.red, () {
          HapticFeedback.mediumImpact();
          _showDeleteConfirmation(context);
        }),
      ),
    );
  }

  Widget _buildFooter() {
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse('https://erihdev.com'), mode: LaunchMode.externalApplication),
      onLongPress: () => _showThankYouMessage(context),
      child: Text.rich(
        TextSpan(
          text: 'إصدار التطبيق 1.2.0 (Build 25)\nمؤسسة معاذ يحي محمد المالكي\nتم التطوير بواسطة\n',
          style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey),
          children: [
            TextSpan(
              text: 'إرث',
              style: GoogleFonts.tajawal(fontSize: 22, color: _brand, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _brand.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _brand, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[500])),
                Text(value, style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(IconData icon, String title, Color color, VoidCallback onTap) {
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
            Expanded(child: Text(title, style: GoogleFonts.tajawal(fontSize: 15, color: Colors.black87))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Text('حذف الحساب نهائياً', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
                        style: GoogleFonts.tajawal(fontSize: 10, color: Colors.red),
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
              child: Text('تراجع', style: GoogleFonts.tajawal(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteAccount();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('تأكيد الحذف النهائي', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
