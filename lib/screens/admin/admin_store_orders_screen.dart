import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/audit_service.dart';

class AdminStoreOrdersScreen extends StatelessWidget {
  const AdminStoreOrdersScreen({super.key});

  /// نافذة اعتماد الطلب مع تحديد السعر النهائي (يشمل أي رسوم توصيل/تعديلات).
  /// السعر مبدئياً = مجموع السلة، وقابل للتعديل من الإدارة.
  void _showApprovalDialog(BuildContext context, String orderId, Map<String, dynamic> order) {
    final double cartTotal = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final controller = TextEditingController(text: cartTotal.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('اعتماد الطلب وتحديد السعر',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سعر المنتجات في السلة: ${cartTotal.toStringAsFixed(2)} ر.س',
                  style: GoogleFonts.tajawal(fontSize: 13, color: Colors.grey[700])),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'المبلغ النهائي المعتمد (ر.س)',
                  helperText: 'يُضاف إليه التوصيل أو أي تعديلات — هذا ما سيدفعه العميل',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () {
                final val = double.tryParse(controller.text.trim());
                if (val == null || val <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                _approveOrder(context, orderId, order, val);
              },
              child: const Text('اعتماد وإشعار العميل'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => controller.dispose());
  }

  /// الموافقة على الطلب بالسعر النهائي [finalAmount]: تنتقل حالته إلى
  /// approved/بانتظار الدفع، ويُشعَر العميل لإتمام الدفع عبر شاشة طلباته.
  void _approveOrder(BuildContext context, String orderId, Map<String, dynamic> order,
      double finalAmount) async {
    try {
      await FirebaseFirestore.instance.collection('store_orders').doc(orderId).update({
        'status': 'approved',
        'payment_status': 'awaiting_payment',
        'final_amount': finalAmount,
        'updated_at': FieldValue.serverTimestamp(),
      });
      await ZyiarahAuditService().logAction(
        action: 'APPROVE_STORE_ORDER',
        details: {'code': order['code'], 'final_amount': finalAmount},
        targetId: orderId,
      );
      // إشعار العميل يتولّاه الآن مُشغّل notifyClientOnStoreOrderStatus خادميّاً عند
      // status→approved (يعمل للوحة الويب أيضاً). أزلنا النداء المباشر لمنع التكرار.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تمت الموافقة وإشعار العميل لإتمام الدفع")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء الموافقة")));
      }
    }
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5D1B5E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
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
      case 'cash_on_delivery':
        return 'عند الاستلام';
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
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('store_orders').orderBy('created_at', descending: true).limit(100).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return const Center(child: Text("تعذّر تحميل الطلبات، تحقّق من الاتصال"));
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("لا توجد طلبات في المتجر حتى الآن"));

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final orderDoc = snapshot.data!.docs[index];
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
                              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF5D1B5E)),
                              onPressed: () => _showOrderItems(context, order),
                            ),
                            if (status == 'pending')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('الموافقة على الطلب'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => _showApprovalDialog(context, orderDoc.id, order),
                              ),
                             if (status == 'processing' || status == 'shipped')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.local_shipping, size: 18),
                                label: const Text('تم الشحن / اكتمل'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                onPressed: () => _updateOrderStatus(context, orderDoc.id, 'delivered'),
                              ),
                          ],
                        ),
                        if (status == 'pending')
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _updateOrderStatus(context, orderDoc.id, 'rejected'),
                              child: const Text('رفض الطلب', style: TextStyle(color: Colors.red)),
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
    );
  }
}
