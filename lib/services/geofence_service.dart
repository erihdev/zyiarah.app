import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// يُستدعى مرة واحدة عند بدء التطبيق لتحميل المحافظات من Firestore
  static Future<void> initialize() async {
    try {
      final db = FirebaseFirestore.instance;
      final snapshot = await db
          .collection('service_zones')
          .where('enabled', isEqualTo: true)
          .get();

      // المجموعة فارغة — ابذر البيانات الافتراضية تلقائياً. وإن كانت عامرة فلا شيء
      // نفعله: القراءةُ هنا تقرّر البذر فقط. (كانت تملأ ذاكرةً مؤقّتة قارئُها الوحيد
      // `supportedZones` بلا مُنادٍ، فيُبنى الجدولُ كلَّ إقلاعٍ ثمّ يُرمى.)
      if (snapshot.docs.isEmpty) {
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
      final ref = db.collection('service_zones').doc();
      batch.set(ref, {
        'name': z.name,
        'centerLoc': GeoPoint(z.latitude, z.longitude),
        'radiusKm': z.radiusInMeters / 1000,
        'enabled': true,
        'rank': i + 1,
        // يغطي كل خيارات «الساعات المتاحة» — شريحةٌ بلا مفتاح سعر تُقرأ صفراً
        // فتبدو الخدمة «غير مسعّرة» في تثبيتٍ جديد.
        'prices': {
          '1': 35.0,
          '2': 70.0,
          '4': 120.0,
          '5': 150.0,
          '6': 180.0,
          '7': 210.0,
          '8': 240.0,
        },
        // صفر = «غير مسعّرة» فتُعطَّل الخدمة حتى تُسعّرها الإدارة لكل منطقة.
        // كان هذا البذر يضع 35/15 تلقائياً بلا أن يراها بشر — ومنذ صارت حقول م² هي
        // ما يحاسب العميلة فعلاً، صار ذلك بيعاً بسعرٍ لم يعتمده أحد. ولوحة React كانت
        // تبذر صفراً في الحقول نفسها، فكانت المنطقة تُسعَّر أو تُعطَّل حسب الشاشة التي
        // أنشأتها. مصدر واحد الآن: لا سعر ⇒ لا بيع.
        // (sofaPrice/rugPrice الطوليان لم يعودا يُبذران — النظام أُلغي ولا قارئ لهما.)
        'sofaSqmPrice': 0,
        'rugSqmPrice': 0,
        'acMaintWindowPrice': 0,
        'acMaintSplitPrice': 0,
        'acWashWindowPrice': 0,
        'acWashSplitPrice': 0,
        'carSmallPrice': 0,
        'carMediumPrice': 0,
        'carLargePrice': 0,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

}
