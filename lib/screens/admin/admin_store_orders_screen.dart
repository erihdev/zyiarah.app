import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminStoreOrdersScreen extends StatefulWidget {
  const AdminStoreOrdersScreen({super.key});

  @override
  State<AdminStoreOrdersScreen> createState() => _AdminStoreOrdersScreenState();
}

class _AdminStoreOrdersScreenState extends State<AdminStoreOrdersScreen> {
  // (المتجر المباشر — قرار المالك) حُذف مسار «الموافقة والتسعير النهائي»:
  // العميل يدفع فوراً، والإدارة تدير التوصيل نقرةً نقرة أدناه.

  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateOrderStatus(BuildContext context, String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('store_orders').doc(orderId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ZyiarahAuditService().logAction(
        action: 'UPDATE_STORE_ORDER_STATUS',
        details: {'new_status': newStatus},
        targetId: orderId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تحديث حالة الطلب بنجاح")));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء التحديث")));
      }
    }
  }

  void _showOrderItems(BuildContext context, Map<String, dynamic> order) {
    final List<dynamic> items = order['items'] ?? [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('مشتريات العميل (${items.length} منتجات)', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),
              ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.inventory_2, color: Colors.blue),
                    ),
                    title: Text(item['name'] ?? 'منتج غير معروف', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('الكمية: ${item['quantity']} × السعر: ${item['price']} ر.س'),
                    trailing: Text('${(double.tryParse('${item['quantity'] ?? 0}') ?? 0) * (double.tryParse('${item['price'] ?? 0}') ?? 0)} ر.س', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green)),
                  );
                },
              ),
              const Divider(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الإجمالي المطلوب:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${order['total_amount'] ?? 0} ر.س', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006FBA), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق التفاصيل'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  String _paymentLabel(Map<String, dynamic> order) {
    final method = order['payment_method'] ?? 'pending';
    final paid = order['is_paid'] == true;
    switch (method) {
      // شاهد قبر: الدفع عند الاستلام حُذف من الجذور ولا يمكن إنشاؤه بعد اليوم، لكن
      // طلبات المتجر التاريخية قد تحمله — تركُ التسمية يُبقيها مقروءة للإدارة بدل
      // عرض 'cash_on_delivery' خامّاً. لا شيء في التطبيق يكتب هذه القيمة الآن.
      case 'cash_on_delivery':
        return 'عند الاستلام (طلب قديم)';
      case 'tamara':
        return paid ? 'تمارا (مدفوع)' : 'تمارا';
      case 'card':
        return paid ? 'بطاقة (مدفوع)' : 'بطاقة';
      case 'pending':
        return 'بانتظار الدفع';
      default:
        return paid ? 'مدفوع' : 'غير محدد';
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'pending': return 'جديد (بانتظار الموافقة)';
      case 'awaiting_payment': return 'بانتظار دفع العميل';
      case 'under_review': return 'مدفوع — تحت المراجعة';
      case 'delivering': return 'جاري التوصيل';
      case 'approved': return 'تمت الموافقة (بانتظار دفع العميل)';
      case 'processing': return 'مدفوع (جاري التجهيز)';
      case 'shipped': return 'تم التسليم للمندوب / الشحن';
      case 'delivered':
      case 'completed': return 'مكتمل ومُسلم';
      case 'rejected':
      case 'cancelled': return 'مرفوض / ملغي';
      default: return 'تحت المعالجة';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'awaiting_payment': return Colors.deepOrange;
      case 'under_review': return Colors.orange;
      case 'delivering': return Colors.indigo;
      case 'approved': return Colors.blue;
      case 'processing': return Colors.teal;
      case 'shipped': return Colors.purple;
      case 'delivered':
      case 'completed': return Colors.green;
      case 'rejected':
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: Text("مبيعات المتجر الإلكتروني", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF006FBA),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  hintText: 'ابحث برقم الطلب أو اسم العميل',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF006FBA)),
                  suffixIcon: _search.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _search = '');
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF006FBA), width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('store_orders').orderBy('created_at', descending: true).limit(100).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return const Center(child: Text("تعذّر تحميل الطلبات، تحقّق من الاتصال"));
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات في المتجر حتى الآن"));

                  final query = _search.trim().toLowerCase();
                  final docs = query.isEmpty
                      ? snapshot.data!.docs
                      : snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final code = doc.id.substring(0, 6).toLowerCase();
                          final clientName = (data['client_name'] ?? '').toString().toLowerCase();
                          return code.contains(query) || clientName.contains(query);
                        }).toList();

                  if (docs.isEmpty) {
                    return Center(child: Text('لا نتائج للبحث «${_search.trim()}»'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final orderDoc = docs[index];
                      final order = orderDoc.data() as Map<String, dynamic>;
                      final status = order['status'] ?? 'pending';

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("رقم الطلب #${orderDoc.id.substring(0, 6).toUpperCase()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha:0.1), borderRadius: BorderRadius.circular(12)),
                              child: Text(_translateStatus(status), style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                        const Divider(height: 25),
                        Row(
                          children: [
                            const Icon(Icons.person, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text("العميل: ${order['client_name'] ?? 'غير محدد'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.attach_money, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              order['final_amount'] != null
                                  ? "المعتمد: ${order['final_amount']} ر.س (السلة: ${order['total_amount'] ?? 0})"
                                  : "الإجمالي: ${order['total_amount'] ?? 0} ر.س",
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.payment, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text("الدفع: ${_paymentLabel(order)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.visibility, size: 18),
                              label: const Text('عرض المشتريات'),
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF006FBA)),
                              onPressed: () => _showOrderItems(context, order),
                            ),
                            // سلسلة الإدارة: تحت المراجعة ⇒ جاري التوصيل ⇒
                            // تم التوصيل — كل نقرة تصل العميل حيّاً بإشعار خادمي.
                            // 'processing' إرث المسار القديم يُعامل كتحت المراجعة.
                            if (status == 'under_review' || status == 'processing')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                                label: const Text('بدء التوصيل'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                                onPressed: () => _updateOrderStatus(context, orderDoc.id, 'delivering'),
                              ),
                            if (status == 'delivering' || status == 'shipped')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('تم التوصيل'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => _updateOrderStatus(context, orderDoc.id, 'delivered'),
                              ),
                          ],
                        ),
                        if (order['delivery_location'] is GeoPoint)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.location_on_outlined, size: 18),
                              label: const Text('عنوان التوصيل على الخريطة'),
                              onPressed: () {
                                final gp = order['delivery_location'] as GeoPoint;
                                launchUrl(
                                    Uri.parse(
                                        'https://maps.google.com/?q=${gp.latitude},${gp.longitude}'),
                                    mode: LaunchMode.externalApplication);
                              },
                            ),
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
          ],
        ),
      ),
    );
  }
}
