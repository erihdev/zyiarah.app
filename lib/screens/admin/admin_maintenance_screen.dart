import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';

class AdminMaintenanceScreen extends StatelessWidget {
  AdminMaintenanceScreen({super.key});

  final ZyiarahNotificationTriggerService _notificationService = ZyiarahNotificationTriggerService();

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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ZyiarahShimmer.buildListSkeleton(count: 4);
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات صيانة"));

            final docs = snapshot.data!.docs.toList();
            
            // Stats Calculation
            int pending = docs.where((d) => (d.data() as Map)['status'] == 'under_review').length;
            int waitingPayment = docs.where((d) => (d.data() as Map)['status'] == 'waiting_payment').length;
            int completed = docs.where((d) => (d.data() as Map)['status'] == 'completed').length;

            // Sort manually
            docs.sort((a, b) {
              final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildStatsHeader(pending, waitingPayment, completed),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = docs[index];
                        final req = doc.data() as Map<String, dynamic>;
                        String status = req['status'] ?? 'under_review';
                        
                        String statusAr = 'قيد المراجعة';
                        Color statusColor = Colors.orange;
                        if (status == 'waiting_payment') { statusAr = 'بانتظار الدفع'; statusColor = Colors.blue; }
                        if (status == 'approved') { statusAr = 'مقبول / جاري العمل'; statusColor = Colors.indigo; }
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
                                      onPressed: () => _showStatusDialog(context, doc.id, req, req['userId'] ?? ''),
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
                      childCount: docs.length,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsHeader(int pending, int waiting, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatCard("طلبات جديدة", pending.toString(), Colors.orange, Icons.new_releases),
            _buildStatCard("بانتظار الدفع", waiting.toString(), Colors.blue, Icons.payment),
            _buildStatCard("طلبات منجزة", total.toString(), Colors.green, Icons.task_alt),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
        border: Border.all(color: color.withValues(alpha: 0.1), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value, style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A))),
          Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showStatusDialog(BuildContext context, String docId, Map<String, dynamic> currentData, String userId) {
    final TextEditingController priceCtrl = TextEditingController(text: (currentData['quotePrice'] ?? '').toString());
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تحديث حالة الطلب وتسعيره'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   if (isSaving) 
                    const Padding(
                      padding: EdgeInsets.only(bottom: 15),
                      child: LinearProgressIndicator(),
                    ),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      labelText: "سعر الخدمة المقترح (ر.س)",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("اختر الحالة الجديدة:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const Divider(),
                  _buildStatusItem(
                    title: 'قيد المراجعة',
                    icon: Icons.hourglass_empty,
                    color: Colors.orange,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'under_review', priceCtrl.text, userId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث الحالة بنجاح")));
                      }
                    },
                  ),
                  _buildStatusItem(
                    title: 'مقبول (بانتظار الدفع)',
                    icon: Icons.payment,
                    color: Colors.blue,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'waiting_payment', priceCtrl.text, userId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم قبول الطلب وإرسال العرض للعميل"), backgroundColor: Colors.blue));
                      }
                    },
                  ),
                  _buildStatusItem(
                    title: 'جاري العمل (مدفوع)',
                    icon: Icons.build,
                    color: Colors.blueGrey,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'approved', priceCtrl.text, userId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث الحالة: جاري العمل"), backgroundColor: Colors.green));
                      }
                    },
                  ),
                  _buildStatusItem(
                    title: 'مكتمل',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'completed', priceCtrl.text, userId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إغلاق الطلب كمكتمل"), backgroundColor: Colors.green));
                      }
                    },
                  ),
                  _buildStatusItem(
                    title: 'مرفوض',
                    icon: Icons.cancel,
                    color: Colors.red,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'rejected', priceCtrl.text, userId);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم رفض الطلب"), backgroundColor: Colors.red));
                      }
                    },
                  ),
                ],
              ),
              actions: [
                if (!isSaving)
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildStatusItem({required String title, required IconData icon, required Color color, required VoidCallback onTap, bool enabled = true}) {
    return ListTile(
      title: Text(title, style: TextStyle(color: enabled ? Colors.black : Colors.grey)),
      leading: Icon(icon, color: enabled ? color : Colors.grey),
      onTap: enabled ? onTap : null,
      dense: true,
    );
  }

  Future<void> _updateStatus(String docId, String status, String price, String userId) async {
    final Map<String, dynamic> updates = {'status': status};
    double quotedAmount = 0.0;
    if (price.isNotEmpty) {
      quotedAmount = double.tryParse(price) ?? 0.0;
      updates['quotePrice'] = quotedAmount;
    }
    await FirebaseFirestore.instance.collection('maintenance_requests').doc(docId).update(updates);

    if (status == 'waiting_payment' && userId.isNotEmpty) {
      await _notificationService.notifyClientOfMaintenanceQuote(userId, docId, quotedAmount);
    }
  }
}
