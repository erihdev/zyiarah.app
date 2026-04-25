import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/zyiarah_contract_pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

class AdminContractsScreen extends StatefulWidget {
  const AdminContractsScreen({super.key});

  @override
  State<AdminContractsScreen> createState() => _AdminContractsScreenState();
}

class _AdminContractsScreenState extends State<AdminContractsScreen> {
  final Color primaryNavy = const Color(0xFF1E293B);
  final Color brandBlue = const Color(0xFF2563EB);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("العقود الإلكترونية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 20)),
          backgroundColor: primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('contracts').orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                return _buildContractCard(doc);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContractCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String planName = data['planName'] ?? 'باقة اشتراك';
    final String clientName = data['userName'] ?? data['clientName'] ?? 'عميل زيارة';
    final String status = data['status'] ?? 'pending';
    final DateTime createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final String contractId = doc.id.substring(0, 8).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blueGrey.shade100, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: brandBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.description_rounded, color: brandBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName,
                        style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 16, color: primaryNavy),
                      ),
                      Text(
                        "رقم العقد: #$contractId",
                        style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),
          ),
          
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Details Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildInfoBit("العميل", clientName, Icons.person_outline),
                _buildInfoBit("تاريخ التوقيع", intl.DateFormat('dd-MM-yyyy').format(createdAt), Icons.calendar_today_outlined),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (status == 'pending')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveContract(doc.id, planName),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: Text("اعتماد العقد", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _showDetails(data),
                  icon: const Icon(Icons.info_outline_rounded),
                  style: IconButton.styleFrom(backgroundColor: Colors.blueGrey[50], foregroundColor: Colors.blueGrey[600]),
                ),
                IconButton.filled(
                  onPressed: () => _deleteContract(doc.id),
                  icon: const Icon(Icons.delete_outline_rounded),
                  style: IconButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBit(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold, color: primaryNavy),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = Colors.grey;
    String text = status;
    IconData icon = Icons.help_outline;

    switch (status) {
      case 'active':
        color = Colors.green;
        text = "مفعل";
        icon = Icons.verified_user_rounded;
        break;
      case 'approved_waiting_payment':
        color = Colors.blue;
        text = "بانتظار الدفع";
        icon = Icons.payments_rounded;
        break;
      case 'pending':
        color = Colors.orange;
        text = "قيد المراجعة";
        icon = Icons.timer_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _approveContract(String id, String plan) async {
    final confirm = await _showConfirm("اعتماد العقد", "هل أنت متأكد من اعتماد باقة ($plan)؟");
    if (confirm) {
      await FirebaseFirestore.instance.collection('contracts').doc(id).update({
        'status': 'approved_waiting_payment',
        'adminApprovedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _deleteContract(String id) async {
    final confirm = await _showConfirm("حذف العقد", "سيتم حذف هذا السجل نهائياً. هل أنت متأكد؟");
    if (confirm) {
      await FirebaseFirestore.instance.collection('contracts').doc(id).delete();
    }
  }

  void _showDetails(Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Text("تفاصيل العقد", style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 20)),
            const Divider(height: 32),
            _buildDetailRow("اسم العميل", data['userName'] ?? data['clientName'] ?? 'عميل زيارة'),
            _buildDetailRow("الباقة", data['planName'] ?? 'باقة اشتراك'),
            _buildDetailRow("قيمة التعاقد", "${data['planPrice'] ?? 0} ر.س"),
            _buildDetailRow("الزيارات المتاحة", "${data['planVisits'] ?? 0} زيارة"),
            _buildDetailRow("رقم الاتصال", data['userPhone'] ?? 'غير مسجل'),
            const Divider(height: 32),
            if (data['status'] == 'active' || data['status'] == 'approved_waiting_payment')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ZyiarahContractPdfService.generateAndDownloadContract(
                        contractId: data['contractId'] ?? 'XXXX',
                        planName: data['planName'] ?? 'باقة اشتراك',
                        userName: data['userName'] ?? data['clientName'] ?? 'عميل زيارة',
                        userPhone: data['userPhone'] ?? 'غير مسجل',
                        price: (data['planPrice'] ?? 0).toDouble(),
                        visits: data['planVisits'] ?? 0,
                        startDate: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        signatureData: data['signatureData'], // Passing the actual signature data
                      );
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إنشاء الملف: $e')));
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("تحميل نسخة العقد (PDF)", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.blue),
                    foregroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("إغلاق", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          Text(value, style: GoogleFonts.tajawal(color: primaryNavy, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<bool> _showConfirm(String title, String body) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
        content: Text(body, style: GoogleFonts.tajawal()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: primaryNavy, foregroundColor: Colors.white), child: const Text("تأكيد")),
        ],
      ),
    ) ?? false;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text("لا توجد عقود حالياً", style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
