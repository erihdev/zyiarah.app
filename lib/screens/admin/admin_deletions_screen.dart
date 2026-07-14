import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminDeletionsScreen extends StatelessWidget {
  const AdminDeletionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلبات حذف الحسابات", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E), // Red
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('account_deletions').orderBy('requested_at', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات حذف حساب حالياً"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final req = doc.data() as Map<String, dynamic>;
                final status = req['status'] as String? ?? 'pending';
                // زر الحذف يظهر فقط للحالة pending. الدالة تكتب failed_deletion عند فشل
                // التنظيف — كان يظهر كـ«قيد الانتظار» بزرّ حذف نشط فيُعيد الأدمن تشغيله بصمت.
                final isPending = status == 'pending';
                final statusText = status == 'deleted_fully_processed'
                    ? 'تم مسح البيانات نهائياً'
                    : status == 'deleted'
                        ? 'جاري المسح...'
                        : status == 'failed_deletion'
                            ? 'فشل الحذف — يتطلب مراجعة'
                            : status == 'rejected'
                                ? 'مرفوض'
                                : 'قيد الانتظار';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.no_accounts, color: Colors.white)),
                    title: Text(req['email'] ?? req['phone'] ?? 'حساب مجهول', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("السبب: ${req['reason'] ?? 'غير محدد'}\nتاريخ الطلب: ${req['requested_at'] != null ? (req['requested_at'] as Timestamp).toDate().toString().split(' ')[0] : ''}\nالحالة: $statusText"),
                    isThreeLine: true,
                    trailing: !isPending
                        ? Text(
                            status == 'deleted_fully_processed'
                                ? "تم الحذف"
                                : status == 'deleted'
                                    ? "جاري الحذف..."
                                    : status == 'failed_deletion'
                                        ? "فشل الحذف"
                                        : status == 'rejected'
                                            ? "مرفوض"
                                            : status,
                            style: TextStyle(
                              color: status == 'deleted_fully_processed'
                                  ? Colors.green
                                  : status == 'failed_deletion' || status == 'rejected'
                                      ? Colors.red
                                      : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: AlertDialog(
                                    title: Text("تأكيد الحذف النهائي", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                                    content: const Text("هل أنت متأكد من حذف هذا الحساب نهائياً؟ ستتم إزالة بيانات المستخدم والملف الشخصي FCM والرمز المميز وكلمة المرور فوراً عبر خادم آمن تماشياً مع معايير حماية البيانات GDPR."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                        child: const Text("حذف الآن", style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              if (confirm == true) {
                                try {
                                  await FirebaseFirestore.instance.collection('account_deletions').doc(doc.id).update({
                                    'status': 'deleted',
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("تم بدء عملية الحذف بنجاح. سيتم مسح البيانات خلال ثوانٍ.")),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("فشل الحذف: $e")),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Text("حذف"),
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
