import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminMaintenanceScreen extends StatelessWidget {
  const AdminMaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text("طلبات الصيانة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('maintenance_requests').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات صيانة"));

            // Sort manually to handle missing timestamps
            final docs = snapshot.data!.docs.toList();
            docs.sort((a, b) {
              final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final req = doc.data() as Map<String, dynamic>;
                String status = req['status'] ?? 'under_review';
                
                String statusAr = 'قيد المراجعة';
                Color statusColor = Colors.orange;
                if (status == 'approved') { statusAr = 'مقبول / جاري العمل'; statusColor = Colors.blue; }
                if (status == 'rejected') { statusAr = 'مرفوض'; statusColor = Colors.red; }
                if (status == 'completed') { statusAr = 'مكتمل'; statusColor = Colors.green; }

                return Card(
                   elevation: 2,
                  margin: const EdgeInsets.only(bottom: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.brown.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.build, color: Colors.brown)
                          ),
                          title: Text(req['serviceType'] ?? 'عطل غير محدد', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                          subtitle: Text("العميل: ${req['userName'] ?? 'مستخدم'}\nالجوال: ${req['userPhone'] ?? ''}\nالتاريخ: ${req['scheduledAt'] != null ? (req['scheduledAt'] as Timestamp).toDate().toString().split(' ')[0] : '-'}\nالسعر: ${req['quotePrice'] ?? 'لم يحدد'} ر.س"),
                          trailing: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(statusAr, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            TextButton.icon(
                              onPressed: () => _showStatusDialog(context, doc.id, req),
                              icon: const Icon(Icons.edit_note, size: 18),
                              label: const Text("تحديث"),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text("تأكيد الحذف"),
                                    content: const Text("هل أنت متأكد من حذف هذا الطلب؟"),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
                                      TextButton(onPressed: () async {
                                        await FirebaseFirestore.instance.collection('maintenance_requests').doc(doc.id).delete();
                                        if (context.mounted) Navigator.pop(ctx);
                                      }, child: const Text("حذف", style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              label: const Text("حذف", style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        )
                      ],
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

  void _showStatusDialog(BuildContext context, String docId, Map<String, dynamic> currentData) {
    final TextEditingController priceCtrl = TextEditingController(text: (currentData['quotePrice'] ?? '').toString());
    
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تحديث حالة الطلب وتسعيره'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "سعر الخدمة المقترح (ر.س)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payments),
                ),
              ),
              const SizedBox(height: 20),
              const Text("اختر الحالة الجديدة:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const Divider(),
              ListTile(
                title: const Text('قيد المراجعة'), 
                leading: const Icon(Icons.hourglass_empty, color: Colors.orange),
                onTap: () { _updateStatus(docId, 'under_review', priceCtrl.text); Navigator.pop(ctx); }
              ),
              ListTile(
                title: const Text('مقبول (بانتظار الدفع)'), 
                leading: const Icon(Icons.payment, color: Colors.blue),
                onTap: () { _updateStatus(docId, 'waiting_payment', priceCtrl.text); Navigator.pop(ctx); }
              ),
              ListTile(
                title: const Text('جاري العمل (مدفوع)'), 
                leading: const Icon(Icons.build, color: Colors.blueGrey),
                onTap: () { _updateStatus(docId, 'approved', priceCtrl.text); Navigator.pop(ctx); }
              ),
              ListTile(
                title: const Text('مكتمل'), 
                leading: const Icon(Icons.check_circle, color: Colors.green),
                onTap: () { _updateStatus(docId, 'completed', priceCtrl.text); Navigator.pop(ctx); }
              ),
              ListTile(
                title: const Text('مرفوض'), 
                leading: const Icon(Icons.cancel, color: Colors.red),
                onTap: () { _updateStatus(docId, 'rejected', priceCtrl.text); Navigator.pop(ctx); }
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateStatus(String docId, String status, String price) async {
    final Map<String, dynamic> updates = {'status': status};
    if (price.isNotEmpty) {
      updates['quotePrice'] = double.tryParse(price) ?? 0.0;
    }
    await FirebaseFirestore.instance.collection('maintenance_requests').doc(docId).update(updates);
  }
}
