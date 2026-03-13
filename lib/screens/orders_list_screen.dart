import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';

class OrdersListScreen extends StatelessWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('حجوزاتي والطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('client_id', isEqualTo: user?.uid)
              .orderBy('created_at', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)));
            }
            if (snapshot.hasError) {
              return Center(child: Text('خطأ في التحميل: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildEmptyState();
            }

            final orders = snapshot.data!.docs;
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index].data() as Map<String, dynamic>;
                final orderDocId = orders[index].id;
                return _buildOrderCard(context, order, orderDocId);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text('لا توجد حجوزات سابقة', 
            style: GoogleFonts.tajawal(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('ابدأ بحجز أول خدمة لك الآن', style: GoogleFonts.tajawal(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order, String docId) {
    final status = order['status'] ?? 'pending';
    final createdAt = (order['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = intl.DateFormat('yyyy/MM/dd HH:mm').format(createdAt);
    
    Color statusColor = Colors.orange;
    String statusText = "قيد الانتظار";
    if (status == 'completed') {
      statusColor = Colors.green;
      statusText = "مكتمل";
    } else if (status == 'in_progress' || status == 'accepted' || status == 'arrived') {
      statusColor = Colors.blue;
      statusText = "جاري التنفيذ";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order['service_type'] ?? 'خدمة عامة', 
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusText, 
                  style: GoogleFonts.tajawal(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 5),
              Text(dateStr, style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${order['amount']} ر.س', 
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF2563EB))),
              if (status == 'completed')
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentSummaryScreen(
                      serviceName: order['service_type'] ?? 'خدمة عامة',
                      amount: (order['amount'] ?? 0.0).toDouble(),
                      location: order['location'],
                    )));
                  },
                  icon: const Icon(Icons.replay, size: 16),
                  label: Text('أعد الطلب', style: GoogleFonts.tajawal(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF2563EB)),
                )
              else if (status != 'pending')
                ElevatedButton.icon(
                  onPressed: () {
                    if (order['driver_id'] != null && order['location'] != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => OrderTrackingScreen(
                        orderId: docId,
                        driverId: order['driver_id'],
                        destination: order['location'],
                      )));
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: Text('تتبع السائق', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )
              else
                 const Icon(Icons.chevron_left, color: Colors.grey, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
