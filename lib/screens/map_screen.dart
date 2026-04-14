import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zyiarah/services/order_service.dart';

class ZyiarahMapTracking extends StatefulWidget {
  final String orderId;
  const ZyiarahMapTracking({super.key, required this.orderId});

  @override
  State<ZyiarahMapTracking> createState() => _ZyiarahMapTrackingState();
}

class _ZyiarahMapTrackingState extends State<ZyiarahMapTracking> {
  final ZyiarahOrderService _orderService = ZyiarahOrderService();
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تتبع السائق - زيارة",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF5D1B5E),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _orderService.streamOrderTracking(widget.orderId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return const Center(child: Text('الطلب غير موجود'));
          }

          GeoPoint? clientPos = data['location'] as GeoPoint?;
          GeoPoint? driverPos = data['driver_location'] as GeoPoint?;

          if (clientPos == null) {
            return const Center(child: Text('جاري جلب موقع العميل...'));
          }

          LatLng clientLatLng = LatLng(clientPos.latitude, clientPos.longitude);
          LatLng? driverLatLng = driverPos != null
              ? LatLng(driverPos.latitude, driverPos.longitude)
              : null;

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: driverLatLng ?? clientLatLng,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.zyiarah.zyiarah',
              ),
              // عرض الخط الواصل بين السائق والعميل (Route)
              if (driverLatLng != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [driverLatLng, clientLatLng],
                      color: const Color(0xFF5D1B5E),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              // العلامات (Markers)
              MarkerLayer(
                markers: [
                  // موقع العميل
                  Marker(
                    point: clientLatLng,
                    width: 40,
                    height: 40,
                    child:
                        const Icon(Icons.home_work, color: Colors.green, size: 40),
                  ),
                  // موقع السائق (يتحرك حياً)
                  if (driverLatLng != null)
                    Marker(
                      point: driverLatLng,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.directions_car,
                          color: Color(0xFF5D1B5E), size: 40),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      bottomSheet: _buildTrackingInfoPanel(),
    );
  }

  Widget _buildTrackingInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      height: 150,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("حالة الطلب", style: TextStyle(color: Colors.grey)),
              Text("جاري الوصول",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          const Divider(height: 30),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: const Text("السائق: محمد المالكي"),
            subtitle: const Text("تويوتا هايلوكس - رقم ٤٤٥٢"),
            trailing: IconButton(
              icon: const Icon(Icons.phone, color: Colors.green),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
