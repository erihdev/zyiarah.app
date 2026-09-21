import 'package:cloud_firestore/cloud_firestore.dart';

/// سائق في مهمة الآن — يُشتقّ من مستند طلب نشط يحمل `driver_location`
/// (يكتبه تطبيق السائق أثناء «في الطريق / قيد التنفيذ» مع `last_location_update`).
///
/// نقيّ بلا Flutter ليُختبر مباشرة؛ الشاشة ترسم منه العلامات والقائمة.
class FleetVehicle {
  final String orderId;
  final String orderCode;
  final String driverId;
  final String driverName;
  final String clientName;
  final String serviceName;
  final String zoneName;
  final String status;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  const FleetVehicle({
    required this.orderId,
    required this.orderCode,
    required this.driverId,
    required this.driverName,
    required this.clientName,
    required this.serviceName,
    required this.zoneName,
    required this.status,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  /// الحالات التي يبثّ فيها تطبيق السائق موقعه (driver_dashboard._startSync).
  static const List<String> activeStatuses = [
    'accepted', 'on_the_way', 'in_progress',
  ];

  /// بعد هذه المدة بلا تحديث تُعدّ العلامة «بلا تحديث حديث» (رمادية).
  static const Duration staleAfter = Duration(minutes: 10);

  /// null عند غياب الموقع أو السائق — طلب نشط بلا موقع بعد لا يُرسم.
  static FleetVehicle? fromOrder(String id, Map<String, dynamic> d) {
    final loc = d['driver_location'];
    double? lat;
    double? lng;
    if (loc is GeoPoint) {
      lat = loc.latitude;
      lng = loc.longitude;
    } else if (loc is Map) {
      lat = (loc['latitude'] ?? loc['lat'] as num?)?.toDouble();
      lng = (loc['longitude'] ?? loc['lng'] as num?)?.toDouble();
    }
    if (lat == null || lng == null) return null;
    final driverId = (d['driver_id'] ?? '').toString();
    if (driverId.isEmpty) return null;

    final ts = d['last_location_update'];
    DateTime? updated;
    if (ts is Timestamp) {
      updated = ts.toDate();
    } else if (ts is DateTime) {
      updated = ts;
    }
    String pick(List<dynamic> candidates, String fallback) {
      for (final c in candidates) {
        final s = (c ?? '').toString().trim();
        if (s.isNotEmpty && s != 'None') return s;
      }
      return fallback;
    }

    return FleetVehicle(
      orderId: id,
      orderCode: pick([d['code'], d['order_code']], id.length > 6 ? id.substring(0, 6).toUpperCase() : id),
      driverId: driverId,
      driverName: pick([d['driver_name'], d['assigned_driver']], 'سائق'),
      clientName: pick([d['client_name'], d['userName']], 'عميل'),
      serviceName: pick([d['service_name'], d['service']], ''),
      zoneName: pick([d['zone_name']], ''),
      status: (d['status'] ?? '').toString(),
      lat: lat,
      lng: lng,
      updatedAt: updated,
    );
  }

  bool get isWorking => status == 'in_progress';
  bool get isMoving => status == 'on_the_way' || status == 'accepted';

  bool isStale(DateTime now) =>
      updatedAt == null || now.difference(updatedAt!) > staleAfter;

  String ageLabel(DateTime now) {
    final u = updatedAt;
    if (u == null) return 'بلا تحديث';
    final diff = now.difference(u);
    if (diff.inSeconds < 60) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    return 'قبل ${diff.inDays} ي';
  }

  /// أول حرف من أول كلمتين — للعلامة على الخريطة (نمط Stitch «أف»).
  String get initials {
    final parts = driverName.trim().split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return parts[0].substring(0, 1) + parts[1].substring(0, 1);
  }

  /// سطر المهمة: «طلب #كود · خدمة · منطقة» — يُسقط الفارغ.
  String get taskLine => [
        'طلب #$orderCode',
        if (serviceName.isNotEmpty) serviceName,
        if (zoneName.isNotEmpty) zoneName,
      ].join(' · ');

  static int statusRank(String s) =>
      s == 'in_progress' ? 0 : (s == 'on_the_way' || s == 'accepted') ? 1 : 2;

  /// علامة واحدة لكل سائق: إن حمل طلبان نشطان موقعه فالأحدث تحديثاً يفوز
  /// (بلا تحديث يخسر دائماً). الترتيب: قيد التنفيذ ← في الطريق ← بالاسم.
  static List<FleetVehicle> latestPerDriver(Iterable<FleetVehicle> all) {
    final best = <String, FleetVehicle>{};
    for (final v in all) {
      final cur = best[v.driverId];
      if (cur == null || _newer(v, cur)) best[v.driverId] = v;
    }
    final list = best.values.toList()
      ..sort((a, b) {
        final r = statusRank(a.status).compareTo(statusRank(b.status));
        return r != 0 ? r : a.driverName.compareTo(b.driverName);
      });
    return list;
  }

  static bool _newer(FleetVehicle a, FleetVehicle b) {
    if (a.updatedAt == null) return false;
    if (b.updatedAt == null) return true;
    return a.updatedAt!.isAfter(b.updatedAt!);
  }

  static FleetSummary summarize(List<FleetVehicle> list, DateTime now) =>
      FleetSummary(
        total: list.length,
        working: list.where((v) => v.isWorking).length,
        moving: list.where((v) => v.isMoving).length,
        stale: list.where((v) => v.isStale(now)).length,
      );
}

class FleetSummary {
  final int total;
  final int working;
  final int moving;
  final int stale;
  const FleetSummary({
    required this.total,
    required this.working,
    required this.moving,
    required this.stale,
  });
}
