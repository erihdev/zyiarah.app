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
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final contract = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                final contractId = snapshot.data!.docs[index].id;
                final bool hasPdf = contract['pdfUrl'] != null && contract['pdfUrl'].toString().isNotEmpty;

                return Card(
                  elevation: 2,
                  shadowColor: Colors.black.withValues(alpha: 0.1),
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: ListTile(
                      onTap: () async {
                        if (hasPdf) {
                          final url = Uri.parse(contract['pdfUrl']);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          } else {
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('رابط العقد غير متوفر حالياً. جاري التحقق...'),
                                action: SnackBarAction(label: 'إعادة محاولة', onPressed: () {
                                  // logic to trigger repair if needed in future
                                }),
                              )
                            );
                          }
                        }
                      },
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (hasPdf ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasPdf ? Icons.description_rounded : Icons.warning_amber_rounded,
                          color: hasPdf ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(
                        contract['clientName'] ?? 'عقد مستخدم',
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            "التاريخ: ${contract['createdAt'] != null ? (contract['createdAt'] as Timestamp).toDate().toString().split(' ')[0] : 'غير محدد'}",
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasPdf ? "اضغط لفتح العقد (PDF)" : "⚠️ الرابط غير متوفر حالياً",
                            style: TextStyle(
                              fontSize: 11,
                              color: hasPdf ? Colors.blue : Colors.red,
                              fontWeight: hasPdf ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        onPressed: () => _deleteContract(context, contractId),
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

  Future<void> _deleteContract(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('تأكيد الحذف', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text('هل أنت متأكد من حذف هذا العقد نهائياً من السجلات؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(_, true), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف الآن', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('contracts').doc(id).delete();
    }
  }
}
