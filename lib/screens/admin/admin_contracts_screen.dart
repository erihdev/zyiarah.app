import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminContractsScreen extends StatelessWidget {
  const AdminContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("العقود الإلكترونية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('contracts').orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد عقود حتى الآن"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final contract = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                final contractId = snapshot.data!.docs[index].id;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () async {
                      if (contract['pdfUrl'] != null) {
                        final url = Uri.parse(contract['pdfUrl']);
                        if (await canLaunchUrl(url)) await launchUrl(url);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رابط العقد غير متوفر حالياً')));
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.history_edu, color: Colors.white)),
                      title: Text(contract['clientName'] ?? 'عقد مستخدم', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("التاريخ: ${contract['createdAt'] != null ? (contract['createdAt'] as Timestamp).toDate().toString().split(' ')[0] : 'غير محدد'}\nاضغط لفتح العقد (PDF)"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                               final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: AlertDialog(
                                      title: const Text('تأكيد الحذف'),
                                      content: const Text('هل أنت متأكد من حذف هذا العقد؟'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
                                        TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                      ],
                                    ),
                                  ),
                               );
                               if (confirm == true) {
                                 await FirebaseFirestore.instance.collection('contracts').doc(contractId).delete();
                               }
                            },
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
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
