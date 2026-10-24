import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:zyiarah/services/zone_locator_service.dart';

/// **موقعُ العميلةِ مرّةً واحدةً للتطبيقِ كلِّه** (قرار المالك 2026-10-24).
///
/// كانت كلُّ شاشةِ خدمةٍ من السبع تُحدِّدُ الموقعَ بنفسِها عند فتحِها
/// (`ZyiarahZoneLocator.locate`) وتَرسمُ سطرَها: «جارٍ تحديد موقعك…»، أو
/// «موقعك الحالي خارج نطاق خدماتنا…» بروابطِ «إعادة المحاولة / من الخريطة».
/// والمالكُ يُريدُ الموقعَ **في البدايةِ فقط** — طلبُ الإذنِ عند فتحِ
/// التطبيق، ونقطةٌ خضراءُ واسمُ المنطقةِ أعلى الرئيسيّة — والشاشاتُ تَقرؤه
/// ولا تَسألُ عنه.
///
/// فهذا هو المصدرُ الواحد: الرئيسيّةُ تُنادي [ensure] عند الفتح (الإذنُ مرّة)،
/// والشاشاتُ تُنادي [resolve] فتأخذُ النتيجةَ المحفوظةَ بلا GPS ولا نافذةِ
/// إذن، وتغييرُ الموقعِ من الخريطةِ (رأسُ الرئيسيّة أو احتياطُ الشاشة)
/// يَمرُّ بـ[setManual] فيَتّبعُه الجميع.
class ClientLocation extends ChangeNotifier {
  ClientLocation._();
  static final ClientLocation instance = ClientLocation._();

  /// للاختبار وحدَه: نسخةٌ معزولة.
  @visibleForTesting
  factory ClientLocation.forTest() => ClientLocation._();

  ZoneLocateResult? _result;
  Future<ZoneLocateResult>? _inflight;
  bool _manual = false;

  /// آخرُ نتيجة (`null` قبلَ أوّلِ محاولة).
  ZoneLocateResult? get result => _result;

  bool get isLocating => _inflight != null;

  /// اختارتها العميلةُ من الخريطة — تحديثُ العودةِ الصامتُ لا يَطغى عليها.
  bool get isManual => _manual;

  /// المحدِّدُ نفسُه — مُعاملٌ للاختبار فقط.
  @visibleForTesting
  Future<ZoneLocateResult> Function(List<Map<String, dynamic>> zones,
      {bool requestPermission}) locator = ZyiarahZoneLocator.locate;

  /// عند فتحِ التطبيق: يُحدِّدُ ويَطلبُ الإذنَ إن لزم. نداءٌ ثانٍ وهو جارٍ
  /// يَنتظرُ الأوّلَ ولا يَفتحُ GPS ثانياً.
  Future<ZoneLocateResult> ensure(List<Map<String, dynamic>> zones) =>
      _locate(zones, requestPermission: true);

  /// ما تُناديه الشاشات: المحفوظُ إن وُجد، وإلّا محاولةٌ واحدة. فشلٌ محفوظٌ
  /// يُعادُ كما هو — الشاشةُ لا تُعيدُ السؤالَ عن إذنٍ رُفض.
  Future<ZoneLocateResult> resolve(List<Map<String, dynamic>> zones,
      {bool requestPermission = true}) {
    final r = _result;
    if (r != null) return Future.value(r);
    return _locate(zones, requestPermission: requestPermission);
  }

  /// قراءةٌ جديدةٌ صراحةً (إعادةُ المحاولةِ من الرأس، أو العودةُ للتطبيق
  /// صامتةً). اختيارُ الخريطةِ يَبقى ما لم يُطلَب `force`.
  Future<ZoneLocateResult> refresh(List<Map<String, dynamic>> zones,
      {bool requestPermission = false, bool force = false}) {
    final r = _result;
    if (_manual && !force && r != null) return Future.value(r);
    return _locate(zones, requestPermission: requestPermission, fresh: true);
  }

  /// اختيارٌ من الخريطةِ داخلَ منطقةِ خدمة.
  void setManual(GeoPoint location, Map<String, dynamic> zone) {
    _result = ZoneLocateResult.success(location, zone);
    _manual = true;
    notifyListeners();
  }

  Future<ZoneLocateResult> _locate(List<Map<String, dynamic>> zones,
      {required bool requestPermission, bool fresh = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!fresh && _result != null) return Future.value(_result!);
    final f = () async {
      try {
        final r = await locator(zones, requestPermission: requestPermission);
        // نتيجةٌ أسوأُ من محفوظةٍ ناجحةٍ لا تَمحوها على تحديثٍ صامت: انقطاعُ
        // GPS لحظةً داخلَ مبنى لا يُحوِّلُ النقطةَ الخضراءَ إلى «تعذّر».
        final prev = _result;
        final keepPrev = fresh &&
            !requestPermission &&
            prev != null &&
            prev.isSuccess &&
            !r.isSuccess &&
            r.failure != LocateFailure.outOfServiceArea;
        if (!keepPrev) {
          _result = r;
          if (r.isSuccess) _manual = false;
        }
        return _result!;
      } finally {
        _inflight = null;
        notifyListeners();
      }
    }();
    _inflight = f;
    notifyListeners();
    return f;
  }
}
