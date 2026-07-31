import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

class DriverTasksScreen extends StatefulWidget {
  const DriverTasksScreen({super.key});

  @override
  State<DriverTasksScreen> createState() => _DriverTasksScreenState();
}

class _DriverTasksScreenState extends State<DriverTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String? _driverId = FirebaseAuth.instance.currentUser?.uid;

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: Text('مهامي',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF660033),
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'النشطة'),
              Tab(text: 'السجل'),
            ],
            indicatorColor: Colors.white,
            labelStyle:
                GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 14),
            unselectedLabelStyle: GoogleFonts.tajawal(fontSize: 14),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTasksList(active: true),
            _buildTasksList(active: false),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList({required bool active}) {
    if (_driverId == null) {
      return const Center(child: Text('يرجى تسجيل الدخول'));
    }

    // التوجيه المباشر يستخدم scheduled→on_the_way→in_progress (+accepted القديمة).
    // 'assigned' ليست من مسار التوجيه لكنّ الأدمن يكتبها يدوياً من شاشة تفاصيل
    // الطلب — كانت مستثناة هنا فيختفي الطلب من «النشطة» بينما يظهر على اللوحة.
    final activeStatuses = ['assigned', 'scheduled', 'accepted', 'on_the_way', 'in_progress'];
    final historyStatuses = ['completed', 'cancelled'];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('driver_id', isEqualTo: _driverId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF660033)));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text('خطأ في التحميل',
                  style: GoogleFonts.tajawal(color: Colors.red)));
        }

        final all = snapshot.data?.docs ?? [];
        final filtered = all.where((doc) {
          final status =
              (doc.data() as Map<String, dynamic>)['status'] as String? ??
                  'pending';
          return active
              ? activeStatuses.contains(status)
              : historyStatuses.contains(status);
        }).toList();

        filtered.sort((a, b) {
          final aTime =
              (a.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          final bTime =
              (b.data() as Map<String, dynamic>)['created_at'] as Timestamp?;
          return (bTime ?? Timestamp.now())
              .compareTo(aTime ?? Timestamp.now());
        });

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? Icons.work_outline : Icons.history,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  active ? 'لا توجد مهام نشطة حالياً' : 'لا يوجد سجل مهام بعد',
                  style: GoogleFonts.tajawal(color: Colors.grey, fontSize: 15),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final data = filtered[i].data() as Map<String, dynamic>;
            return _buildTaskCard(data);
          },
        );
      },
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'pending';
    final serviceName =
        data['service_type'] ?? data['service_name'] ?? 'خدمة زيارة';
    final clientName = data['client_name'] ?? 'عميل';
    final code = data['code'] ?? '-';
    final createdAt =
        (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('yyyy/MM/dd').format(createdAt);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'completed':
        statusColor = Colors.green;
        statusLabel = 'مكتملة';
        statusIcon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        statusColor = Colors.red;
        statusLabel = 'ملغاة';
        statusIcon = Icons.cancel_outlined;
        break;
      case 'in_progress':
        statusColor = Colors.blue;
        statusLabel = 'قيد التنفيذ';
        statusIcon = Icons.timer_outlined;
        break;
      case 'scheduled':
        statusColor = const Color(0xFF660033);
        statusLabel = 'مجدولة';
        statusIcon = Icons.event_available_outlined;
        break;
      case 'assigned':
        // إسناد يدوي من الأدمن — بانتظار الجدولة (لا يستطيع السائق تقديمها بنفسه)
        statusColor = Colors.orange;
        statusLabel = 'مُسنَدة — بانتظار الجدولة';
        statusIcon = Icons.assignment_ind_outlined;
        break;
      case 'on_the_way':
      case 'accepted':
        statusColor = Colors.orange;
        statusLabel = status == 'on_the_way' ? 'في الطريق' : 'مقبولة';
        statusIcon = Icons.directions_car_outlined;
        break;
      default:
        statusColor = const Color(0xFF660033);
        statusLabel = 'معلقة';
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(serviceName,
                    style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(clientName,
                    style: GoogleFonts.tajawal(
                        color: Colors.grey[600], fontSize: 12)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 11, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(dateStr,
                        style: GoogleFonts.tajawal(
                            color: Colors.grey[400], fontSize: 11)),
                    const SizedBox(width: 10),
                    Icon(Icons.tag, size: 11, color: Colors.grey[400]),
                    Text(code,
                        style: GoogleFonts.tajawal(
                            color: Colors.grey[400], fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel,
                style: GoogleFonts.tajawal(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
