import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

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
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }
  }

  // (دمج من لوحة الويب) حظر/رفع حظر مستخدم دون حذفه. يفرضه التطبيق فعلاً:
  // user_provider يفحص status=='banned' فيُسجّل خروجه ويمنعه من الاستخدام.
  Future<void> _toggleBan(
      BuildContext context, String uid, String name, bool isBanned) async {
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
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'status': isBanned ? 'active' : 'banned',
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
          backgroundColor: const Color(0xFF5D1B5E),
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

            final docs = snapshot.data!.docs;

            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_search, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'لا يوجد عملاء مسجلون بعد',
                      style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

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
                            backgroundColor: const Color(0xFF5D1B5E).withValues(alpha: 0.1),
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
                                _toggleBan(context, doc.id, name, isBanned);
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
