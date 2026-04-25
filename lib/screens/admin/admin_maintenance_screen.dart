import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';
import 'package:zyiarah/utils/status_util.dart';

class AdminMaintenanceScreen extends StatelessWidget {
  const AdminMaintenanceScreen({super.key});

  static final ZyiarahNotificationTriggerService _notificationService = ZyiarahNotificationTriggerService();

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
                        
                        final statusData = ZyiarahStatus.getMaintenanceStatus(status);
                        String statusAr = statusData['text'];
                        Color statusColor = statusData['color'];

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
                                    child: const Icon(Icons.handyman, color: Colors.brown)
                                  ),
                                  title: Text(req['serviceType'] ?? 'صيانة مكيفات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 5),
                                      Text("العميل: ${req['userName'] ?? 'غير معروف'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text("الجوال: ${req['userPhone'] ?? '-'}", style: const TextStyle(fontSize: 12)),
                                      Text("العنوان: ${req['address'] ?? 'حسب الخريطة'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text("التاريخ: ${req['scheduledAt'] != null ? (req['scheduledAt'] as Timestamp).toDate().toString().split(' ')[0] : '-'}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      Text("السعر: ${req['quotePrice'] ?? 'قيد التسعير'} ر.س", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
                                    ],
                                  ),
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
                                      icon: const Icon(Icons.price_check, size: 18),
                                      label: const Text("تسعير / تحديث"),
                                    ),
                                    if (req['location'] != null)
                                      TextButton.icon(
                                        onPressed: () async {
                                          final loc = req['location'] as GeoPoint;
                                          final url = 'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}';
                                          if (await canLaunchUrl(Uri.parse(url))) {
                                            await launchUrl(Uri.parse(url));
                                          }
                                        },
                                        icon: const Icon(Icons.map_outlined, size: 18, color: Colors.green),
                                        label: const Text("الموقع", style: TextStyle(color: Colors.green)),
                                      ),
                                    TextButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text("حذف الطلب"),
                                            content: const Text("هل أنت متأكد؟ لا يمكن التراجع."),
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
                                      icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
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
            _buildStatCard("تحت المراجعة", pending.toString(), Colors.orange, Icons.pending_actions),
            _buildStatCard("بانتظار الدفع", waiting.toString(), Colors.blue, Icons.payments),
            _buildStatCard("طلبات مكتملة", total.toString(), Colors.green, Icons.check_circle_outline),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Icon(Icons.edit_attributes, color: const Color(0xFF1E293B)),
                  const SizedBox(width: 10),
                  const Text('تحديث الحالة والتسعير'),
                ],
              ),
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
                    decoration: InputDecoration(
                      labelText: "سعر الخدمة المقترح (ر.س)",
                      fillColor: Colors.grey.shade50,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.payments),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("اختر الحالة الجديدة لمزامنتها مع العميل:", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                  const Divider(),
                  _buildStatusItem(
                    title: 'قيد المراجعة',
                    icon: Icons.hourglass_top,
                    color: Colors.orange,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'under_review', priceCtrl.text, userId, currentData['serviceType'] ?? 'صيانة');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  _buildStatusItem(
                    title: 'إرسال التسعيرة (بانتظار الدفع)',
                    icon: Icons.send_and_archive,
                    color: Colors.blue,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'waiting_payment', priceCtrl.text, userId, currentData['serviceType'] ?? 'صيانة');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  _buildStatusItem(
                    title: 'اعتماد (تم الدفع)',
                    icon: Icons.check_circle,
                    color: Colors.green,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'approved', priceCtrl.text, userId, currentData['serviceType'] ?? 'صيانة');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  _buildStatusItem(
                    title: 'طلب مرفوض',
                    icon: Icons.cancel,
                    color: Colors.red,
                    enabled: !isSaving,
                    onTap: () async {
                      setDialogState(() => isSaving = true);
                      await _updateStatus(docId, 'rejected', priceCtrl.text, userId, currentData['serviceType'] ?? 'صيانة');
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              actions: [
                if (!isSaving)
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق")),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildStatusItem({required String title, required IconData icon, required Color color, required VoidCallback onTap, bool enabled = true}) {
    return ListTile(
      title: Text(title, style: GoogleFonts.tajawal(color: enabled ? Colors.black : Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
      leading: Icon(icon, color: enabled ? color : Colors.grey),
      onTap: enabled ? onTap : null,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Future<void> _updateStatus(String docId, String status, String price, String userId, String serviceType) async {
    final Map<String, dynamic> updates = {'status': status};
    double quotedAmount = 0.0;
    if (price.isNotEmpty) {
      quotedAmount = double.tryParse(price) ?? 0.0;
      updates['quotePrice'] = quotedAmount;
    }
    
    await FirebaseFirestore.instance.collection('maintenance_requests').doc(docId).update(updates);

    if (status == 'waiting_payment' && userId.isNotEmpty) {
      // --- TRIGGER EXTERNAL NOTIFICATION TO CLIENT ---
      await FirebaseFirestore.instance.collection('notification_triggers').add({
        'type': 'maintenance_priced',
        'title': 'تم تحديد تكلفة طلبك! 🏷️',
        'body': 'تم تسعير خدمة ($serviceType) بمبلغ $quotedAmount ر.س. يرجى الدفع للبدء.',
        'toUid': userId,
        'data': {
          'type': 'maintenance_payment',
          'requestId': docId,
        },
        'processed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // ------------------------------------------------
    }
    
    // Create actual order if approved (paid) - legacy logic
    if (status == 'approved' || status == 'paid') {
       // ... existing driver assignment logic ...
    }
  }
}
