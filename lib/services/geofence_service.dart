import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class ZyiarahZone {
  final String name;
  final double latitude;
  final double longitude;
  final double radiusInMeters;

  const ZyiarahZone({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusInMeters = 15000,
  });
}

class GeofenceService {
  // المحافظات الافتراضية — تُستخدم عند فشل التحميل من Firestore
  static const List<ZyiarahZone> _fallbackZones = [
    ZyiarahZone(name: 'الدائر',               latitude: 17.3453018, longitude: 43.1572370),
    ZyiarahZone(name: 'فيفاء',                latitude: 17.2528553, longitude: 43.1447016),
    ZyiarahZone(name: 'خاشر',                 latitude: 17.3160817, longitude: 43.1907216),
    ZyiarahZone(name: 'الحشر',                latitude: 17.4547547, longitude: 43.0651835),
    ZyiarahZone(name: 'عثوان',                latitude: 17.3334736, longitude: 43.2140566),
    ZyiarahZone(name: 'المشاف',               latitude: 17.2254621, longitude: 42.8848916),
    ZyiarahZone(name: 'عيبان',                latitude: 17.2775666, longitude: 43.0608273),
    ZyiarahZone(name: 'العشبة',               latitude: 17.2777339, longitude: 43.1329307),
    ZyiarahZone(name: 'القاع',                latitude: 17.2928767, longitude: 42.9775972),
    ZyiarahZone(name: 'المشوف',               latitude: 17.1951042, longitude: 42.9729626),
    ZyiarahZone(name: 'الطلعه',               latitude: 17.2335933, longitude: 43.0290303),
    ZyiarahZone(name: 'إسكان حرس الحدود',    latitude: 17.1840212, longitude: 43.0426361),
    ZyiarahZone(name: 'صدر جورا',             latitude: 17.4221939, longitude: 43.1016947),
    ZyiarahZone(name: 'العيدابي',             latitude: 17.3060000, longitude: 43.0180000),
    ZyiarahZone(name: 'ريع',                  latitude: 17.2666000, longitude: 43.1000000),
  ];

  static List<ZyiarahZone> _cachedZones = [];

  static List<ZyiarahZone> get supportedZones =>
      _cachedZones.isNotEmpty ? _cachedZones : _fallbackZones;

  /// يُستدعى مرة واحدة عند بدء التطبيق لتحميل المحافظات من Firestore
  static Future<void> initialize() async {
    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db
          .collection('coverage_zones')
          .where('enabled', isEqualTo: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _cachedZones = snapshot.docs.map((doc) {
          final d = doc.data();
          return ZyiarahZone(
            name: d['name'] as String? ?? '',
            latitude: (d['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude: (d['longitude'] as num?)?.toDouble() ?? 0.0,
            radiusInMeters: ((d['radiusKm'] as num?)?.toDouble() ?? 15.0) * 1000,
          );
        }).where((z) => z.name.isNotEmpty).toList();
      } else {
        // المجموعة فارغة — ابذر البيانات الافتراضية تلقائياً
        await _seedDefaultZones(db);
      }
    } catch (_) {
      // عند الفشل تعمل القائمة المشفَّرة كـ fallback
    }
  }

  static Future<void> _seedDefaultZones(FirebaseFirestore db) async {
    final batch = db.batch();
    for (int i = 0; i < _fallbackZones.length; i++) {
      final z = _fallbackZones[i];
      final ref = db.collection('coverage_zones').doc();
      batch.set(ref, {
        'name': z.name,
        'latitude': z.latitude,
        'longitude': z.longitude,
        'radiusKm': z.radiusInMeters / 1000,
        'enabled': true,
        'rank': i + 1,
      });
    }
    await batch.commit();
    _cachedZones = List.of(_fallbackZones);
  }

  static bool isLocationSupported(Position userPosition) {
    for (final zone in supportedZones) {
      final distance = Geolocator.distanceBetween(
        userPosition.latitude, userPosition.longitude,
        zone.latitude, zone.longitude,
      );
      if (distance <= zone.radiusInMeters) return true;
    }
    return false;
  }

  static String? getNearestSupportedZoneName(Position userPosition) {
    double minDistance = double.infinity;
    String? nearestZoneName;
    for (final zone in supportedZones) {
      final distance = Geolocator.distanceBetween(
        userPosition.latitude, userPosition.longitude,
        zone.latitude, zone.longitude,
      );
      if (distance <= zone.radiusInMeters && distance < minDistance) {
        minDistance = distance;
        nearestZoneName = zone.name;
      }
    }
    return nearestZoneName;
  }

  static double calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  static bool isNearTarget(double currentLat, double currentLng, double targetLat, double targetLng, {double threshold = 2000}) {
    return calculateDistance(currentLat, currentLng, targetLat, targetLng) <= threshold;
  }
}
