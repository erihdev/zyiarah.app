import 'package:flutter_map/flutter_map.dart';
import 'package:zyiarah/utils/env.dart';

/// **مصدرُ بلاطاتِ الخريطةِ في التطبيق: Mapbox، من موضعٍ واحد.**
///
/// كانت الخرائطُ الستُّ (منتقي الموقع، والتتبّع، ولوحةُ السائق، وخريطةُ الطلب،
/// وخريطةُ الأسطول، ومحرِّرُ المناطق) تَطلبُ `tile.openstreetmap.org` مباشرةً.
/// وسياسةُ استخدامِ ذلك الخادمِ تَمنعُ التطبيقاتِ ذاتَ الحركةِ الكبيرة وتَحجبُها
/// بلا إنذار، فخريطةُ تطبيقٍ منشورٍ لا يَجوزُ أن تَقومَ عليه (قرارُ المالك،
/// 2026-10-24: «حوّل له»).
///
/// **ثمنٌ معلَن:** بلاطاتُ Mapbox النقطيّةُ بنمطِ `streets-v12` تَكتبُ أسماءَ
/// الأماكنِ كما في بياناتِه (كثيرٌ منها إنجليزيّ)، ولا مُعامِلَ لغةٍ لها. فإن
/// أُنشئَ نمطٌ عربيٌّ في Mapbox Studio يُوضَعُ مُعرّفُه في [kMapboxStyle] وحدَه.
///
/// والاحتياطُ لـOSM يَبقى لحالةٍ واحدة: رمزٌ غائب (`.env` الفارغُ في الفحوص).
/// مساراتُ البناءِ كلُّها تَفشلُ على `MAPBOX_TOKEN` الغائب، فلا يَصلُ ذلك
/// الاحتياطُ إلى مستخدمٍ في الإنتاج.
const String kMapboxStyle = 'mapbox/streets-v12';

/// احتياطٌ بلا رمز — لا يُستعمَلُ في بناءٍ منشور.
const String kOsmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// قالبُ رابطِ البلاطة. [token] للفحص؛ الافتراضُ رمزُ `.env`.
String mapTileUrlTemplate({String? token}) {
  final t = (token ?? envOrEmpty('MAPBOX_TOKEN')).trim();
  if (t.isEmpty) return kOsmTileUrl;
  return 'https://api.mapbox.com/styles/v1/$kMapboxStyle/tiles/256/{z}/{x}/{y}@2x'
      '?access_token=$t';
}

/// طبقةُ البلاطاتِ المشترَكة لكلِّ خرائطِ التطبيق.
TileLayer zyiarahTileLayer({String? token}) => TileLayer(
      urlTemplate: mapTileUrlTemplate(token: token),
      userAgentPackageName: 'com.zyiarah.zyiarah',
    );
