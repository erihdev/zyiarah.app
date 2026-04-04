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
    this.radiusInMeters = 15000, // 15 km default radius per center
  });
}

class GeofenceService {
  // إحداثيات النقاط والمراكز المعتمدة مع القرى التابعة لها (محافظة الدائر والعيدابي وما يتبعهما)
  static const List<ZyiarahZone> supportedZones = [
    ZyiarahZone(name: 'الدائر', latitude: 17.3453018, longitude: 43.1572370),
    ZyiarahZone(name: 'فيفاء', latitude: 17.2528553, longitude: 43.1447016),
    ZyiarahZone(name: 'خاشر', latitude: 17.3160817, longitude: 43.1907216),
    ZyiarahZone(name: 'الحشر', latitude: 17.4547547, longitude: 43.0651835),
    ZyiarahZone(name: 'عثوان', latitude: 17.3334736, longitude: 43.2140566),
    ZyiarahZone(name: 'المشاف', latitude: 17.2254621, longitude: 42.8848916),
    ZyiarahZone(name: 'عيبان', latitude: 17.2775666, longitude: 43.0608273),
    ZyiarahZone(name: 'العشبة', latitude: 17.2777339, longitude: 43.1329307),
    ZyiarahZone(name: 'القاع', latitude: 17.2928767, longitude: 42.9775972),
    ZyiarahZone(name: 'المشوف', latitude: 17.1951042, longitude: 42.9729626),
    ZyiarahZone(name: 'الطلعه', latitude: 17.2335933, longitude: 43.0290303),
    ZyiarahZone(name: 'إسكان حرس الحدود', latitude: 17.1840212, longitude: 43.0426361),
    ZyiarahZone(name: 'صدر جورا', latitude: 17.4221939, longitude: 43.1016947),
    ZyiarahZone(name: 'العيدابي', latitude: 17.3060000, longitude: 43.0180000), // مركز العيدابي المرجعي
    ZyiarahZone(name: 'ريع', latitude: 17.2666000, longitude: 43.1000000), // إحداثية استدلالية لمركز ريع والأحياء التابعة
  ];

  /// التحقق مما إذا كان موقع المستخدم يقع ضمن أي من النطاقات المحددة أعلاه
  static bool isLocationSupported(Position userPosition) {
    for (var zone in supportedZones) {
      double distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        zone.latitude,
        zone.longitude,
      );

      // إذا كانت المسافة بين المستخدم ومركز المنطقة أقل من نصف القطر المسموح (بالأمتار)
      if (distance <= zone.radiusInMeters) {
        return true;
      }
    }
    return false;
  }

  /// الحصول على اسم المنطقة الأقرب للمستخدم إن كانت مدعومة
  static String? getNearestSupportedZoneName(Position userPosition) {
    double minDistance = double.infinity;
    String? nearestZoneName;

    for (var zone in supportedZones) {
      double distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        zone.latitude,
        zone.longitude,
      );

      if (distance <= zone.radiusInMeters && distance < minDistance) {
        minDistance = distance;
        nearestZoneName = zone.name;
      }
    }
    return nearestZoneName;
  }
}
