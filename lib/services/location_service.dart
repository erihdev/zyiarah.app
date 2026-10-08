import 'package:geolocator/geolocator.dart';
import 'package:zyiarah/utils/error_report.dart';

/// **إذنُ الموقعِ — ونداءٌ مُسقَطٌ لا يَجدُ مَن يَلتقطُ رميَه (2026-10-08).**
///
/// `requestPermission` كانت بلا `try` إطلاقاً، ومُنادِيها الوحيدُ
/// (`driver_dashboard._ensureLocationPermission`) **يُسقِطُ** مستقبلَها من
/// `addPostFrameCallback`. و`Geolocator.checkPermission`/`requestPermission`
/// يَرميانِ فعلاً — أظهرُها `PermissionRequestInProgressException` حين يَكونُ
/// طلبٌ آخرُ جارياً، و`MissingPluginException` على سطحٍ لا يُنفّذُها. فالرميُ
/// يَخرُجُ إلى لا أحد:
///
///  • `_locationDenied` لا يُضبَط، فلا شريطَ ولا زرَّ «الإعدادات»؛
///  • و`_startPositionStream` لا يُنادى، **فلا موقعَ في الجلسةِ كلِّها** —
///    وهو بعينُه ما يَقولُ تعليقُ ذلك المُنادي إنّه وُجد لمنعِه («بدون هذا
///    الطلب الصريح… وتفشل كل عمليات الموقع بصمت»)؛
///  • ويُسجَّلُ الرميُ **قاتلاً** في Crashlytics عبرَ
///    `PlatformDispatcher.onError` في `main.dart`.
///
/// فـ«تعذّرَ السؤالُ» يُقرأُ **«لم يُمنَح»**: هو الجوابُ المحافظُ، وهو الذي
/// يُشغّلُ المسارَ الذي يُخبِرُ السائقَ ويَفتحُ له الإعدادات. ويُبلَّغُ صامتاً
/// لأنّ موقعَ السائقِ استمرارُ خدمةٍ — نطاقُ `reportSilent` المُعلَن.
///
/// ونظيرُ هذا الطلبِ مكتوبٌ **مرّةً أخرى** داخلَ `zone_locator_service.locate`
/// وهو محروسٌ هناك بـ`on Exception catch` المحيط: فالقاعدةُ كانت مُنفَّذةً في
/// نسخةٍ من نسختَين.
class ZyiarahLocationService {
  static final ZyiarahLocationService _instance = ZyiarahLocationService._internal();
  factory ZyiarahLocationService() => _instance;
  ZyiarahLocationService._internal();

  /// Just checks/requests permission without necessarily waiting for a lock.
  Future<bool> requestPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e, st) {
      reportSilent(e, st, reason: 'location_permission_request_failed');
      return false;
    }
  }
}
