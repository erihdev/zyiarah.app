import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:geolocator/geolocator.dart';

/// سبب تعذّر التحديد التلقائي — **لكل حالة رسالة وإجراء**.
///
/// كان كل مسار فشل في `_attemptAutoLocation` ينتهي بـ`return;` أو `catch { /* Silent */ }`،
/// فتبقى الشاشة على «لم يُحدَّد موقعك بعد» دون أن تعرف العميلة (ولا نحن) **لماذا**:
/// أخدمة الموقع مطفأة؟ أم الإذن مرفوض؟ أم GPS لم يستجب؟ لا سجلّ ولا رسالة.
enum LocateFailure {
  /// خدمة الموقع في الجهاز مطفأة كلياً.
  serviceDisabled,

  /// رفضت العميلة الإذن هذه المرة (يمكن طلبه ثانيةً).
  permissionDenied,

  /// رفضٌ دائم — لا يُطلب الإذن مجدداً، يلزم فتح الإعدادات.
  permissionDeniedForever,

  /// GPS لم يُرجع موقعاً خلال المهلة (داخل مبنى غالباً).
  timeout,

  /// حُدِّد الموقع لكنه خارج كل نطاقات الخدمة.
  outOfServiceArea,

  /// خطأ غير متوقّع (يُسجَّل، ولا يُبتلع).
  unknown,
}

extension LocateFailureX on LocateFailure {
  /// رسالة تُعرض للعميلة — تشرح السبب وتقترح الإجراء.
  ///
  /// **الرفض الدائم يختلف جذرياً بين الويب والجوال**: على الجوال يُفتح إعدادات
  /// التطبيق، أما في المتصفّح فلا وجود لـ«إعدادات تطبيق» أصلاً — الحظر لكل موقع على
  /// حدة ويُرفع من شريط العنوان. عرض «افتحي إعدادات التطبيق» في كروم إرشادٌ إلى
  /// مكانٍ غير موجود، وزرٌّ يستدعي openAppSettings() هناك **زرٌّ ميت**.
  String get message => switch (this) {
        LocateFailure.serviceDisabled =>
          'خدمة الموقع مطفأة في جهازك. فعّليها ثم أعيدي المحاولة، أو حدّدي موقعك من الخريطة.',
        LocateFailure.permissionDenied =>
          'لم تُمنح صلاحية الموقع. اسمحي بها لتحديد منطقتك تلقائياً، أو حدّديها من الخريطة.',
        LocateFailure.permissionDeniedForever => kIsWeb
            ? 'الموقع محظور لهذا الموقع في متصفّحك. اضغطي أيقونة القفل (أو ⓘ) يسار شريط '
                'العنوان ← الموقع ← السماح، ثم حدّثي الصفحة. أو حدّدي موقعك من الخريطة.'
            : 'صلاحية الموقع مرفوضة دائماً. فعّليها من إعدادات التطبيق، أو حدّدي موقعك من الخريطة.',
        LocateFailure.timeout =>
          'تعذّر تحديد موقعك (قد تكوني داخل مبنى). أعيدي المحاولة أو حدّديه من الخريطة.',
        LocateFailure.outOfServiceArea =>
          'موقعك الحالي خارج نطاق خدماتنا. إن كنتِ داخل نطاقنا حدّدي موقعك من الخريطة.',
        LocateFailure.unknown =>
          'تعذّر تحديد موقعك تلقائياً. حدّديه من الخريطة.',
      };

  /// هل يُجدي زرّ «إعادة المحاولة»؟ (الرفض الدائم يحتاج رفع الحظر لا إعادة محاولة)
  bool get canRetry => this != LocateFailure.permissionDeniedForever;

  /// هل نعرض زرّ «فتح الإعدادات»؟
  ///
  /// **على الويب: أبداً.** `Geolocator.openAppSettings()` غير مدعومة في المتصفّح
  /// (ترمي UnimplementedError) — فالزر يبدو حلّاً وهو لا يفعل شيئاً. النصّ أعلاه
  /// يشرح للعميلة كيف ترفع الحظر من شريط العنوان بدلاً منه.
  bool get needsSettings =>
      !kIsWeb && this == LocateFailure.permissionDeniedForever;
}

class ZoneLocateResult {
  final GeoPoint? location;
  final Map<String, dynamic>? zone;
  final LocateFailure? failure;

  const ZoneLocateResult._({this.location, this.zone, this.failure});

  factory ZoneLocateResult.success(GeoPoint loc, Map<String, dynamic> zone) =>
      ZoneLocateResult._(location: loc, zone: zone);

  factory ZoneLocateResult.failed(LocateFailure f, {GeoPoint? location}) =>
      ZoneLocateResult._(failure: f, location: location);

  bool get isSuccess => failure == null && zone != null;
  String? get zoneName => zone?['name'] as String?;
}

/// تحديد الموقع ومطابقته بمنطقة خدمة — **مصدر واحد لثلاث شاشات**.
///
/// كان هذا المنطق منسوخاً حرفياً في hourly_details و sofa_rug_details و
/// ac_service_details: نفس جلب المناطق، نفس `Geolocator.distanceBetween`، ونفس
/// مسارات الفشل الصامتة. تكرار المنطق هو ما أنتج في هذا المشروع نظامَي تسعير
/// متنازعَين وحسابَي سعة متناقضَين — فلا نُكرّره هنا.
class ZyiarahZoneLocator {
  ZyiarahZoneLocator._();

  /// مهلة GPS. بدونها كان `getCurrentPosition()` ينتظر بلا نهاية داخل المبنى،
  /// فتبقى الشاشة صامتة كأنها لا تعمل.
  static const Duration gpsTimeout = Duration(seconds: 12);

  /// المناطق المفعّلة مرتّبة بـ rank.
  static Future<List<Map<String, dynamic>>> fetchZones() async {
    final snap = await FirebaseFirestore.instance
        .collection('service_zones')
        .where('enabled', isEqualTo: true)
        .get();
    return snap.docs.map((d) => d.data()).toList()
      ..sort((a, b) => (a['rank'] as int? ?? 0).compareTo(b['rank'] as int? ?? 0));
  }

  /// أقرب منطقة يقع [loc] داخل نصف قطرها، أو null إن كان خارجها كلّها.
  static Map<String, dynamic>? matchZone(
      GeoPoint loc, List<Map<String, dynamic>> zones) {
    Map<String, dynamic>? matched;
    double minDistance = double.infinity;
    for (final z in zones) {
      final center = z['centerLoc'];
      if (center is! GeoPoint) continue;
      final radiusM = ((z['radiusKm'] as num?)?.toDouble() ?? 15.0) * 1000;
      final d = Geolocator.distanceBetween(
          loc.latitude, loc.longitude, center.latitude, center.longitude);
      if (d <= radiusM && d < minDistance) {
        minDistance = d;
        matched = z;
      }
    }
    return matched;
  }

  /// يحدّد الموقع ويطابقه بمنطقة. **لا يفشل بصمت أبداً**: كل مسار يُرجع سبباً.
  ///
  /// [requestPermission] عند false لا يُظهر مربّع الإذن (لمحاولة صامتة عند فتح
  /// الشاشة)؛ وعند true يطلبه صراحةً (لزرّ «حدّد موقعي»).
  static Future<ZoneLocateResult> locate(
    List<Map<String, dynamic>> zones, {
    bool requestPermission = true,
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return ZoneLocateResult.failed(LocateFailure.serviceDisabled);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!requestPermission) {
          return ZoneLocateResult.failed(LocateFailure.permissionDenied);
        }
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return ZoneLocateResult.failed(LocateFailure.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return ZoneLocateResult.failed(LocateFailure.permissionDeniedForever);
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(gpsTimeout);

      final loc = GeoPoint(pos.latitude, pos.longitude);
      final zone = matchZone(loc, zones);
      if (zone == null) {
        // نُعيد الموقع مع الفشل: الشاشة قد تعرضه على الخريطة ليصحّحه المستخدم.
        return ZoneLocateResult.failed(LocateFailure.outOfServiceArea,
            location: loc);
      }
      return ZoneLocateResult.success(loc, zone);
    } on Exception catch (e) {
      // TimeoutException وغيره — يُسجَّل ولا يُبتلع.
      debugPrint('[ZoneLocator] locate failed: $e');
      return ZoneLocateResult.failed(
          e.toString().contains('Timeout') ? LocateFailure.timeout : LocateFailure.unknown);
    }
  }

  /// يفتح إعدادات التطبيق (للرفض الدائم على الجوال فقط).
  /// حارس صريح: الاستدعاء على الويب يرمي UnimplementedError — لا نتركه يفشل بصمت.
  static Future<bool> openSettings() async {
    if (kIsWeb) {
      debugPrint('[ZoneLocator] openAppSettings unsupported on web — no-op');
      return false;
    }
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[ZoneLocator] openAppSettings failed: $e');
      return false;
    }
  }
}
