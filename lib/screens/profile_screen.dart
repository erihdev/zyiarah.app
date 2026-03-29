import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/firebase_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/models/user_model.dart';
import 'package:zyiarah/screens/support_screen.dart';
import 'package:zyiarah/screens/orders_list_screen.dart';
import 'package:zyiarah/screens/contracts_list_screen.dart';
import 'package:zyiarah/screens/support_screen.dart';

class ZyiarahProfileScreen extends StatefulWidget {
  const ZyiarahProfileScreen({super.key});

  @override
  State<ZyiarahProfileScreen> createState() => _ZyiarahProfileScreenState();
}

class _ZyiarahProfileScreenState extends State<ZyiarahProfileScreen> {
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

  Future<void> _deleteAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // تسجيل طلب الحذف في Firestore (متطلب Apple)
      await _firestore.collection('account_deletions').doc(uid).set({
        'uid': uid,
        'phone': _auth.currentUser?.phoneNumber,
        'requested_at': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      // حذف بيانات المستخدم
      await _firestore.collection('users').doc(uid).delete();

      // تسجيل الخروج وحذف الحساب
      await _auth.currentUser?.delete();
      await _firebaseService.signOut();

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('الملف الشخصي', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF5D1B5E)))
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeader(
                      _currentUser?.name?.isNotEmpty == true ? _currentUser!.name : 'عميل زيارة',
                      user?.phoneNumber ?? '',
                    ),
                    const SizedBox(height: 20),
                    _buildInfoTile(
                      Icons.phone,
                      'رقم الجوال',
                      _currentUser?.phone.isNotEmpty == true ? _currentUser!.phone : (user?.phoneNumber ?? 'غير متوفر'),
                    ),
                    _buildInfoTile(
                      Icons.badge_outlined,
                      'نوع الحساب',
                      _currentUser?.role == 'driver' ? '🚗 سائق' : '👤 عميل',
                    ),
                    const Divider(height: 10, indent: 20, endIndent: 20),
                    _buildMenuTile(Icons.history, 'سجل الطلبات', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const OrdersListScreen()));
                    }),
                    _buildMenuTile(Icons.description_outlined, 'عقودي الإلكتـرونية', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahContractsListScreen()));
                    }),
                    _buildMenuTile(Icons.support_agent, 'الدعم الفنـي', () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const ZyiarahSupportScreen()));
                    }),
                    _buildMenuTile(Icons.shield_outlined, 'سياسة الخصوصية', () {
                      launchUrl(Uri.parse('https://zyiarah.com/privacy'),
                          mode: LaunchMode.externalApplication);
                    }),
                    _buildMenuTile(Icons.support_agent, 'الدعم الفني', () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ZyiarahSupportScreen()),
                      );
                    }),
                    const Divider(height: 40),
                    _buildMenuTile(Icons.logout, 'تسجيل الخروج', () async {
                      await _firebaseService.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }, color: Colors.orange),
                    _buildMenuTile(Icons.delete_forever, 'حذف الحساب نهائياً', () {
                      _showDeleteConfirmation(context);
                    }, color: Colors.red),
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: () => launchUrl(Uri.parse('https://erihdev.com'),
                          mode: LaunchMode.externalApplication),
                      onLongPress: () => _showThankYouMessage(context),
                      child: Text.rich(
                        TextSpan(
                          text: 'إصدار التطبيق 1.0.0 (Build 1)\nمؤسسة معاذ يحي محمد المالكي\nتم التطوير بواسطة\n',
                          style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey),
                          children: [
                            TextSpan(
                              text: 'إرث',
                              style: GoogleFonts.tajawal(
                                fontSize: 22,
                                color: const Color(0xFF5D1B5E),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(String name, String phone) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Color(0xFF5D1B5E),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'Z',
              style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أهلاً بك،', style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 14)),
              Text(name, style: GoogleFonts.tajawal(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              if (phone.isNotEmpty)
                Text(phone, style: GoogleFonts.tajawal(color: Colors.white60, fontSize: 13)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF5D1B5E)),
      title: Text(label, style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey)),
      subtitle: Text(value, style: GoogleFonts.tajawal(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap, {Color color = const Color(0xFF5D1B5E)}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: GoogleFonts.tajawal(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف الحساب', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text(
            'هل أنت متأكد من رغبتك في حذف الحساب؟ سيتم مسح كافة بياناتك وفواتيرك نهائياً ولا يمكن استعادتها.',
            style: GoogleFonts.tajawal(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('تراجع', style: GoogleFonts.tajawal()),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteAccount();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('حذف الآن', style: GoogleFonts.tajawal(color: Colors.white)),
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
        backgroundColor: const Color(0xFF5D1B5E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
