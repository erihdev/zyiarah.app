import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:zyiarah/services/firebase_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  // دور الأدمن الحالي: الشاشة متاحة لـ orders_manager أيضاً، لكن قواعد Firestore
  // تحصر الحذف النهائي (account_deletions) ومسح علم is_blocked بالمدير العام —
  // نخفي/نمنع هذه الأفعال في الواجهة بدل خطأ permission-denied غامض.
  String _role = 'none';

  @override
  void initState() {
    super.initState();
    _fetchAdminRole();
  }

  Future<void> _fetchAdminRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final role = await ZyiarahFirebaseService().getUserRole(user.uid) ?? 'none';
      if (mounted) {
        // توحيد admin القديم إلى super_admin (نفس نمط admin_dashboard_screen)
        setState(() => _role = role == 'admin' ? 'super_admin' : role);
      }
    } catch (_) {
      // فشل جلب الدور لا يعطّل الشاشة — تبقى الأفعال الحساسة مخفية والقواعد هي الفيصل.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deleteUser(BuildContext context, String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('تأكيد الحذف', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف المستخدم "$name"؟\nسيتم حذف بياناته نهائياً ولا يمكن التراجع.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // نوجّه الحذف عبر account_deletions ليحذف الخادمُ (processAccountDeletion) حساب
        // Auth + مستند users + رموز FCM. حذف مستند users وحده كان يترك حساب Auth حيّاً
        // قابلاً للدخول (وبيانات مالية يتيمة + تجاوز التزام الحذف القانوني).
        await FirebaseFirestore.instance.collection('account_deletions').doc(uid).set({
          'status': 'deleted',
          'deleted_by_admin': true,
          'requested_at': FieldValue.serverTimestamp(),
        });
        await ZyiarahAuditService().logAction(
          action: 'DELETE_USER',
          details: {'name': name},
          targetId: uid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('تم حذف المستخدم بنجاح ✅'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          // permission-denied يعني أن الدور الحالي لا يملك صلاحية الحذف (القواعد
          // تحصره بالمدير العام) — رسالة مفهومة بدل نص الاستثناء الخام.
          final msg = e.toString().contains('permission-denied')
              ? 'الحذف النهائي يتطلب صلاحية الإدارة العليا'
              : 'حدث خطأ: $e';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
  }

  // (دمج من لوحة الويب) حظر/رفع حظر مستخدم دون حذفه. يفرضه التطبيق فعلاً:
  // user_provider يفحص status=='banned' أو is_blocked==true فيُسجّل خروجه ويمنعه.
  Future<void> _toggleBan(BuildContext context, String uid, String name,
      bool isBanned, bool hasBlockedFlag) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isBanned ? Icons.lock_open_rounded : Icons.block_rounded,
                color: isBanned ? Colors.green : Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(isBanned ? 'رفع الحظر' : 'حظر المستخدم',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          isBanned
              ? 'رفع الحظر عن "$name"؟ سيتمكّن من استخدام التطبيق مجدداً.'
              : 'حظر "$name"؟ سيُسجَّل خروجه فوراً ويُمنع من استخدام التطبيق '
                  '(دون حذف بياناته — يمكن رفع الحظر لاحقاً).',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isBanned ? Colors.green.shade600 : Colors.orange.shade700,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isBanned ? 'رفع الحظر' : 'حظر'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // حظر قديم عبر is_blocked (يُضبط من المدير العام/الكونسول): كتابة status
      // وحدها كانت تُظهر «تم رفع الحظر ✅» بينما user_provider يستمر بطرد المستخدم
      // لأن العلم باقٍ. القواعد تمنع غير المدير العام من لمس is_blocked، فنمنع
      // النجاح الكاذب برسالة واضحة بدل الكتابة الناقصة.
      if (isBanned && hasBlockedFlag && _role != 'super_admin') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('رفع هذا الحظر يتطلب صلاحية الإدارة العليا (حظر مثبَّت بعلم is_blocked)'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'status': isBanned ? 'active' : 'banned',
          // نمسح علم الحظر القديم أيضاً حتى لا يبقى المستخدم مطروداً بعد رفع الحظر.
          if (isBanned && hasBlockedFlag) 'is_blocked': FieldValue.delete(),
        });
        await ZyiarahAuditService().logAction(
          action: isBanned ? 'UNBAN_USER' : 'BAN_USER',
          details: {'name': name},
          targetId: uid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isBanned ? 'تم رفع الحظر ✅' : 'تم حظر المستخدم 🚫'),
            backgroundColor: isBanned ? Colors.green : Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            "العملاء والمستخدمون",
            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          // نصفّي role=='client' خادميّاً: كان التصفية محليّاً على آخر 100 مستخدم
          // (قد يكونون سائقين/إدارة) فيختفي عملاء حقيقيون ويكون العدّاد مضلِّلاً.
          stream: FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'client')
              .orderBy('created_at', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'لا يوجد مستخدمون',
                      style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            final allDocs = snapshot.data!.docs;

            // تصفية محليّة على القائمة المحمَّلة فقط (لا نغيّر استعلام Firestore)
            final String query = _search.trim().toLowerCase();
            final docs = query.isEmpty
                ? allDocs
                : allDocs.where((d) {
                    final u = d.data() as Map<String, dynamic>;
                    final name = (u['name'] ?? '').toString().toLowerCase();
                    final phone = (u['phone'] ?? '').toString().toLowerCase();
                    final email = (u['email'] ?? '').toString().toLowerCase();
                    return name.contains(query) ||
                        phone.contains(query) ||
                        email.contains(query);
                  }).toList();

            return Column(
              children: [
                // Summary bar
                Container(
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'إجمالي العملاء: ${docs.length}',
                        style: GoogleFonts.tajawal(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // شريط البحث الحيّ — يصفّي القائمة المعروضة فقط
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _search = v),
                    textInputAction: TextInputAction.search,
                    style: GoogleFonts.tajawal(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الجوال أو البريد',
                      hintStyle: GoogleFonts.tajawal(
                          fontSize: 14, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF660033)),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Color(0xFF64748B)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _search = '');
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF1F5F9),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF660033), width: 1.5),
                      ),
                    ),
                  ),
                ),
                if (docs.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'لا نتائج للبحث «${_search.trim()}»',
                            style: GoogleFonts.tajawal(
                                fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final user = doc.data() as Map<String, dynamic>;
                      final String name = user['name'] ?? 'مستخدم';
                      final String contact = user['phone'] ?? user['email'] ?? 'لا يوجد رقم';
                      final bool isBanned =
                          user['status'] == 'banned' || user['is_blocked'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF660033).withValues(alpha: 0.1),
                            child: Text(
                              name.isNotEmpty ? name[0] : 'م',
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(contact, style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isBanned ? Colors.red : const Color(0xFF10B981)).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isBanned ? 'محظور 🚫' : 'عميل نشط',
                                  style: TextStyle(fontSize: 11, color: isBanned ? Colors.red : const Color(0xFF10B981), fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            onSelected: (v) {
                              if (v == 'ban') {
                                _toggleBan(context, doc.id, name, isBanned,
                                    user['is_blocked'] == true);
                              } else if (v == 'delete') {
                                _deleteUser(context, doc.id, name);
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem<String>(
                                value: 'ban',
                                child: Row(children: [
                                  Icon(isBanned ? Icons.lock_open_rounded : Icons.block_rounded,
                                      color: isBanned ? Colors.green : Colors.orange.shade700, size: 20),
                                  const SizedBox(width: 10),
                                  Text(isBanned ? 'رفع الحظر' : 'حظر المستخدم'),
                                ]),
                              ),
                              // الحذف النهائي يكتب account_deletions والقواعد تحصره
                              // بالمدير العام — إظهاره لمدير العمليات كان زراً معطوباً
                              // ينتهي دوماً بـ permission-denied.
                              if (_role == 'super_admin')
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                                    const SizedBox(width: 10),
                                    const Text('حذف نهائي'),
                                  ]),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
