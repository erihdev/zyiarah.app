import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:zyiarah/screens/payment_summary_screen.dart';
import 'package:zyiarah/screens/store_payment_screen.dart';
import 'package:zyiarah/widgets/shimmer_loading.dart';
import 'package:zyiarah/utils/status_util.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:go_router/go_router.dart';

// تحويل رقمي دفاعي — حقول Firestore (amount/total_amount/quotePrice) قد تصل نصّاً
// أو null، و.toDouble()/as num المباشر كان يعطّل بطاقة الطلب داخل القائمة.
double _asDouble(dynamic v) => v is num
    ? v.toDouble()
    : (v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0);

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
    // تبويبان: قسم الصيانة أُزيل مع حذف مسار عرض السعر (الأجهزة المنزلية).
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
          backgroundColor: const Color(0xFF006FBA),
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "الخدمات المنزلية", icon: Icon(Icons.cleaning_services)),
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
              Icon(icon, size: 16, color: isSelected ? const Color(0xFF006FBA) : Colors.grey),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF006FBA) : Colors.grey,
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
          return const Center(child: Text('تعذّر تحميل البيانات، تحقّق من الاتصال'));
        }
        // Filter based on phase
        // كل حالات المسار النشط بما فيها لهجة الإرسال المباشر (Direct Dispatch)
        final List<String> activeStatuses = [
          'pending', 'awaiting_payment', 'under_review',
          'assigned', 'scheduled', 'accepted', 'on_the_way', 'in_progress',
        ];
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
          return const Center(child: Text('تعذّر تحميل البيانات، تحقّق من الاتصال'));
        }
        
        // دورة المتجر الحقيقية: awaiting_payment ⇒ under_review ⇒ delivering ⇒ delivered.
        // بدون الثلاث الأولى كان الطلب المدفوع يختفي من التبويبين معاً حتى «delivered».
        final List<String> activeStatuses = [
          'awaiting_payment', 'under_review', 'delivering',
          'pending', 'approved', 'processing', 'shipped',
        ];
        final List<String> historyStatuses = ['delivered', 'completed', 'cancelled', 'rejected'];
        
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
            return _buildStoreOrderCard(context, storeOrders[index].id, data);
          },
        );
      },
    );
  }

  Widget _buildStoreOrderCard(BuildContext context, String docId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final code = data['code'] ?? 'ORD-000';
    final double total = _asDouble(data['total_amount']);
    // المتجر المباشر يُنشئ awaiting_payment؛ 'approved' إرث مسار الموافقة القديم.
    final bool awaitingPayment =
        (status == 'awaiting_payment' || status == 'approved') &&
            data['is_paid'] != true;
    // المبلغ الذي يدفعه العميل = السعر المعتمد من الإدارة إن وُجد، وإلا مجموع السلة
    final double payAmount =
        (data['final_amount'] as num?)?.toDouble() ?? total;

    Color statusColor = Colors.orange;
    String statusText = "قيد المعالجة";

    if (status == 'pending') { statusColor = Colors.orange; statusText = "بانتظار موافقة الإدارة"; }
    else if (status == 'awaiting_payment' || status == 'approved') { statusColor = Colors.deepOrange; statusText = "بانتظار الدفع"; }
    else if (status == 'under_review') { statusColor = Colors.orange; statusText = "تحت المراجعة"; }
    else if (status == 'delivering') { statusColor = Colors.indigo; statusText = "جاري التوصيل"; }
    else if (status == 'processing') { statusColor = Colors.blue; statusText = "قيد التجهيز"; }
    else if (status == 'shipped') { statusColor = Colors.indigo; statusText = "تم الشحن"; }
    else if (status == 'delivered' || status == 'completed') { statusColor = Colors.green; statusText = "تم التوصيل"; }
    else if (status == 'cancelled' || status == 'rejected') { statusColor = Colors.red; statusText = "ملغي"; }

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
                Text("المجموع: ${total % 1 == 0 ? total.toStringAsFixed(0) : total.toStringAsFixed(2)} ر.س", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF006FBA))),
                Text("${(data['items'] as List?)?.length ?? 0} منتجات", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            if (awaitingPayment) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "المبلغ المعتمد للدفع: ${payAmount.toStringAsFixed(2)} ر.س",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      fontWeight: FontWeight.bold, color: const Color(0xFF006FBA)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text("ادفع الآن", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006FBA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final items = ((data['items'] as List?) ?? [])
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StorePaymentScreen(
                          storeOrderId: docId,
                          orderCode: code,
                          items: items,
                          total: payAmount,
                          customerName: data['client_name'] ?? 'عميل زيارة',
                          customerPhone: data['client_phone'] ?? '',
                        ),
                      ),
                    );
                  },
                ),
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
                color: const Color(0xFF006FBA).withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.calendar_today_rounded, size: 52, color: Color(0xFF006FBA)),
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
              onPressed: () {
                // الشاشة مسار في الراوتر: pop يرجع للرئيسية إن جئنا منها، وإلا نذهب
                // إليها صراحةً (رابط عميق فتح '/orders' مباشرةً بلا مكدّس تحته).
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/client');
                }
              },
              icon: const Icon(Icons.home_rounded),
              label: Text('العودة للرئيسية', style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF006FBA),
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
              Text('تاريخ الطلب: $dateStr', style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 12)),
            ],
          ),
          // موعد الخدمة المجدول — بارز حتى لا ينساه العميل
          _buildAppointmentBanner(order),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_asDouble(order['amount']).toStringAsFixed(2)} ر.س',
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: const Color(0xFF006FBA))),
              if (status == 'completed')
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => PaymentSummaryScreen(
                      serviceName: order['service_type'] ?? 'خدمة عامة',
                      amount: _asDouble(order['amount']),
                      location: order['location'],
                    )));
                  },
                  icon: const Icon(Icons.replay, size: 16),
                  label: Text('أعد الطلب', style: GoogleFonts.tajawal(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF006FBA)),
                )
              else if (['pending', 'waiting_payment_cod',
                'scheduled', 'accepted'].contains(status))
                // كان الإلغاء متاحاً لـ pending فقط، فالطلبات المدفوعة غير الساعية
                // (كنب/صيانة/اشتراك = pending_admin_approval) لا يستطيع العميل إلغاءها
                // ولا يُطلق استرداد المحفظة الجاهز خادميّاً. نُتيحه قبل انطلاق السائق.
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
              else if (status == 'under_review' ||
                  (status == 'in_progress' && order['driver_id'] == null))
                // خدمة مُدارة إدارياً بلا سائق (تنظيف داخلية السيارة): لا تتبّع —
                // كان زرّ «تتبع السائق» يظهر ويقول «لم يُعيَّن سائق بعد» للأبد.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006FBA).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.verified_outlined,
                        size: 15, color: Color(0xFF006FBA)),
                    const SizedBox(width: 6),
                    Text(
                        status == 'under_review'
                            ? 'تحت المراجعة — تصلك الإشعارات'
                            : 'جاري التنفيذ',
                        style: GoogleFonts.tajawal(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF006FBA))),
                  ]),
                )
              else
                ElevatedButton.icon(
                  onPressed: () {
                    if (order['driver_id'] != null && order['location'] != null) {
                      ZyiarahCoreService.triggerHapticLight();
                      context.push('/track/$docId');
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('لم يُعيَّن سائق بعد، يُرجى الانتظار')),
                      );
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: Text('تتبع السائق', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF006FBA),
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

  /// شارة موعد الخدمة المجدول — تُظهر التاريخ والوقت وعدّاداً نسبياً بوضوح
  /// حتى لا ينسى العميل موعده. تظهر فقط للطلبات ذات موعد محدد (service_date
  /// أو booking_date/booking_time_slot).
  Widget _buildAppointmentBanner(Map<String, dynamic> order) {
    DateTime? appt = (order['service_date'] as Timestamp?)?.toDate();
    if (appt == null && order['booking_date'] is String) {
      try {
        final t = (order['booking_time_slot'] as String?) ?? '00:00';
        appt = DateTime.parse('${order['booking_date']}T${t.length == 5 ? t : '00:00'}:00');
      } catch (_) {}
    }
    if (appt == null) return const SizedBox.shrink();

    const days = ['', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    const months = ['', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final dateStr = '${days[appt.weekday]} ${appt.day} ${months[appt.month]}';

    final period = appt.hour < 12 ? 'صباحاً' : 'مساءً';
    int h12 = appt.hour % 12;
    if (h12 == 0) h12 = 12;
    final timeStr = '$h12:${appt.minute.toString().padLeft(2, '0')} $period';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(appt.year, appt.month, appt.day);
    final diffDays = apptDay.difference(today).inDays;
    String rel;
    Color relColor = const Color(0xFF006FBA);
    if (diffDays < 0) {
      rel = 'انتهى الموعد';
      relColor = Colors.grey;
    } else if (diffDays == 0) {
      rel = 'اليوم';
      relColor = Colors.green.shade700;
    } else if (diffDays == 1) {
      rel = 'غداً';
      relColor = Colors.orange.shade800;
    } else {
      rel = 'بعد $diffDays أيام';
    }

    const purple = Color(0xFF006FBA);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: purple.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available, size: 18, color: purple),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('موعد الخدمة',
                      style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('$dateStr — $timeStr',
                      style: GoogleFonts.tajawal(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: relColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(rel, style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold, color: relColor)),
            ),
          ],
        ),
      ),
    );
  }

}
