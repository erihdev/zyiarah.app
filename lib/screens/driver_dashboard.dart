import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zyiarah/screens/profile_screen.dart';

/// لوحة تحكم السائق - تطبيق زيارة
class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final ZyiarahCoreService _coreService = ZyiarahCoreService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();

  // نفترض أن هذا هو ID السائق الحالي (يمكن جلبه من FirebaseAuth)
  // final String _currentDriverId = "driver_123";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("لوحة التحكم",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsHeader(),
              const SizedBox(height: 25),
              const Text(
                "المهمة الحالية",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A)),
              ),
              const SizedBox(height: 15),
              _buildActiveOrderStream(),
              const SizedBox(height: 25),
              const Text(
                "الإجراءات السريعة",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              _buildQuickActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveOrderStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: _orderService
          .streamAvailableOrders(), // Changed to use the available stream method
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildNoTaskPlaceholder();
        }

        var orderDoc = snapshot.data!.docs.first;
        var orderData = orderDoc.data() as Map<String, dynamic>;

        return _buildActiveTaskCard(orderDoc.id, orderData);
      },
    );
  }

  // ملخص الإحصائيات (الطلبات، الأرباح)
  Widget _buildStatsHeader() {
    return Row(
      children: [
        _buildStatCard(
            "طلبات اليوم", "1", Icons.assignment_turned_in, Colors.blue),
        const SizedBox(width: 15),
        _buildStatCard(
            "الأرباح (ر.س)", "150", Icons.account_balance_wallet, Colors.green),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Future<void> _checkGeofenceAndStartOrder(
      String orderId, GeoPoint clientLocation) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء تفعيل خدمات الموقع')));
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('صلاحيات الموقع مرفوضة')));
        }
        return;
      }
    }

    final Position position = await Geolocator.getCurrentPosition();

    // التحقق من الجيوفنسينج (نطاق 100 متر)
    bool isAuthorized = _coreService.isDriverOnSite(position.latitude,
        position.longitude, clientLocation.latitude, clientLocation.longitude);

    if (isAuthorized) {
      await _orderService.updateOrderStatus(orderId, 'in_progress');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم بدء المهمة وتفعيل قفل الوقت!'),
              backgroundColor: Colors.green),
        );
      }
    } else {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الموقع غير مسموح', textAlign: TextAlign.right),
            content: const Text(
                'أنت لست في نطاق العميل (100 متر). يرجى التوجه لموقع العميل لبدء المهمة وتفعيل العقد.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'))
            ],
          ),
        );
      }
    }
  }

  // بطاقة المهمة النشطة مع عداد قفل الوقت
  Widget _buildActiveTaskCard(String orderId, Map<String, dynamic> data) {
    String status = data['status'];
    String clientName = data['client_name'] ?? 'عميل غير معروف';
    int contractHours = data['duration_hours'] ?? 4;
    GeoPoint clientLocation = data['location'];

    // الترجمة للعربية
    String statusAr = "معلّق";
    if (status == 'accepted' || status == 'arrived') statusAr = "بانتظار البدء";
    if (status == 'in_progress') statusAr = "قيد التنفيذ";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: status == 'in_progress'
              ? [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)] // أزرق عند التنفيذ
              : [
                  Colors.orange.shade800,
                  Colors.orange.shade400
                ], // برتقالي قبل البدء
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("رقم العقد: #${orderId.substring(0, 6).toUpperCase()}",
                  style: const TextStyle(color: Colors.white70)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(statusAr,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 20),
          if (status == 'in_progress') ...[
            const Text("الوقت المتبقي لفتح القفل",
                style: TextStyle(color: Colors.white, fontSize: 14)),
            StreamBuilder<Duration>(
              stream: _coreService.taskTimerStream(contractHours),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Text("--:--:--");
                final duration = snapshot.data!;
                String twoDigits(int n) => n.toString().padLeft(2, "0");
                return Text(
                  "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}",
                  style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                );
              },
            ),
          ] else ...[
            const Icon(Icons.location_on, color: Colors.white, size: 50),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () =>
                  _checkGeofenceAndStartOrder(orderId, clientLocation),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange.shade800,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text("تأكيد الوصول وبدء المهمة (Geofence)"),
            )
          ],
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Color(0xFF1E3A8A))),
            title: Text(clientName,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text("خدمة: ${data['service_type']}",
                style: const TextStyle(color: Colors.white70)),
            trailing: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.map, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTaskPlaceholder() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: const Column(
        children: [
          Icon(Icons.search, size: 50, color: Colors.grey),
          SizedBox(height: 10),
          Text("لا توجد مهام نشطة حالياً", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        _buildActionItem(Icons.history, "السجلات", () {}),
        _buildActionItem(Icons.support_agent, "الدعم", () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const ZyiarahProfileScreen()));
        }),
        _buildActionItem(Icons.person, "الملف الشخصي", () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const ZyiarahProfileScreen()));
        }),
      ],
    );
  }

  Widget _buildActionItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF1E3A8A)),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
