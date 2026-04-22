import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/notification_trigger_service.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:intl/intl.dart' as intl;

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
                return _buildContractCard(context, contract, contractId);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContractCard(BuildContext context, Map<String, dynamic> data, String id) {
    final status = data['status'] ?? 'pending';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final clientName = data['clientName'] ?? data['userName'] ?? 'عميل غير معروف';
    final planName = data['planName'] ?? 'باقة اشتراك';

    Color statusColor = Colors.orange;
    String statusText = "بانتظار المراجعة";
    if (status == 'active') {
      statusColor = Colors.green;
      statusText = "نشط";
    } else if (status == 'approved_waiting_payment') {
      statusColor = Colors.blue;
      statusText = "بانتظار الدفع";
    } else if (status == 'rejected') {
      statusColor = Colors.red;
      statusText = "مرفوض";
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () => _showContractDetails(context, data, id),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.description_rounded, color: statusColor, size: 24),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(clientName, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(planName, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "التاريخ: ${intl.DateFormat('yyyy/MM/dd').format(createdAt)}",
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  Row(
                    children: [
                      if (status == 'pending')
                        TextButton(
                          onPressed: () => _showContractDetails(context, data, id),
                          child: Text("مراجعة واعتماد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.blue)),
                        )
                      else
                        TextButton(
                          onPressed: () => _showContractDetails(context, data, id),
                          child: Text("عرض التفاصيل", style: GoogleFonts.tajawal(color: Colors.grey)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => _deleteContract(context, id),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContractDetails(BuildContext context, Map<String, dynamic> data, String id) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text("مراجعة العقد", style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection("بيانات العميل:", [
                        "الاسم: ${data['clientName'] ?? data['userName'] ?? 'غير معروف'}",
                        "الجوال: ${data['userPhone'] ?? 'غير متوفر'}",
                        "المعرف: ${data['userId'] ?? 'غير متوفر'}",
                      ]),
                      const SizedBox(height: 20),
                      _buildInfoSection("تفاصيل الباقة:", [
                        "اسم الباقة: ${data['planName']}",
                        "السعر: ${data['planPrice']} ر.س",
                        "الزيارات: ${data['planVisits']} زيارة",
                      ]),
                      const SizedBox(height: 30),
                      Text("معاينة التوثيق:", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            Text(
                              "أقر أنا الطرف الثاني بالموافقة على بنود العقد الإلكتروني الموضح أعلاه.",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(fontSize: 13, height: 1.6),
                            ),
                            const SizedBox(height: 20),
                            if (data['hasSignature'] == true)
                              Column(
                                children: [
                                  const Icon(Icons.gesture, color: Colors.blueGrey, size: 40),
                                  Text("تم التوقيع إلكترونياً", style: GoogleFonts.tajawal(fontSize: 11, color: Colors.blueGrey)),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              if (data['status'] == 'pending')
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle),
                          label: const Text("اعتماد وطلب دفع"),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _updateContractStatus(id, 'approved_waiting_payment', userId: data['userId'], planName: data['planName'], clientName: data['clientName'] ?? data['userName']);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: const Text("رفض العقد"),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _updateContractStatus(id, 'rejected', userId: data['userId'], planName: data['planName'], clientName: data['clientName'] ?? data['userName']);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF1E293B))),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(item, style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey[700])),
        )),
      ],
    );
  }

  Future<void> _updateContractStatus(String id, String status, {String? userId, String? planName, String? clientName}) async {
    await FirebaseFirestore.instance.collection('contracts').doc(id).update({
      'status': status,
      'adminApprovedAt': status == 'approved_waiting_payment' ? FieldValue.serverTimestamp() : null,
    });

    ZyiarahAuditService().logAction(
      action: status == 'approved_waiting_payment' ? 'APPROVE_CONTRACT' : 'REJECT_CONTRACT',
      details: {
        'contract_id': id,
        'client': clientName ?? 'غير متوفر',
        'plan': planName ?? 'غير متوفر',
        'new_status': status,
      },
      targetId: id,
    );

    if (userId != null && status == 'approved_waiting_payment') {
      await ZyiarahNotificationTriggerService().notifyContractApproved(userId, planName ?? 'باقة اشتراك');
    }
  }

  Future<void> _deleteContract(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text('تأكيد الحذف', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: const Text('هل أنت متأكد من حذف هذا العقد نهائياً؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
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
