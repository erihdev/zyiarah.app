import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _mapReady = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تتبع السائق',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF5D1B5E),
          foregroundColor: Colors.white,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _orderService.streamOrderTracking(widget.orderId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text("تعذّر تحميل بيانات التتبع", style: TextStyle(color: Colors.grey)));
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF5D1B5E)));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final GeoPoint? clientPos = data['location'] as GeoPoint?;
            final GeoPoint? driverPos = data['driver_location'] as GeoPoint?;

            if (clientPos == null) {
              return Center(
                child: Text('موقع العميل غير محدد بعد',
                    style: GoogleFonts.tajawal(color: Colors.grey)),
              );
            }

            final clientLatLng = LatLng(clientPos.latitude, clientPos.longitude);
            final driverLatLng = driverPos != null
                ? LatLng(driverPos.latitude, driverPos.longitude)
                : null;

            // Auto-center on driver when first available
            if (driverLatLng != null && !_mapReady) {
              _mapReady = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _mapController.move(driverLatLng, 14.0);
              });
            }

            return Stack(
              children: [
                FlutterMap(
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
                    if (driverLatLng != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [driverLatLng, clientLatLng],
                            color: const Color(0xFF5D1B5E),
                            strokeWidth: 3.0,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: clientLatLng,
                          width: 44,
                          height: 44,
                          child: const _MapMarker(
                            icon: Icons.home_work_rounded,
                            color: Colors.green,
                          ),
                        ),
                        if (driverLatLng != null)
                          Marker(
                            point: driverLatLng,
                            width: 44,
                            height: 44,
                            child: const _MapMarker(
                              icon: Icons.directions_car_rounded,
                              color: Color(0xFF5D1B5E),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                // Legend
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildLegend(driverLatLng != null),
                ),
                // Center-on-driver FAB
                if (driverLatLng != null)
                  Positioned(
                    bottom: 170,
                    left: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'center_driver',
                      backgroundColor: const Color(0xFF5D1B5E),
                      onPressed: () => _mapController.move(driverLatLng, 15.0),
                      child: const Icon(Icons.my_location, color: Colors.white, size: 18),
                    ),
                  ),
              ],
            );
          },
        ),
        bottomSheet: _buildInfoPanel(),
      ),
    );
  }

  Widget _buildLegend(bool hasDriver) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendRow(Icons.home_work_rounded, Colors.green, 'موقع العميل'),
          if (hasDriver) ...[
            const SizedBox(height: 4),
            _legendRow(Icons.directions_car_rounded, const Color(0xFF5D1B5E), 'السائق (حي)'),
          ],
        ],
      ),
    );
  }

  Widget _legendRow(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.tajawal(fontSize: 11, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildInfoPanel() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _orderService.streamOrderTracking(widget.orderId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};

        final driverName = data['assigned_driver'] as String? ?? 'جاري التعيين...';
        final driverPhone = data['driver_phone'] as String? ?? '';
        final status = data['status'] as String? ?? 'pending';
        final clientName = data['client_name'] as String? ?? '';
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final driverPos = data['driver_location'] as GeoPoint?;
        final clientPos = data['location'] as GeoPoint?;

        String distanceText = '';
        if (driverPos != null && clientPos != null) {
          final dist = _calcDistanceKm(driverPos, clientPos);
          distanceText = dist < 1
              ? '${(dist * 1000).toStringAsFixed(0)} م'
              : '${dist.toStringAsFixed(1)} كم';
        }

        final statusLabels = {
          'accepted': 'السائق في الطريق',
          'in_progress': 'جاري تنفيذ الخدمة',
          'completed': 'اكتملت الخدمة',
          'assigned': 'تم التعيين',
          'cancelled': 'ملغي',
        };
        final statusLabel = statusLabels[status] ?? status;
        final statusColor = status == 'completed'
            ? Colors.green
            : status == 'cancelled'
                ? Colors.red
                : status == 'in_progress'
                    ? Colors.blue
                    : const Color(0xFF5D1B5E);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -3))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName,
                            style: GoogleFonts.tajawal(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        if (clientName.isNotEmpty)
                          Text(clientName,
                              style: GoogleFonts.tajawal(
                                  color: Colors.grey[500], fontSize: 11)),
                      ],
                    ),
                  ),
                  if (distanceText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5D1B5E).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.straighten, size: 12, color: Color(0xFF5D1B5E)),
                          const SizedBox(width: 4),
                          Text(distanceText,
                              style: GoogleFonts.tajawal(
                                  fontSize: 12,
                                  color: const Color(0xFF5D1B5E),
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (driverPhone.isNotEmpty)
                    IconButton(
                      onPressed: () => launchUrl(Uri.parse('tel:$driverPhone')),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.phone_rounded, color: Colors.green, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(statusLabel,
                        style: GoogleFonts.tajawal(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  if (amount > 0)
                    Text('${amount.toStringAsFixed(0)} ر.س',
                        style: GoogleFonts.tajawal(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: const Color(0xFF1E293B))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  double _calcDistanceKm(GeoPoint a, GeoPoint b) {
    const R = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final hav = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(hav), math.sqrt(1 - hav));
  }
}

class _MapMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapMarker({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}
