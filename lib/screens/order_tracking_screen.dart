import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:zyiarah/services/zyiarah_core_services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'package:zyiarah/services/order_service.dart';
import 'package:zyiarah/widgets/rating_dialog.dart';


class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  final ZyiarahCoreService _coreService = ZyiarahCoreService();
  final MapController _mapController = MapController();
  bool _ratingPromptShown = false;

  final List<Map<String, dynamic>> _steps = [
    {'status': 'accepted', 'label': 'السائق في الطريق', 'icon': Icons.directions_car},
    {'status': 'arrived', 'label': 'وصل السائق للموقع', 'icon': Icons.location_on},
    {'status': 'in_progress', 'label': 'بدء الخدمة', 'icon': Icons.cleaning_services},
    {'status': 'completed', 'label': 'تمت المهمة بنجاح', 'icon': Icons.verified},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text("تتبع طلبك", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text("الطلب غير موجود"));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final status = data['status'] ?? 'pending';
            final clientLoc = data['location'] as GeoPoint?;
            final driverLoc = data['driver_location'] as GeoPoint?;

            // Trigger Rating Prompt if completed and not yet rated
            if (status == 'completed' && data['rating'] == null && !_ratingPromptShown && mounted) {
              _ratingPromptShown = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => ZyiarahRatingDialog(
                    onSubmitted: (rating, comment, {reason, evidence}) {
                      _orderService.submitOrderRating(
                        widget.orderId, 
                        rating, 
                        comment,
                        reason: reason,
                        evidence: evidence,
                      );
                    },
                  ),
                );
              });
            }

            return Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildLiveMap(clientLoc, driverLoc),
                ),
                Expanded(
                  flex: 4,
                  child: _buildDetailsPanel(data, status, driverLoc, clientLoc),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveMap(GeoPoint? clientLoc, GeoPoint? driverLoc) {
    if (clientLoc == null) return const Center(child: Text("موقع العميل غير متوفر"));

    final clientLatLng = LatLng(clientLoc.latitude, clientLoc.longitude);
    final driverLatLng = driverLoc != null ? LatLng(driverLoc.latitude, driverLoc.longitude) : null;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: driverLatLng ?? clientLatLng,
        initialZoom: 14.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.zyiarah.zyiarah',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: clientLatLng,
              width: 40,
              height: 40,
              child: const Icon(Icons.home, color: Color(0xFF1E293B), size: 35),
            ),
            if (driverLatLng != null)
              Marker(
                point: driverLatLng,
                width: 50,
                height: 50,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                      child: const Icon(Icons.directions_car, color: Colors.white, size: 20),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.blue, size: 15),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailsPanel(Map<String, dynamic> data, String status, GeoPoint? driverLoc, GeoPoint? clientLoc) {
    String distanceInfo = "جاري حساب المسافة...";
    if (driverLoc != null && clientLoc != null) {
      double dist = _coreService.getDistanceInMeters(driverLoc.latitude, driverLoc.longitude, clientLoc.latitude, clientLoc.longitude);
      distanceInfo = "يبعد عنك: ${_coreService.getFormattedDistance(dist)}";
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))],
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("حالة الطلب الحالية", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF1E293B))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(distanceInfo, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          _buildStaleStatus(data['last_location_update']),
                        ],
                      ),
                    ],
                  ),
                  if (status == 'in_progress')
                    Lottie.network(
                      'https://lottie.host/6429f55e-a61d-4519-94b2-0545cf026131/V088G0M8hS.json',
                      width: 50,
                      height: 50,
                    ),
                  IconButton(onPressed: () => _callDriver(data['driver_phone'] ?? '05xxxx'), icon: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.phone, color: Colors.white, size: 20))),
                ],
          ),
          const SizedBox(height: 25),
          _buildStepper(status),
          const Divider(height: 40),
          _buildDriverInfo(data),
          const SizedBox(height: 20),
          _buildServiceSummary(data),
        ],
      ),
    );
  }

  Widget _buildStepper(String currentStatus) {
    // Map Firestore status to our UI steps
    Map<String, int> stepMapping = {
      'accepted': 0,
      'arrived': 1,
      'in_progress': 2,
      'completed': 3,
    };
    int uiIndex = stepMapping[currentStatus] ?? -1;

    return Column(
      children: List.generate(_steps.length, (index) {
        final step = _steps[index];
        final isActive = index <= uiIndex;
        final isLast = index == _steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(color: isActive ? Colors.green : Colors.grey.shade300, shape: BoxShape.circle),
                  child: Icon(isActive ? Icons.check : step['icon'], color: Colors.white, size: 14),
                ),
                if (!isLast) Container(width: 2, height: 35, color: index < uiIndex ? Colors.green : Colors.grey.shade200),
              ],
            ),
            const SizedBox(width: 15),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                step['label'],
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? const Color(0xFF1E293B) : Colors.grey,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildDriverInfo(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
      child: Row(
        children: [
          const CircleAvatar(radius: 25, backgroundColor: Colors.amber, child: Icon(Icons.person, color: Colors.white, size: 30)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("الكادر المعين", style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(data['assigned_driver'] ?? "جاري تعيين سائق", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          Column(
            children: [
              const Icon(Icons.star, color: Colors.amber, size: 18),
              Text(
                (data['driver_rating_avg'] ?? 5.0).toStringAsFixed(1),
                style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceSummary(Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("ملخص الخدمة", style: GoogleFonts.tajawal(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("نوع الخدمة", style: TextStyle(color: Colors.grey)),
            Text(data['service_type'] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("المبلغ", style: TextStyle(color: Colors.grey)),
            Text("${data['amount'] ?? 0} ر.س", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          ],
        ),
      ],
    );
  }

  Widget _buildStaleStatus(dynamic timestamp) {
    if (timestamp == null) return const SizedBox();
    
    DateTime lastUpdate;
    if (timestamp is Timestamp) {
      lastUpdate = timestamp.toDate();
    } else {
      return const SizedBox();
    }

    final diff = DateTime.now().difference(lastUpdate).inMinutes;
    if (diff >= 5) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade200)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 10, color: Colors.orange),
            SizedBox(width: 4),
            Text("اتصال ضعيف", style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  void _callDriver(String phone) async {
    final url = 'tel:$phone';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}
