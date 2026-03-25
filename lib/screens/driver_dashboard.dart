import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:zyiarah/services/order_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final ZyiarahCoreService _coreService = ZyiarahCoreService();
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isOnline = true;
  String? _currentDriverId;

  @override
  void initState() {
    super.initState();
    _currentDriverId = _auth.currentUser?.uid;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDriverId == null) {
      return const Scaffold(body: Center(child: Text("يرجى تسجيل الدخول")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsRow(),
                    const SizedBox(height: 25),
                    _buildMainSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF5D1B5E),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(right: 20, bottom: 16),
        title: Text(
          "لوحة التحكم",
          style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5D1B5E), Color(0xFF7E3080)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Row(
            children: [
              Text(_isOnline ? "متصل" : "أوفلاين", 
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Switch(
                value: _isOnline,
                onChanged: (val) async {
                  setState(() => _isOnline = val);
                  if (_currentDriverId != null) {
                    await FirebaseFirestore.instance.collection('drivers').doc(_currentDriverId).update({
                      'is_available': val,
                      'status': val ? 'idle' : 'off',
                    });
                  }
                },
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.grey[400],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildCompactStat("مهام اليوم", "0", Icons.today, Colors.blue),
        const SizedBox(width: 12),
        _buildCompactStat("إجمالي المهام", "14", Icons.assignment_turned_in, Colors.orange),
        const SizedBox(width: 12),
        _buildCompactStat("التقييم", "4.8", Icons.star, Colors.amber),
      ],
    );
  }

  Widget _buildCompactStat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: GoogleFonts.tajawal(fontWeight: FontWeight.w900, fontSize: 18)),
            Text(label, style: GoogleFonts.tajawal(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildMainSection() {
    if (!_isOnline) {
      return _buildStatusPlaceholder(
        Icons.cloud_off, 
        "أنت حالياً غير متصل", 
        "قم بتغيير حالتك للأعلى لبدء استقبال الطلبات"
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _orderService.streamDriverActiveOrders(_currentDriverId!),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final orderDoc = snapshot.data!.docs.first;
          return _buildActivePipeline(orderDoc);
        }

        return _buildAvailableTasksSection();
      },
    );
  }

  Widget _buildActivePipeline(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'];
    final orderId = doc.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flash_on, color: Colors.orange, size: 20),
            const SizedBox(width: 8),
            Text("المهمة الحالية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF5D1B5E))),
          ],
        ),
        const SizedBox(height: 15),
        _buildStateGuidedCard(orderId, data, status),
      ],
    );
  }

  Widget _buildStateGuidedCard(String id, Map<String, dynamic> data, String status) {
    String stateTitle = "";
    String actionLabel = "";
    String nextStatus = "";
    Color stateColor = const Color(0xFF5D1B5E);
    IconData stateIcon = Icons.directions_car;

    switch (status) {
      case 'accepted':
        stateTitle = "في الطريق للعميل";
        actionLabel = "لقد وصلت للموقع";
        nextStatus = "arrived";
        stateColor = Colors.blue;
        stateIcon = Icons.map;
        break;
      case 'arrived':
        stateTitle = "وصلت للموقع";
        actionLabel = "بدء الخدمة الآن";
        nextStatus = "in_progress";
        stateColor = Colors.orange;
        stateIcon = Icons.location_on;
        break;
      case 'in_progress':
        stateTitle = "الخدمة قيد التنفيذ";
        actionLabel = "إتمام المهمة";
        nextStatus = "completed";
        stateColor = Colors.green;
        stateIcon = Icons.timer;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: stateColor.withOpacity(0.1), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: stateColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(stateIcon, color: stateColor),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stateTitle, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: stateColor)),
                    Text("عميل: ${data['client_name'] ?? 'بدون اسم'}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (status == 'accepted' || status == 'arrived') 
                      _buildDistanceInfo(data['location']),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _openMaps(data['location']),
                icon: const Icon(Icons.directions, color: Colors.blue),
                tooltip: "فتح الخريطة",
              ),
            ],
          ),
          const Divider(height: 30),
          if (status == 'in_progress') _buildTimer(data['hours_contracted'] ?? 4),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () => _updateStatus(id, nextStatus),
              style: ElevatedButton.styleFrom(
                backgroundColor: stateColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(actionLabel, style: GoogleFonts.tajawal(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _callClient(data['client_phone'] ?? '05xxxx'), 
                icon: const Icon(Icons.phone, size: 16),
                label: const Text("اتصال بالعميل"),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              ),
              const SizedBox(width: 15),
              TextButton.icon(
                onPressed: () => _reportIssue(id), 
                icon: const Icon(Icons.support_agent, size: 16, color: Colors.redAccent),
                label: const Text("بلاغ للإدارة", style: TextStyle(color: Colors.redAccent)),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo(GeoPoint clientLoc) {
    return StreamBuilder<Position>(
      stream: Geolocator.getPositionStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        double dist = _coreService.getDistanceInMeters(
          snapshot.data!.latitude, snapshot.data!.longitude,
          clientLoc.latitude, clientLoc.longitude
        );
        String formatted = _coreService.getFormattedDistance(dist);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("على بعد: $formatted", style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildMiniMap(snapshot.data!, clientLoc),
          ],
        );
      },
    );
  }

  Widget _buildMiniMap(Position driverPos, GeoPoint clientLoc) {
    final driverLatLng = LatLng(driverPos.latitude, driverPos.longitude);
    final clientLatLng = LatLng(clientLoc.latitude, clientLoc.longitude);

    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: driverLatLng,
            initialZoom: 13.0,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.zyiarah.app',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: driverLatLng,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.directions_car, color: Colors.blue, size: 30),
                ),
                Marker(
                  point: clientLatLng,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("الطلبات المتاحة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 15),
        StreamBuilder<QuerySnapshot>(
          stream: _orderService.streamAvailableOrders(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildStatusPlaceholder(Icons.search, "لا توجد طلبات حالياً", "بانتظار وصول طلبات جديدة من العملاء");
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final doc = snapshot.data!.docs[index];
                final data = doc.data() as Map<String, dynamic>;
                return _buildNewTaskCard(doc.id, data);
              }
            );
          },
        ),
      ],
    );
  }

  Widget _buildNewTaskCard(String id, Map<String, dynamic> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: const Color(0xFF5D1B5E).withOpacity(0.1), child: const Icon(Icons.local_offer, color: Color(0xFF5D1B5E), size: 20)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['service_type'] ?? "خدمة تنظيف", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
                Text("${data['hours_contracted'] ?? 4} ساعات", style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _acceptOrder(id),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5D1B5E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("قبول", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPlaceholder(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(
          children: [
            Icon(icon, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, color: Colors.grey[600])),
            Text(subtitle, style: GoogleFonts.tajawal(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _buildTimer(int hours) {
    return Column(
      children: [
        const Text("وقت بدء المهمة", style: TextStyle(fontSize: 10, color: Colors.grey)),
        StreamBuilder<Duration>(
          stream: _coreService.taskTimerStream(hours),
          builder: (context, snapshot) {
            String time = "--:--:--";
            Color timerColor = const Color(0xFF5D1B5E);
            if (snapshot.hasData) {
              final d = snapshot.data!;
              time = "${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
              // تنبيه إذا تبقى أقل من 15 دقيقة
              if (d.inMinutes < 15) {
                timerColor = Colors.redAccent;
              }
            }
            return Text(time, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: timerColor));
          },
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  void _reportIssue(String orderId) async {
    final message = "بلاغ عن الطلب #$orderId: لدي مشكلة في هذا الطلب السائق: $_currentDriverId";
    final url = "https://wa.me/966XXXXXXXXX?text=${Uri.encodeComponent(message)}"; // ارجو استبدال XXXXXXXXX برقم الإدارة
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
  void _acceptOrder(String id) async {
    bool success = await _orderService.acceptOrder(id, _currentDriverId!);
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لديك طلب نشط بالفعل! قم بإنهائه أولاً.")));
      }
    }
  }

  void _updateStatus(String id, String status) async {
    await _orderService.updateOrderStatus(id, status);
  }

  void _openMaps(GeoPoint loc) async {
    final url = 'https://www.google.com/maps/search/?api=1&query=${loc.latitude},${loc.longitude}';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  void _callClient(String phone) async {
    final url = 'tel:$phone';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}
