import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/services.dart';

/// خدمة إدارة العمليات الجوهرية (قفل الوقت والجيوفنسينج)
/// تم التطوير بواسطة: إرث (erihdev.com)
class ZyiarahCoreService {
  
  // --- 1. مؤقّت المدّة المنقضية (Elapsed timer) ---

  /// تيار «المدّة المنقضية» منذ لحظة بدءٍ **خادميّة** (start_time). عدٌّ تصاعديّ حقيقي
  /// بدل العدّ التنازلي القديم الذي كان يفترض ساعات العقد بلا مرساة زمنية فعلية.
  /// يُطلق قيمةً فوراً ثم كل ثانية، ويُثبّت السالب على صفر (ساعة الجهاز قد تتخلّف عن
  /// الخادم فتُنتج فرقاً سالباً يعرضه المنسّق كقمامة).
  Stream<Duration> elapsedSinceStream(DateTime startedAt) async* {
    while (true) {
      final d = DateTime.now().difference(startedAt);
      yield d.isNegative ? Duration.zero : d;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// منسّق مشترك HH:MM:SS مع تثبيت السالب على صفر — يُستعمَل في شاشات السائق/العميل/الإدارة.
  static String formatElapsed(Duration d) {
    final x = d.isNegative ? Duration.zero : d;
    final h = x.inHours.toString().padLeft(2, '0');
    final m = (x.inMinutes % 60).toString().padLeft(2, '0');
    final s = (x.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // --- 2. نظام الجيوفنسينج (Geofencing) ---

  /// حساب المسافة بالمتر بين السائق والعميل باستخدام معادلة Haversine
  double getDistanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 + 
          c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000; // النتيجة بالمتر
  }

  /// حساب المسافة وعرضها بتنسيق مقروء (مثلاً: 2.5 كم)
  String getFormattedDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return "${distanceInMeters.toStringAsFixed(0)} متر";
    } else {
      double distanceInKm = distanceInMeters / 1000;
      return "${distanceInKm.toStringAsFixed(1)} كم";
    }
  }

  // --- 3. التوقيع الرقمي (Digital Signature) ---

  // --- 4. التحليلات (Business Analytics) ---
  //
  // **حُذِفَ `logEvent` و`_analytics` (2026-10-05): بلا نداءٍ واحد.** ولم
  // يَرَهما `no_dead_code_test` لأنّ `logEvent` **يُطابقُ اسمَ دالّةٍ في
  // حزمةِ `firebase_analytics` نفسِها**، فالعدُّ داخلَ الملفِّ كان اثنَين
  // (سطرُ التعريفِ + `_analytics.logEvent(`) فتَخطّاه شرطُ `own > 1`. وهو
  // الخامسُ من عمًى «اسمٌ يُشبهُ حزمةً خارجيّة» المسجَّلِ أعلاه
  // (`updatePassword`، `verifyPhoneNumber`، `verifyOTP`،
  // `checkHourlySlotAvailability`) — وله الآن فحصٌ صريحٌ يَطلبُ نداءً **من
  // خارجِ ملفِّ التعريف**.
  //
  // **والاعتمادُ `firebase_analytics` باقٍ في `pubspec.yaml` عن قصد**، وهذا
  // ليس تناقضاً: الـSDK يُهيّئُ نفسَه مع `Firebase.initializeApp` ويَجمعُ
  // تلقائيّاً (`first_open`، `session_start`، مشاهداتُ الشاشات، معرّفُ نسخةِ
  // التطبيق، موقعٌ تقريبيٌّ من الـIP) بلا سطرِ شفرةٍ واحد — وهو كذلك ما
  // يُغذّي «المستخدمون بلا انهيارات» والجلسات في Crashlytics. فحذفُه قرارٌ
  // تجاريٌّ (يُغيّرُ ما يُجمَع) لا تنظيفُ شفرةٍ ميّتة. وما جُمِعَ تلقائيّاً
  // **مُعلَنٌ الآن** في `ios/Runner/PrivacyInfo.xcprivacy`، وكان ناقصاً.
  // القرارُ المتبقّي للمالك: توصيلُ أحداثٍ مخصَّصةٍ للقُمع، أو إسقاطُ
  // الاعتماد.

  // --- 5. نظام التفاعل الحسي (Sensory UI) ---

  /// اهتزاز خفيف للتفاعلات العادية (مثل اختيار خيار)
  static Future<void> triggerHapticSelection() async {
    await HapticFeedback.selectionClick();
  }

  /// اهتزاز قوي للنجاح (مثل إتمام الحجز)
  static Future<void> triggerHapticSuccess() async {
    await HapticFeedback.heavyImpact();
  }

  /// تأثير خفيف للمس الأزرار
  static Future<void> triggerHapticLight() async {
    await HapticFeedback.lightImpact();
  }
}
