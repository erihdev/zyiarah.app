import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/services.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';
import 'package:zyiarah/utils/csv_export_util.dart';


class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'assigned': return Colors.blue;
      case 'in_progress': return Colors.purple;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار';
      case 'assigned': return 'تم التعيين';
      case 'in_progress': return 'جاري التنفيذ';
      case 'completed': return 'مكتمل';
      case 'cancelled': return 'ملغي';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('orders').orderBy('created_at', descending: true).limit(50).snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          
          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            appBar: AppBar(
              title: Text("سجل الطلبات الشامل", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                if (docs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: IconButton(
                      tooltip: "تصدير للتقرير المحاسبي",
                      onPressed: () {
                        final csvData = ZyiarahExportUtil.convertToCsv(docs);
                        Clipboard.setData(ClipboardData(text: csvData));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("تم تجهيز التقرير المحاسبي ونسخه بنجاح ✅"),
                          backgroundColor: Colors.green,
                        ));
                      }, 
                      icon: const Icon(Icons.file_download_outlined)
                    ),
                  )
              ],
            ),
            body: _buildBody(snapshot, docs),
          );
        },
      ),
    );
  }

  Widget _buildBody(AsyncSnapshot<QuerySnapshot> snapshot, List<QueryDocumentSnapshot> docs) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _buildShimmerLoading();
    }

    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text("لا توجد طلبات مسجلة حالياً", style: GoogleFonts.tajawal(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';
        final service = data['service_name'] ?? 'خدمة غير معروفة';
        final amount = data['final_amount'] ?? data['amount'] ?? 0;
        final code = data['code'] ?? docs[index].id.substring(0, 8).toUpperCase();
        
        DateTime date = DateTime.now();
        if (data['created_at'] != null) {
          date = (data['created_at'] as Timestamp).toDate();
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.grey.shade100)),
          child: InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AdminOrderDetailsScreen(orderId: docs[index].id)));
            },
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
                    child: Icon(Icons.receipt_long_rounded, color: _getStatusColor(status), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B))),
                        const SizedBox(height: 2),
                        Text("رقم الطلب: #$code", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("$amount ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), fontSize: 14)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                        child: Text(_getStatusText(status), style: TextStyle(fontSize: 10, color: _getStatusColor(status), fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerLoading() {
    return ZyiarahShimmer.buildListSkeleton(count: 6);
  }
}
