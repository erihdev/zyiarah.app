import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("العملاء والمستخدمين", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').orderBy('created_at', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا يوجد مستخدمين"));

            final docs = snapshot.data!.docs.where((d) => d['role'] == 'client').toList();
            
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final user = docs[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                    title: Text(user['name'] ?? 'مستخدم', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${user['phone'] ?? user['email'] ?? 'لا يوجد رقم'}\nمُسجل في تطبيق العملاء"),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red), 
                      onPressed: () async {
                        bool? confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => Directionality(
                            textDirection: TextDirection.rtl,
                            child: AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              title: Text("حذف المستخدم", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                              content: const Text("هل أنت متأكد من رغبتك في حذف هذا المستخدم نهائياً؟ بمجرد الحذف يفقد وصوله للتطبيق."),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(ctx, true), 
                                  child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        );

                        if (confirm == true) {
                          try {
                            final String uid = docs[index].id;
                            // 1. حذف من قاعدة البيانات فوراً
                            await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                            
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('تم حذف بيانات المستخدم وصلاحية وصوله بنجاح ✅'),
                                backgroundColor: Colors.green,
                              ));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('حدث خطأ: $e'),
                                backgroundColor: Colors.red,
                              ));
                            }
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
