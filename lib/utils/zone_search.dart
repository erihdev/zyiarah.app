/// **البحثُ في مناطقِ الخدمةِ نفسِها، ومركزُ الخدمةِ للخريطة.**
///
/// محرّكُ البحثِ الجغرافيّ (Mapbox) لا يَعرفُ قرى الجبالِ التي تَعملُ فيها
/// الخدمةُ فعلاً — «فيفاء» و«الداير» و«عثوان» تُعيدُ صفراً — فعميلةٌ تَكتبُ
/// اسمَ قريتِها لا تَجدُ شيئاً، والخريطةُ كانت تَفتحُ على مدينةِ جازان
/// (أو صبيا) خارجَ كلِّ منطقةٍ مفعّلة. فهنا قاعدتان نقيّتان:
///
/// - [matchZones]: مطابقةُ ما تَكتبُه بأسماءِ المناطقِ **المفعّلة**، بعد
///   توحيدِ الهمزاتِ والتاءِ المربوطةِ والألفِ المقصورةِ و«ال» — فـ«فيفاء»
///   تُطابِقُ «فيفا» و«الجوه» تُطابِقُ «الجوة».
/// - [serviceCenter]: مركزُ المناطقِ المفعّلةِ بـ**الوسيط** لا بالمتوسّط،
///   لأنّ منطقةً واحدةً بإحداثيّاتٍ مغلوطةٍ (موجودةٌ في الإنتاج) تَجرُّ
///   المتوسّطَ إلى الصحراء ولا تُحرِّكُ الوسيط.
library;

/// منطقةُ خدمةٍ صالحةٌ للعرضِ في نتائجِ البحث.
class ZoneHit {
  final String name;
  final double lat;
  final double lng;
  const ZoneHit(this.name, this.lat, this.lng);
}

/// توحيدُ الكتابةِ العربيّةِ للمقارنة.
String normalizeArabicPlace(String s) {
  var t = s.trim();
  t = t.replaceAll(RegExp('[ً-ْـ]'), ''); // التشكيلُ والتطويل
  t = t.replaceAll(RegExp('[أإآٱ]'), 'ا');
  t = t.replaceAll('ة', 'ه').replaceAll('ى', 'ي');
  t = t.replaceAll(RegExp('[ءؤئ]'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  // «ال» التعريفِ في أوّلِ كلِّ كلمة.
  t = t
      .split(' ')
      .map((w) => w.startsWith('ال') && w.length > 3 ? w.substring(2) : w)
      .join(' ');
  // الألفُ الأخيرةُ تُكتبُ وتُحذَفُ («فيفا» / «فيفاء» بعد حذفِ الهمزة).
  t = t
      .split(' ')
      .map((w) =>
          w.endsWith('ا') && w.length > 2 ? w.substring(0, w.length - 1) : w)
      .join(' ');
  return t;
}

/// مركزُ مستندِ المنطقة: `centerLoc` (GeoPoint) أو `lat`/`lng`. لا يُعيدُ
/// شيئاً لمستندٍ بلا إحداثيّات.
({double lat, double lng})? zoneCenterOf(Map<String, dynamic> z) {
  final c = z['centerLoc'];
  if (c != null) {
    try {
      final dynamic g = c;
      return (
        lat: (g.latitude as num).toDouble(),
        lng: (g.longitude as num).toDouble()
      );
    } catch (_) {
      // ليس GeoPoint — نُكمِلُ إلى الحقولِ الصريحة.
    }
  }
  final lat = z['lat'] ?? z['latitude'];
  final lng = z['lng'] ?? z['longitude'];
  if (lat is num && lng is num) {
    return (lat: lat.toDouble(), lng: lng.toDouble());
  }
  return null;
}

bool _enabled(Map<String, dynamic> z) =>
    z['enabled'] != false && z['is_active'] != false;

/// المناطقُ المفعّلةُ التي يُطابِقُ اسمُها ما كُتب — بلا تكرارِ اسمٍ واحد.
List<ZoneHit> matchZones(List<Map<String, dynamic>> zones, String query,
    {int limit = 5}) {
  final q = normalizeArabicPlace(query);
  if (q.isEmpty) return const [];
  final seen = <String>{};
  final out = <ZoneHit>[];
  for (final z in zones) {
    if (!_enabled(z)) continue;
    final name = (z['name'] ?? '').toString().trim();
    if (name.isEmpty) continue;
    final n = normalizeArabicPlace(name);
    if (!(n.contains(q) || q.contains(n))) continue;
    final c = zoneCenterOf(z);
    if (c == null) continue;
    if (!seen.add(n)) continue;
    out.add(ZoneHit(name, c.lat, c.lng));
    if (out.length >= limit) break;
  }
  return out;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// مركزُ الخدمة: وسيطُ مراكزِ المناطقِ المفعّلة، أو null إن لم يَكن شيء.
({double lat, double lng})? serviceCenter(List<Map<String, dynamic>> zones) {
  final lats = <double>[];
  final lngs = <double>[];
  for (final z in zones) {
    if (!_enabled(z)) continue;
    final c = zoneCenterOf(z);
    if (c == null) continue;
    lats.add(c.lat);
    lngs.add(c.lng);
  }
  if (lats.isEmpty) return null;
  return (lat: _median(lats), lng: _median(lngs));
}
