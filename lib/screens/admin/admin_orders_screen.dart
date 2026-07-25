import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/widgets/service_meta_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';
import 'package:zyiarah/widgets/zyiarah_shimmer.dart';
import 'package:zyiarah/utils/csv_export_util.dart';
import 'package:zyiarah/utils/status_util.dart';
import 'package:zyiarah/services/audit_service.dart';


class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // بحث حيّ داخل القائمة المحمّلة (بلا تغيير استعلام Firestore).
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    return ZyiarahStatus.getOrderStatus(status)['color'];
  }

  String _getStatusText(String status) {
    return ZyiarahStatus.getOrderStatus(status)['text'];
  }

  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "غير محدد";
    final now = DateTime.now();
    final date = timestamp.toDate();
    final difference = now.difference(date);

    if (difference.inSeconds < 60) return "الآن";
    if (difference.inMinutes < 60) return "منذ ${difference.inMinutes} د";
    if (difference.inHours < 24) return "منذ ${difference.inHours} س";
    return "منذ ${difference.inDays} يوم";
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
              backgroundColor: const Color(0xFF006FBA),
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

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[200]),
            const SizedBox(height: 16),
            Text("تعذّر تحميل الطلبات، تحقّق من الاتصال",
                style: GoogleFonts.tajawal(color: Colors.grey)),
          ],
        ),
      );
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

    // فلترة القائمة المحمّلة محلياً: رقم الطلب / اسم العميل / نوع الخدمة.
    final query = _search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? docs
        : docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final code =
                (data['code'] ?? doc.id.substring(0, 8)).toString().toLowerCase();
            final clientName =
                (data['client_name'] ?? data['userName'] ?? '').toString().toLowerCase();
            final service = (data['service_name'] ??
                    data['service_type'] ??
                    data['service_name_ar'] ??
                    '')
                .toString()
                .toLowerCase();
            return code.contains(query) ||
                clientName.contains(query) ||
                service.contains(query);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            style: GoogleFonts.tajawal(fontSize: 14),
            decoration: InputDecoration(
              hintText: "ابحث برقم الطلب أو اسم العميل أو الخدمة",
              hintStyle: GoogleFonts.tajawal(color: Colors.grey, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF006FBA)),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF006FBA), width: 1.5),
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text("لا نتائج للبحث «${_search.trim()}»",
                          style: GoogleFonts.tajawal(color: Colors.grey)),
                    ],
                  ),
                )
              : _buildOrdersList(filtered),
        ),
      ],
    );
  }

  Widget _buildOrdersList(List<QueryDocumentSnapshot> docs) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data() as Map<String, dynamic>;
        final status = data['status'] ?? 'pending';
        
        // Improved service name mapping with fallbacks
        final service = data['service_name'] ?? data['service_type'] ?? data['service_name_ar'] ?? 'خدمة غير معروفة';
        
        // Secure amount formatting — tryParse so a non-numeric/empty amount can't
        // crash the whole orders list.
        final rawAmount = data['final_amount'] ?? data['amount'] ?? 0;
        final String formattedAmount =
            (double.tryParse(rawAmount.toString()) ?? 0).toStringAsFixed(2);
        
        final code = data['code'] ?? docs[index].id.substring(0, 8).toUpperCase();
        // نوع المكيف وعدد الوحدات / قطع الكنب بمساحاتها — في البطاقة نفسها، لا
        // خلف نقرة تفاصيل (ملاحظة المالك: «أضف خانات مثل نوع المكيف وكم وحدة»).
        final metaSummary = zyiarahServiceMetaSummary(data['service_meta']);
        
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
              child: Column(
                children: [
                  Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15)),
                    child: Icon(Icons.receipt_long_rounded, color: _getStatusColor(status), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF1E293B))),
                        if (metaSummary != null) ...[
                          const SizedBox(height: 2),
                          Text(metaSummary,
                              style: GoogleFonts.tajawal(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF006FBA))),
                        ],
                        const SizedBox(height: 2),
                        Text("رقم الطلب: #$code", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 10, color: (status == 'pending' && DateTime.now().difference((data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now()).inMinutes > 15) ? Colors.red : Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              _getTimeAgo(data['created_at'] as Timestamp?),
                              style: TextStyle(
                                fontSize: 9, 
                                fontWeight: FontWeight.bold,
                                color: (status == 'pending' && DateTime.now().difference((data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now()).inMinutes > 15) ? Colors.red : Colors.grey
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("$formattedAmount ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, color: const Color(0xFF1E293B), fontSize: 14)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
                        child: Text(_getStatusText(status), style: TextStyle(fontSize: 10, color: _getStatusColor(status), fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ],
              ),
                  // (نمط المتجر — قرار المالك) الخدمات المُدارة إدارياً بلا سائق
                  // (تنظيف السيارات): تحت المراجعة ⇒ جاري التنفيذ ⇒ تم التنفيذ.
                  // كل نقرة تصل العميل حيّاً بإشعار خادمي.
                  if (status == 'under_review' ||
                      (status == 'in_progress' &&
                          '${data['driver_id'] ?? ''}'.isEmpty)) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(
                            status == 'under_review'
                                ? Icons.play_arrow_rounded
                                : Icons.check_circle_outline,
                            size: 18),
                        label: Text(status == 'under_review'
                            ? 'جاري التنفيذ'
                            : 'تم التنفيذ'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: status == 'under_review'
                                ? Colors.indigo
                                : Colors.green,
                            foregroundColor: Colors.white),
                        onPressed: () =>
                            _advanceManagedOrder(docs[index].id, status),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// نقلة الخدمات المُدارة إدارياً: under_review ⇒ in_progress ⇒ completed.
  Future<void> _advanceManagedOrder(String orderId, String status) async {
    final next = status == 'under_review' ? 'in_progress' : 'completed';
    try {
      await _db.collection('orders').doc(orderId).update({
        'status': next,
        if (next == 'completed') 'completed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ZyiarahAuditService().logAction(
        action: 'ADVANCE_MANAGED_ORDER',
        details: {'new_status': next},
        targetId: orderId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(next == 'in_progress'
                ? 'بدأ التنفيذ — أُشعر العميل'
                : 'اكتمل الطلب — أُشعر العميل')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر تحديث الحالة')));
      }
    }
  }

  Widget _buildShimmerLoading() {
    return ZyiarahShimmer.buildListSkeleton(count: 6);
  }
}
