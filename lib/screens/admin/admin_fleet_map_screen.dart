import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:zyiarah/models/fleet_vehicle.dart';
import 'package:zyiarah/screens/admin/admin_order_details_screen.dart';
import 'package:zyiarah/theme/app_theme.dart';
import 'package:zyiarah/utils/status_util.dart';

/// رادار الأسطول المباشر (تصميم Stitch `_21` «رادار الأسطول في المرتفعات»):
/// كل سائق في مهمة الآن على خريطة واحدة، بعلامة تحمل حروفه ولونَ حالته،
/// وتحتها قائمة السائقين بمهمّة كلٍّ وعمر آخر تحديث لموقعه.
///
/// المصدر: الطلبات بحالة نشطة (`accepted / on_the_way / in_progress`) التي
/// يكتب فيها تطبيق السائق `driver_location` + `last_location_update` —
/// تدفّق حيّ، `whereIn` على `status` وحده فلا فهرس مركّب جديد. السائقون
/// بلا مناطق (قرار المالك) فالرادار للنشاط كلّه لا لمنطقة.
class AdminFleetMapScreen extends StatefulWidget {
  /// للاختبارات: تدفّق محقون بدل Firestore، وساعة ثابتة، وطبقة بلاطات بديلة
  /// (لا شبكة في الاختبار)، ومستقبِل «تفاصيل الطلب».
  final Stream<List<FleetVehicle>>? vehicles;
  final DateTime Function()? clock;
  final Widget? tileLayer;
  final void Function(BuildContext context, FleetVehicle vehicle)? openOrder;

  const AdminFleetMapScreen({
    super.key,
    this.vehicles,
    this.clock,
    this.tileLayer,
    this.openOrder,
  });

  @override
  State<AdminFleetMapScreen> createState() => _AdminFleetMapScreenState();
}

class _AdminFleetMapScreenState extends State<AdminFleetMapScreen> {
  /// مركز جازان — نقطة البدء قبل وصول أول موقع.
  static const LatLng _fallbackCenter = LatLng(16.8892, 42.5511);

  final MapController _map = MapController();
  late Stream<List<FleetVehicle>> _stream;
  Timer? _ticker;
  String? _selectedDriverId;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _stream = widget.vehicles ?? _firestoreStream();
    // عمر آخر تحديث («قبل ٣ د») يتقدّم وحده كل نصف دقيقة دون انتظار حدث.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _map.dispose();
    super.dispose();
  }

  static Stream<List<FleetVehicle>> _firestoreStream() {
    return FirebaseFirestore.instance
        .collection('orders')
        // whereIn على status وحده — بلا orderBy فلا فهرس مركّب جديد.
        .where('status', whereIn: FleetVehicle.activeStatuses)
        .snapshots()
        .map((snap) => FleetVehicle.latestPerDriver(snap.docs
            .map((d) => FleetVehicle.fromOrder(d.id, d.data()))
            .whereType<FleetVehicle>()));
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  void _fitAll(List<FleetVehicle> list) {
    if (list.isEmpty) return;
    final pts = list.map((v) => LatLng(v.lat, v.lng)).toList();
    if (pts.length == 1) {
      _map.move(pts.first, 14);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(56),
      maxZoom: 15,
    ));
  }

  void _focus(FleetVehicle v) {
    setState(() => _selectedDriverId = v.driverId);
    _map.move(LatLng(v.lat, v.lng), 15);
  }

  void _openOrder(FleetVehicle v) {
    if (widget.openOrder != null) {
      widget.openOrder!(context, v);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminOrderDetailsScreen(orderId: v.orderId),
      ),
    );
  }

  Color _color(FleetVehicle v, DateTime now) {
    if (v.isStale(now)) return const Color(0xFF94A3B8);
    return ZyiarahStatus.getOrderStatus(v.status)['color'] as Color;
  }

  String _statusLabel(FleetVehicle v, DateTime now) {
    if (v.isStale(now)) return 'بلا تحديث حديث';
    return ZyiarahStatus.getOrderStatus(v.status)['text'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: ZyiarahTheme.surface,
        appBar: AppBar(
          backgroundColor: ZyiarahTheme.brand,
          foregroundColor: Colors.white,
          title: Text('رادار الأسطول المباشر',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w800)),
        ),
        body: StreamBuilder<List<FleetVehicle>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) return _errorView();
            if (!snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: ZyiarahTheme.brand));
            }
            final list = snap.data!;
            final now = _now;
            if (list.isNotEmpty && !_fitted) {
              _fitted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitAll(list);
              });
            }
            FleetVehicle? selected;
            for (final v in list) {
              if (v.driverId == _selectedDriverId) selected = v;
            }
            return Column(
              children: [
                _summaryBar(FleetVehicle.summarize(list, now)),
                Expanded(
                  flex: 5,
                  child: Stack(
                    children: [
                      _mapView(list, now),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _roundButton(
                          icon: Icons.fit_screen_rounded,
                          tooltip: 'إظهار الكل',
                          onTap: () => _fitAll(list),
                        ),
                      ),
                      if (selected != null)
                        Positioned(
                          right: 10,
                          left: 10,
                          bottom: 10,
                          child: _selectedCard(selected, now),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: list.isEmpty ? _emptyList() : _vehicleList(list, now),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _mapView(List<FleetVehicle> list, DateTime now) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _fallbackCenter,
        initialZoom: 9,
        onTap: (_, __) => setState(() => _selectedDriverId = null),
      ),
      children: [
        widget.tileLayer ??
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.zyiarah.zyiarah',
            ),
        MarkerLayer(
          markers: [
            for (final v in list)
              Marker(
                point: LatLng(v.lat, v.lng),
                width: 48,
                height: 48,
                child: GestureDetector(
                  onTap: () => _focus(v),
                  child: _VehicleMarker(
                    initials: v.initials,
                    color: _color(v, now),
                    selected: v.driverId == _selectedDriverId,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _summaryBar(FleetSummary s) {
    final caption = s.total == 0
        ? 'لا سائق في مهمة الآن'
        : '${s.total} في مهمة الآن • ${s.working} قيد التنفيذ • '
            '${s.moving} في الطريق'
            '${s.stale > 0 ? ' • ${s.stale} بلا تحديث حديث' : ''}';
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: ZyiarahTheme.brand, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(caption,
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w700, color: ZyiarahTheme.ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('تحديث حيّ',
                style: GoogleFonts.tajawal(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF166534))),
          ),
        ],
      ),
    );
  }

  Widget _vehicleList(List<FleetVehicle> list, DateTime now) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final v = list[i];
        final color = _color(v, now);
        final stale = v.isStale(now);
        final selected = v.driverId == _selectedDriverId;
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _focus(v),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? ZyiarahTheme.brand : const Color(0xFFE2E8F0),
                    width: selected ? 1.6 : 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: color,
                    child: Text(v.initials,
                        style: GoogleFonts.tajawal(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(v.driverName,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.tajawal(
                                      fontWeight: FontWeight.w800,
                                      color: ZyiarahTheme.ink)),
                            ),
                            _chip(_statusLabel(v, now), color),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(v.taskLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(
                                fontSize: 12, color: ZyiarahTheme.inkMuted)),
                        const SizedBox(height: 2),
                        Text('العميل: ${v.clientName} • آخر تحديث: ${v.ageLabel(now)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.tajawal(
                                fontSize: 12,
                                color: stale
                                    ? ZyiarahTheme.error
                                    : ZyiarahTheme.inkMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'تفاصيل الطلب',
                    icon: const Icon(Icons.open_in_new_rounded,
                        color: ZyiarahTheme.brand),
                    onPressed: () => _openOrder(v),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _selectedCard(FleetVehicle v, DateTime now) {
    final color = _color(v, now);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color,
              child: Text(v.initials,
                  style: GoogleFonts.tajawal(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${v.driverName} — ${_statusLabel(v, now)}',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(
                          fontWeight: FontWeight.w800, color: ZyiarahTheme.ink)),
                  Text('${v.taskLine} • ${v.ageLabel(now)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tajawal(
                          fontSize: 12, color: ZyiarahTheme.inkMuted)),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => _openOrder(v),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text('تفاصيل الطلب',
                  style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: ZyiarahTheme.brand),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyList() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined,
                size: 40, color: ZyiarahTheme.inkFaint),
            const SizedBox(height: 8),
            Text('لا سائق في مهمة الآن',
                style: GoogleFonts.tajawal(
                    fontWeight: FontWeight.w800, color: ZyiarahTheme.ink)),
            const SizedBox(height: 4),
            Text(
              'تظهر المركبات هنا فور انطلاق سائق إلى طلب (في الطريق / قيد التنفيذ).',
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  fontSize: 12, color: ZyiarahTheme.inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 40, color: ZyiarahTheme.error),
          const SizedBox(height: 8),
          Text('تعذّر تحميل الأسطول — تحقّق من الاتصال',
              style: GoogleFonts.tajawal(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _fitted = false;
              _stream = widget.vehicles ?? _firestoreStream();
            }),
            icon: const Icon(Icons.refresh_rounded),
            label: Text('إعادة المحاولة', style: GoogleFonts.tajawal()),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: GoogleFonts.tajawal(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _roundButton(
      {required IconData icon,
      required String tooltip,
      required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: ZyiarahTheme.brand),
        onPressed: onTap,
      ),
    );
  }
}

class _VehicleMarker extends StatelessWidget {
  final String initials;
  final Color color;
  final bool selected;
  const _VehicleMarker(
      {required this.initials, required this.color, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            color: selected ? ZyiarahTheme.accent : Colors.white,
            width: selected ? 3 : 2),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(initials,
          style: GoogleFonts.tajawal(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}
