import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text('حجوزاتي والطلبات', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "الخدمات المنزلية", icon: Icon(Icons.cleaning_services)),
              Tab(text: "قسم الصيانة", icon: Icon(Icons.settings_suggest)),
            ],
            indicatorColor: Colors.white,
            labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOrdersTab(user),
            _buildMaintenanceTab(user),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersTab(User? user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('client_id', isEqualTo: user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (user == null) return const Center(child: Text('يرجى تسجيل الدخول لعرض حجوزاتك'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 5,
            itemBuilder: (context, index) => const ShimmerCard(),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Sort in-memory to avoid composite index requirement
        final orders = snapshot.data!.docs.toList();
        orders.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
        });

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
    );
  }

  Widget _buildMaintenanceTab(User? user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_requests')
          .where('userId', isEqualTo: user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (user == null) return const Center(child: Text('يرجى تسجيل الدخول'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 5,
            itemBuilder: (context, index) => const ShimmerCard(),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        // Sort in-memory to avoid composite index requirement
        final reqs = snapshot.data!.docs.toList();
        reqs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reqs.length,
          itemBuilder: (context, index) {
            final data = reqs[index].data() as Map<String, dynamic>;
            final String docId = reqs[index].id;
            return _buildMaintenanceCard(context, data, docId);
          },
        );
      },
    );
  }

  Widget _buildMaintenanceCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final status = data['status'] ?? 'under_review';
    final requestId = data['requestId'] ?? '-';
    final quotePrice = (data['quotePrice'] ?? 0.0).toDouble();
    
    Color statusColor = Colors.orange;
    String statusText = "تحت المراجعة";

    if (status == 'waiting_payment') {
       statusColor = Colors.blue;
       statusText = "بانتظار الدفع";
    } else if (status == 'approved' || status == 'paid' || status == 'completed') {
       statusColor = Colors.green;
       statusText = "مقبول / جاري العمل";
    } else if (status == 'rejected') {
       statusColor = Colors.red;
       statusText = "مرفوض";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.build_circle_outlined, color: statusColor),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data['serviceType'] ?? 'طلب صيانة', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                      Text('رقم الطلب: #$requestId', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            _buildProgressStepper(status),
            if (quotePrice > 0) ...[
              const Divider(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("التكلفة المقدرة", style: TextStyle(fontSize: 10, color: Colors.grey)),
                      Text("$quotePrice ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF5D1B5E))),
                    ],
                  ),
                  if (status == 'waiting_payment')
                    ElevatedButton(
                      onPressed: () {
                        // Navigate to payment
                        Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentSummaryScreen(
                          serviceName: data['serviceType'] ?? 'صيانة',
                          amount: quotePrice,
                          maintenanceId: docId,
                        )));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5D1B5E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text("ادفع الآن", style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.network(
            'https://lottie.host/9972352b-4780-4545-8f65-021199346747/XJzQitkR2f.json', // Search/Empty anim
            height: 200,
          ),
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
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF5D1B5E))),
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
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF5D1B5E)),
                )
              else if (status != 'pending')
                ElevatedButton.icon(
                  onPressed: () {
                    if (order['driver_id'] != null && order['location'] != null) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => OrderTrackingScreen(
                        orderId: docId,
                      )));
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: Text('تتبع السائق', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF5D1B5E),
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

  Widget _buildProgressStepper(String status) {
    int currentStep = 0;
    bool isRejected = status == 'rejected';
    
    // Status Mapping
    if (status == 'waiting_payment') {
      currentStep = 1;
    } else if (status == 'approved' || status == 'paid' || status == 'in_progress') {
      currentStep = 2;
    } else if (status == 'completed') {
      currentStep = 3;
    }

    final steps = [
      {'label': 'مراجعة', 'icon': Icons.search},
      {'label': 'تسعير', 'icon': Icons.payments},
      {'label': 'تنفيذ', 'icon': Icons.build},
      {'label': 'اكتمال', 'icon': Icons.check_circle},
    ];

    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (index) {
          final bool isCompleted = !isRejected && index <= currentStep;
          final bool isLast = index == steps.length - 1;
          
          Color activeColor = const Color(0xFF5D1B5E);
          if (isRejected && index == 0) activeColor = Colors.red;
          
          final color = isCompleted ? activeColor : (isRejected && index <= currentStep ? Colors.red.withValues(alpha: 0.3) : Colors.grey.shade300);

          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: color, width: 2)
                      ),
                      child: Icon(
                        isRejected && index == 0 ? Icons.error_outline : steps[index]['icon'] as IconData, 
                        size: 14, 
                        color: color
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isRejected && index == 0 ? 'مرفوض' : steps[index]['label'] as String, 
                      style: GoogleFonts.tajawal(
                        fontSize: 8, 
                        fontWeight: isCompleted || (isRejected && index == 0) ? FontWeight.bold : FontWeight.normal, 
                        color: isCompleted ? const Color(0xFF0F172A) : (isRejected && index == 0 ? Colors.red : Colors.grey)
                      )
                    ),
                  ],
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 15, left: 4, right: 4),
                      decoration: BoxDecoration(
                        color: !isRejected && index < currentStep ? activeColor : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
