import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/order_tracking_screen.dart';
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';
import 'package:zyiarah/utils/status_util.dart';
import 'package:zyiarah/services/order_service.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activePhase = 0; // 0 for Active, 1 for History

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
              Tab(text: "طلبات المتجر", icon: Icon(Icons.shopping_bag)),
            ],
            indicatorColor: Colors.white,
            labelStyle: GoogleFonts.tajawal(fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            _buildPhaseFilter(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOrdersTab(user),
                  _buildMaintenanceTab(user),
                  _buildStoreOrdersTab(user),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseFilter() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildPhaseButton(0, "الطلبات النشطة", Icons.bolt),
          _buildPhaseButton(1, "سجل الطلبات", Icons.history),
        ],
      ),
    );
  }

  Widget _buildPhaseButton(int index, String title, IconData icon) {
    bool isSelected = _activePhase == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activePhase = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF5D1B5E) : Colors.grey,
                ),
              ),
            ],
          ),
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
        // Filter based on phase
        final List<String> activeStatuses = ['pending', 'assigned', 'accepted', 'in_progress'];
        final List<String> historyStatuses = ['completed', 'cancelled'];
        
        final allDocs = snapshot.data!.docs;
        final orders = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'pending';
          return _activePhase == 0 
              ? activeStatuses.contains(status)
              : historyStatuses.contains(status);
        }).toList();

        if (orders.isEmpty) {
          return _buildEmptyState();
        }

        // Sort in-memory to avoid composite index requirement
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
        // Filter based on phase
        final List<String> historyStatuses = ['completed', 'rejected'];
        
        final allDocs = snapshot.data!.docs;
        final reqs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'under_review';
          return _activePhase == 0 
              ? !historyStatuses.contains(status)
              : historyStatuses.contains(status);
        }).toList();

        if (reqs.isEmpty) {
          return _buildEmptyState();
        }

        // Sort in-memory to avoid composite index requirement
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

  Widget _buildStoreOrdersTab(User? user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('store_orders')
          .where('client_id', isEqualTo: user?.uid)
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
        
        final List<String> activeStatuses = ['pending', 'processing', 'shipped'];
        final List<String> historyStatuses = ['delivered', 'cancelled'];
        
        final allDocs = snapshot.data!.docs;
        final storeOrders = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'pending';
          return _activePhase == 0 
              ? activeStatuses.contains(status)
              : historyStatuses.contains(status);
        }).toList();

        if (storeOrders.isEmpty) {
          return _buildEmptyState();
        }

        storeOrders.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          return (bTime ?? Timestamp.now()).compareTo(aTime ?? Timestamp.now());
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: storeOrders.length,
          itemBuilder: (context, index) {
            final data = storeOrders[index].data() as Map<String, dynamic>;
            return _buildStoreOrderCard(context, data);
          },
        );
      },
    );
  }

  Widget _buildStoreOrderCard(BuildContext context, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final code = data['code'] ?? 'ORD-000';
    final total = data['total_amount'] ?? 0;
    
    Color statusColor = Colors.orange;
    String statusText = "قيد المعالجة";
    
    if (status == 'pending') { statusColor = Colors.orange; statusText = "بانتظار التأكيد"; }
    else if (status == 'processing') { statusColor = Colors.blue; statusText = "قيد التجهيز"; }
    else if (status == 'shipped') { statusColor = Colors.indigo; statusText = "تم الشحن"; }
    else if (status == 'delivered') { statusColor = Colors.green; statusText = "تم التوصيل"; }
    else if (status == 'cancelled') { statusColor = Colors.red; statusText = "ملغي"; }

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
                  child: Icon(Icons.shopping_bag_outlined, color: statusColor),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("طلب أدوات ومنظفات", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                      Text('رقم الطلب: #$code', style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey)),
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
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("المجموع: $total ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF5D1B5E))),
                Text("${(data['items'] as List?)?.length ?? 0} منتجات", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final status = data['status'] ?? 'under_review';
    final requestId = data['requestId'] ?? '-';
    final quotePrice = (data['quotePrice'] ?? 0.0).toDouble();
    
    final statusData = ZyiarahStatus.getMaintenanceStatus(status);
    final statusColor = statusData['color'];
    final statusText = statusData['text'];

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF5D1B5E).withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today_rounded, size: 52, color: Color(0xFF5D1B5E)),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد طلبات',
              style: GoogleFonts.tajawal(fontSize: 20, color: const Color(0xFF0F172A), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'لم تقم بأي حجز بعد.\nابدأ بطلب خدمتك الأولى الآن!',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: const Color(0xFF64748B), height: 1.6, fontSize: 14),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.home_rounded),
              label: Text('العودة للرئيسية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5D1B5E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelOrder(BuildContext context, String docId, String? code) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('إلغاء الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          content: Text(
            'هل أنت متأكد من إلغاء الطلب #${code ?? docId}؟\nلا يمكن التراجع عن هذا الإجراء.',
            style: GoogleFonts.tajawal(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('تراجع', style: GoogleFonts.tajawal()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text('نعم، إلغاء الطلب', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ZyiarahOrderService().cancelOrder(docId, cancelledBy: 'client');
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم إلغاء الطلب بنجاح', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString().replaceAll("Exception: ", "")}', style: GoogleFonts.tajawal()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order, String docId) {
    final status = order['status'] ?? 'pending';
    final createdAt = (order['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = intl.DateFormat('yyyy/MM/dd HH:mm').format(createdAt);
    
    final statusData = ZyiarahStatus.getOrderStatus(status);
    final statusColor = statusData['color'];
    final statusText = statusData['text'];

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order['service_type'] ?? 'خدمة عامة', 
                    style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (order['code'] != null)
                    Text('رقم الطلب: #${order['code']}', style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                ],
              ),
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
              else if (status == 'pending')
                OutlinedButton.icon(
                  onPressed: () => _confirmCancelOrder(context, docId, order['code']),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text('إلغاء', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )
              else
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
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStepper(String status) {
    final statusData = ZyiarahStatus.getMaintenanceStatus(status);
    int currentStep = statusData['step'];
    bool isRejected = status == 'rejected';

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
